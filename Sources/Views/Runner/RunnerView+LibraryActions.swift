import SwiftUI
import AppKit

extension RunnerView {
    @ToolbarContentBuilder var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { preferences.sidebarVisible.toggle() } label: {
                WorkspaceSymbol("sidebar.left", size: .toolbar)
            }
            .buttonStyle(WorkspaceIconButtonStyle())
            .help(preferences.sidebarVisible ? L("Hide Sidebar") : L("Show Sidebar"))
            .accessibilityLabel(preferences.sidebarVisible ? L("Hide Sidebar") : L("Show Sidebar"))
            // Keep toolbar geometry stable while hiding script-only controls.
            .opacity(navigation.destination == .scripts ? 1 : 0)
            .disabled(navigation.destination != .scripts)
            .allowsHitTesting(navigation.destination == .scripts)
            .accessibilityHidden(navigation.destination != .scripts)
        }
        .workspaceToolbarAppearance()
        ToolbarItemGroup(placement: .primaryAction) {
            if navigation.destination == .scripts && !preferences.sidebarVisible {
                libraryMenu
            }
        }
        .workspaceToolbarAppearance()
    }

    var workspaceMenu: some View {
        Menu {
            ForEach(workspaces.items) { item in
                Button {
                    workspaces.select(item.id)
                } label: {
                    Label(item.name + (workspaces.availability[item.id].map { " · " + $0 } ?? ""),
                          systemImage: item.id == workspaceInfo.id ? "checkmark" : "folder")
                }.help(item.directory)
            }
            Divider()
            Button(L("Add Workspace…"), action: addWorkspace)
            Button(L("Import Workspace Package…")) { WorkspaceDialogs.importPackage(to: workspaces) }
            Button(L("Export Workspace Package…")) { WorkspaceDialogs.export(workspaceInfo, from: workspaces) }
            Button(L("Manage Workspaces…"), action: manageWorkspaces)
        } label: {
            HStack(spacing: SidebarLayout.itemSpacing) {
                WorkspaceSymbol("square.stack.3d.up").foregroundStyle(.secondary).fixedSize()
                Text(workspaceInfo.name)
                    .underline(false)
                    .font(WorkspaceTypography.bodyStrong).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
                WorkspaceSymbol("chevron.down", size: .disclosure).foregroundStyle(.secondary).fixedSize()
            }
            .padding(.horizontal, SidebarLayout.contentInset)
            .frame(maxWidth: .infinity, minHeight: SidebarLayout.controlHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(WorkspaceSwitcherButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(L("Switch workspace: ") + workspaceInfo.name + "\n" + workspaceInfo.directory)
        .accessibilityLabel(L("Switch workspace: ") + workspaceInfo.name)
    }

    var libraryMenu: some View {
        Menu {
            Button(L("Open Workspace in Finder")) { NSWorkspace.shared.open(workspaceInfo.directoryURL) }
            Button(L("Edit library.json")) { if let file = store.fileURL { NSWorkspace.shared.open(file) } }
            Button(L("Reload Configuration")) { store.reloadFromDisk(force: true) }
            Divider()
            Button(L("Manage Workspaces…"), action: manageWorkspaces)
        } label: { WorkspaceSymbol("ellipsis.circle", size: .toolbar).workspaceCompactTarget() }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(L("Workspace Actions")).accessibilityLabel(L("Workspace Actions"))
    }
    func addWorkspace() { WorkspaceDialogs.add(to: workspaces) }
    func manageWorkspaces() {
        navigation.managingWorkspaces = true
    }
    func openEditor(_ item: ScriptItem) {
        editorRevision = store.revision
        editor = item
    }
}
