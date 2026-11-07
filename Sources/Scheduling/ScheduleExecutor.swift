import Foundation
import Darwin

/// This entry point uses no windows or application lifecycle. launchd owns its lifetime.
enum ScheduleExecutor {
    static func run(definitionURL: URL, force: Bool = false) throws {
        let root = definitionURL.deletingLastPathComponent()
        let id = definitionURL.deletingPathExtension().lastPathComponent
        guard UUID(uuidString: id) != nil else { throw RunnerError(message: L("Invalid schedule ID.")) }
        let fd = open(ScheduleFiles.lock(root, id).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RunnerError(message: L("Unable to lock the schedule.")) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return } // Never overlap the same schedule.
        let task = try ScheduleFiles.read(ScheduledTask.self, definitionURL)
        guard task.id == id, task.enabled || force else { return }
        var state: ScheduleRuntime
        if FileManager.default.fileExists(atPath: ScheduleFiles.runtime(root, id).path) {
            // A damaged occurrence ledger must not cause an already consumed task to repeat.
            state = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(root, id))
        } else {
            state = ScheduleRuntime(revision: task.revision, nextFireAt: task.kind == .once ? task.date : task.nextDate(after: task.createdAt))
        }
        if state.revision != task.revision {
            state = ScheduleRuntime(revision: task.revision, nextFireAt: task.kind == .once ? task.date : task.nextDate(after: task.createdAt))
        }
        let now = Date()
        guard force || (state.nextFireAt.map { $0 <= now.addingTimeInterval(1) } ?? false) else { return }
        // Claim this occurrence before launching: a crash must not repeat a one-time execution.
        if !force { state.nextFireAt = task.kind == .once ? nil : task.nextDate(after: max(now, state.nextFireAt ?? now)) }
        state.runID = UUID().uuidString
        state.startedAt = now
        state.endedAt = nil
        state.outcome = .running
        state.message = nil
        state.logPath = nil
        state.metadataPath = nil
        try ScheduleFiles.write(state, ScheduleFiles.runtime(root, id))
        var writer: RunLogWriter?
        var result: ExecutionOutcome = .launchFailed
        var exitCode: Int32?
        do {
            guard task.item.path.hasPrefix("/") else { throw RunnerError(message: L("The script must use an absolute path.")) }
            let log = try RunLogWriter(id: state.runID!, item: task.item, workspaceID: task.workspaceID,
                                      workspaceName: task.workspaceName, startedAt: now) { message in
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
            writer = log
            state.logPath = log.logURL.path
            state.metadataPath = log.metadataURL.path
            try ScheduleFiles.write(state, ScheduleFiles.runtime(root, id))
            try task.validate(requireFuture: false)
            let command = try executionCommand(task.item, arguments: scriptArguments(for: task.item, values: task.values))
            log.appendMessage(L("Command: {0}", command.argv.map(shellQuote).joined(separator: " ")))
            log.appendMessage(L("Scheduled task: {0} · {1}", "\(task.name)", "\(task.workspaceName)"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--execute-script", command.directory] + command.argv
            process.currentDirectoryURL = URL(fileURLWithPath: command.directory)
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["TERM"] = "dumb"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            try? pipe.fileHandleForWriting.close()
            let readFD = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)
            defer { try? pipe.fileHandleForReading.close() }
            var bytes = [UInt8](repeating: 0, count: 65536)
            func drain() -> Bool {
                for _ in 0..<32 {
                    let count = read(readFD, &bytes, bytes.count)
                    if count > 0 { log.append(Data(bytes.prefix(count))) }
                    else { return count == 0 }
                }
                return false
            }
            var stopped = false
            var forceStopped = false
            while process.isRunning {
                _ = drain()
                if let request = try? String(contentsOf: ScheduleFiles.stop(root, id), encoding: .utf8),
                   request == state.runID! || request == state.runID! + ":force" {
                    let force = request.hasSuffix(":force")
                    if !stopped || (force && !forceStopped) {
                        let pid = process.processIdentifier
                        if getpgid(pid) == pid { kill(-pid, force ? SIGKILL : SIGTERM) }
                        else { kill(pid, force ? SIGKILL : SIGTERM) }
                        stopped = true
                        forceStopped = force
                    }
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            process.waitUntilExit()
            // Descendants holding stdout open must not prevent finalization forever.
            let drainDeadline = Date().addingTimeInterval(2)
            while !drain() && Date() < drainDeadline { Thread.sleep(forTimeInterval: 0.02) }
            exitCode = process.terminationStatus
            result = stopped ? .stopped : process.terminationReason == .exit && exitCode == 0 ? .succeeded : .failed
            state.message = result.title
            log.appendMessage(L("{0}, elapsed {1} seconds", "\(result.title)", "\(Int(Date().timeIntervalSince(now)))"))
        } catch {
            state.message = error.localizedDescription
            writer?.appendMessage(L("Failed to start: {0}", "\(error.localizedDescription)"))
        }
        if let writer {
            let finished = DispatchSemaphore(value: 0)
            writer.finish(outcome: result, exitCode: exitCode) { finished.signal() }
            finished.wait()
        }
        state.outcome = result
        state.endedAt = Date()
        try ScheduleFiles.write(state, ScheduleFiles.runtime(root, id))
        try? FileManager.default.removeItem(at: ScheduleFiles.stop(root, id))
    }
}
