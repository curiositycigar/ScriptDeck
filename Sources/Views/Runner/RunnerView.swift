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
                    Button(L("Reload")) { store.reloadFromDisk(force: true) }
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            GeometryReader { geometry in
                workspacePane
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: preferences.sidebarVisible ? 820 : 680, minHeight: 280)
        .navigationTitle(navigation.destination == .schedules ? L("Scheduled Tasks") : selected?.name ?? workspaceInfo.name)
        .navigationSubtitle(workspaceInfo.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { preferences.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(preferences.sidebarVisible ? L("Hide Sidebar") : L("Show Sidebar"))
                    .accessibilityLabel(preferences.sidebarVisible ? L("Hide Sidebar") : L("Show Sidebar"))
                if !preferences.sidebarVisible { workspaceMenu.frame(maxWidth: 220) }
            }
            ToolbarItemGroup {
                Button(action: importScripts) { Label(L("Import Scripts"), systemImage: "square.and.arrow.down") }
                    .help(L("Import local scripts (⌘I)"))
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
                Button { openEditor(ScriptItem()) } label: { Label(L("New Script"), systemImage: "plus") }
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
        .alert(L("Delete Folder?"), isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletingFolder = nil }
            Button(L("Delete Folder"), role: .destructive) {
                if let path = deletingFolder { _ = store.removeFolder(path, expectedRevision: folderRevision) }
                deletingFolder = nil
            }
        } message: {
            let path = deletingFolder ?? ""
            let count = store.items.filter { ScriptGroup.contains($0.category, in: path) }.count
            Text(L("Delete “{0}” and its subfolders, moving {1} scripts to “Ungrouped”. Script configurations, local files, and execution history will be preserved.", "\(path)", "\(count)"))
        }
        .alert(L("Operation Failed"), isPresented: Binding(get: { error != nil || store.error != nil }, set: { if !$0 { error = nil; store.error = nil } })) {
            Button(L("OK"), role: .cancel) { error = nil; store.error = nil }
        } message: { Text(error ?? store.error ?? "") }
        .alert(L("Remove from Library?"), isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button(L("Cancel"), role: .cancel) { deleteItem = nil }
            Button(L("Remove"), role: .destructive) {
                if let item = deleteItem { store.remove(item.id); if session.selectedID == item.id { session.selectedID = store.items.first?.id } }
                deleteItem = nil
            }
        } message: { Text(L("Only the configuration will be removed. Local script files will be preserved.")) }
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
