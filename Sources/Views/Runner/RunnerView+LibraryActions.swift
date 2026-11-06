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
            Button("添加 Workspace…", action: addWorkspace)
            Button("管理 Workspaces…", action: manageWorkspaces)
        } label: {
            Label(workspaceInfo.name, systemImage: "square.stack.3d.up")
                .font(.headline).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(workspaceInfo.directory)
        .accessibilityLabel("切换 Workspace：" + workspaceInfo.name)
    }

    var libraryMenu: some View {
        Menu {
            Button("在 Finder 中打开 Workspace") { NSWorkspace.shared.open(workspaceInfo.directoryURL) }
            Button("编辑 library.json") { if let file = store.fileURL { NSWorkspace.shared.open(file) } }
            Button("重新加载配置") { store.reloadFromDisk(force: true) }
            Divider()
            Button("管理 Workspaces…", action: manageWorkspaces)
        } label: { Image(systemName: "ellipsis.circle") }
        .help("Workspace 操作").accessibilityLabel("Workspace 操作")
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
