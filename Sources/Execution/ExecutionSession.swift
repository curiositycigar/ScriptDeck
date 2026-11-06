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
    @Published private(set) var status = "等待运行"
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
        status = isRunning ? (stopping ? "正在停止" : "定时执行中（后台）") : state.message ?? state.outcome?.title ?? "等待执行"
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
                state.message = record.outcome == .running ? "后台执行器未正常结束" : record.outcome.title
            }
        }
        if state.outcome == .running { state.outcome = .failed; state.endedAt = Date(); state.message = "后台执行器未正常结束" }
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
        guard recordID == nil else { throw RunnerError(message: "执行会话不能重复启动。") }
        let command = try executionCommand(item, arguments: arguments)
        guard let executable = Bundle.main.executableURL?.path else {
            throw RunnerError(message: "找不到应用的脚本执行入口。")
        }
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
        } catch { throw RunnerError(message: "无法创建本地执行日志，任务未启动：\(error.localizedDescription)") }
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
        status = "运行中"
        stopping = false
        stopRequested = false
        startedAt = startDate
        outcome = .running
        isRunning = true
        if !workspaceName.isEmpty { event("Workspace：\(workspaceName)") }
        event("开始：\(item.name)")
        event("工作目录：\(command.directory)")
        // Keep arguments out of the application metadata; scripts may receive secrets.
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["PYTHONUNBUFFERED"] = "1"
        environment.removeValue(forKey: "NO_COLOR")
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
                status = force ? "正在强制停止" : "正在停止"
            } catch { historyIssue = "无法请求停止后台任务：\(error.localizedDescription)" }
            return
        }
        let process = terminalView.process!
        guard isRunning, process.running, !stopping || force else { return }
        let pid = process.shellPid
        guard pid > 0 else { return }
        stopRequested = true
        stopping = true
        status = force ? "正在强制停止" : "正在停止"
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
        status = "启动失败"
        event("无法启动任务：\(error)")
        complete(outcome: .launchFailed, exitCode: nil)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }
        if stopRequested { status = "已停止" }
        else if let code = exitCode { status = code == 0 ? "执行成功" : "执行失败（退出码 \(code)）" }
        else { status = "进程被信号终止或状态不可用" }
        terminalView.feed(text: "\r\n")
        event("\(status)，耗时 \(Int(Date().timeIntervalSince(startedAt))) 秒")
        complete(outcome: stopRequested ? .stopped : exitCode == 0 ? .succeeded : .failed, exitCode: exitCode)
    }

    private func complete(outcome: ExecutionOutcome, exitCode: Int32?) {
        self.outcome = outcome
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
