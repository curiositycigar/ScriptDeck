import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor func runNavigationSelfTests(root: URL) throws {
    let droppedFiles = [root.appendingPathComponent("文件 one.sh"), root.appendingPathComponent("file two.sh")]
    let providers = droppedFiles.map {
        NSItemProvider(item: $0.dataRepresentation as NSData, typeIdentifier: UTType.fileURL.identifier)
    }
    var loadedFiles: [URL]?
    check(loadDroppedFileURLs(providers) { loadedFiles = $0 }, "Accept file URL pasteboard data")
    pump(until: { loadedFiles != nil })
    check(loadedFiles == droppedFiles, "Load all dropped paths in order, preserving spaces and Unicode")

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
                             search: script.name,
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
    check(table.window === window,
          "Switching modules retains the hidden native script list")
    check(descendants(host).compactMap { $0 as? NSScrollView }.contains {
        $0 !== viewport && $0 !== formScroll && abs($0.convert($0.bounds, to: host).width - host.bounds.width) < 1
    }, "Scheduled Tasks occupies the full browser width without a script sidebar")
    check(preferences.sidebarVisible, "Entering Scheduled Tasks preserves the script-sidebar visibility preference")
    browser.scriptNavigationSelection.wrappedValue = nil
    check(navigation.destination == .schedules && session.selectedID == script.id,
          "原生列表取消选择不会清除记忆或切走定时页面")
    browser.scriptNavigationSelection.wrappedValue = script.id
    layout()
    check(navigation.destination == .scripts && navigation.highlightedScript(in: session) == script.id,
          "再次点击同一个脚本也能从定时页面返回并高亮")
    check(table.selectionHighlightStyle == .none,
          "Returning to a script keeps the native selection highlight disabled")
    check(table.convert(table.bounds, to: host) == sidebarFrame,
          "Returning to Scripts restores the original sidebar layout")
    check(formScroll?.window === window && formScroll?.contentView.bounds.origin == formOffset,
          "往返定时页面后保留原表单实例及滚动位置")
    check(descendants(host).compactMap { $0 as? NSTextField }.contains { $0.stringValue == script.name },
          "Returning to Scripts restores the existing search text")
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
    window.isMovable = false
    window.isMovableByWindowBackground = false
    delegate.configureMainWindow(window)
    layout()
    check(!window.styleMask.contains(.fullSizeContentView) && !window.titlebarAppearsTransparent,
          "主窗口标题栏与内容区独立，不允许内容延伸到窗口按钮下方")
    check(window.isMovable && window.isMovableByWindowBackground,
          "Main-window configuration enables native titlebar and toolbar-background dragging")
    let parameterHost = NSHostingView(rootView:
        ParameterRowLayout(labelWidth: 180) {
            Text("A parameter with a long label").font(WorkspaceTypography.bodyStrong)
            TextField("Value", text: .constant("Preserved input")).textFieldStyle(.roundedBorder)
            Text("Validation guidance stays with the input").font(WorkspaceTypography.caption)
        }
        .padding(16).workspaceTypography()
    )
    parameterHost.frame = NSRect(x: 0, y: 0, width: 640, height: 180)
    window.contentView = parameterHost
    parameterHost.layoutSubtreeIfNeeded()
    let parameterField = descendants(parameterHost).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Preserved input" }!
    let wideInput = parameterField.convert(parameterField.bounds, to: parameterHost)
    parameterHost.setFrameSize(NSSize(width: 400, height: 180))
    parameterHost.layoutSubtreeIfNeeded()
    let narrowInput = parameterField.convert(parameterField.bounds, to: parameterHost)
    check(wideInput.minX > 180 && narrowInput.minX < 40,
          "Parameter rows change from label columns to stacked inputs in narrow space")
    check(parameterField.window === window && parameterField.stringValue == "Preserved input"
          && narrowInput.maxX <= parameterHost.bounds.maxX,
          "Responsive parameter layout retains the native input and its value without horizontal overflow")
    window.contentView = nil
    checkOutputLayoutPersistence(workspaces: workspaces, preferences: preferences,
                                 runner: runner, schedules: schedules)
    try checkScheduleViewport(root: root, workspaces: workspaces, preferences: preferences, runner: runner, item: script)
    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1" {
        try captureWorkspaceAppearance(workspaces: workspaces, preferences: preferences,
                                       runner: runner, schedules: schedules)
    }
}

