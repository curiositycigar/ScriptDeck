import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension RunnerView {
    var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKSPACES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                workspaceMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索脚本", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                }
            }
            .font(.callout).padding(9)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12).padding(.bottom, 12)
            .help("搜索名称、分组或路径")
            List(selection: scriptNavigationSelection) {
                ForEach(ScriptGroup.tree(filtered, folders: visibleFolders)) { group in groupView(group) }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .frame(minHeight: 0, maxHeight: .infinity)
                .overlay {
                if filtered.isEmpty && visibleFolders.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: search.isEmpty ? "tray" : "magnifyingglass").font(.title)
                        Text(store.configurationIssue != nil ? "Workspace 暂不可用" : store.items.isEmpty ? "拖入脚本以添加" : "没有匹配的脚本")
                            .font(.callout)
                    }.foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
            .contextMenu {
                Button("新建文件夹…", systemImage: "folder.badge.plus") { beginFolderCreation() }
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.vertical, 4)
                Text("定时任务").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { navigation.destination = .schedules } label: {
                    HStack {
                        Label("全部定时任务", systemImage: "calendar.badge.clock")
                        Spacer()
                        Text("\(schedules.tasks.count)").foregroundStyle(.secondary)
                    }.padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(navigation.destination == .schedules ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
            }.padding(.horizontal, 14).padding(.bottom, 12)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text(search.isEmpty ? "\(store.items.count) 个脚本" : "找到 \(filtered.count) 个脚本")
                Spacer()
                Button { beginFolderCreation() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.plain).help("新建文件夹").accessibilityLabel("新建文件夹")
                    .disabled(store.directoryURL == nil || store.configurationIssue != nil)
            }.font(.caption).foregroundStyle(.secondary).padding(14)
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

    func groupView(_ group: ScriptGroup) -> AnyView {
        AnyView(DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || (expandedGroups[group.id] ?? true) }, set: { expandedGroups[group.id] = $0 })) {
            ForEach(group.children) { child in groupView(child) }
            ForEach(group.scripts) { item in
                HStack {
                    Image(systemName: "terminal").foregroundStyle(.secondary).font(.system(size: 13))
                    Text(item.name).lineLimit(1)
                    Spacer()
                    if isActive(item) { ProgressView().controlSize(.small) }
                }.padding(.vertical, 4).tag(item.id).help(item.path)
                .contextMenu {
                    Button("编辑") { openEditor(item) }.disabled(isActive(item))
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.resolved(item).path)]) }
                    Button("移除", role: .destructive) { deleteItem = item }.disabled(isActive(item))
                }
            }
        } label: { Label { Text(group.name).font(.callout.weight(.medium)) } icon: {
            Image(systemName: "folder").foregroundStyle(.tint)
        }.contextMenu {
            Button("新建子文件夹…", systemImage: "folder.badge.plus") { beginFolderCreation(parent: group.id) }
            Button("新增脚本…", systemImage: "plus") {
                var item = ScriptItem()
                item.category = group.id
                openEditor(item)
            }
            Divider()
            Button("删除文件夹…", role: .destructive) {
                folderRevision = store.revision
                deletingFolder = group.id
            }.disabled(group.id == "未分组")
        }.disabled(store.configurationIssue != nil) })
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
            Label(folderParent.isEmpty ? "新建文件夹" : "新建子文件夹", systemImage: "folder.badge.plus")
                .font(.title2.weight(.semibold))
            Text(folderParent.isEmpty ? "位置：当前 Workspace" : "位置：\(folderParent)")
                .font(.callout).foregroundStyle(.secondary)
            TextField("文件夹名称", text: $folderName).textFieldStyle(.roundedBorder)
                .onSubmit { createFolder() }
            if let folderError { Text(folderError).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { creatingFolder = false }.keyboardShortcut(.cancelAction)
                Button("创建", action: createFolder).keyboardShortcut(.defaultAction)
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
