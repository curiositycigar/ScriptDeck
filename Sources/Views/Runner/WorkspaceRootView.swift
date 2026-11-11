import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceRootView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    @Environment(\.openWindow) private var openWindow
    @State private var outputExpanded = false
    @StateObject private var navigation = WorkspaceNavigation()

    var body: some View {
        WorkspaceOutputLayout(expanded: outputExpanded) {
            workspaceShell
        } output: {
            TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: $outputExpanded)
        }
        .frame(minWidth: preferences.sidebarVisible ? 800 : 680)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            loadDroppedFileURLs(providers) { WorkspaceDialogs.importDroppedPackage($0, to: workspaces) }
        }
        .workspaceTypography()
        .onChange(of: runner.launchRevision) { _ in outputExpanded = true }
        .onAppear { presentWorkspaceError() }
        .onChange(of: workspaces.error) { _ in presentWorkspaceError() }
        .alert(L("Scheduled Task Operation Failed"), isPresented: Binding(get: { schedules.error != nil }, set: { if !$0 { schedules.error = nil } })) {
            Button(L("OK"), role: .cancel) { schedules.error = nil }
        } message: { Text(schedules.error ?? "") }
    }

    private var workspaceShell: some View {
        HStack(spacing: 0) {
            WorkspaceRailView(workspaces: workspaces, navigation: navigation,
                              showSettings: {
                                  preferences.settingsTab = .general
                                  openWindow(id: "settings")
                              })
            Divider()
            currentWorkspace
                .transition(.opacity)
        }
        .workspaceAnimation(value: workspaces.selectedID, motion: .layout)
    }

    private func presentWorkspaceError() {
        guard let message = workspaces.error else { return }
        workspaces.error = nil
        // An app-modal alert remains visible even when the Settings window is in front.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L("Workspace Operation Failed")
            alert.informativeText = message
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
        }
    }

    @ViewBuilder private var currentWorkspace: some View {
        if let workspace = workspaces.selected {
            RunnerView(store: workspaces.library(for: workspace), runner: runner,
                       workspaces: workspaces, preferences: preferences,
                       session: workspaces.session(for: workspace), workspaceInfo: workspace,
                       schedules: schedules, navigation: navigation,
                       outputExpanded: $outputExpanded)
                .id(workspace.id)
        } else {
            HSplitView {
                if navigation.destination == .scripts {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("WORKSPACES")).font(WorkspaceTypography.sectionLabel).foregroundStyle(.secondary)
                        Button { WorkspaceDialogs.add(to: workspaces) } label: {
                            Label(L("Add Workspace…"), systemImage: "plus")
                                .font(WorkspaceTypography.body)
                                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(WorkspaceNavigationButtonStyle(selected: false))
                    }
                    .padding(14)
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 330, maxHeight: .infinity, alignment: .topLeading)
                    .background(WorkspaceStyle.sidebar)
                }
                ZStack {
                    VStack(spacing: 0) {
                        WorkspaceEmptyState(symbol: "square.stack.3d.up", title: L("Your Script Workspace"),
                                            message: L("Add a folder to manage local scripts, configure parameters, and browse execution records."))
                        Button(L("Add Workspace…")) { WorkspaceDialogs.add(to: workspaces) }
                            .workspacePrimaryAction().controlSize(.large)
                    }
                    .opacity(navigation.destination == .scripts ? 1 : 0)
                    .allowsHitTesting(navigation.destination == .scripts)
                    .accessibilityHidden(navigation.destination != .scripts)
                    ScheduleDashboard(schedules: schedules, workspaces: workspaces, runner: runner,
                                      showOutput: { outputExpanded = true })
                        .opacity(navigation.destination == .schedules ? 1 : 0)
                        .allowsHitTesting(navigation.destination == .schedules)
                        .accessibilityHidden(navigation.destination != .schedules)
                }
                .workspaceAnimation(value: navigation.destination, motion: .layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Keep both panes in the same native split view when output is toggled.
/// Reparenting the workspace into/out of a split view remounts its UI and fades it.
struct WorkspaceOutputLayout<Workspace: View, Output: View>: View {
    let expanded: Bool
    @ViewBuilder let workspace: Workspace
    @ViewBuilder let output: Output

    var body: some View {
        VSplitView {
            workspace
                .frame(minHeight: 280, idealHeight: 460)
            output
                .frame(minHeight: expanded ? 140 : 46,
                       idealHeight: expanded ? 240 : 46,
                       maxHeight: expanded ? .infinity : 46)
        }
    }
}
