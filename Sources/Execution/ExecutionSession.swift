import AppKit
import Combine
import Darwin
import SwiftTerm

/// One execution owns its PTY, terminal, process controls and log writer.
@MainActor
final class ExecutionSession: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    private(set) var startedAt = Date()
    private(set) var endedAt: Date?
    @Published private(set) var outcome: ExecutionOutcome?
    @Published private(set) var isRunning = false
    @Published private(set) var activeName = ""
    @Published private(set) var workspaceID: String?
    @Published private(set) var workspaceName = ""
    @Published private(set) var scriptID: String?
    @Published private(set) var status = L("Ready to run")
    @Published private(set) var stopping = false
    @Published private(set) var hasOutput = false
    private(set) var terminalView: RunnerTerminalView
    private let preferences: AppPreferences
    private var fontSubscription: AnyCancellable?

    init(preferences: AppPreferences? = nil) {
        let preferences = preferences ?? AppPreferences()
        self.preferences = preferences
        terminalView = RunnerTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 240),
                                          fontSize: preferences.terminalFontSize,
                                          scrollback: preferences.terminalScrollback)
        super.init()
        fontSubscription = preferences.$terminalFontSize.dropFirst().sink { [weak self] size in
            self?.terminalView.font = .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
    @Published private(set) var historyRevision = 0
    @Published private(set) var recordID: String?
    @Published private(set) var historyIssue: String?
    private var logWriter: RunLogWriter?
    @Published private(set) var pendingHistoryRecordIDs = Set<String>()
    var protectedHistoryRecordIDs: Set<String> {
        pendingHistoryRecordIDs.union(isRunning ? Set([recordID].compactMap { $0 }) : [])
    }
    private var pendingHistoryWrites = 0
    private var historyWaiters: [@MainActor @Sendable () -> Void] = []
    var hasPendingHistoryWrites: Bool { pendingHistoryWrites > 0 }

    func afterHistorySaved(_ completion: @escaping @MainActor @Sendable () -> Void) {
        if pendingHistoryWrites == 0 { DispatchQueue.main.async { completion() } }
        else { historyWaiters.append(completion) }
    }
    /// ECHO-off is a hint for hidden input, not a claim that the process needs a password.
    var needsHiddenInputNotice: Bool {
        interactiveChannel != nil && isRunning && !stopping && terminalView.acceptsInput
            && terminalView.isInputEchoDisabled
    }

    @Published var showingTerminalLog = false
    @Published private(set) var interactiveChannel: InteractiveChannel?
    private var stopRequested = false
    private(set) var scheduledTaskID: String?
    private var scheduleRoot: URL?
    private var scheduledLogOffset: UInt64 = 0
    private var scheduledState: ScheduleRuntime?
    var isBackgroundExecution: Bool { scheduledTaskID != nil }

    func updateScheduled(task: ScheduledTask, state: ScheduleRuntime, root: URL, running: Bool) {
        scheduledState = state
        scheduledTaskID = task.id
        scheduleRoot = root
        recordID = state.runID
        activeName = task.name
        workspaceID = task.workspaceID
        workspaceName = task.workspaceName
        scriptID = task.item.id
        startedAt = state.startedAt ?? Date()
        endedAt = state.endedAt
        outcome = state.outcome
        isRunning = running && state.outcome == .running
        status = isRunning ? (stopping ? L("Stopping") : L("Scheduled task running in background")) : state.message ?? state.outcome?.title ?? L("Waiting to run")
        if !isRunning { stopping = false }
        terminalView.acceptsInput = false
        if let path = state.logPath, let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: scheduledLogOffset)
            if let data = try? handle.read(upToCount: 256 * 1024), !data.isEmpty {
                scheduledLogOffset += UInt64(data.count)
                terminalView.feed(byteArray: data.flatMap { $0 == 10 ? [UInt8(13), UInt8(10)] : [$0] }[...])
                hasOutput = true
            }
        }
    }

    func reconcilePreviousScheduled(task: ScheduledTask, root: URL) {
        guard var state = scheduledState else { return }
        if let path = state.metadataPath {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let record = try? decoder.decode(ExecutionRecord.self, from: data) {
                state.outcome = record.outcome == .running ? .failed : record.outcome
                state.endedAt = record.endedAt ?? Date()
                state.message = record.outcome == .running ? L("The background executor ended unexpectedly") : record.outcome.title
            }
        }
        if state.outcome == .running { state.outcome = .failed; state.endedAt = Date(); state.message = L("The background executor ended unexpectedly") }
        updateScheduled(task: task, state: state, root: root, running: false)
    }

    // Snapshot the rendered buffer, never record the user's keyboard input.
    var output: String { exportText() }
    func exportText() -> String {
        guard hasOutput else { return "" }
        return String(decoding: terminalView.getBufferAsData(), as: UTF8.self)
    }

    func event(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let message = "[\(formatter.string(from: Date()))] \(text)"
        terminalView.feed(text: "\u{1B}\\\u{1B}[0m" + message + "\r\n")
        logWriter?.appendMessage(message)
        hasOutput = true
    }

    func run(item: ScriptItem, arguments: [String], workspaceID: String? = nil, workspaceName: String = "") throws {
        guard recordID == nil else { throw RunnerError(message: L("An execution session can only be started once.")) }
        let command = try executionCommand(item, arguments: arguments)
        guard let executable = Bundle.main.executableURL?.path else {
            throw RunnerError(message: L("Unable to find the app's script execution entry point."))
        }
        let channel = item.interactiveUI ? try InteractiveChannel() : nil
        defer { if recordID == nil { channel?.finish() } }
        let runID = UUID().uuidString
        let startDate = Date()
        let writer: RunLogWriter
        do {
            writer = try RunLogWriter(id: runID, item: item, workspaceID: workspaceID, workspaceName: workspaceName,
                                      startedAt: startDate) { [weak self] message in
                DispatchQueue.main.async {
                    guard let self, self.recordID == runID else { return }
                    self.historyIssue = message
                }
            }
        } catch { throw RunnerError(message: L("Unable to create the execution log. The task was not started: {0}", "\(error.localizedDescription)")) }
        interactiveChannel = channel
        logWriter = writer
        recordID = runID
        historyIssue = nil
        HistoryDirectories.shared.remember(writer.directory)
        historyRevision += 1
        let initialFrame = NSRect(x: 0, y: 0, width: max(640, terminalView.bounds.width),
                                  height: max(180, terminalView.bounds.height))
        let view = RunnerTerminalView(frame: initialFrame, fontSize: preferences.terminalFontSize,
                                      scrollback: preferences.terminalScrollback)
        view.onOutput = { [weak writer] data in writer?.append(data) }
        view.onExit = { [weak self, weak view] code in
            guard let self, let view else { return }
            self.processTerminated(source: view, exitCode: code)
        }
        view.onFailure = { [weak self, weak view] error in
            guard let self, let view else { return }
            self.processFailedToStart(source: view, error: error)
        }
        terminalView = view
        hasOutput = false
        activeName = item.name
        scriptID = item.id
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        status = L("Running")
        stopping = false
        stopRequested = false
        startedAt = startDate
        outcome = .running
        isRunning = true
        event(L("Command: {0}", command.argv.map(shellQuote).joined(separator: " ")))
        if !workspaceName.isEmpty { event(L("Workspace: {0}", workspaceName)) }
        event(L("Started: {0}", "\(item.name)"))
        event(L("Working directory: {0}", "\(command.directory)"))
        // Keep arguments out of the application metadata; scripts may receive secrets.
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["PYTHONUNBUFFERED"] = "1"
        environment.removeValue(forKey: "NO_COLOR")
        environment.removeValue(forKey: "SCRIPTDECK_UI_SESSION")
        environment.removeValue(forKey: "SCRIPTDECK_UI")
        environment["SCRIPTDECK_LANGUAGE"] = L10n.language
        if let channel {
            environment["SCRIPTDECK_UI_SESSION"] = channel.directory.path
            environment["SCRIPTDECK_UI"] = executable
        }
        view.acceptsInput = true
        view.startProcess(
            executable: executable,
            args: ["--execute-script", command.directory] + command.argv,
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: command.directory
        )
    }

    func focusTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.terminalView.window?.makeFirstResponder(self.terminalView)
        }
    }

    /// Ctrl+C is delivered by the terminal line discipline to the foreground job.
    func interrupt() {
        if isBackgroundExecution { stop(); return }
        guard isRunning else { return }
        terminalView.process.send(data: [UInt8(3)][...])
        focusTerminal()
    }

    /// Stop both the foreground job and the session's original process group.
    func stop(force: Bool = false) {
        if let scheduledTaskID, let scheduleRoot, let recordID {
            guard isRunning else { return }
            do {
                try (recordID + (force ? ":force" : "")).write(to: ScheduleFiles.stop(scheduleRoot, scheduledTaskID), atomically: true, encoding: .utf8)
                stopping = true
                status = force ? L("Force stopping") : L("Stopping")
            } catch { historyIssue = L("Unable to request a background task stop: {0}", "\(error.localizedDescription)") }
            return
        }
        let process = terminalView.process!
        guard isRunning, process.running, !stopping || force else { return }
        let pid = process.shellPid
        guard pid > 0 else { return }
        interactiveChannel?.finish()
        stopRequested = true
        stopping = true
        status = force ? L("Force stopping") : L("Stopping")
        let signal = force ? SIGKILL : SIGTERM
        let foreground = tcgetpgrp(process.childfd)
        if foreground > 0, foreground != pid, getsid(foreground) == pid {
            kill(-foreground, signal)
        }
        if getpgid(pid) == pid { kill(-pid, signal) }
        else { kill(pid, signal) }
    }

    func clearOutput() {
        guard !isRunning else { return }
        terminalView.resetToInitialState()
        hasOutput = false
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        guard source === terminalView else { return }
        status = L("Failed to start")
        event(L("Unable to start the task: {0}", "\(error)"))
        complete(outcome: .launchFailed, exitCode: nil)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }
        if stopRequested { status = L("Stopped") }
        else if let code = exitCode { status = code == 0 ? L("Completed successfully") : L("Failed (exit code {0})", "\(code)") }
        else { status = L("The process was terminated by a signal or its status is unavailable") }
        terminalView.feed(text: "\r\n")
        event(L("{0}, elapsed {1} seconds", "\(status)", "\(Int(Date().timeIntervalSince(startedAt)))"))
        complete(outcome: stopRequested ? .stopped : exitCode == 0 ? .succeeded : .failed, exitCode: exitCode)
    }

    private func complete(outcome: ExecutionOutcome, exitCode: Int32?) {
        self.outcome = outcome
        interactiveChannel?.receive()
        interactiveChannel?.finish()
        if let writer = logWriter {
            pendingHistoryWrites += 1
            let finishingRecordID = writer.id
            pendingHistoryRecordIDs.insert(finishingRecordID)
            writer.finish(outcome: outcome, exitCode: exitCode) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingHistoryRecordIDs.remove(finishingRecordID)
                    self.historyRevision += 1
                    self.pendingHistoryWrites -= 1
                    if self.pendingHistoryWrites == 0 {
                        let waiters = self.historyWaiters
                        self.historyWaiters = []
                        waiters.forEach { $0() }
                    }
                }
            }
        }
        logWriter = nil
        terminalView.acceptsInput = false
        endedAt = Date()
        isRunning = false
        stopping = false
    }
}