@MainActor private func checkScheduleViewport(root: URL, workspaces: WorkspaceStore,
                                              preferences: AppPreferences, runner: ProcessRunner, item: ScriptItem) throws {
    let scheduleRoot = root.appendingPathComponent("schedule-viewport")
    let workspace = workspaces.selected!
    for index in 1...12 {
        let task = ScheduledTask(name: "Task \(index)", enabled: false, workspaceID: workspace.id,
                                 workspaceName: workspace.name, item: item, values: [:])
        try ScheduleFiles.write(task, ScheduleFiles.definition(scheduleRoot, task.id))
    }
    let schedules = ScheduleStore(runner: runner, root: scheduleRoot, startMonitoring: false)
    check(schedules.tasks.count == 12, "Load a task list taller than the schedule viewport")
    let navigation = WorkspaceNavigation()
    navigation.destination = .schedules
    let host = NSHostingView(rootView: WorkspaceOutputLayout(expanded: true) {
        RunnerView(store: workspaces.library(for: workspace), runner: runner, workspaces: workspaces,
                   preferences: preferences, session: workspaces.session(for: workspace), workspaceInfo: workspace,
                   schedules: schedules, navigation: navigation, outputExpanded: .constant(true))
    } output: {
        TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: .constant(true))
    })
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 720),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func layout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
    }
    layout()
    let split = descendants(host).compactMap { $0 as? NSSplitView }.first { !$0.isVertical }!
    let pane = split.subviews[0]
    let scroll = descendants(pane).compactMap { $0 as? NSScrollView }
        .first { abs($0.bounds.width - pane.bounds.width) < 1 }!
    let tallViewport = scroll.bounds.height
    window.setContentSize(NSSize(width: 850, height: 460))
    layout()
    let viewport = scroll.convert(scroll.bounds, to: pane)
    check(viewport.height < tallViewport && (scroll.documentView?.frame.height ?? 0) > viewport.height,
          "The schedule list viewport shrinks and remains scrollable")
    check(viewport.minY > 30 && viewport.maxY < pane.bounds.maxY - 30,
          "The schedule viewport reserves space for the header and footer within the short pane")
    check(host.bounds.insetBy(dx: -1, dy: -1).contains(pane.convert(pane.bounds, to: host)),
          "The schedule pane fits within the resized window")
}

