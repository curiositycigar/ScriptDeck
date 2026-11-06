import SwiftUI
import AppKit

struct WorkspaceRootView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    @Environment(\.openWindow) private var openWindow
    @State private var outputExpanded = false
    @StateObject private var navigation = WorkspaceNavigation()

    var body: some View {
        VStack(spacing: 0) {
            if outputExpanded {
                VSplitView {
                    currentWorkspace.frame(minHeight: 280, idealHeight: 460)
                    TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: $outputExpanded,
                                   onRevealScript: { navigation.destination = .scripts })
                        .frame(minHeight: 140, idealHeight: 240)
                }
            } else {
                currentWorkspace.frame(maxHeight: .infinity)
                Divider()
                TaskOutputView(runner: runner, workspaces: workspaces, outputExpanded: $outputExpanded,
                               onRevealScript: { navigation.destination = .scripts })
            }
        }
        .frame(minWidth: 680, minHeight: 540)
        .onChange(of: runner.launchRevision) { _ in outputExpanded = true }
        .onAppear { presentWorkspaceError() }
        .onChange(of: workspaces.error) { _ in presentWorkspaceError() }
        .alert("定时任务操作失败", isPresented: Binding(get: { schedules.error != nil }, set: { if !$0 { schedules.error = nil } })) {
            Button("好", role: .cancel) { schedules.error = nil }
        } message: { Text(schedules.error ?? "") }
    }

    private func presentWorkspaceError() {
        guard let message = workspaces.error else { return }
        workspaces.error = nil
        // An app-modal alert remains visible even when the Settings window is in front.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Workspace 操作失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("WORKSPACES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Button("添加 Workspace…") { WorkspaceDialogs.add(to: workspaces) }
                    Spacer()
                    Divider()
                    Text("定时任务").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Button { navigation.destination = .schedules } label: {
                        Label("全部定时任务", systemImage: "calendar.badge.clock").padding(8)
                    }
                    .buttonStyle(.plain)
                    .background(navigation.destination == .schedules ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                }.padding(14)
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 330, maxHeight: .infinity)
                .background(.bar)
                ZStack {
                    VStack(spacing: 0) {
                        WorkspaceEmptyState(symbol: "square.stack.3d.up", title: "你的脚本工作空间",
                                            message: "添加一个文件夹来管理本地脚本、配置运行参数并查看执行记录。")
                        Button("添加 Workspace…") { WorkspaceDialogs.add(to: workspaces) }
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("ScriptDeck")
            .toolbar {
                ToolbarItem {
                    Button("管理 Workspaces…") {
                        preferences.settingsTab = .workspaces
                        openWindow(id: "settings")
                    }
                }
            }
        }
    }
}
