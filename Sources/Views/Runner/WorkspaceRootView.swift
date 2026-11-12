import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceRootView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    @ObservedObject var navigation: WorkspaceNavigation
    @State private var editingSchedule: ScheduledTask?

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceRailView(navigation: navigation)
            Divider()
            ZStack {
                workspacePage
                    .opacity(navigation.destination == .scripts ? 1 : 0)
                    .disabled(navigation.destination != .scripts)
                    .allowsHitTesting(navigation.destination == .scripts)
                    .accessibilityHidden(navigation.destination != .scripts)
                if navigation.destination != .scripts { globalPage }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(WorkspaceStyle.canvas)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            loadDroppedFileURLs(providers) { WorkspaceDialogs.importDroppedPackage($0, to: workspaces) }
        }
        .workspaceTypography()
        .onAppear {
            presentWorkspaceError()
            schedules.synchronizeWorkspaces(workspaces.items)
        }
        .onChange(of: workspaces.items) { items in schedules.synchronizeWorkspaces(items) }
        .onChange(of: workspaces.error) { _ in presentWorkspaceError() }
        .sheet(isPresented: $navigation.managingWorkspaces) {
            VStack(spacing: 0) {
                WorkspaceSettingsView(workspaces: workspaces, runner: runner) {
                    navigation.managingWorkspaces = false
                    navigation.destination = .scripts
                }
                HStack {
                    Spacer()
                    Button(L("Close")) { navigation.managingWorkspaces = false }
                        .keyboardShortcut(.cancelAction)
                }.padding(16)
            }.frame(width: 800, height: 600)
        }
        .sheet(item: $editingSchedule) { task in
            ScheduleEditor(workspaces: workspaces, initial: task) { try schedules.save($0) }
        }
        .alert(L("Scheduled Task Operation Failed"), isPresented: Binding(
            get: { schedules.error != nil }, set: { if !$0 { schedules.error = nil } }
        )) {
            Button(L("OK"), role: .cancel) { schedules.error = nil }
        } message: { Text(schedules.error ?? "") }
    }

    @ViewBuilder private var globalPage: some View {
        switch navigation.destination {
        case .home:
            HomeDashboard(workspaces: workspaces, preferences: preferences, runner: runner, schedules: schedules,
                          openScript: { workspace, item in
                              workspaces.select(workspace.id)
                              navigation.selectScript(item.id, in: workspaces.session(for: workspace))
                          },
                          openWorkspaces: { navigation.destination = .scripts },
                          openSchedules: { navigation.destination = .schedules },
                          editSchedule: { editingSchedule = $0 })
        case .schedules:
            ScheduleDashboard(schedules: schedules, workspaces: workspaces, runner: runner,
                              showOutput: { runner.showSelectedExecution() },
                              showHistory: { navigation.showHistory($0) })
        case .logs:
            VStack(spacing: 0) {
                if navigation.logScope != nil {
                    HStack {
                        Button(L("All Logs")) { navigation.showHistory() }
                        Spacer()
                    }.padding(.horizontal, 20).padding(.top, 16)
                }
                ExecutionHistoryView(workspaces: workspaces, runner: runner,
                                     scheduleScope: navigation.logScope, canDismiss: false)
                    .id(navigation.logScope?.task.id ?? "all")
            }
        case .settings:
            AppSettingsView(workspaces: workspaces, preferences: preferences, runner: runner)
        case .scripts:
            EmptyView()
        }
    }

    @ViewBuilder private var workspacePage: some View {
        if let workspace = workspaces.selected {
            RunnerView(store: workspaces.library(for: workspace), runner: runner,
                       workspaces: workspaces, preferences: preferences,
                       session: workspaces.session(for: workspace), workspaceInfo: workspace,
                       schedules: schedules, navigation: navigation)
                .id(workspace.id)
        } else {
            VStack(spacing: 16) {
                WorkspaceEmptyState(symbol: "square.stack.3d.up", title: L("Your Script Workspace"),
                                    message: L("Add a folder to manage local scripts, configure parameters, and browse execution records."))
                Button(L("Add Workspace…")) { WorkspaceDialogs.add(to: workspaces) }
                    .workspacePrimaryAction().controlSize(.large)
                Button(L("Manage Workspaces…")) { navigation.managingWorkspaces = true }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func presentWorkspaceError() {
        guard let message = workspaces.error else { return }
        workspaces.error = nil
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L("Workspace Operation Failed")
            alert.informativeText = message
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
        }
    }
}
