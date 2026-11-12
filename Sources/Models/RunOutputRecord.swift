import Foundation

@MainActor
enum RunOutputRecord {
    case live(ExecutionSession)
    case saved(HistoryEntry)

    static func merge(sessions: [ExecutionSession], history: [HistoryEntry], hiding hiddenIDs: Set<String>) -> [Self] {
        let live = sessions.reversed().map(Self.live)
        let liveIDs = Set(live.map(\.id))
        let saved = history.filter { !liveIDs.contains($0.id) }.map(Self.saved)
        return (live + saved).filter { !hiddenIDs.contains($0.id) }.sorted { $0.startedAt > $1.startedAt }
    }

    var session: ExecutionSession? {
        if case .live(let session) = self { return session }
        return nil
    }

    private var entry: HistoryEntry? {
        if case .saved(let entry) = self { return entry }
        return nil
    }

    var id: String {
        switch self {
        case .live(let session): return session.recordID ?? session.id.uuidString
        case .saved(let entry): return entry.id
        }
    }
    var name: String {
        switch self {
        case .live(let session): return session.activeName
        case .saved(let entry): return entry.record.scriptName
        }
    }
    var workspaceName: String {
        switch self {
        case .live(let session): return session.workspaceName
        case .saved(let entry): return entry.record.workspaceName
        }
    }
    var startedAt: Date {
        switch self {
        case .live(let session): return session.startedAt
        case .saved(let entry): return entry.record.startedAt
        }
    }
    var endedAt: Date? {
        if let session { return session.endedAt }
        return entry?.record.endedAt
    }
    var outcome: ExecutionOutcome? {
        if let session { return session.outcome }
        return entry?.record.outcome == .running ? .failed : entry?.record.outcome
    }
    var status: String {
        switch self {
        case .live(let session): return session.status
        case .saved(let entry): return entry.status(activeRecordID: nil)
        }
    }
    var isRunning: Bool { session?.isRunning == true }
    var canHide: Bool { !isRunning && session?.hasPendingHistoryWrites != true }
}

