import Foundation

/// All mutable writer state is confined to this serial queue after initialization.
final class RunLogWriter: @unchecked Sendable {
    let id: String
    let directory: URL
    let metadataURL: URL
    let logURL: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "local.scripts.run-log", qos: .utility)
    private var record: ExecutionRecord
    private var decoder = PlainLogDecoder()
    private var endsWithNewline = true
    private var finished = false
    private var reportedError = false
    private let onError: @Sendable (String) -> Void

    init(id: String = UUID().uuidString, item: ScriptItem, workspaceID: String?, workspaceName: String, startedAt: Date, scheduledTaskID: String? = nil,
         onError: @escaping @Sendable (String) -> Void) throws {
        self.id = id
        directory = Self.directory(for: URL(fileURLWithPath: item.path))
        self.onError = onError
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let stem = formatter.string(from: startedAt) + "_" + id
        logURL = directory.appendingPathComponent(stem + ".log")
        metadataURL = directory.appendingPathComponent(stem + ".json")
        record = ExecutionRecord(id: id, scriptID: item.id, scriptName: item.name,
                                 scriptFile: item.path, workspaceID: workspaceID,
                                 workspaceName: workspaceName, scheduledTaskID: scheduledTaskID, startedAt: startedAt,
                                 logFilename: logURL.lastPathComponent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try Data().write(to: logURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        handle = try FileHandle(forWritingTo: logURL)
        do { try Self.write(record, to: metadataURL, initial: true) }
        catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: logURL)
            throw error
        }
    }

    static func directory(for script: URL) -> URL {
        script.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(script.lastPathComponent, isDirectory: true)
    }
    func append(_ bytes: Data) {
        queue.async {
            guard !self.finished else { return }
            let text = self.decoder.decode(bytes)
            do {
                if !text.isEmpty {
                    try self.handle.write(contentsOf: text)
                    self.endsWithNewline = text.last == 10
                }
            }
            catch { self.report(error) }
        }
    }
    func appendMessage(_ message: String) {
        queue.async {
            guard !self.finished else { return }
            self.decoder = PlainLogDecoder()
            do {
                let text = (self.endsWithNewline ? "" : "\n") + message + "\n"
                try self.handle.write(contentsOf: Data(text.utf8))
                self.endsWithNewline = true
            }
            catch { self.report(error) }
        }
    }
    func finish(outcome: ExecutionOutcome, exitCode: Int32?, endedAt: Date = Date(), completion: @escaping @Sendable () -> Void) {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            self.record.endedAt = endedAt
            self.record.outcome = outcome
            self.record.exitCode = exitCode
            do { try self.handle.synchronize() } catch { self.report(error) }
            do { try self.handle.close() } catch { self.report(error) }
            do { try Self.write(self.record, to: self.metadataURL) } catch { self.report(error) }
            completion()
        }
    }
    private func report(_ error: Error) {
        guard !reportedError else { return }
        reportedError = true
        let message = L("Unable to save the execution log: {0}\n{1}", "\(error.localizedDescription)", "\(directory.path)")
        record.logError = message
        onError(message)
    }
    private static func write(_ record: ExecutionRecord, to url: URL, initial: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: url, options: initial ? .withoutOverwriting : .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
