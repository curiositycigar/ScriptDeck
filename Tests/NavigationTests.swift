import AppKit
import SwiftUI

@MainActor func runNavigationSelfTests(root: URL) throws {
    let suite = "ScriptDeck.NavigationTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(preferences: defaults)
    let workspaces = WorkspaceStore(preferences: defaults)
    let directory = root.appendingPathComponent("navigation-workspace")
    let library = ScriptStore(preferences: defaults)
    try library.initialize(directory)
    var script = ScriptItem()
    script.name = "导航测试脚本"
    script.path = "/bin/true"
    script.parameters = (1...20).map { ScriptParameter(id: "p\($0)", name: "参数 \($0)") }
    check(library.upsert(script), "准备导航回归测试的脚本配置")
    try workspaces.register(directory)
    let workspace = workspaces.selected!
    let store = workspaces.library(for: workspace)
    let session = workspaces.session(for: workspace)
    session.selectedID = script.id
    session.values[script.id] = ["p1": "保留的参数"]
    let runner = ProcessRunner(preferences: preferences)
    let schedules = ScheduleStore(runner: runner, root: root.appendingPathComponent("navigation-schedules"), startMonitoring: false)
    let navigation = WorkspaceNavigation()
    let browser = RunnerView(store: store, runner: runner, workspaces: workspaces, preferences: preferences,
                             session: session, workspaceInfo: workspace, schedules: schedules, navigation: navigation,
                             outputExpanded: .constant(false))
    let host = NSHostingView(rootView: browser)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.toolbar = NSToolbar(identifier: "NavigationLayoutTests")
    window.toolbarStyle = .unified
    window.titlebarAppearsTransparent = true
    window.contentView = host
    func layout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    layout()
    let table = descendants(host).compactMap { $0 as? NSTableView }.first!
    check(table.numberOfRows >= 2,
          "Sidebar folders and scripts remain separate selectable rows")
    check(table.selectionHighlightStyle == .none,
          "Sidebar uses the shared row background instead of the native blue selection")
    let sidebarFrame = table.convert(table.bounds, to: host)
    let viewport = table.enclosingScrollView!
    let contentBounds = host.convert(window.contentLayoutRect, from: nil)
    check(contentBounds.insetBy(dx: -1, dy: -1).contains(viewport.convert(viewport.bounds, to: host)),
          "侧栏列表内容位于窗口安全区域内")
    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1", let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/navigation-layout.png"))
    }
    let formScroll = descendants(host).compactMap { $0 as? NSScrollView }
        .first { $0 !== table.enclosingScrollView && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height }
    check(formScroll != nil, "脚本参数表单具备可保留的滚动视图")
    formScroll?.contentView.scroll(to: NSPoint(x: 0, y: 140))
    let formOffset = formScroll?.contentView.bounds.origin
    navigation.destination = .schedules
    layout()
    check(navigation.highlightedScript(in: session) == nil && session.selectedID == script.id,
          "进入定时任务仅取消脚本高亮，保留上次脚本选择")
    check(table.window === window && table.convert(table.bounds, to: host) == sidebarFrame,
          "切换定时任务保留同一侧栏列表及尺寸位置")
    browser.scriptNavigationSelection.wrappedValue = nil
    check(navigation.destination == .schedules && session.selectedID == script.id,
          "原生列表取消选择不会清除记忆或切走定时页面")
    browser.scriptNavigationSelection.wrappedValue = script.id
    layout()
    check(navigation.destination == .scripts && navigation.highlightedScript(in: session) == script.id,
          "再次点击同一个脚本也能从定时页面返回并高亮")
    check(table.selectionHighlightStyle == .none,
          "Returning to a script keeps the native selection highlight disabled")
    check(formScroll?.window === window && formScroll?.contentView.bounds.origin == formOffset,
          "往返定时页面后保留原表单实例及滚动位置")
    check(session.values[script.id]?["p1"] == "保留的参数", "切换页面保留已输入参数")
    navigation.destination = .schedules
    let otherDirectory = root.appendingPathComponent("navigation-second-workspace")
    try library.initialize(otherDirectory)
    check(library.upsert(script), "准备包含脚本的第二个 Workspace")
    try workspaces.register(otherDirectory)
    let other = workspaces.selected!
    let otherBrowser = RunnerView(store: workspaces.library(for: other), runner: runner, workspaces: workspaces,
                                  preferences: preferences, session: workspaces.session(for: other), workspaceInfo: other,
                                  schedules: schedules, navigation: navigation, outputExpanded: .constant(false))
    host.rootView = otherBrowser
    layout()
    check(navigation.destination == .schedules, "切换 Workspace 并初始化脚本选择时仍停留在全部定时任务")
    let delegate = AppDelegate()
    delegate.configureMainWindow(window)
    layout()
    check(!window.styleMask.contains(.fullSizeContentView) && !window.titlebarAppearsTransparent,
          "主窗口标题栏与内容区独立，不允许内容延伸到窗口按钮下方")
    window.contentView = nil
}
