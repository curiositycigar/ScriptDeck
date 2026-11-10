import Foundation

enum ExecutionOutcome: String, Codable {
    case running, succeeded, failed, stopped, launchFailed
    var title: String {
        switch self {
        case .running: return L("Running")
        case .succeeded: return L("Succeeded")
        case .failed: return L("Failed")
        case .stopped: return L("Stopped")
        case .launchFailed: return L("Failed to start")
        }
    }
}

struct ExecutionRecord: Codable, Identifiable {
    var version = 1
    var id: String
    var scriptID: String
    var scriptName: String
    var scriptFile: String
    var workspaceID: String?
    var workspaceName: String
    var scheduledTaskID: String?
    var startedAt: Date
    var endedAt: Date?
    var outcome: ExecutionOutcome = .running
    var exitCode: Int32?
    var logFilename: String
    var logError: String?
}

struct HistoryEntry: Identifiable {
    let record: ExecutionRecord
    let metadataURL: URL
    var id: String { record.id }
    var logURL: URL { metadataURL.deletingLastPathComponent().appendingPathComponent(record.logFilename) }
    func status(activeRecordID: String?) -> String {
        record.outcome == .running && id != activeRecordID ? L("Ended unexpectedly") : record.outcome.title
    }
}

/// Older records can only be attributed when the schedule still identifies their run.
struct ScheduleHistoryScope {
    let task: ScheduledTask
    let latestRunID: String?
    let metadataPath: String?

    func contains(_ record: ExecutionRecord) -> Bool {
        if let id = record.scheduledTaskID { return id == task.id }
        return record.id == latestRunID
    }

    var directories: [URL] {
        var result = [RunLogWriter.directory(for: URL(fileURLWithPath: task.item.path))]
        if let metadataPath { result.append(URL(fileURLWithPath: metadataPath).deletingLastPathComponent()) }
        return result
    }
}
