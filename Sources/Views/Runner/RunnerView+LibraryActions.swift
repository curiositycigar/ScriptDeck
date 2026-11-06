import SwiftUI
import AppKit

extension RunnerView {
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
            Button(L("Manage Workspaces…"), action: manageWorkspaces)
        } label: {
            Label(workspaceInfo.name, systemImage: "square.stack.3d.up")
                .font(.headline).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(workspaceInfo.directory)
        .accessibilityLabel(L("Switch workspace: ") + workspaceInfo.name)
    }

    var libraryMenu: some View {
        Menu {
            Button(L("Open Workspace in Finder")) { NSWorkspace.shared.open(workspaceInfo.directoryURL) }
            Button(L("Edit library.json")) { if let file = store.fileURL { NSWorkspace.shared.open(file) } }
            Button(L("Reload Configuration")) { store.reloadFromDisk(force: true) }
            Divider()
            Button(L("Manage Workspaces…"), action: manageWorkspaces)
        } label: { Image(systemName: "ellipsis.circle") }
        .help(L("Workspace Actions")).accessibilityLabel(L("Workspace Actions"))
    }
    func addWorkspace() { WorkspaceDialogs.add(to: workspaces) }
    func manageWorkspaces() {
        preferences.settingsTab = .workspaces
        openWindow(id: "settings")
    }
    func openEditor(_ item: ScriptItem) {
        editorRevision = store.revision
        editor = item
    }
}
