import Foundation
import AppKit
import SwiftUI

@MainActor func runScriptInstanceSelfTests(root: URL) throws {
    let directory = root.appendingPathComponent("instance-fixtures")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("instances.sh")
    try "printf 'instance-ready\\n'\nwhile true; do sleep 1; done\n".write(to: source, atomically: true, encoding: .utf8)
    var item = ScriptItem.importing(source)
    item.name = "Instance Demo"
    let legacy = Data(#"{"id":"legacy","name":"Legacy","file":"legacy.sh"}"#.utf8)
    let legacyItem = try JSONDecoder().decode(ScriptItem.self, from: legacy)
    check(!legacyItem.allowsMultipleInstances,
          "Legacy script configurations default to single-instance execution")
    let workspaceID = UUID().uuidString
    let runner = ProcessRunner()
    let observer = ProcessRunner()
    var children: [(process: Process, task: ScheduledTask)] = []

    func startSchedule(snapshot: ScriptItem, library: URL? = nil) throws -> (Process, ScheduledTask) {
        let task = ScheduledTask(name: "Instance Schedule", workspaceID: workspaceID, workspaceName: "Instance Tests",
                                 item: snapshot, values: [:], date: Date().addingTimeInterval(-5),
                                 workspaceDirectory: library?.path)
        try ScheduleFiles.write(task, ScheduleFiles.definition(directory, task.id))
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--run-schedule", ScheduleFiles.definition(directory, task.id).path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        children.append((process, task))
        return (process, task)
    }
    func wait(_ process: Process) { pump(until: { !process.isRunning }, timeout: 10) }
    func state(_ task: ScheduledTask) throws -> ScheduleRuntime {
        try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, task.id))
    }
    func assertBlocked(_ process: Process, _ task: ScheduledTask) throws {
        wait(process)
        let runtime = try state(task)
        check(runtime.outcome == .launchFailed && runtime.nextFireAt == nil,
              "A conflicting one-time schedule records a failed launch and consumes its occurrence")
        let log = try String(contentsOfFile: runtime.logPath!, encoding: .utf8)
        check(!log.contains("instance-ready") && log.contains(L("This script already has a running instance. Open its current instance to view progress.")),
              "Blocked schedule launches never execute the script")
    }
    defer {
        for session in runner.runningSessions + observer.runningSessions { session.stop(force: true) }
        for child in children where child.process.isRunning {
            if let runtime = try? state(child.task), let id = runtime.runID {
                try? (id + ":force").write(to: ScheduleFiles.stop(directory, child.task.id), atomically: true, encoding: .utf8)
            }
        }
        pump(until: { !runner.isRunning && !observer.isRunning && children.allSatisfy { !$0.process.isRunning } }, timeout: 10)
        var saved = false
        runner.afterHistorySaved { observer.afterHistorySaved { saved = true } }
        pump(until: { saved })
    }

    let first = try runner.run(item: item, arguments: [], workspaceID: workspaceID)
    pump(until: { first.output.contains("instance-ready") })
    let duplicate = try runner.run(item: item, arguments: ["different-parameters"], workspaceID: workspaceID)
    check(duplicate === first && runner.sessions.count == 1,
          "Repeated single-instance requests reuse the current session without creating another process or log")
    do {
        _ = try observer.run(item: item, arguments: [], workspaceID: workspaceID)
        fatalError("A second execution registry bypassed the instance lock")
    } catch { check(observer.sessions.isEmpty, "The instance lock protects independent execution registries") }
    let (blocked, blockedTask) = try startSchedule(snapshot: item)
    try assertBlocked(blocked, blockedTask)
    let migrationRunner = ProcessRunner()
    let migrationStore = ScheduleStore(runner: migrationRunner, root: directory, startMonitoring: false)
    let originalRevision = blockedTask.revision
    migrationStore.synchronizeWorkspaces([Workspace(id: workspaceID, name: "Instance Tests", directory: directory.path)])
    let migrated = try ScheduleFiles.read(ScheduledTask.self, ScheduleFiles.definition(directory, blockedTask.id))
    check(migrated.workspaceDirectory == directory.path && migrated.revision == originalRevision,
          "Older schedules gain a source location without resetting their revision or consumed occurrence")
    first.stop()
    pump(until: { !first.isRunning })
    let restarted = try observer.run(item: item, arguments: [], workspaceID: workspaceID)
    pump(until: { restarted.output.contains("instance-ready") })
    check(restarted.id != first.id, "Completing an instance releases its lock for the next run")
    restarted.stop()
    pump(until: { !restarted.isRunning })

    item.allowsMultipleInstances = true
    let restored = try JSONDecoder().decode(ScriptItem.self, from: JSONEncoder().encode(item))
    check(restored.allowsMultipleInstances,
          "The multiple-instance flag survives configuration serialization")
    let library = directory.appendingPathComponent("library.json")
    try LibraryDocument(scripts: [item]).encoded().write(to: library)
    let alpha = try runner.run(item: item, arguments: [], workspaceID: workspaceID, workspaceDirectory: directory.path)
    let beta = try runner.run(item: item, arguments: [], workspaceID: workspaceID, workspaceDirectory: directory.path)
    pump(until: { alpha.output.contains("instance-ready") && beta.output.contains("instance-ready") })
    check(alpha !== beta && runner.activeSessions(workspaceID: workspaceID, scriptID: item.id).count == 2,
          "Enabled scripts create independent parallel instances in the same workspace")
    var staleSingleSnapshot = item
    staleSingleSnapshot.allowsMultipleInstances = false
    let (parallel, parallelTask) = try startSchedule(snapshot: staleSingleSnapshot, library: directory)
    var parallelState: ScheduleRuntime?
    pump(until: {
        parallelState = try? state(parallelTask)
        return parallelState?.logPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.contains("instance-ready") == true
    })
    runner.synchronizeScheduled(task: parallelTask, state: parallelState!, root: directory, running: true)
    check(runner.activeSessions(workspaceID: workspaceID, scriptID: item.id).count == 3,
          "Instance lists include manual and scheduled runs and honor the current library policy")

    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1" {
        try captureInstanceViews(runner: runner, item: item, workspaceID: workspaceID, directory: directory)
    }
    var single = item
    single.allowsMultipleInstances = false
    try LibraryDocument(scripts: [single]).encoded().write(to: library, options: .atomic)
    let (staleParallel, staleParallelTask) = try startSchedule(snapshot: item, library: directory)
    try assertBlocked(staleParallel, staleParallelTask)
    alpha.stop()
    pump(until: { !alpha.isRunning })
    let (stillBlocked, stillBlockedTask) = try startSchedule(snapshot: item, library: directory)
    try assertBlocked(stillBlocked, stillBlockedTask)
    beta.stop()
    pump(until: { !beta.isRunning })
    let (backgroundBlocks, backgroundBlocksTask) = try startSchedule(snapshot: item, library: directory)
    try assertBlocked(backgroundBlocks, backgroundBlocksTask)
    check(parallel.isRunning, "A remaining background instance keeps single-instance launch protection active")
    try parallelState!.runID!.write(to: ScheduleFiles.stop(directory, parallelTask.id), atomically: true, encoding: .utf8)
    wait(parallel)
    runner.synchronizeScheduled(task: parallelTask, state: try state(parallelTask), root: directory, running: false)

    let (singleBackground, singleBackgroundTask) = try startSchedule(snapshot: item, library: directory)
    var runningState: ScheduleRuntime?
    pump(until: {
        runningState = try? state(singleBackgroundTask)
        return runningState?.logPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.contains("instance-ready") == true
    })
    do {
        _ = try observer.run(item: item, arguments: [], workspaceID: workspaceID, workspaceDirectory: directory.path)
        fatalError("A stale multi-instance flag bypassed an active single-instance background run")
    } catch { check(true, "Scheduled executions block manual launches even before UI synchronization") }
    runner.synchronizeScheduled(task: singleBackgroundTask, state: runningState!, root: directory, running: true)
    let reused = try runner.run(item: item, arguments: [], workspaceID: workspaceID, workspaceDirectory: directory.path)
    check(reused.recordID == runningState!.runID,
          "Manual entry points reuse the current background instance when multi-instance execution is disabled")
    reused.stop()
    wait(singleBackground)
    runner.synchronizeScheduled(task: singleBackgroundTask, state: try state(singleBackgroundTask), root: directory, running: false)
}

