import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RunnerView: View {
    @ObservedObject var store: ScriptStore
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var session: WorkspaceSession
    let workspaceInfo: Workspace
    @ObservedObject var schedules: ScheduleStore
    @ObservedObject var navigation: WorkspaceNavigation
    @State var schedulingItem: ScheduledTask?
    @Environment(\.openWindow) var openWindow
    @State var detailsExpanded = false
    @State var validatedScripts: Set<String> = []
    @FocusState var focusedParameter: String?
    @State var search = ""
    @State var editor: ScriptItem?
    @State var editorRevision = 0
    @State var expandedGroups: [String: Bool] = [:]
    @State var error: String?
    @State var deleteItem: ScriptItem?
    @State var creatingFolder = false
    @State var folderName = ""
    @State var folderParent = ""
    @State var folderError: String?
    @State var folderRevision = 0
    @State var deletingFolder: String?
    @State var dropTarget = false
    @Binding var outputExpanded: Bool

    var selected: ScriptItem? { store.items.first { $0.id == session.selectedID } }
    var filtered: [ScriptItem] {
        store.items.filter { search.isEmpty || "\($0.name) \($0.category) \($0.path)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.configurationIssue {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(issue).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("重新加载") { store.reloadFromDisk(force: true) }
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            GeometryReader { geometry in
                workspacePane
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: preferences.sidebarVisible ? 820 : 680, minHeight: 280)
        .navigationTitle(navigation.destination == .schedules ? "定时任务" : selected?.name ?? workspaceInfo.name)
        .navigationSubtitle(workspaceInfo.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { preferences.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(preferences.sidebarVisible ? "隐藏侧栏" : "显示侧栏")
                    .accessibilityLabel(preferences.sidebarVisible ? "隐藏侧栏" : "显示侧栏")
                if !preferences.sidebarVisible { workspaceMenu.frame(maxWidth: 220) }
            }
            ToolbarItemGroup {
                Button(action: importScripts) { Label("导入脚本", systemImage: "square.and.arrow.down") }
                    .help("导入本地脚本（⌘I）")
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
                Button { openEditor(ScriptItem()) } label: { Label("新增脚本", systemImage: "plus") }
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }
            ToolbarItem(placement: .automatic) { libraryMenu }
        }
        .focusedSceneValue(\.runnerActions, RunnerActions(
            canImport: store.directoryURL != nil && store.configurationIssue == nil,
            sidebarVisible: preferences.sidebarVisible, outputExpanded: outputExpanded,
            importScripts: importScripts,
            toggleSidebar: { preferences.sidebarVisible.toggle() }, toggleOutput: { outputExpanded.toggle() }
        ))
        .onChange(of: session.selectedID) { _ in detailsExpanded = false; focusedParameter = nil }
        .onChange(of: navigation.destination) { destination in
            if destination == .schedules { focusedParameter = nil }
        }
        .sheet(item: $editor) { item in
            ScriptEditor(item: item, resolve: store.resolved) { updated in
                guard workspaces.selectedID == workspaceInfo.id,
                      store.upsert(updated, expectedRevision: editorRevision) else { return false }
                navigation.selectScript(updated.id, in: session)
                return true
            }
        }
        .sheet(isPresented: $creatingFolder) { folderCreationSheet }
        .sheet(item: $schedulingItem) { task in
            ScheduleEditor(workspaces: workspaces, initial: task) { try schedules.save($0) }
        }
        .alert("删除文件夹？", isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("取消", role: .cancel) { deletingFolder = nil }
            Button("删除文件夹", role: .destructive) {
                if let path = deletingFolder { _ = store.removeFolder(path, expectedRevision: folderRevision) }
                deletingFolder = nil
            }
        } message: {
            let path = deletingFolder ?? ""
            let count = store.items.filter { ScriptGroup.contains($0.category, in: path) }.count
            Text("将删除“\(path)”及其子文件夹，其中 \(count) 个脚本会移到“未分组”。脚本配置、本地文件和执行历史均会保留。")
        }
        .alert("操作失败", isPresented: Binding(get: { error != nil || store.error != nil }, set: { if !$0 { error = nil; store.error = nil } })) {
            Button("好", role: .cancel) { error = nil; store.error = nil }
        } message: { Text(error ?? store.error ?? "") }
        .alert("从脚本库移除？", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button("取消", role: .cancel) { deleteItem = nil }
            Button("移除", role: .destructive) {
                if let item = deleteItem { store.remove(item.id); if session.selectedID == item.id { session.selectedID = store.items.first?.id } }
                deleteItem = nil
            }
        } message: { Text("仅移除应用中的配置，本地脚本文件会保留。") }
        .onAppear { reconcileParameters() }
        .onChange(of: store.revision) { _ in reconcileParameters() }
    }

    func reconcileParameters() {
        if !store.items.contains(where: { $0.id == session.selectedID }) { session.selectedID = store.items.first?.id }
        var retained: [String: [String: String]] = [:]
        for item in store.items {
            for parameter in item.parameters {
                if let value = session.values[item.id]?[parameter.id], parameter.passing == .flag || parameter.kind != .select || value.isEmpty || parameter.options.contains(where: { $0.value == value }) {
                    retained[item.id, default: [:]][parameter.id] = value
                }
            }
        }
        session.values = retained
    }

    func isActive(_ item: ScriptItem) -> Bool {
        runner.isActive(workspaceID: workspaceInfo.id, scriptID: item.id)
    }

    var workspacePane: some View {
        HSplitView {
            if preferences.sidebarVisible {
                sidebar
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 330, maxHeight: .infinity)
                    .background(.bar)
            }
            ZStack {
                configurationPane
                    .opacity(navigation.destination == .scripts ? 1 : 0)
                    .disabled(navigation.destination != .scripts)
                    .allowsHitTesting(navigation.destination == .scripts)
                    .accessibilityHidden(navigation.destination != .scripts)
                ScheduleDashboard(schedules: schedules, workspaces: workspaces, runner: runner,
                                  showOutput: { outputExpanded = true })
                    .opacity(navigation.destination == .schedules ? 1 : 0)
                    .allowsHitTesting(navigation.destination == .schedules)
                    .accessibilityHidden(navigation.destination != .schedules)
            }
            .frame(minWidth: 490, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
