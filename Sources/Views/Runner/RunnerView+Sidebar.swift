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
            HStack(spacing: 7) {
                WorkspaceSymbol("magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search scripts"), text: $search).textFieldStyle(.plain)
                    .focused($searchFocused)
                if search.isEmpty {
                    Text("⌘F").font(WorkspaceTypography.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                } else {
                    Button { search = "" } label: { WorkspaceSymbol("xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L("Clear search"))
                }
            }
            .font(WorkspaceTypography.body).padding(9)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            .help(L("Search names, groups, or paths"))
            HStack(spacing: 2) {
                workspaceMenu
                    .layoutPriority(-1)
                Button { beginFolderCreation() } label: { WorkspaceSymbol("folder.badge.plus", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("New Folder")).accessibilityLabel(L("New Folder"))
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
                Button { openEditor(ScriptItem()) } label: { WorkspaceSymbol("plus", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("New Script")).accessibilityLabel(L("New Script"))
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }
            .padding(.horizontal, 12).padding(.bottom, 4)
            List(selection: sidebarSelection) {
                ForEach(sidebarRows) { row in
                    switch row.content {
                    case .folder(let group):
                        folderRow(group, depth: row.depth)
                    case .script(let item):
                        scriptRow(item, depth: row.depth)
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .workspaceListAppearance()
                .workspaceAnimation(value: expandedGroups, motion: .layout)
                .frame(minHeight: 0, maxHeight: .infinity)
                .overlay {
                if filtered.isEmpty && visibleFolders.isEmpty {
                    VStack(spacing: 10) {
                        WorkspaceSymbol(search.isEmpty ? "tray" : "magnifyingglass", size: .emptyState)
                        Text(store.configurationIssue != nil ? L("Workspace Unavailable") : store.items.isEmpty ? L("Drop scripts to add them") : L("No matching scripts"))
                            .font(WorkspaceTypography.body)
                    }.foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            .contextMenu {
                Button(L("New Folder…"), systemImage: "folder.badge.plus") { beginFolderCreation() }
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            HStack(spacing: 6) {
                WorkspaceSymbol(store.configurationIssue == nil ? "folder" : "exclamationmark.triangle")
                Text(L("{0} scripts", "\(store.items.count)"))
                Spacer()
                libraryMenu.buttonStyle(.plain)
            }
            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
        .background { if dropTarget { Color.accentColor.opacity(0.12) } }
        .workspaceAnimation(value: dropTarget)
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

    // Flat native rows preserve selection and keyboard navigation without disclosure gutters.
    private var sidebarRows: [SidebarTreeRow] {
        func rows(_ groups: [ScriptGroup], depth: Int) -> [SidebarTreeRow] {
            groups.flatMap { group in
                var result = [SidebarTreeRow(content: .folder(group), depth: depth)]
                if isFolderExpanded(group.id) {
                    result += rows(group.children, depth: depth + 1)
                    result += group.scripts.map { SidebarTreeRow(content: .script($0), depth: depth + 1) }
                }
                return result
            }
        }
        return rows(ScriptGroup.tree(filtered, folders: visibleFolders), depth: 0)
    }

    func isFolderExpanded(_ id: String) -> Bool {
        !search.isEmpty || (expandedGroups[id] ?? true)
    }

    func isFolderEmpty(_ id: String) -> Bool {
        !store.items.contains { ScriptGroup.contains($0.category, in: id) }
            && !store.folders.contains { $0.hasPrefix(id + "/") }
    }

    func scriptRow(_ item: ScriptItem, depth: Int) -> some View {
        HStack(spacing: 6) {
            WorkspaceSymbol("terminal").foregroundStyle(.secondary)
            Text(item.name).font(WorkspaceTypography.body).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if isActive(item) { ProgressView().controlSize(.small) }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .frame(minHeight: 30)
        .tag(SidebarSelection.script(item.id)).help(item.path)
        .workspaceListSelection(sidebarSelection.wrappedValue == .script(item.id))
        .contextMenu {
            Button(L("Edit")) { openEditor(item) }.disabled(isActive(item))
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.resolved(item).path)]) }
            Button(L("Remove"), role: .destructive) { deleteItem = item }.disabled(isActive(item))
        }
    }

    func folderRow(_ group: ScriptGroup, depth: Int) -> some View {
        let empty = isFolderEmpty(group.id)
        let expanded = isFolderExpanded(group.id)
        return HStack(spacing: 6) {
            SidebarFolderIcon(isEmpty: empty, isExpanded: expanded)
            Text(group.displayName).font(WorkspaceTypography.bodyStrong).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Text("\(store.items.filter { ScriptGroup.contains($0.category, in: group.id) }.count)")
                .font(WorkspaceTypography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.leading, CGFloat(depth) * 18)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            sidebarSelection.wrappedValue = .folder(group.id)
            if !empty { expandedGroups[group.id] = !expanded }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            sidebarSelection.wrappedValue = .folder(group.id)
            if !empty { expandedGroups[group.id] = !expanded }
        }
        .accessibilityValue(empty ? L("Empty Folder") : expanded ? L("Expanded") : L("Collapsed"))
        .contextMenu {
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
        }
        .disabled(store.configurationIssue != nil)
        .tag(SidebarSelection.folder(group.id))
        .workspaceListSelection(sidebarSelection.wrappedValue == .folder(group.id))
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
            HStack(spacing: 10) {
                WorkspaceSymbol("folder.badge.plus", size: .header).foregroundStyle(.tint)
                Text(folderParent.isEmpty ? L("New Folder") : L("New Subfolder"))
                    .font(WorkspaceTypography.dialogTitle)
            }
            Text(folderParent.isEmpty ? L("Location: current workspace") : L("Location: {0}", "\(folderParent)"))
                .font(WorkspaceTypography.body).foregroundStyle(.secondary)
            TextField(L("Folder Name"), text: $folderName).textFieldStyle(.roundedBorder)
                .onSubmit { createFolder() }
            if let folderError { Text(folderError).font(WorkspaceTypography.body).foregroundStyle(.red) }
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

private struct SidebarTreeRow: Identifiable {
    enum Content {
        case folder(ScriptGroup)
        case script(ScriptItem)
    }
    let content: Content
    let depth: Int
    var id: SidebarSelection {
        switch content {
        case .folder(let group): return .folder(group.id)
        case .script(let item): return .script(item.id)
        }
    }
}

private struct SidebarFolderIcon: View {
    let isEmpty: Bool
    let isExpanded: Bool

    var body: some View {
        Group {
            if isEmpty {
                WorkspaceSymbol("folder").foregroundStyle(.secondary)
            } else if isExpanded {
                // An open front flap distinguishes expanded folders without an extra chevron.
                OpenFolderShape()
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay { OpenFolderShape().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)) }
                    .frame(width: 14, height: 12)
                    .frame(width: WorkspaceIconSize.inline.footprint, height: WorkspaceIconSize.inline.footprint)
            } else {
                WorkspaceSymbol("folder.fill").foregroundStyle(.tint)
            }
        }
        .accessibilityHidden(true)
        .workspaceAnimation(value: isExpanded)
    }
}

private struct OpenFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: point(0.04, 0.87))
            path.addLine(to: point(0.04, 0.12))
            path.addQuadCurve(to: point(0.12, 0.04), control: point(0.04, 0.04))
            path.addLine(to: point(0.38, 0.04))
            path.addLine(to: point(0.50, 0.21))
            path.addLine(to: point(0.86, 0.21))
            path.addLine(to: point(0.86, 0.39))
            path.addLine(to: point(0.25, 0.39))
            path.addLine(to: point(0.04, 0.93))
            path.closeSubpath()
            path.move(to: point(0.04, 0.93))
            path.addLine(to: point(0.25, 0.39))
            path.addLine(to: point(0.98, 0.39))
            path.addLine(to: point(0.79, 0.93))
            path.closeSubpath()
        }
    }
}
