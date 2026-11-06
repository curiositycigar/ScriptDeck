import Foundation

struct HistoryDeletionResult {
    var removedIDs = Set<String>()
    var failures: [String] = []
}

/// Removes only the two files belonging to each confirmed record, never whole directories.
enum HistoryRecordDeletion {
    static func remove(_ entries: [HistoryEntry], protectedIDs: Set<String>) -> HistoryDeletionResult {
        var result = HistoryDeletionResult()
        let files = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for entry in entries where !protectedIDs.contains(entry.id) {
            do {
                let metadata = entry.metadataURL
                guard metadata.pathExtension == "json",
                      entry.record.logFilename.hasSuffix(".log"),
                      URL(fileURLWithPath: entry.record.logFilename).lastPathComponent == entry.record.logFilename else {
                    throw RunnerError(message: "记录路径无效，未删除文件")
                }
                // Revalidate after confirmation, in case another process replaced a record.
                if try isRegularFile(metadata, files: files) {
                    let current = try decoder.decode(ExecutionRecord.self, from: Data(contentsOf: metadata))
                    guard current.version == 1, current.id == entry.id,
                          current.logFilename == entry.record.logFilename else {
                        throw RunnerError(message: "记录已发生变化，请刷新后重试")
                    }
                }
                if try isRegularFile(entry.logURL, files: files) { try files.removeItem(at: entry.logURL) }
                if try isRegularFile(metadata, files: files) { try files.removeItem(at: metadata) }
                result.removedIDs.insert(entry.id)
            } catch {
                result.failures.append("\(entry.record.scriptName)：\(error.localizedDescription)")
            }
        }
        return result
    }

    private static func isRegularFile(_ url: URL, files: FileManager) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try files.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return false
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RunnerError(message: "日志路径不是普通文件，未删除")
        }
        return true
    }
}
