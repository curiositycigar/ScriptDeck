import Foundation
import Combine

struct HistoryLogPage {
    let text: String
    let index: Int
    let total: Int
    let size: UInt64
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var warning: String?
    @Published private(set) var page: HistoryLogPage?
    @Published private(set) var pageRecordID: String?
    @Published private(set) var pageError: String?
    @Published private(set) var loadingPage = false
    @Published private(set) var deleting = false
    private var reloadGeneration = 0
    private var pageGeneration = 0

    func reload(directories: [URL]) async {
        guard !deleting else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        loading = true
        let result = await Task.detached(priority: .userInitiated) { Self.readEntries(directories) }.value
        guard generation == reloadGeneration else { return }
        entries = result.entries
        warning = result.warning
        loading = false
    }
    func load(_ entry: HistoryEntry, page requested: Int? = nil) async {
        guard !deleting else { return }
        pageGeneration += 1
        let generation = pageGeneration
        loadingPage = true
        pageError = nil
        if pageRecordID != entry.id { page = nil }
        pageRecordID = entry.id
        let result = await Task.detached(priority: .userInitiated) {
            Result { try Self.readPage(entry.logURL, requested: requested) }
        }.value
        guard generation == pageGeneration else { return }
        switch result {
        case .success(let value): page = value
        case .failure(let error): page = nil; pageError = L("Unable to read the log: {0}", "\(error.localizedDescription)")
        }
        loadingPage = false
    }
    func remove(_ targets: [HistoryEntry], protectedIDs: Set<String>) async -> String? {
        guard !deleting else { return nil }
        deleting = true
        reloadGeneration += 1
        pageGeneration += 1
        loading = false
        loadingPage = false
        let result = await Task.detached(priority: .userInitiated) {
            HistoryRecordDeletion.remove(targets, protectedIDs: protectedIDs)
        }.value
        entries.removeAll { result.removedIDs.contains($0.id) }
        if let id = pageRecordID, result.removedIDs.contains(id) {
            page = nil
            pageRecordID = nil
            pageError = nil
        }
        deleting = false
        guard !result.failures.isEmpty else { return nil }
        return L("{0} records could not be fully deleted. Refresh and try again.\n", "\(result.failures.count)") + result.failures.prefix(3).joined(separator: "\n")
    }

    private nonisolated static func readEntries(_ directories: [URL]) -> (entries: [HistoryEntry], warning: String?) {
        var entries: [String: HistoryEntry] = [:]
        var unreadable = 0
        var invalid = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for directory in Set(directories) {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for url in urls where url.pathExtension == "json" {
                    do {
                        let record = try decoder.decode(ExecutionRecord.self, from: Data(contentsOf: url))
                        guard record.version == 1, !record.id.isEmpty,
                              record.logFilename.hasSuffix(".log"),
                              URL(fileURLWithPath: record.logFilename).lastPathComponent == record.logFilename else {
                            throw RunnerError(message: L("Invalid execution record format"))
                        }
                        entries[record.id] = HistoryEntry(record: record, metadataURL: url)
                    } catch { invalid += 1 }
                }
            } catch { unreadable += 1 }
        }
        var issues: [String] = []
        if unreadable > 0 { issues.append(L("{0} log directories could not be read", "\(unreadable)")) }
        if invalid > 0 { issues.append(L("Skipped {0} damaged or incompatible records", "\(invalid)")) }
        return (entries.values.sorted {
            $0.record.startedAt == $1.record.startedAt ? $0.id > $1.id : $0.record.startedAt > $1.record.startedAt
        }, issues.isEmpty ? nil : issues.joined(separator: "；"))
    }
    private nonisolated static func readPage(_ url: URL, requested: Int?) throws -> HistoryLogPage {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let chunk: UInt64 = 256 * 1024
        let total = max(1, Int((size + chunk - 1) / chunk))
        let index = min(total - 1, max(0, requested ?? total - 1))
        let start = UInt64(index) * chunk
        // Overlap UTF-8 boundaries, assigning each scalar to the page where it begins.
        try handle.seek(toOffset: start)
        let data = try handle.read(upToCount: Int(min(chunk + 3, size - min(size, start)))) ?? Data()
        let bytes = Array(data)
        var leading = 0
        if index > 0 { while leading < bytes.count && bytes[leading] & 0xc0 == 0x80 { leading += 1 } }
        var end = min(bytes.count, Int(min(chunk, size - min(size, start))))
        while end < bytes.count && bytes[end] & 0xc0 == 0x80 { end += 1 }
        return HistoryLogPage(text: String(decoding: bytes[leading..<max(leading, end)], as: UTF8.self),
                              index: index, total: total, size: size)
    }
}
