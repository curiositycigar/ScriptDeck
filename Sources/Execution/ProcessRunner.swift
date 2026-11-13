import AppKit
import Combine

/// App-wide execution registry. Global state is aggregated across every session;
/// execution windows bind controls and credential fills to their own session.
@MainActor
final class ProcessRunner: ObservableObject {
    @Published private(set) var sessions: [ExecutionSession] = []
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var launchRevision = 0
    @Published private(set) var historyRevision = 0
    @Published private(set) var hiddenOutputRecordIDs = Set<String>()
    private var executionWindows: [UUID: ExecutionWindowController] = [:]

    func showExecution(_ session: ExecutionSession) {
        guard sessions.contains(where: { $0 === session }) else { return }
        select(session.id)
        let controller = executionWindows[session.id] ?? ExecutionWindowController(session: session, runner: self)
        executionWindows[session.id] = controller
        controller.present()
    }

    var keyExecutionIsRunning: Bool {
        executionWindows.values.contains { $0.window === NSApp.keyWindow && $0.session.isRunning }
    }

    func stopKeyExecution() {
        guard let session = executionWindows.values.first(where: { $0.window === NSApp.keyWindow })?.session else { return }
        session.stop(force: session.stopping)
    }

    func stopAndCloseExecution(_ session: ExecutionSession) {
        session.stop(force: session.stopping)
        executionWindows[session.id]?.close()
    }

    func showSelectedExecution() {
        guard let session = sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.last else { return }
        showExecution(session)
    }

    private let preferences: AppPreferences
    private let idleSession: ExecutionSession
    private var subscriptions: [UUID: Set<AnyCancellable>] = [:]
    private var importedScheduledRuns = Set<String>()
    var foregroundRunningSessions: [ExecutionSession] { runningSessions.filter { !$0.isBackgroundExecution } }

    func synchronizeScheduled(task: ScheduledTask, state: ScheduleRuntime, root: URL, running: Bool) {
        guard let runID = state.runID else { return }
        for session in sessions where session.scheduledTaskID == task.id && session.recordID != runID && session.isRunning {
            session.reconcilePreviousScheduled(task: task, root: root)
            historyRevision += 1
        }
        if let session = sessions.first(where: { $0.recordID == runID }) {
            let changed = session.isRunning != running || session.outcome != state.outcome
            session.updateScheduled(task: task, state: state, root: root, running: running)
            if changed { historyRevision += 1 }
        } else if !importedScheduledRuns.contains(runID) {
            if !running, let path = state.metadataPath, !FileManager.default.fileExists(atPath: path) { return }
            HistoryDirectories.shared.remember(RunLogWriter.directory(for: URL(fileURLWithPath: task.item.path)))
            importedScheduledRuns.insert(runID)
            let session = ExecutionSession(preferences: preferences)
            session.updateScheduled(task: task, state: state, root: root, running: running)
            sessions.append(session)
            var observers = Set<AnyCancellable>()
            session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
            subscriptions[session.id] = observers
            if selectedSessionID == nil { selectedSessionID = session.id }
            if running { launchRevision += 1 }
            historyRevision += 1
        }
    }

    init(preferences: AppPreferences? = nil) {
        let preferences = preferences ?? AppPreferences()
        self.preferences = preferences
        idleSession = ExecutionSession(preferences: preferences)
    }

