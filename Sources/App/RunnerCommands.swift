import SwiftUI

struct RunnerActions {
    var canImport: Bool
    var sidebarVisible: Bool
    var canToggleSidebar: Bool
    var importScripts: () -> Void
    var newScript: () -> Void
    var findScript: () -> Void
    var toggleSidebar: () -> Void
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
    @ObservedObject var navigation: WorkspaceNavigation
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.runnerActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L("Settings…")) { navigation.destination = .settings; openWindow(id: "main") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button(L("Add Workspace…")) { navigation.destination = .scripts; WorkspaceDialogs.add(to: workspaces) }
                .keyboardShortcut("o", modifiers: .command)
            Button(L("Import Workspace Package…")) { WorkspaceDialogs.importPackage(to: workspaces) }
            Button(L("Export Workspace Package…")) {
                if let workspace = workspaces.selected { WorkspaceDialogs.export(workspace, from: workspaces) }
            }
            .disabled(workspaces.selected == nil)
            Divider()
            Button(L("New Script")) { actions?.newScript() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions?.canImport != true)
            Button(L("Import Scripts…")) { actions?.importScripts() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(actions?.canImport != true)
        }
        CommandGroup(after: .sidebar) {
            Button(L("Search scripts")) { actions?.findScript() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
            Button(actions?.sidebarVisible == true ? L("Hide Sidebar") : L("Show Sidebar")) { actions?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(actions?.canToggleSidebar != true)
            Button(L("View Output")) { runner.showSelectedExecution() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(runner.sessions.isEmpty)
        }
        CommandMenu(L("Run")) {
            Button(runner.stopping ? L("Force stop the selected task") : L("Stop the selected task")) { runner.stopKeyExecution() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!runner.keyExecutionIsRunning)
        }
    }
}
