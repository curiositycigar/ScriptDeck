import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case folder(String)
    case script(String)
}

extension RunnerView {
    var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("WORKSPACES")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { beginFolderCreation() } label: { Image(systemName: "folder.badge.plus") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L("New Folder")).accessibilityLabel(L("New Folder"))
                        .disabled(store.directoryURL == nil || store.configurationIssue != nil)
                }
                workspaceMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search scripts"), text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L("Clear search"))
                }
            }
            .font(.callout).padding(9)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12).padding(.bottom, 12)
            .help(L("Search names, groups, or paths"))
            List(selection: sidebarSelection) {
                ForEach(ScriptGroup.tree(filtered, folders: visibleFolders)) { group in groupView(group) }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .workspaceListAppearance()
                .frame(minHeight: 0, maxHeight: .infinity)
                .overlay {
                if filtered.isEmpty && visibleFolders.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: search.isEmpty ? "tray" : "magnifyingglass").font(.title)
                        Text(store.configurationIssue != nil ? L("Workspace Unavailable") : store.items.isEmpty ? L("Drop scripts to add them") : L("No matching scripts"))
                            .font(.callout)
                    }.foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            .contextMenu {
                Button(L("New Folder…"), systemImage: "folder.badge.plus") { beginFolderCreation() }
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Scheduled Tasks")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { navigation.destination = .schedules } label: {
                    HStack {
                        Label(L("All Scheduled Tasks"), systemImage: "calendar.badge.clock")
                        Spacer()
                        Text("\(schedules.tasks.count)").foregroundStyle(.secondary)
                    }.padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(navigation.destination == .schedules ? WorkspaceStyle.selectionColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .background { if dropTarget { Color.accentColor.opacity(0.12) } }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
            guard store.directoryURL != nil, store.configurationIssue == nil else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { if let id = store.importURLs([url]) { navigation.selectScript(id, in: session) } }
                }
            }
            return true
        }
    }

    var scriptNavigationSelection: Binding<String?> {
        Binding(get: { navigation.highlightedScript(in: session) }, set: { id in
            // List deselection must not erase the workspace's remembered script.
            if let id { navigation.selectScript(id, in: session) }
        })
    }

    var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: {
            guard navigation.destination == .scripts else { return nil }
            if let folder = selectedSidebarFolder { return .folder(folder) }
            return navigation.highlightedScript(in: session).map(SidebarSelection.script)
        }, set: { selection in
            switch selection {
            case .folder(let id):
                navigation.destination = .scripts
                selectedSidebarFolder = id
            case .script(let id):
                selectedSidebarFolder = nil
                scriptNavigationSelection.wrappedValue = id
            case nil:
                break
            }
        })
    }

    func groupView(_ group: ScriptGroup) -> AnyView {
        AnyView(DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || (expandedGroups[group.id] ?? true) }, set: { expandedGroups[group.id] = $0 })) {
            ForEach(group.children) { child in groupView(child) }
            ForEach(group.scripts) { item in
                HStack {
                    Image(systemName: "terminal").foregroundStyle(.secondary).font(.system(size: 13))
                    Text(item.name).lineLimit(1)
                    Spacer()
                    if isActive(item) { ProgressView().controlSize(.small) }
                }.padding(.vertical, 4).tag(SidebarSelection.script(item.id)).help(item.path)
                .workspaceListSelection(sidebarSelection.wrappedValue == .script(item.id))
                .contextMenu {
                    Button(L("Edit")) { openEditor(item) }.disabled(isActive(item))
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.resolved(item).path)]) }
                    Button(L("Remove"), role: .destructive) { deleteItem = item }.disabled(isActive(item))
                }
            }
        } label: { Label { Text(group.displayName).font(.callout.weight(.medium)) } icon: {
            Image(systemName: "folder").foregroundStyle(.tint)
        }.contextMenu {
            Button(L("New Subfolder…"), systemImage: "folder.badge.plus") { beginFolderCreation(parent: group.id) }
            Button(L("New Script…"), systemImage: "plus") {
                var item = ScriptItem()
                item.category = group.id
                openEditor(item)
            }
            Divider()
            Button(L("Delete Folder…"), role: .destructive) {
                folderRevision = store.revision
                deletingFolder = group.id
            }.disabled(group.id == "未分组")
        }.disabled(store.configurationIssue != nil) }
        .tag(SidebarSelection.folder(group.id))
        .workspaceListSelection(sidebarSelection.wrappedValue == .folder(group.id)))
    }

    var visibleFolders: [String] {
        store.folders.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }

    func beginFolderCreation(parent: String = "") {
        folderName = ""
        folderParent = parent
        folderError = nil
        folderRevision = store.revision
        creatingFolder = true
    }

    var folderCreationSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(folderParent.isEmpty ? L("New Folder") : L("New Subfolder"), systemImage: "folder.badge.plus")
                .font(.title2.weight(.semibold))
            Text(folderParent.isEmpty ? L("Location: current workspace") : L("Location: {0}", "\(folderParent)"))
                .font(.callout).foregroundStyle(.secondary)
            TextField(L("Folder Name"), text: $folderName).textFieldStyle(.roundedBorder)
                .onSubmit { createFolder() }
            if let folderError { Text(folderError).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("Cancel"), role: .cancel) { creatingFolder = false }.keyboardShortcut(.cancelAction)
                Button(L("Create"), action: createFolder).keyboardShortcut(.defaultAction)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 380)
    }

    func createFolder() {
        guard store.createFolder(name: folderName, parent: folderParent, expectedRevision: folderRevision) else {
            folderError = store.error
            store.error = nil
            return
        }
        let path = folderParent.isEmpty ? folderName.trimmingCharacters(in: .whitespacesAndNewlines) : folderParent + "/" + folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/")
        for depth in 1...components.count { expandedGroups[components.prefix(depth).joined(separator: "/")] = true }
        search = ""
        creatingFolder = false
    }
}