    var selectedSession: ExecutionSession {
        sessions.first { $0.id == selectedSessionID } ?? idleSession
    }
    var runningSessions: [ExecutionSession] { sessions.filter(\.isRunning) }
    var completedSessions: [ExecutionSession] { sessions.filter { !$0.isRunning }.reversed() }
    var isRunning: Bool { sessions.contains(where: \.isRunning) }
    var selectedIsRunning: Bool { selectedSession.isRunning }
    var activeRecordIDs: Set<String> { Set(runningSessions.compactMap(\.recordID)) }
    var protectedHistoryRecordIDs: Set<String> {
        sessions.reduce(into: Set<String>()) { $0.formUnion($1.protectedHistoryRecordIDs) }
    }
    var hasPendingHistoryWrites: Bool { sessions.contains(where: \.hasPendingHistoryWrites) }
    func isWorkspaceRunning(_ id: String) -> Bool { runningSessions.contains { $0.workspaceID == id } }
    func protectedWorkspaceID(for id: String) -> String? { isWorkspaceRunning(id) ? id : nil }
    func activeSessions(workspaceID: String?, scriptID: String) -> [ExecutionSession] {
        runningSessions.filter { $0.workspaceID == workspaceID && $0.scriptID == scriptID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func isActive(workspaceID: String, scriptID: String) -> Bool {
        !activeSessions(workspaceID: workspaceID, scriptID: scriptID).isEmpty
    }

    // Selected-session accessors keep terminal presentation separate from global activity.
    var activeName: String { selectedSession.activeName }
    var workspaceID: String? { selectedSession.workspaceID }
    var workspaceName: String { selectedSession.workspaceName }
    var scriptID: String? { selectedSession.scriptID }
    var status: String { selectedSession.status }
    var stopping: Bool { selectedSession.stopping }
    var hasOutput: Bool { selectedSession.hasOutput }
    var sessionID: UUID { selectedSession.id }
    var terminalView: RunnerTerminalView { selectedSession.terminalView }
    var recordID: String? { selectedSession.recordID }
    var historyIssue: String? { selectedSession.historyIssue }
    var output: String { exportText() }
    func exportText() -> String { selectedSession.exportText() }
    func clearOutput() { selectedSession.clearOutput() }
    func interrupt() { selectedSession.interrupt() }
    func stop(force: Bool = false) { selectedSession.stop(force: force) }
    func focusTerminal() { selectedSession.focusTerminal() }

    func validateCredentialTarget(_ id: UUID) throws {
        guard let session = sessions.first(where: { $0.id == id }),
              session.isRunning, !session.stopping, !session.isBackgroundExecution,
              session.terminalView.acceptsInput else {
            throw RunnerError(message: L("The target terminal is no longer accepting input."))
        }
        guard session.terminalView.isInputEchoDisabled else {
            throw RunnerError(message: L("Password not sent. Wait until the script requests hidden password input."))
        }
    }

    func fillPassword(_ password: String, sessionID: UUID, appendReturn: Bool) async throws {
        try CredentialStore.validatePassword(password)
        try validateCredentialTarget(sessionID)
        guard let terminal = sessions.first(where: { $0.id == sessionID })?.terminalView else { return }
        let data = Array((password + (appendReturn ? "\r" : "")).utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            terminal.process.send(data: data[...]) { result in
                switch result {
                case .success(let written) where written == data.count: continuation.resume()
                default: continuation.resume(throwing: RunnerError(message: L("Unable to fill the password. Check the terminal before trying again.")))
                }
            }
        }
    }

    func select(_ id: UUID?) {
        if let id, !sessions.contains(where: { $0.id == id }) { return }
        guard selectedSessionID != id else { return }
        selectedSessionID = id
    }

    func historyDidRemove(_ recordIDs: Set<String>) {
        guard !recordIDs.isEmpty else { return }
        let removed = sessions.filter { session in
            session.recordID.map { recordIDs.contains($0) } == true && !session.isRunning && !session.hasPendingHistoryWrites
        }
        removeSessions(Set(removed.map(\.id)))
        hideSavedOutputRecords(recordIDs)
        historyRevision += 1
    }

    @discardableResult
    func run(item: ScriptItem, arguments: [String], workspaceID: String? = nil,
             workspaceName: String = "", workspaceDirectory: String? = nil) throws -> ExecutionSession {
        var item = item
        item.allowsMultipleInstances = try ScriptInstanceLease.allowsMultipleInstances(for: item, workspaceDirectory: workspaceDirectory)
        if !item.allowsMultipleInstances, let existing = activeSessions(workspaceID: workspaceID, scriptID: item.id).first {
            return existing
        }
        let selectNewSession = !isRunning || selectedSessionID == nil
        let session = ExecutionSession(preferences: preferences)
        try session.run(item: item, arguments: arguments, workspaceID: workspaceID, workspaceName: workspaceName)
        sessions.append(session)
        var observers = Set<AnyCancellable>()
        session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &observers)
        session.$historyRevision.dropFirst().sink { [weak self] _ in
            self?.historyRevision += 1
        }.store(in: &observers)
        subscriptions[session.id] = observers
        if selectNewSession { selectedSessionID = session.id }
        launchRevision += 1
        historyRevision += 1
        return session
    }

    /// Removing a session never deletes its persisted execution history.
    @discardableResult
    func dismissSession(_ id: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == id }),
              !session.isRunning, !session.hasPendingHistoryWrites else { return false }
        if let recordID = session.recordID { hideSavedOutputRecords([recordID]) }
        removeSessions([id])
        return true
    }

    /// Release terminal buffers only when execution and its log finalization are complete.
    func dismissCompletedSessions(savedIDs: Set<String> = []) {
        let removable = sessions.filter { !$0.isRunning && !$0.hasPendingHistoryWrites }
        hideSavedOutputRecords(savedIDs.union(removable.compactMap(\.recordID)))
        removeSessions(Set(removable.map(\.id)))
    }

    func hideSavedOutputRecords(_ recordIDs: Set<String>) {
        guard !recordIDs.isSubset(of: hiddenOutputRecordIDs) else { return }
        hiddenOutputRecordIDs.formUnion(recordIDs)
    }

    private func removeSessions(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sessions.removeAll { ids.contains($0.id) }
        for id in ids {
            subscriptions.removeValue(forKey: id)
            if let controller = executionWindows.removeValue(forKey: id) {
                controller.close()
                controller.window?.contentView = nil
            }
        }
        if let selectedSessionID, ids.contains(selectedSessionID) {
            self.selectedSessionID = runningSessions.first?.id ?? sessions.last?.id
        }
    }

    func afterHistorySaved(_ completion: @escaping @MainActor @Sendable () -> Void) {
        let pending = sessions.filter(\.hasPendingHistoryWrites)
        guard !pending.isEmpty else { DispatchQueue.main.async { completion() }; return }
        var remaining = pending.count
        for session in pending {
            session.afterHistorySaved {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }
}
