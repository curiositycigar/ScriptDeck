import Foundation
import AppKit
import SwiftUI

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("FAIL: \(description)") }
    print("PASS: \(description)")
}

@MainActor func pump(until predicate: () -> Bool, timeout: TimeInterval = 5) {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    check(predicate(), "异步任务在时限内完成")
}

@MainActor func runSelfTests() {
    _ = NSApplication.shared
    do {
        try runLocalizationSelfTests()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scriptdeck-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if ProcessInfo.processInfo.environment["RUNNER_TEST_NAVIGATION_ONLY"] == "1" {
            try runNavigationSelfTests(root: root)
            print("导航检查通过。")
            return
        }
        let source = root.appendingPathComponent("上传 ' $(touch should-not-exist).sh")
        try """
        #!/bin/bash
        printf 'stdout:%s\\n' "$1"
        printf 'stderr:test\\n' >&2
        printf 'cwd:%s\\n' "$PWD"
        printf '\\xe4'
        sleep 0.05
        printf '\\xb8\\xad\\xe6\\x96\\x87\\n'
        sleep 0.15
        printf 'done\\n'
        """.write(to: source, atomically: true, encoding: .utf8)
        var item = ScriptItem.importing(source)
        item.parameters = [ScriptParameter(name: "输入", required: true), ScriptParameter(name: "可选")]
        let payload = "a b'\";$(touch injected)\n第二行"
        let args = try scriptArguments(for: item, values: [item.parameters[0].id: payload])
        check(args == [payload], "末尾空的可选参数会省略，保留参数原文")
        do {
            _ = try scriptArguments(for: item, values: [:])
            fatalError("没有拦截必填参数")
        } catch { print("PASS: 拦截空的必填参数") }
        item.parameters[0].required = false
        do {
            _ = try scriptArguments(for: item, values: [item.parameters[1].id: "value"])
            fatalError("没有拦截跳过位置参数")
        } catch { print("PASS: 拦截中间空的位置参数") }
        func checkArguments(_ condition: Bool, _ description: String) { check(condition, description) }
        var mixed = ScriptItem.importing(source)
        let input = ScriptParameter(name: "输入")
        var output = ScriptParameter(name: "输出", passing: .named, argumentName: "--output")
        var verbose = ScriptParameter(name: "详细日志", passing: .flag, argumentName: "--verbose")
        let optionalPosition = ScriptParameter(name: "可选位置参数")
        mixed.parameters = [input, output, verbose, optionalPosition]
        let mixedValues = [input.id: "input file", output.id: payload, verbose.id: "true"]
        checkArguments(try scriptArguments(for: mixed, values: mixedValues) == ["input file", "--output", payload, "--verbose"], "混合参数保留顺序和特殊字符，省略末尾空位置参数")
        output.argumentFormat = .equals
        mixed.parameters = [input, output, verbose]
        checkArguments(try scriptArguments(for: mixed, values: mixedValues) == ["input file", "--output=" + payload, "--verbose"], "支持等号格式，值不经 Shell 拆分")
        checkArguments(try scriptArguments(for: mixed, values: [input.id: "input"]) == ["input"], "空可选命名参数与关闭的开关均省略")
        verbose.defaultValue = "true"
        mixed.parameters = [verbose, input, output]
        checkArguments(try scriptArguments(for: mixed, values: [:]) == ["--verbose"], "开启的默认开关不会导致空位置参数报错")
        checkArguments(try scriptArguments(for: mixed, values: [verbose.id: "false"]) == [], "显式关闭覆盖开关默认值")
        output.required = true
        mixed.parameters = [output]
        check(parameterIssues(for: mixed, values: [:])[output.id] != nil, "必填命名参数缺失时阻止运行")
        output.argumentName = "--output injected"
        mixed.parameters = [output]
        do {
            try LibraryDocument(scripts: [mixed]).validate()
            fatalError("没有拒绝非法命名参数")
        } catch { print("PASS: 拒绝含空白的参数名") }
        output.argumentName = "--output"
        mixed.parameters = [output, output]
        do {
            try LibraryDocument(scripts: [mixed]).validate()
            fatalError("没有拒绝重复参数")
        } catch { print("PASS: 拒绝重复参数定义") }
        mixed.parameters = [input, output, verbose]
        let mixedRoundTrip = try JSONDecoder().decode(ScriptItem.self, from: JSONEncoder().encode(mixed))
        check(mixedRoundTrip == mixed, "命名参数格式和开关配置完整持久化")
        let oldParameter = try JSONDecoder().decode(ScriptParameter.self, from: Data("{\"id\":\"old\",\"label\":\"旧参数\"}".utf8))
        check(oldParameter.passing == .positional, "旧参数配置默认仍为位置参数")
        let runner = ProcessRunner()
        try runner.run(item: item, arguments: [payload])
        pump(until: { runner.output.contains("stderr:test") })
        check(runner.isRunning, "脚本结束前已经收到实时输出")
        pump(until: { !runner.isRunning })
        check(runner.status == L("Completed successfully"), "成功退出码正确")
        check(runner.output.contains("stdout:\(payload)"), "特殊字符参数没有执行为命令")
        let unwrapped = runner.output.replacingOccurrences(of: "\n", with: "")
        check(unwrapped.contains("cwd:\(root.path)") || unwrapped.contains("cwd:\(root.resolvingSymlinksInPath().path)"), "使用脚本目录作为工作目录")
        check(runner.output.contains("中文\n"), "跨数据块 UTF-8 中文输出完整")
        check(runner.output.contains("done\n"), "保留进程退出前的最终日志")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path), "没有参数命令注入")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("should-not-exist").path), "脚本路径中的 Shell 字符不会执行")

        let failure = root.appendingPathComponent("failure.sh")
        try "echo failed >&2\nexit 7\n".write(to: failure, atomically: true, encoding: .utf8)
        try runner.run(item: .importing(failure), arguments: [])
        pump(until: { !runner.isRunning })
        check(runner.status == L("Failed (exit code {0})", "7"), "显示非零退出码")

        let longRunning = root.appendingPathComponent("stop.sh")
        try "echo ready\nsleep 30\necho unexpected\n".write(to: longRunning, atomically: true, encoding: .utf8)
        try runner.run(item: .importing(longRunning), arguments: [])
        pump(until: { runner.output.contains("ready\n") })
        runner.stop()
        pump(until: { !runner.isRunning })
        check(runner.status.hasPrefix(L("Stopped")), "停止父进程及等待中的子进程")
        check(!runner.output.contains("unexpected\n"), "停止后不会继续执行后续步骤")

        try "sleep 30 &\necho background-ready\nexit 0\n".write(to: longRunning, atomically: true, encoding: .utf8)
        try runner.run(item: .importing(longRunning), arguments: [])
        pump(until: { runner.output.contains("background-ready\n") })
        pump(until: { !runner.isRunning })
        check(runner.status == L("Completed successfully"), "PTY 根任务退出后完成会话，不被后台输出描述符无限阻塞")

        try "trap '' TERM\necho ignore-term-ready\nwhile true; do sleep 1; done\n".write(to: longRunning, atomically: true, encoding: .utf8)
        try runner.run(item: .importing(longRunning), arguments: [])
        pump(until: { runner.output.contains("ignore-term-ready\n") })
        runner.stop()
        runner.stop(force: true)
        pump(until: { !runner.isRunning })
        check(runner.status.hasPrefix(L("Stopped")), "可以强制停止忽略终止信号的脚本")

        let interactive = root.appendingPathComponent("interactive.sh")
        try """
        test -t 0 && test -t 1 || exit 9
        printf 'input-ready\\n'
        read -r value
        printf 'received:%s\\n' "$value"
        read -r -s -p 'hidden-ready' hidden
        printf '\\nhidden-done\\n'
        """.write(to: interactive, atomically: true, encoding: .utf8)
        try runner.run(item: .importing(interactive), arguments: [])
        pump(until: { runner.output.contains("input-ready") })
        runner.terminalView.process.send(data: Array("hello\n".utf8)[...])
        pump(until: { runner.output.contains("hidden-ready") })
        runner.terminalView.process.send(data: Array("not-echoed-secret\n".utf8)[...])
        pump(until: { !runner.isRunning })
        check(runner.status == L("Completed successfully") && runner.output.contains("received:hello"), "PTY 支持终端检测和交互输入")
        check(!runner.output.contains("not-echoed-secret"), "终端隐藏输入不出现在导出文本中")

        // Two live PTYs must preserve selection, input, signals and history independently.
        let concurrentScript = root.appendingPathComponent("concurrent.sh")
        try """
        printf 'ready:%s\\n' "$1"
        read -r value
        printf 'reply:%s:%s\\n' "$1" "$value"
        sleep 30
        """.write(to: concurrentScript, atomically: true, encoding: .utf8)
        let concurrent = ProcessRunner()
        let concurrentItem = ScriptItem.importing(concurrentScript)
        let firstSession = try concurrent.run(item: concurrentItem, arguments: ["alpha"], workspaceID: "first", workspaceName: "First")
        let secondSession = try concurrent.run(item: concurrentItem, arguments: ["beta"], workspaceID: "second", workspaceName: "Second")
        pump(until: { firstSession.output.contains("ready:alpha") && secondSession.output.contains("ready:beta") })
        check(concurrent.runningSessions.count == 2, "两个独立终端可以同时运行")
        check(!concurrent.dismissSession(firstSession.id) && concurrent.sessions.count == 2, "拒绝删除运行中的任务记录")
        check(firstSession.id != secondSession.id && firstSession.recordID != secondSession.recordID, "执行会话和日志使用独立 ID")
        check(concurrent.selectedSessionID == firstSession.id, "并发启动不会抢走当前终端选择")
        check(concurrent.isWorkspaceRunning("first") && concurrent.isWorkspaceRunning("second"), "所有运行任务所属 Workspace 均受保护")
        check(concurrent.isActive(workspaceID: "first", scriptID: concurrentItem.id), "脚本活动状态不依赖终端选择")
        check(concurrent.activeRecordIDs.count == 2 && concurrent.protectedHistoryRecordIDs.count == 2, "全部活动记录受保护且被识别为运行中")
        firstSession.terminalView.process.send(data: Array("one\n".utf8)[...])
        secondSession.terminalView.process.send(data: Array("two\n".utf8)[...])
        pump(until: { firstSession.output.contains("reply:alpha:one") && secondSession.output.contains("reply:beta:two") })
        check(!firstSession.output.contains("reply:beta") && !secondSession.output.contains("reply:alpha"), "并发终端的输入输出互不串流")
        let uiSuite = "ScriptDeck.UITests.\(UUID())"
        let uiPreferences = UserDefaults(suiteName: uiSuite)!
        defer { uiPreferences.removePersistentDomain(forName: uiSuite) }
        let uiWorkspaces = WorkspaceStore(preferences: uiPreferences)
        let outputHost = NSHostingView(rootView: TaskOutputView(runner: concurrent, workspaces: uiWorkspaces, outputExpanded: .constant(true)))
        let outputWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 340), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        outputWindow.contentView = outputHost
        outputHost.layoutSubtreeIfNeeded()
        pump(until: { firstSession.terminalView.superview != nil })
        check(secondSession.terminalView.superview == nil, "仅挂载所选终端，隐藏会话持续执行")
        concurrent.select(secondSession.id)
        check(concurrent.terminalView === secondSession.terminalView && concurrent.output == secondSession.output, "选择任务切换对应终端及导出内容")
        pump(until: { secondSession.terminalView.superview != nil && firstSession.terminalView.superview == nil })
        check(secondSession.output.contains("reply:beta:two") && firstSession.isRunning, "原生输出面板切换终端后保留缓冲区及后台执行")
        outputWindow.setContentSize(NSSize(width: 680, height: 300))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        outputHost.layoutSubtreeIfNeeded()
        check(secondSession.terminalView.bounds.width >= 300, "窄窗口中任务列表与终端保留可用宽度")
        if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1",
           let bitmap = outputHost.bitmapImageRepForCachingDisplay(in: outputHost.bounds) {
            outputHost.cacheDisplay(in: outputHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-multisession.png"))
        }
        concurrent.stop()
        pump(until: { !secondSession.isRunning })
        check(firstSession.isRunning && concurrent.isRunning && !concurrent.selectedIsRunning, "停止所选任务不会停止其他任务，全局仍报告运行中")
        check(concurrent.isWorkspaceRunning("first") && !concurrent.isWorkspaceRunning("second"), "结束一个任务仅解除其 Workspace 保护")
        concurrent.select(firstSession.id)
        concurrent.stop()
        pump(until: { !concurrent.isRunning })
        var concurrentHistorySaved = false
        concurrent.afterHistorySaved { concurrentHistorySaved = true }
        pump(until: { concurrentHistorySaved })
        check(!concurrent.hasPendingHistoryWrites && concurrent.protectedHistoryRecordIDs.isEmpty, "所有会话日志落盘后统一解除保护")
        let concurrentLogDirectory = RunLogWriter.directory(for: concurrentScript)
        let concurrentMetadata = try FileManager.default.contentsOfDirectory(at: concurrentLogDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let concurrentDecoder = JSONDecoder()
        concurrentDecoder.dateDecodingStrategy = .iso8601
        let concurrentRecords = try concurrentMetadata.map { try concurrentDecoder.decode(ExecutionRecord.self, from: Data(contentsOf: $0)) }
        check(concurrentRecords.count == 2 && Set(concurrentRecords.compactMap(\.workspaceID)) == Set(["first", "second"]), "并发执行分别保存对应 Workspace 的元数据")
        for record in concurrentRecords {
            let log = try String(contentsOf: concurrentLogDirectory.appendingPathComponent(record.logFilename), encoding: .utf8)
            check(record.outcome == .stopped && record.endedAt != nil, "每次并发执行独立记录停止结果和结束时间")
            check(record.workspaceID == "first" ? log.contains("reply:alpha:one") && !log.contains("reply:beta") : log.contains("reply:beta:two") && !log.contains("reply:alpha"), "持久日志不混入其他会话输出")
        }
        check(concurrent.dismissSession(firstSession.id), "支持删除单个已完成任务记录")
        check(concurrent.sessions.count == 1 && concurrent.sessions.first?.id == secondSession.id, "单条删除不影响其他执行会话")
        check(concurrent.selectedSessionID == secondSession.id, "删除所选任务后自动选择剩余会话")
        check(!concurrent.dismissSession(firstSession.id), "重复删除已移除记录不会改变列表")
        concurrent.dismissCompletedSessions()
        check(concurrent.sessions.isEmpty && concurrent.selectedSessionID == nil, "移出已完成任务释放终端并修复选择")
        let preservedLogFiles = try FileManager.default.contentsOfDirectory(at: concurrentLogDirectory, includingPropertiesForKeys: nil)
        check(preservedLogFiles.count == 4, "移出任务列表保留全部日志文件")

        let suite = "ScriptDeck.Tests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = ScriptStore(preferences: preferences)
        try store.initialize(root.appendingPathComponent("config"))
        check(store.upsert(item), "保存脚本配置")
        let loaded = ScriptStore(preferences: preferences)
        check(loaded.items == store.items, "完整恢复脚本和参数配置")
        check(loaded.createFolder(name: "空文件夹"), "创建空文件夹")
        check(loaded.createFolder(name: "子文件夹", parent: "空文件夹"), "创建子文件夹")
        check(!loaded.createFolder(name: "空文件夹") && !loaded.createFolder(name: "../无效"), "拒绝重名和非法文件夹名称")
        loaded.error = nil
        var grouped = item
        grouped.category = "空文件夹/子文件夹"
        check(loaded.upsert(grouped), "向子文件夹添加脚本")
        try loaded.open(loaded.directoryURL!)
        let tree = ScriptGroup.tree(loaded.items, folders: loaded.folders)
        check(tree.contains { $0.id == "空文件夹" && $0.children.contains { $0.id == "空文件夹/子文件夹" } }, "文件夹层级保存后可恢复")
        check(loaded.removeFolder("空文件夹/子文件夹"), "删除子文件夹")
        check(loaded.items.first?.category == "未分组" && loaded.folders.contains("空文件夹"), "删除子文件夹保留空父文件夹，脚本移至未分组")
        check(loaded.createFolder(name: "子文件夹", parent: "空文件夹"), "重新创建子文件夹")
        check(loaded.upsert(grouped) && loaded.removeFolder("空文件夹"), "删除整个文件夹层级")
        check(loaded.folders.isEmpty && loaded.items.first?.category == "未分组" && FileManager.default.fileExists(atPath: source.path), "删除文件夹保留脚本配置和原文件")
        check(!loaded.removeFolder("未分组"), "未分组作为保留分组不可删除")
        let staleRevision = loaded.revision
        check(loaded.createFolder(name: "保留"), "创建持久化空文件夹")
        check(!loaded.removeFolder("保留", expectedRevision: staleRevision) && loaded.folders.contains("保留"), "过期操作不会覆盖新文件夹配置")
        let oldDocument = try JSONDecoder().decode(LibraryDocument.self, from: Data("{\"version\":1,\"scripts\":[]}".utf8))
        check(oldDocument.folders.isEmpty, "兼容没有 folders 字段的旧脚本库")
        loaded.remove(item.id)
        check(loaded.items.isEmpty && FileManager.default.fileExists(atPath: source.path), "移除配置保留脚本文件")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: loaded.fileURL!)
        let blocked = ScriptStore(preferences: preferences)
        check(blocked.configurationIssue != nil && !blocked.upsert(item), "损坏配置不会被覆盖")
        let preserved = try Data(contentsOf: loaded.fileURL!)
        check(preserved == corrupt, "损坏配置原文保留")
        let historyRoot = root.appendingPathComponent("history-deletion")
        try FileManager.default.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        func historyFixture(_ name: String, logFilename: String? = nil) throws -> HistoryEntry {
            let record = ExecutionRecord(id: name, scriptID: "test", scriptName: name,
                                         scriptFile: source.path, workspaceID: nil, workspaceName: "Tests",
                                         startedAt: Date(), outcome: .succeeded, logFilename: logFilename ?? name + ".log")
            let metadata = historyRoot.appendingPathComponent(name + ".json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: metadata)
            let entry = HistoryEntry(record: record, metadataURL: metadata)
            if logFilename == nil { try Data("test output".utf8).write(to: entry.logURL) }
            return entry
        }
        let one = try historyFixture("one")
        let two = try historyFixture("two")
        let active = try historyFixture("active")
        let unrelated = historyRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let single = HistoryRecordDeletion.remove([one], protectedIDs: [])
        check(single.removedIDs == [one.id] && single.failures.isEmpty &&
              !FileManager.default.fileExists(atPath: one.logURL.path) &&
              !FileManager.default.fileExists(atPath: one.metadataURL.path), "删除单条历史同时删除日志和元数据")
        check(FileManager.default.fileExists(atPath: two.logURL.path), "删除所选历史保留范围外记录")
        let bulk = HistoryRecordDeletion.remove([two, active], protectedIDs: [active.id])
        check(bulk.removedIDs == [two.id] && FileManager.default.fileExists(atPath: active.logURL.path) &&
              FileManager.default.fileExists(atPath: active.metadataURL.path), "批量清空跳过正在运行或保存中的记录")
        check(FileManager.default.fileExists(atPath: source.path) && FileManager.default.fileExists(atPath: unrelated.path),
              "清空历史保留脚本和无关文件")
        let missing = try historyFixture("missing")
        try FileManager.default.removeItem(at: missing.logURL)
        let missingResult = HistoryRecordDeletion.remove([missing], protectedIDs: [])
        check(missingResult.removedIDs.contains(missing.id) && missingResult.failures.isEmpty,
              "日志已丢失时仍可删除残留历史记录")
        let unsafe = try historyFixture("unsafe", logFilename: "../outside.log")
        let unsafeResult = HistoryRecordDeletion.remove([unsafe], protectedIDs: [])
        check(unsafeResult.removedIDs.isEmpty && !unsafeResult.failures.isEmpty &&
              FileManager.default.fileExists(atPath: unsafe.metadataURL.path), "拒绝越出记录目录的日志路径")
        let folderLog = try historyFixture("folder-log")
        try FileManager.default.removeItem(at: folderLog.logURL)
        try FileManager.default.createDirectory(at: folderLog.logURL, withIntermediateDirectories: true)
        let partial = HistoryRecordDeletion.remove([folderLog, active], protectedIDs: [])
        check(partial.removedIDs == [active.id] && partial.failures.count == 1 &&
              FileManager.default.fileExists(atPath: folderLog.logURL.path) &&
              FileManager.default.fileExists(atPath: folderLog.metadataURL.path), "单条失败不阻止批量清理，也不会递归删除目录")
        let changed = try historyFixture("changed")
        try Data("{}".utf8).write(to: changed.metadataURL)
        let changedResult = HistoryRecordDeletion.remove([changed], protectedIDs: [])
        check(changedResult.removedIDs.isEmpty && !changedResult.failures.isEmpty &&
              FileManager.default.fileExists(atPath: changed.logURL.path), "确认后被替换的记录不会误删日志")
        try runScheduleSelfTests(root: root)
        try runNavigationSelfTests(root: root)
        print("全部检查通过。")
    } catch { fatalError("测试失败：\(error)") }
}
