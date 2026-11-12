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
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var showScriptDetails = false
    @State var showParameterHistory = false
    @ObservedObject var parameterHistory = ParameterCallHistory.shared
    @State var scriptPathCopied = false
    @State var credentialScript: ScriptItem?
    @State var validatedScripts: Set<String> = []
    @FocusState var searchFocused: Bool
    @FocusState var focusedParameter: String?
    @State var search = ""
    @State var editor: ScriptItem?
    @State var editorRevision = 0
    @State var expandedGroups: [String: Bool] = [:]
    @State var selectedSidebarFolder: String?
    @State var error: String?
    @State var deleteItem: ScriptItem?
    @State var creatingFolder = false
    @State var folderName = ""
    @State var folderParent = ""
    @State var folderError: String?
    @State var folderRevision = 0
    @State var deletingFolder: String?
    @State var dropTarget = false

    var selected: ScriptItem? { store.items.first { $0.id == session.selectedID } }
    var filtered: [ScriptItem] {
        store.items.filter { search.isEmpty || "\($0.name) \($0.category) \($0.path)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.configurationIssue {
                HStack(alignment: .top) {
                    WorkspaceSymbol("exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(issue).font(WorkspaceTypography.caption).textSelection(.enabled)
                    Spacer()
                    Button(L("Reload")) { store.reloadFromDisk(force: true) }
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            GeometryReader { geometry in
                workspacePane
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .workspaceTypography()
        .background(WorkspaceStyle.canvas)
        .frame(minWidth: preferences.sidebarVisible ? 740 : 600, minHeight: 280)
        .toolbar { workspaceToolbar }
        .toolbarBackground(.visible, for: .windowToolbar)
        .focusedSceneValue(\.runnerActions, RunnerActions(
            canImport: navigation.destination == .scripts && store.directoryURL != nil && store.configurationIssue == nil,
            sidebarVisible: preferences.sidebarVisible, canToggleSidebar: navigation.destination == .scripts,
            importScripts: importScripts,
            newScript: { openEditor(ScriptItem()) },
            findScript: {
                navigation.destination = .scripts
                preferences.sidebarVisible = true
                // The search field must be mounted before focus is requested.
                DispatchQueue.main.async { searchFocused = true }
            },
            toggleSidebar: { preferences.sidebarVisible.toggle() }
        ))
        .onChange(of: session.selectedID) { _ in
            showScriptDetails = false
            showParameterHistory = false
            focusedParameter = nil
            selectedSidebarFolder = nil
        }
        .onChange(of: navigation.destination) { destination in
            if destination != .scripts {
                searchFocused = false
                focusedParameter = nil
            }
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
        .sheet(item: $credentialScript) { item in
            CredentialManagerView(runner: runner,
                                  target: CredentialTarget(workspaceID: workspaceInfo.id, scriptID: item.id),
                                  scriptName: item.name)
        }
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
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
                    .background(WorkspaceStyle.sidebar)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            configurationPane
                .frame(minWidth: 490, maxWidth: .infinity, maxHeight: .infinity)
        }
        .workspaceAnimation(value: preferences.sidebarVisible, motion: .layout)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
