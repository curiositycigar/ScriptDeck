import Foundation
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var tasks: [ScheduledTask] = []
    @Published private(set) var states: [String: ScheduleRuntime] = [:]
    @Published private(set) var runningIDs = Set<String>()
    @Published var error: String?
    private(set) var root: URL
    private let runner: ProcessRunner
    private let service: any ScheduleService
    private var deferredUnregistrations = Set<String>()
    private var cleanedIDs = Set<String>()
    private var timer: Timer?
    private var registrationErrors: [String: String] = [:]
    private var runtimeErrors: [String: String] = [:]
    private var initialized = false

    init(runner: ProcessRunner, root: URL = ScheduleFiles.root, startMonitoring: Bool = true, service: (any ScheduleService)? = nil) {
        self.runner = runner
        self.root = root
        self.service = service ?? LaunchAgentService(root: root)
        load()
        refresh(registerSystem: false)
        if startMonitoring {
            // Installation is deferred until a task exists, so merely opening the app creates no agent.
            timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }
    deinit { timer?.invalidate() }

    private func load() {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "json" {
                do {
                    let task = try ScheduleFiles.read(ScheduledTask.self, url)
                    guard UUID(uuidString: task.id) != nil, url.lastPathComponent == task.id + ".json" else {
                        throw RunnerError(message: L("The schedule ID does not match its filename."))
                    }
                    tasks.append(task)
                } catch { self.error = L("Some schedules could not be read. Their files were preserved: {0}", "\(error.localizedDescription)") }
            }
            tasks.sort { $0.createdAt < $1.createdAt }
        } catch { self.error = error.localizedDescription }
    }
    func state(for task: ScheduledTask) -> ScheduleRuntime? { states[task.id] }
    func issue(for task: ScheduledTask) -> String? { registrationErrors[task.id] ?? runtimeErrors[task.id] }
    var enabledTaskCount: Int {
        tasks.filter { $0.enabled && ($0.kind != .once || states[$0.id]?.nextFireAt != nil) }.count
    }
    var failedTaskCount: Int {
        tasks.filter { issue(for: $0) != nil || states[$0.id]?.outcome == .launchFailed || states[$0.id]?.outcome == .failed }.count
    }
    var nextTask: (ScheduledTask, Date)? {
        tasks.compactMap { task -> (ScheduledTask, Date)? in
            guard task.enabled, let date = states[task.id]?.nextFireAt else { return nil }
            return (task, date)
        }.min { $0.1 < $1.1 }
    }
    func refresh(registerSystem: Bool = true) {
        if registerSystem && !initialized && !tasks.isEmpty {
            initialized = true
            do { try service.installHelper() }
            catch { self.error = error.localizedDescription; return }
            for task in tasks where !task.enabled { deferredUnregistrations.insert(task.id) }
            for task in tasks where task.enabled {
                if task.kind == .once, let state = states[task.id], state.runID != nil, state.nextFireAt == nil {
                    deferredUnregistrations.insert(task.id)
                    continue
                }
                do { if !service.isLoaded(task.id) { try service.register(task) } }
                catch { registrationErrors[task.id] = error.localizedDescription }
            }
        }
        var updated: [String: ScheduleRuntime] = [:]
        var running = Set<String>()
        for task in tasks {
            let snapshot: (state: ScheduleRuntime, running: Bool)
            do {
                snapshot = try ScheduleFiles.snapshot(root: root, id: task.id)
                runtimeErrors[task.id] = nil
            } catch {
                runtimeErrors[task.id] = L("Unable to read execution state. Edit and save the task again: {0}", "\(error.localizedDescription)")
                continue
            }
            let state = snapshot.state
            if snapshot.running { running.insert(task.id) }
            if registerSystem && !cleanedIDs.contains(task.id) && task.kind == .once && state.runID != nil && state.nextFireAt == nil && !snapshot.running {
                deferredUnregistrations.insert(task.id)
            }
            updated[task.id] = state
            runner.synchronizeScheduled(task: task, state: state, root: root, running: running.contains(task.id))
        }
        for id in deferredUnregistrations where registerSystem && !running.contains(id) {
            do { try service.unregister(id); deferredUnregistrations.remove(id); cleanedIDs.insert(id) }
            catch { registrationErrors[id] = error.localizedDescription }
        }
        states = updated
        runningIDs = running
    }
    /// Add source locations to older schedules and follow workspace relocations.
    /// The revision and occurrence ledger remain stable.
    func synchronizeWorkspaces(_ workspaces: [Workspace]) {
        for index in tasks.indices {
            guard let workspace = workspaces.first(where: { $0.id == tasks[index].workspaceID }),
                  tasks[index].workspaceDirectory != workspace.directory else { continue }
            var task = tasks[index]
            task.workspaceDirectory = workspace.directory
            do {
                try ScheduleFiles.write(task, ScheduleFiles.definition(root, task.id))
                tasks[index] = task
            } catch { self.error = error.localizedDescription }
        }
    }

    func save(_ input: ScheduledTask) throws {
        guard UUID(uuidString: input.id) != nil else { throw RunnerError(message: L("Invalid schedule ID.")) }
        guard !ScheduleFiles.isRunning(root: root, id: input.id) else { throw RunnerError(message: L("Wait for this scheduled task to finish before editing it.")) }
        var task = input
        task.revision = UUID().uuidString
        task.createdAt = Date()
        task.date = task.calendar.dateInterval(of: .minute, for: task.date)?.start ?? task.date
        try task.validate()
        let old = tasks.first { $0.id == task.id }
        let oldState = try? ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(root, task.id))
        try service.installHelper()
        // Disarm before unregistering. bootout must never be used to pause an executing script.
        if var old { old.enabled = false; try ScheduleFiles.write(old, ScheduleFiles.definition(root, old.id)) }
        if ScheduleFiles.isRunning(root: root, id: task.id) {
            if let old { try? ScheduleFiles.write(old, ScheduleFiles.definition(root, old.id)) }
            throw RunnerError(message: L("The task just started. Wait for it to finish and try again."))
        }
        do {
            try service.unregister(task.id)
            try ScheduleFiles.write(task, ScheduleFiles.definition(root, task.id))
            let state = ScheduleRuntime(revision: task.revision, nextFireAt: task.kind == .once ? task.date : task.nextDate(after: Date()))
            try ScheduleFiles.write(state, ScheduleFiles.runtime(root, task.id))
            if task.enabled { try service.register(task) }
        } catch {
            // Never leave an enabled definition after an incomplete registration.
            var disabled = task
            disabled.enabled = false
            try? ScheduleFiles.write(disabled, ScheduleFiles.definition(root, task.id))
            try? service.unregister(task.id)
            if let old {
                try? ScheduleFiles.write(old, ScheduleFiles.definition(root, old.id))
                if let oldState { try? ScheduleFiles.write(oldState, ScheduleFiles.runtime(root, old.id)) }
                if old.enabled {
                    do { try service.register(old) }
                    catch {
                        var paused = old
                        paused.enabled = false
                        try? ScheduleFiles.write(paused, ScheduleFiles.definition(root, old.id))
                        if let index = tasks.firstIndex(where: { $0.id == old.id }) { tasks[index] = paused }
                        registrationErrors[old.id] = L("Unable to restore system registration; paused: {0}", "\(error.localizedDescription)")
                    }
                }
            } else {
                try? FileManager.default.removeItem(at: ScheduleFiles.definition(root, task.id))
                try? FileManager.default.removeItem(at: ScheduleFiles.runtime(root, task.id))
            }
            throw error
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        registrationErrors[task.id] = nil
        cleanedIDs.remove(task.id)
        deferredUnregistrations.remove(task.id)
        initialized = true
        HistoryDirectories.shared.remember(RunLogWriter.directory(for: URL(fileURLWithPath: task.item.path)))
        refresh()
    }
    func setEnabled(_ task: ScheduledTask, _ enabled: Bool) throws {
        if enabled {
            var task = task
            task.enabled = true
            try save(task)
        } else {
            var paused = task
            paused.enabled = false
            try ScheduleFiles.write(paused, ScheduleFiles.definition(root, task.id))
            if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = paused }
            deferredUnregistrations.insert(task.id)
            if !ScheduleFiles.isRunning(root: root, id: task.id) {
                try service.unregister(task.id)
                deferredUnregistrations.remove(task.id)
            }
            refresh()
        }
    }
    func remove(_ task: ScheduledTask) throws {
        guard !ScheduleFiles.isRunning(root: root, id: task.id) else { throw RunnerError(message: L("Stop the task before deleting it.")) }
        try setEnabled(task, false)
        guard !ScheduleFiles.isRunning(root: root, id: task.id) else { throw RunnerError(message: L("The task just started. Stop it and try again.")) }
        try service.unregister(task.id)
        try FileManager.default.removeItem(at: ScheduleFiles.definition(root, task.id))
        tasks.removeAll { $0.id == task.id }
        states[task.id] = nil
        // Keep lock inodes stable; completed execution logs are always retained.
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}
