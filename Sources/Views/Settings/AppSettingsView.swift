import SwiftUI
import AppKit

struct AppSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $preferences.settingsTab)
            Divider()
            Group {
                switch preferences.settingsTab {
                case .general: generalPane
                case .credentials: CredentialManagerView(runner: runner, canDismiss: false)
                case .terminal: terminalPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas)
        .workspaceTypography()
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsPaneHeader(title: L("General"), symbol: "gearshape", showsSymbol: false)
            ScrollView {
                SettingsSection(title: L("Language"),
                                help: L("Quit and reopen ScriptDeck to apply language changes. Running tasks are not interrupted by changing this setting.")) {
                    Picker(L("App Language"), selection: $preferences.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .padding(24)
    }

    private var terminalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsPaneHeader(title: L("Terminal Appearance"),
                               subtitle: L("Adjust fonts and scrollback for all workspaces."), symbol: "terminal", showsSymbol: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection(title: L("Display"),
                                    help: L("Font size changes apply to terminals immediately.")) {
                        Stepper(value: $preferences.terminalFontSize, in: 10...24, step: 1) {
                            LabeledContent(L("Font Size"), value: "\(Int(preferences.terminalFontSize)) pt")
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("❯ ./script.sh").foregroundStyle(.secondary)
                            Text(L("Hello, world."))
                        }
                        .font(WorkspaceTypography.terminal(size: preferences.terminalFontSize))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                    }
                    SettingsSection(title: L("History"),
                                    help: L("Applies to new sessions. Current terminal contents are preserved.")) {
                        Picker(L("Scrollback Lines"), selection: $preferences.terminalScrollback) {
                            ForEach(AppPreferences.historyOptions, id: \.self) { count in
                                Text(L("{0} lines", "\(count)")).tag(count)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}

/// Sidebar rows have identical hit areas and equal space around the selection.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    private let tabs: [(SettingsTab, String, String)] = [
        (.general, "General", "gearshape"),
        (.credentials, "Credentials", "key"),
        (.terminal, "Terminal", "terminal")
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title, symbol in
                Button { selection = tab } label: {
                    HStack(spacing: 10) {
                        WorkspaceSymbol(symbol, size: .navigation)
                        Text(L(title)).font(WorkspaceTypography.bodyStrong)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(WorkspaceNavigationButtonStyle(selected: selection == tab, cornerRadius: 10))
                .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 184)
        .frame(maxHeight: .infinity)
        .background(WorkspaceStyle.sidebar)
    }
}

/// Section headings, cards and help share the pane's leading and trailing edges.
private struct SettingsSection<Content: View>: View {
    let title: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(WorkspaceTypography.sectionTitle)
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
            Text(help).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    var onOpen: () -> Void = {}
    @State private var selectedID: String?
    @State private var editing: Workspace?
    @State private var draftName = ""
    @State private var pendingRemoval: Workspace?
    private var selected: Workspace? { workspaces.items.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                SettingsPaneHeader(title: L("Workspaces"),
                                   subtitle: L("Manage independent script libraries. Each workspace keeps its own run parameters while you switch."), symbol: "square.stack.3d.up", showsSymbol: false)
                Spacer()
                Button { WorkspaceDialogs.add(to: workspaces) } label: { Label(L("Add…"), systemImage: "plus") }
            }
            List(selection: $selectedID) {
                ForEach(workspaces.items) { item in
                    HStack(spacing: 12) {
                        WorkspaceSymbol("folder.fill", size: .navigation)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: WorkspaceControlMetrics.navigationTarget, height: WorkspaceControlMetrics.navigationTarget)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).font(WorkspaceTypography.bodyStrong).lineLimit(1).help(item.name)
                            if item.id == workspaces.selectedID { Text(L("Current")).font(WorkspaceTypography.caption).foregroundStyle(.secondary) }
                            if runner.isWorkspaceRunning(item.id) { Text(L("Running")).font(WorkspaceTypography.caption).foregroundStyle(.orange) }
                            Spacer()
                            if let issue = workspaces.availability[item.id] {
                                Label(issue, systemImage: "exclamationmark.triangle").font(WorkspaceTypography.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(item.directory).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(item.directory)
                        }
                    }.padding(.vertical, 9).tag(item.id)
                        .workspaceListSelection(selectedID == item.id)
                }
            }
            .listStyle(.inset)
            .workspaceListAppearance()
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .background(WorkspaceStyle.groupedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if workspaces.items.isEmpty {
                    WorkspaceEmptyState(symbol: "folder.badge.plus", title: L("No Workspaces Yet"), message: L("Add a folder containing a script library."))
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button { if let selected { workspaces.move(selected.id, by: -1) } } label: { WorkspaceSymbol("arrow.up") }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .disabled(selected == nil || workspaces.items.first?.id == selectedID)
                    .help(L("Move up")).accessibilityLabel(L("Move workspace up"))
                Button { if let selected { workspaces.move(selected.id, by: 1) } } label: { WorkspaceSymbol("arrow.down") }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .disabled(selected == nil || workspaces.items.last?.id == selectedID)
                    .help(L("Move down")).accessibilityLabel(L("Move workspace down"))
                Spacer()
                if let selected {
                    Menu {
                        Button(L("Rename…")) { draftName = selected.name; editing = selected }
                        Button(L("Open in Finder")) { NSWorkspace.shared.open(selected.directoryURL) }
                        Button(L("Relocate…")) { WorkspaceDialogs.relocate(selected, in: workspaces, runner: runner) }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                        Divider()
                        Button(L("Remove Registration…"), role: .destructive) { pendingRemoval = selected }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                    } label: {
                        WorkspaceSymbol("ellipsis", size: .toolbar)
                            .frame(width: WorkspaceControlMetrics.iconTarget, height: WorkspaceControlMetrics.iconTarget)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .help(L("More Actions")).accessibilityLabel(L("More Actions"))
                    Button(L("Open")) { workspaces.select(selected.id); onOpen() }
                        .workspacePrimaryAction()
                }
            }
            Text(L("Removing a registration preserves folders and files. Finish a workspace's running tasks before removing or relocating it."))
                .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(WorkspaceStyle.canvas)
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
