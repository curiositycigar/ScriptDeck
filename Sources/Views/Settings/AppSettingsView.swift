import SwiftUI
import AppKit

struct AppSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner

    var body: some View {
        TabView(selection: $preferences.settingsTab) {
            Form {
                Section(L("Language")) {
                    Picker(L("App Language"), selection: $preferences.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    Text(L("Quit and reopen ScriptDeck to apply language changes. Running tasks are not interrupted by changing this setting."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("General"), systemImage: "gearshape") }.tag(SettingsTab.general)
            WorkspaceSettingsView(workspaces: workspaces, runner: runner)
                .tabItem { Label(L("Workspaces"), systemImage: "square.stack.3d.up") }.tag(SettingsTab.workspaces)
            CredentialManagerView(runner: runner, canDismiss: false)
                .tabItem { Label(L("Credentials"), systemImage: "key") }.tag(SettingsTab.credentials)
            Form {
                Section {
                    WorkspaceSectionTitle(title: L("Terminal Appearance"), subtitle: L("Adjust fonts and scrollback for all workspaces."))
                }
                Section(L("Display")) {
                    Stepper(value: $preferences.terminalFontSize, in: 10...24, step: 1) {
                        LabeledContent(L("Font Size"), value: "\(Int(preferences.terminalFontSize)) pt")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("❯ ./script.sh").foregroundStyle(.secondary)
                        Text(L("Hello, world."))
                    }
                    .font(.system(size: preferences.terminalFontSize, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    Text(L("Font size changes apply to terminals immediately."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L("History")) {
                    Picker(L("Scrollback Lines"), selection: $preferences.terminalScrollback) {
                        ForEach(AppPreferences.historyOptions, id: \.self) { count in
                            Text(L("{0} lines", "\(count)")).tag(count)
                        }
                    }
                    Text(L("Applies to new sessions. Current terminal contents are preserved."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L("Terminal"), systemImage: "terminal") }.tag(SettingsTab.terminal)
        }
        .padding(20)
        .frame(width: 780, height: 560)
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    @Environment(\.openWindow) private var openWindow
    @State private var selectedID: String?
    @State private var editing: Workspace?
    @State private var draftName = ""
    @State private var pendingRemoval: Workspace?
    private var selected: Workspace? { workspaces.items.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WorkspaceSectionTitle(title: L("Workspaces"), subtitle: L("Manage independent script libraries. Each workspace keeps its own run parameters while you switch."))
                Spacer()
                Button { WorkspaceDialogs.add(to: workspaces) } label: { Label(L("Add…"), systemImage: "plus") }
            }
            List(selection: $selectedID) {
                ForEach(workspaces.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).fontWeight(.medium)
                            if item.id == workspaces.selectedID { Text(L("Current")).font(.caption).foregroundStyle(.secondary) }
                            if runner.isWorkspaceRunning(item.id) { Text(L("Running")).font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            if let issue = workspaces.availability[item.id] {
                                Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(item.directory).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(item.directory)
                        }
                    }.padding(.vertical, 9).tag(item.id)
                        .workspaceListSelection(selectedID == item.id)
                }
            }
            .listStyle(.inset)
            .workspaceListAppearance()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if workspaces.items.isEmpty {
                    WorkspaceEmptyState(symbol: "folder.badge.plus", title: L("No Workspaces Yet"), message: L("Add a folder containing a script library."))
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button { if let selected { workspaces.move(selected.id, by: -1) } } label: { Image(systemName: "arrow.up") }
                    .disabled(selected == nil || workspaces.items.first?.id == selectedID)
                    .help(L("Move up")).accessibilityLabel(L("Move workspace up"))
                Button { if let selected { workspaces.move(selected.id, by: 1) } } label: { Image(systemName: "arrow.down") }
                    .disabled(selected == nil || workspaces.items.last?.id == selectedID)
                    .help(L("Move down")).accessibilityLabel(L("Move workspace down"))
                Spacer()
                if let selected {
                    Menu(L("More")) {
                        Button(L("Rename…")) { draftName = selected.name; editing = selected }
                        Button(L("Open in Finder")) { NSWorkspace.shared.open(selected.directoryURL) }
                        Button(L("Relocate…")) { WorkspaceDialogs.relocate(selected, in: workspaces, runner: runner) }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                        Divider()
                        Button(L("Remove Registration…"), role: .destructive) { pendingRemoval = selected }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                    }
                    Button(L("Open")) { workspaces.select(selected.id); openWindow(id: "main") }
                        .workspacePrimaryAction()
                }
            }
            Text(L("Removing a registration preserves folders and files. Finish a workspace's running tasks before removing or relocating it."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .onAppear { selectedID = workspaces.selectedID ?? workspaces.items.first?.id }
        .onChange(of: workspaces.selectedID) { id in selectedID = id }
        .onChange(of: workspaces.items) { items in
            if !items.contains(where: { $0.id == selectedID }) { selectedID = workspaces.selectedID ?? items.first?.id }
        }
        .alert(L("Rename Workspace"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(L("Name"), text: $draftName)
            Button(L("Cancel"), role: .cancel) { editing = nil }
            Button(L("Save")) {
                do { if let editing { try workspaces.rename(editing.id, to: draftName) } }
                catch { workspaces.error = error.localizedDescription }
                editing = nil
            }.disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(L("Remove Workspace Registration?"), isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button(L("Cancel"), role: .cancel) { pendingRemoval = nil }
            Button(L("Remove"), role: .destructive) {
                do { if let pendingRemoval { try workspaces.remove(pendingRemoval.id, protectedID: runner.protectedWorkspaceID(for: pendingRemoval.id)) } }
                catch { workspaces.error = error.localizedDescription }
                pendingRemoval = nil
            }
        } message: { Text(L("Only the local registration for “{0}” will be removed. Its folder, scripts, and configuration will be preserved.", "\(pendingRemoval?.name ?? "")")) }
    }
}
