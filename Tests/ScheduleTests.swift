import Foundation
import AppKit
import SwiftUI

private final class TestScheduleService: ScheduleService {
    var loaded = Set<String>()
    var rejectRegistration = false
    var installations = 0
    func installHelper() throws { installations += 1 }
    func register(_ task: ScheduledTask) throws {
        if rejectRegistration { throw RunnerError(message: "模拟系统拒绝注册") }
        loaded.insert(task.id)
    }
    func isLoaded(_ id: String) -> Bool { loaded.contains(id) }
    func unregister(_ id: String) throws { loaded.remove(id) }
}

@MainActor func runScheduleSelfTests(root: URL) throws {
    let directory = root.appendingPathComponent("schedule-fixtures")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("scheduled.sh")
    try """
    printf 'scheduled:%s\\n' "$1"
    printf 'stderr:后台中文\\n' >&2
    printf 'ran\\n' >> "$2"
    """.write(to: source, atomically: true, encoding: .utf8)
    var item = ScriptItem.importing(source)
    item.parameters = [ScriptParameter(id: "text", name: "文本"), ScriptParameter(id: "marker", name: "计数")]
    let marker = directory.appendingPathComponent("counter.txt")
    let payload = "带空格 ' $(touch scheduled-injection)"
    var task = ScheduledTask(name: "测试定时", workspaceID: "schedule-workspace", workspaceName: "定时库", item: item,
                             values: ["text": payload, "marker": marker.path])
    task.timeZoneID = "UTC"
    let now = ISO8601DateFormatter().date(from: "2026-11-06T08:00:00Z")!
    task.createdAt = now
    task.date = now.addingTimeInterval(3600)
    task.kind = .daily
    check(task.nextDate(after: now) == now.addingTimeInterval(3600), "每天定时计算当天未来时刻")
    check(task.nextDate(after: now.addingTimeInterval(3600)) == now.addingTimeInterval(90000), "已到达的日历时刻推进到下一天")
    task.kind = .weekly; task.weekday = 2
    check(task.calendar.component(.weekday, from: task.nextDate(after: now)!) == 2, "每周定时匹配目标星期")
    task.kind = .interval; task.intervalMinutes = 5
    check(task.nextDate(after: now) == now.addingTimeInterval(300), "固定间隔按分钟推进")
    let service = LaunchAgentService(root: directory)
    let intervalPlist = service.propertyList(for: task)
    check(intervalPlist["StartInterval"] as? Int == 300, "间隔任务生成系统 StartInterval")
    task.kind = .once
    let oncePlist = service.propertyList(for: task)
    check((oncePlist["StartCalendarInterval"] as? [String: Int])?["Month"] == 11 && oncePlist["RunAtLoad"] as? Bool == true,
          "一次性任务生成日历触发和登录到期检查")
    check(!(oncePlist["ProgramArguments"] as! [String]).contains(payload), "系统任务参数不暴露脚本运行参数")
    check(service.helper.path.hasSuffix("bin/ScriptDeck Helper"), "后台执行器使用独立于 App 位置的固定路径")

    try service.installHelper()
    check(FileManager.default.isExecutableFile(atPath: service.helper.path), "后台执行器安装到 ScriptDeck 固定路径")
    check(service.label(task.id) == "com.lucasyou.ScriptDeck.schedule." + task.id, "系统任务使用 ScriptDeck 标识")

    func launch(_ task: ScheduledTask) throws -> Process {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--run-schedule", ScheduleFiles.definition(directory, task.id).path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
    func wait(_ process: Process) { pump(until: { !process.isRunning }, timeout: 10) }
    task.kind = .once; task.date = Date().addingTimeInterval(3600)
    try ScheduleFiles.write(task, ScheduleFiles.definition(directory, task.id))
    let future = try launch(task); wait(future)
    check(!FileManager.default.fileExists(atPath: marker.path), "提前触发不会执行未来的一次性任务")
    task.date = Date().addingTimeInterval(-60)
    try ScheduleFiles.write(task, ScheduleFiles.definition(directory, task.id))
    let once = try launch(task); wait(once)
    var state = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, task.id))
    check(once.terminationStatus == 0 && state.outcome == .succeeded && state.nextFireAt == nil, "无 App 窗口的后台入口完成一次性任务并消费时刻")
    let recordID = state.runID
    let log = try String(contentsOfFile: state.logPath!, encoding: .utf8)
    check(log.contains(payload) && log.contains("stderr:后台中文"), "后台日志收集标准输出、错误与 UTF-8")
    check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("scheduled-injection").path), "后台参数按原文传递，不执行命令替换")
    let replay = try launch(task); wait(replay)
    state = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, task.id))
    let counter = try String(contentsOf: marker, encoding: .utf8)
    check(state.runID == recordID && counter == "ran\n", "重新登录或重复唤醒不会重跑已消费的一次性任务")
    let attributes = try FileManager.default.attributesOfItem(atPath: ScheduleFiles.definition(directory, task.id).path)
    check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "定时配置和参数仅当前用户可读写")
    let metadataDecoder = JSONDecoder(); metadataDecoder.dateDecodingStrategy = .iso8601
    let metadata = try metadataDecoder.decode(ExecutionRecord.self, from: Data(contentsOf: URL(fileURLWithPath: state.metadataPath!)))
    check(metadata.outcome == .succeeded && metadata.workspaceID == task.workspaceID, "后台执行沿用现有执行历史格式和 Workspace 归属")

    // A real running helper must remain independent of the App's ProcessRunner lifecycle.
    let slow = directory.appendingPathComponent("slow.sh")
    try "printf 'background-ready\\n'\nsleep 30\nprintf 'unexpected\\n'\n".write(to: slow, atomically: true, encoding: .utf8)
    var slowTask = ScheduledTask(name: "后台停止测试", workspaceID: task.workspaceID, workspaceName: task.workspaceName,
                                 item: .importing(slow), values: [:])
    slowTask.date = Date().addingTimeInterval(-5)
    try ScheduleFiles.write(slowTask, ScheduleFiles.definition(directory, slowTask.id))
    let slowProcess = try launch(slowTask)
    defer { if slowProcess.isRunning { slowProcess.terminate() } }
    var slowState: ScheduleRuntime?
    pump(until: {
        slowState = try? ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, slowTask.id))
        return slowState?.logPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.contains("background-ready") == true
    })
    check(ScheduleFiles.isRunning(root: directory, id: slowTask.id), "跨进程文件锁标识后台执行中")
    let duplicate = try launch(slowTask); wait(duplicate)
    let duplicateState = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, slowTask.id))
    check(duplicateState.runID == slowState?.runID && slowProcess.isRunning, "同一定时任务的并发触发不会启动第二个实例")
    let backgroundRunner = ProcessRunner()
    backgroundRunner.synchronizeScheduled(task: slowTask, state: slowState!, root: directory, running: true)
    check(backgroundRunner.isRunning && backgroundRunner.foregroundRunningSessions.isEmpty && backgroundRunner.activeRecordIDs.contains(slowState!.runID!),
          "后台任务进入执行列表和历史保护，但不阻止 App 单独退出")
    check(backgroundRunner.output.contains("background-ready"), "执行列表读取后台日志并显示输出")
    backgroundRunner.stop()
    wait(slowProcess)
    slowState = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, slowTask.id))
    backgroundRunner.synchronizeScheduled(task: slowTask, state: slowState!, root: directory, running: false)
    check(slowState?.outcome == .stopped && !backgroundRunner.isRunning, "执行列表的停止请求交给后台执行器终止进程组")
    let stoppedLog = try String(contentsOfFile: slowState!.logPath!, encoding: .utf8)
    check(!stoppedLog.contains("unexpected"), "后台停止不会继续执行后续步骤")
    backgroundRunner.dismissCompletedSessions()
    backgroundRunner.synchronizeScheduled(task: slowTask, state: slowState!, root: directory, running: false)
    check(backgroundRunner.sessions.isEmpty, "已移出的后台执行记录不会被下一次刷新重新导入")

    // A recurring task catches up once, then advances beyond all missed intervals.
    var recurring = task
    recurring.id = UUID().uuidString; recurring.kind = .interval; recurring.intervalMinutes = 1
    recurring.createdAt = Date().addingTimeInterval(-600)
    try ScheduleFiles.write(recurring, ScheduleFiles.definition(directory, recurring.id))
    let catchup = try launch(recurring); wait(catchup)
    let recurringState = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, recurring.id))
    check(recurringState.outcome == .succeeded && recurringState.nextFireAt! > Date(), "错过多个周期只补执行一次并推进到未来")
    let repeatedTick = try launch(recurring); wait(repeatedTick)
    let unchanged = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, recurring.id))
    check(unchanged.runID == recurringState.runID, "同一周期的重复系统触发被消费记录去重")
    recurring.enabled = false
    try ScheduleFiles.write(recurring, ScheduleFiles.definition(directory, recurring.id))
    var overdue = recurringState; overdue.nextFireAt = Date().addingTimeInterval(-60)
    try ScheduleFiles.write(overdue, ScheduleFiles.runtime(directory, recurring.id))
    let paused = try launch(recurring); wait(paused)
    let pausedState = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, recurring.id))
    check(pausedState.runID == recurringState.runID, "暂停后即使系统仍触发也不会启动脚本")
    recurring.enabled = true
    try ScheduleFiles.write(recurring, ScheduleFiles.definition(directory, recurring.id))
    try Data("broken-ledger".utf8).write(to: ScheduleFiles.runtime(directory, recurring.id))
    let damaged = try launch(recurring); wait(damaged)
    check(damaged.terminationStatus == 1, "损坏的消费记录会阻止执行，避免重复运行")
    let damagedStore = ScheduleStore(runner: ProcessRunner(), root: directory, startMonitoring: false, service: TestScheduleService())
    check(damagedStore.issue(for: recurring) != nil && damagedStore.failedTaskCount > 0, "损坏的后台执行状态会在任务列表和菜单栏显示异常")

    var missingTask = task
    missingTask.id = UUID().uuidString; missingTask.date = Date().addingTimeInterval(-60)
    missingTask.item.path = directory.appendingPathComponent("not-found.sh").path
    try ScheduleFiles.write(missingTask, ScheduleFiles.definition(directory, missingTask.id))
    let missingProcess = try launch(missingTask); wait(missingProcess)
    let missingState = try ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(directory, missingTask.id))
    check(missingState.outcome == .launchFailed && missingState.message?.contains("找不到脚本") == true,
          "脚本丢失的后台启动失败会保存可见原因")

    let registry = root.appendingPathComponent("schedule-registry")
    let mock = TestScheduleService()
    let store = ScheduleStore(runner: ProcessRunner(), root: registry, startMonitoring: false, service: mock)
    var newTask = task
    newTask.id = UUID().uuidString; newTask.date = Date().addingTimeInterval(3600)
    try store.save(newTask)
    check(store.tasks.count == 1 && mock.loaded.contains(newTask.id) && store.nextTask != nil, "保存定时任务同时注册系统触发并展示下次时间")
    try store.setEnabled(store.tasks[0], false)
    check(!store.tasks[0].enabled && !mock.loaded.contains(newTask.id), "暂停任务同步停用配置和系统触发")
    try store.setEnabled(store.tasks[0], true)
    check(store.tasks[0].enabled && mock.loaded.contains(newTask.id), "重新启用恢复系统定时任务")
    mock.rejectRegistration = true
    var rejected = newTask; rejected.id = UUID().uuidString
    do { try store.save(rejected); fatalError("未拦截注册失败") }
    catch { check(!FileManager.default.fileExists(atPath: ScheduleFiles.definition(registry, rejected.id).path) && store.tasks.count == 1,
                  "系统注册失败不会留下显示启用的孤立任务") }
    mock.rejectRegistration = false
    let reloaded = ScheduleStore(runner: ProcessRunner(), root: registry, startMonitoring: false, service: mock)
    check(reloaded.tasks.first?.id == newTask.id, "重新启动 App 可恢复定时任务配置")
    try store.remove(store.tasks[0])
    check(store.tasks.isEmpty && !mock.loaded.contains(newTask.id) && FileManager.default.fileExists(atPath: state.logPath!),
          "删除定时任务移除注册且保留执行日志")

    // Render the dashboard with private test data, without registering any real LaunchAgent.
    let defaultsName = "ScriptDeck.ScheduleUI.\(UUID())"
    let defaults = UserDefaults(suiteName: defaultsName)!
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let workspaces = WorkspaceStore(preferences: defaults)
    let host = NSHostingView(rootView: ScheduleDashboard(schedules: reloaded, workspaces: workspaces, runner: backgroundRunner, showOutput: {}))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    check(host.bounds.width >= 700, "原生定时任务面板可挂载并完成布局")
    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1", let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-schedules.png"))
    }
    window.contentView = nil

    if ProcessInfo.processInfo.environment["RUNNER_TEST_LAUNCHD"] == "1" {
        // This opt-in integration check installs one harmless job entirely under the temp fixture.
        let realRoot = root.appendingPathComponent("real-launchd")
        var realService = LaunchAgentService(root: realRoot)
        realService.agentsDirectory = realRoot.appendingPathComponent("LaunchAgents")
        try realService.installHelper()
        var realTask = task
        realTask.id = UUID().uuidString; realTask.date = Date().addingTimeInterval(-5)
        try ScheduleFiles.write(realTask, ScheduleFiles.definition(realRoot, realTask.id))
        defer { try? realService.unregister(realTask.id) }
        try realService.register(realTask)
        check(realService.isLoaded(realTask.id), "真实 launchd 接受独立临时 LaunchAgent")
        var realState: ScheduleRuntime?
        pump(until: {
            realState = try? ScheduleFiles.read(ScheduleRuntime.self, ScheduleFiles.runtime(realRoot, realTask.id))
            return realState?.outcome == .succeeded
        }, timeout: 10)
        check(realState?.outcome == .succeeded, "真实 launchd 在没有 App 窗口时触发后台脚本并完成日志")
        try realService.unregister(realTask.id)
        check(!realService.isLoaded(realTask.id), "真实系统定时测试完成后已卸载临时服务")
    }
}
