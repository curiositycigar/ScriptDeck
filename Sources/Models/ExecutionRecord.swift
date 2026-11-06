import Foundation

enum ExecutionOutcome: String, Codable {
    case running, succeeded, failed, stopped, launchFailed
    var title: String {
        switch self {
        case .running: return "运行中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .stopped: return "已停止"
        case .launchFailed: return "启动失败"
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
        record.outcome == .running && id != activeRecordID ? "未正常结束" : record.outcome.title
    }
}
