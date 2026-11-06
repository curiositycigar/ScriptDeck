import SwiftUI

struct RunnerActions {
    var canImport: Bool
    var sidebarVisible: Bool
    var outputExpanded: Bool
    var importScripts: () -> Void
    var toggleSidebar: () -> Void
    var toggleOutput: () -> Void
}

private struct RunnerActionsKey: FocusedValueKey {
    typealias Value = RunnerActions
}

extension FocusedValues {
    var runnerActions: RunnerActions? {
        get { self[RunnerActionsKey.self] }
        set { self[RunnerActionsKey.self] = newValue }
    }
}

struct RunnerCommands: Commands {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.runnerActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { openWindow(id: "settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("添加 Workspace…") { WorkspaceDialogs.add(to: workspaces) }
                .keyboardShortcut("o", modifiers: .command)
            Button("导入脚本…") { actions?.importScripts() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(actions?.canImport != true)
        }
        CommandGroup(after: .sidebar) {
            Button(actions?.sidebarVisible == true ? "隐藏侧栏" : "显示侧栏") { actions?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(actions == nil)
            Button(actions?.outputExpanded == true ? "收起运行输出" : "展开运行输出") { actions?.toggleOutput() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("运行") {
            Button(runner.stopping ? "强制停止所选任务" : "停止所选任务") { runner.stop(force: runner.stopping) }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!runner.selectedIsRunning)
        }
    }
}