@MainActor private func captureInstanceViews(runner: ProcessRunner, item: ScriptItem, workspaceID: String, directory: URL) throws {
    let suite = "ScriptDeck.InstanceLayout.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(preferences: defaults)
    let workspaces = WorkspaceStore(preferences: defaults)
    let workspace = Workspace(id: workspaceID, name: "Instance Tests", directory: directory.path)
    let store = ScriptStore(preferences: defaults, restoreLastDirectory: false)
    try store.open(directory, remember: false)
    let session = WorkspaceSession()
    session.selectedID = item.id
    let schedules = ScheduleStore(runner: runner, root: directory.appendingPathComponent("layout-schedules"), startMonitoring: false)
    let navigation = WorkspaceNavigation()
    navigation.destination = .scripts
    let view = RunnerView(store: store, runner: runner, workspaces: workspaces, preferences: preferences,
                          session: session, workspaceInfo: workspace, schedules: schedules, navigation: navigation)
    let host = NSHostingView(rootView: view.environment(\.locale, L10n.locale))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-instances-\(L10n.language).png"))
    }
    let chooser = NSHostingView(rootView:
        ScriptInstanceList(instances: runner.activeSessions(workspaceID: workspaceID, scriptID: item.id),
                           open: { runner.showExecution($0) }).environment(\.locale, L10n.locale))
    let chooserWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                                 styleMask: [.titled], backing: .buffered, defer: false)
    chooserWindow.contentView = chooser
    defer { chooserWindow.contentView = nil }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    chooser.layoutSubtreeIfNeeded()
    if let bitmap = chooser.bitmapImageRepForCachingDisplay(in: chooser.bounds) {
        chooser.cacheDisplay(in: chooser.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-instance-list-\(L10n.language).png"))
    }
    let editor = NSHostingView(rootView: ScriptEditor(item: item, resolve: { $0 }, save: { _ in true })
        .environment(\.locale, L10n.locale))
    let editorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
                                styleMask: [.titled], backing: .buffered, defer: false)
    editorWindow.contentView = editor
    defer { editorWindow.contentView = nil }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    editor.layoutSubtreeIfNeeded()
    if let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds) {
        editor.cacheDisplay(in: editor.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-instance-editor-\(L10n.language).png"))
    }
}