/// Render real views against temporary workspaces, without running scripts or installing schedules.
@MainActor private func captureWorkspaceAppearance(workspaces: WorkspaceStore, preferences: AppPreferences,
                                                   runner: ProcessRunner, schedules: ScheduleStore) throws {
    let workspace = workspaces.selected!
    let library = workspaces.library(for: workspace)
    var script = library.items[0]
    script.name = "Selection Parameters Demo"
    script.category = "Examples"
    script.notes = "Configure input parameters before running this script. Each execution creates an independent session."
    script.parameters = [
        ScriptParameter(name: "Environment", kind: .select, required: true, defaultValue: "development",
                        options: [ParameterOption(label: "Development", value: "development")]),
        ScriptParameter(name: "Mode", kind: .select, required: true, defaultValue: "preview",
                        options: [ParameterOption(label: "Preview", value: "preview")]),
        ScriptParameter(name: "Region", defaultValue: "Auto detect"),
        ScriptParameter(name: "Output folder", kind: .folder),
        ScriptParameter(name: "Verbose", passing: .flag, argumentName: "--verbose")
    ]
    check(library.upsert(script), "Prepare temporary appearance fixture")
    let session = workspaces.session(for: workspace)
    session.selectedID = script.id
    let navigation = WorkspaceNavigation()
    let browser = RunnerView(store: library, runner: runner, workspaces: workspaces, preferences: preferences,
                             session: session, workspaceInfo: workspace, schedules: schedules, navigation: navigation,
                             outputExpanded: .constant(true))
    runner.selectedSession.terminalView.suspendsRenderingWhenNotVisible = false
    let preview = VStack(spacing: 0) {
        HStack(spacing: 0) {
            WorkspaceRailView(workspaces: workspaces, navigation: navigation, showSettings: {})
            Divider()
            browser
        }
        Divider()
        TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: .constant(true))
            .frame(height: 240)
    }.environment(\.locale, L10n.locale)
    let host = NSHostingView(rootView: preview)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        window.appearance = NSAppearance(named: appearance)
        for width in [1120, 880] {
            window.setContentSize(NSSize(width: width, height: 780))
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            check(host.bounds.width <= CGFloat(width) + 1, "Workspace fits \(width) points in \(name) appearance")
            let terminal = runner.selectedSession.terminalView
            terminal.effectiveAppearance.performAsCurrentDrawingAppearance {
                let expected = WorkspaceStyle.canvasNSColor.usingColorSpace(.deviceRGB)!
                let actual = terminal.nativeBackgroundColor.usingColorSpace(.deviceRGB)!
                let difference = max(abs(actual.redComponent - expected.redComponent),
                                     abs(actual.greenComponent - expected.greenComponent),
                                     abs(actual.blueComponent - expected.blueComponent))
                check(difference < 0.005, "Terminal shares the \(name) canvas color")
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Unable to render workspace appearance")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = URL(fileURLWithPath: "/tmp/scriptdeck-workspace-\(L10n.language)-\(name)-\(width).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
}

/// Output toggles must resize the existing workspace rather than remounting it.
@MainActor private func checkOutputLayoutPersistence(workspaces: WorkspaceStore, preferences: AppPreferences,
                                                     runner: ProcessRunner, schedules: ScheduleStore) {
    let workspace = workspaces.selected!
    let library = workspaces.library(for: workspace)
    let session = workspaces.session(for: workspace)
    let script = library.items[0]
    session.selectedID = script.id
    let navigation = WorkspaceNavigation()
    func layoutView(expanded: Bool) -> some View {
        WorkspaceOutputLayout(expanded: expanded) {
            RunnerView(store: library, runner: runner, workspaces: workspaces, preferences: preferences,
                       session: session, workspaceInfo: workspace, schedules: schedules, navigation: navigation,
                       search: script.name, outputExpanded: .constant(expanded))
        } output: {
            TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: .constant(expanded))
        }
    }
    let host = NSHostingView(rootView: layoutView(expanded: false))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func layout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }
    layout()
    let views = descendants(host)
    let split = views.compactMap { $0 as? NSSplitView }.first { !$0.isVertical }!
    let table = views.compactMap { $0 as? NSTableView }.first!
    let search = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == script.name }!
    let form = views.compactMap { $0 as? NSScrollView }.first {
        $0 !== table.enclosingScrollView && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height
    }!
    form.contentView.scroll(to: NSPoint(x: 0, y: 100))
    let offset = form.contentView.bounds.origin
    check(split.subviews[1].frame.height <= 47, "Collapsed output keeps a compact header")
    for expanded in [true, false, true, false] {
        host.rootView = layoutView(expanded: expanded)
        layout()
        check(descendants(host).contains { $0 === split }, "Output toggle retains its native split view")
        check(table.window === window && search.window === window && search.stringValue == script.name,
              "Output toggle retains the sidebar instance and search text")
        check(form.window === window && form.contentView.bounds.origin == offset,
              "Output toggle retains the parameter form and scroll position")
        let outputHeight = split.subviews[1].frame.height
        check(expanded ? outputHeight >= 139 : outputHeight <= 47,
              "Output toggle applies the expanded or collapsed pane height (expanded: \(expanded), height: \(outputHeight))")
    }
}
