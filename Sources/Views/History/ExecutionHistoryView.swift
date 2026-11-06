import SwiftUI
import AppKit

struct ExecutionHistoryView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    @StateObject private var model = HistoryViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var workspaceFilter = ""
    @State private var scriptFilter = ""
    @State private var search = ""
    @State private var deletionRequest: HistoryDeletionRequest?
    @State private var deletionError: String?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var selected: HistoryEntry? { model.entries.first { $0.id == selectedID } }
    private func workspaceKey(_ entry: HistoryEntry) -> String { entry.record.workspaceID ?? "unassigned" }
    private func scriptKey(_ entry: HistoryEntry) -> String { workspaceKey(entry) + "/" + entry.record.scriptID }
    private var workspaceChoices: [(id: String, name: String)] {
        var seen = Set<String>()
        return model.entries.compactMap { entry in
            let key = workspaceKey(entry)
            guard seen.insert(key).inserted else { return nil }
            return (key, entry.record.workspaceName.isEmpty ? "未指定 Workspace" : entry.record.workspaceName)
        }
    }
    private var scriptChoices: [(id: String, name: String)] {
        var seen = Set<String>()
        return model.entries.compactMap { entry in
            guard workspaceFilter.isEmpty || workspaceKey(entry) == workspaceFilter else { return nil }
            let key = scriptKey(entry)
            guard seen.insert(key).inserted else { return nil }
            return (key, entry.record.scriptName + (workspaceFilter.isEmpty && !entry.record.workspaceName.isEmpty ? " · " + entry.record.workspaceName : ""))
        }
    }
    private var filtered: [HistoryEntry] {
        model.entries.filter { entry in
            (workspaceFilter.isEmpty || workspaceKey(entry) == workspaceFilter) &&
            (scriptFilter.isEmpty || scriptKey(entry) == scriptFilter) &&
            (search.isEmpty || "\(entry.record.scriptName) \(entry.record.workspaceName) \(entry.record.scriptFile)".localizedCaseInsensitiveContains(search))
        }
    }

    private var busy: Bool { model.loading || model.deleting }
    private func deletable(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.filter { !runner.protectedHistoryRecordIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("执行历史").font(.title3.weight(.semibold))
                    Text("浏览执行结果与保存在本地的完整日志").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button {
                    if let selected { requestDeletion([selected], scope: .selected) }
                } label: { Label("删除记录", systemImage: "trash") }
                    .disabled(busy || selected == nil || runner.protectedHistoryRecordIDs.contains(selectedID ?? ""))
                Menu {
                    Button("清空筛选结果…", role: .destructive) { requestDeletion(filtered, scope: .filtered) }
                        .disabled(deletable(filtered).isEmpty)
                    Divider()
                    Button("清空全部历史…", role: .destructive) { requestDeletion(model.entries, scope: .all) }
                        .disabled(deletable(model.entries).isEmpty)
                } label: { Label("清空", systemImage: "trash.slash") }
                    .disabled(busy || model.entries.isEmpty)
                Button { Task { await refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(busy)
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.deleting)
            }.padding(20).background(.bar)
            HStack(spacing: 12) {
                Picker("Workspace", selection: $workspaceFilter) {
                    Text("所有 Workspaces").tag("")
                    ForEach(workspaceChoices, id: \.id) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 240)
                Picker("脚本", selection: $scriptFilter) {
                    Text("所有脚本").tag("")
                    ForEach(scriptChoices, id: \.id) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                TextField("搜索脚本、Workspace 或路径", text: $search).textFieldStyle(.roundedBorder)
            }.padding(.horizontal, 20).padding(.vertical, 14).disabled(model.deleting)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(filtered) { entry in
                        historyRow(entry).tag(entry.id)
                            .contextMenu {
                                Button("删除此记录…", role: .destructive) { requestDeletion([entry], scope: .selected) }
                                    .disabled(busy || runner.protectedHistoryRecordIDs.contains(entry.id))
                            }
                    }
                }
                .onDeleteCommand {
                    if let selected, !busy { requestDeletion([selected], scope: .selected) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .frame(minWidth: 270, idealWidth: 300, maxWidth: 370)
                .overlay {
                    if filtered.isEmpty && !model.loading {
                        VStack(spacing: 10) {
                            Image(systemName: "clock").font(.title).foregroundStyle(.tertiary)
                            Text(model.entries.isEmpty ? "暂无执行记录" : "没有匹配的记录").font(.callout)
                            if model.entries.isEmpty { Text("运行脚本后会自动保存日志").font(.caption) }
                        }.foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                detail.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("\(filtered.count) 条记录").foregroundStyle(.secondary)
                if let warning = model.warning { Text(warning).foregroundStyle(.orange).lineLimit(1).help(warning) }
                Spacer()
                Text("日志保存在各脚本目录的 logs/脚本文件名/ 中。") .foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
        }
        .frame(minWidth: 960, idealWidth: 1040, minHeight: 620, idealHeight: 700)
        .interactiveDismissDisabled(model.deleting)
        .alert(deletionRequest?.title ?? "删除历史记录？", isPresented: Binding(
            get: { deletionRequest != nil }, set: { if !$0 { deletionRequest = nil } }
        )) {
            Button("取消", role: .cancel) { deletionRequest = nil }
            Button("删除", role: .destructive) {
                guard let request = deletionRequest else { return }
                deletionRequest = nil
                Task {
                    deletionError = await model.remove(request.entries, protectedIDs: runner.protectedHistoryRecordIDs)
                    await refresh()
                }
            }
        } message: { Text(deletionRequest?.message ?? "") }
        .alert("部分历史记录删除失败", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) {
            Button("好", role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
        .task {
            selectedID = runner.recordID
            await refresh()
        }
        .task(id: selectedID) { if let selected { await model.load(selected) } }
        .onChange(of: workspaceFilter) { _ in scriptFilter = "" }
        .onChange(of: filtered.map(\.id)) { ids in
            if !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: runner.historyRevision) { _ in Task { await refresh() } }
        .onReceive(refreshTimer) { _ in
            if let selectedID, runner.activeRecordIDs.contains(selectedID) { Task { await refreshPage() } }
        }
    }

    private func requestDeletion(_ entries: [HistoryEntry], scope: HistoryDeletionRequest.Scope) {
        guard !busy else { return }
        let targets = deletable(entries)
        guard !targets.isEmpty else { return }
        let criteria = [
            workspaceChoices.first { $0.id == workspaceFilter }.map { "Workspace：" + $0.name },
            scriptChoices.first { $0.id == scriptFilter }.map { "脚本：" + $0.name },
            search.isEmpty ? nil : "搜索：" + search
        ].compactMap { $0 }.joined(separator: "；")
        deletionRequest = HistoryDeletionRequest(entries: targets, scope: scope, criteria: criteria)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        let failed = entry.record.outcome == .failed || entry.record.outcome == .launchFailed
        let color: Color = entry.record.outcome == .succeeded ? .green : failed ? .red : .secondary
        let symbol = entry.record.outcome == .succeeded ? "checkmark.circle.fill" : failed ? "exclamationmark.circle.fill" : "clock"
        return VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.record.scriptName)
                    .font(.callout.weight(.semibold)).lineLimit(1)
                    .help(entry.record.scriptName)
                Spacer(minLength: 8)
                Label(entry.status(activeRecordID: runner.activeRecordIDs.contains(entry.id) ? entry.id : nil), systemImage: symbol)
                    .font(.caption.weight(.medium)).foregroundStyle(color).fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(entry.record.workspaceName.isEmpty ? "未指定 Workspace" : entry.record.workspaceName,
                      systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle).help(entry.record.workspaceName)
                Spacer(minLength: 8)
                Text(entry.record.startedAt.formatted(date: .numeric, time: .shortened))
                    .monospacedDigit().fixedSize()
            }.font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var detail: some View {
        if let entry = selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.record.scriptName).font(.title3.weight(.semibold))
                        Text(entry.record.scriptFile).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(entry.record.scriptFile)
                    }
                    Spacer()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.logURL]) }
                }
                HStack(spacing: 14) {
                    Text(entry.status(activeRecordID: runner.activeRecordIDs.contains(entry.id) ? entry.id : nil))
                    if let code = entry.record.exitCode { Text("退出码 \(code)") }
                    if let end = entry.record.endedAt {
                        Text("耗时 \(max(0, Int(end.timeIntervalSince(entry.record.startedAt)))) 秒")
                    }
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary)
                Text("开始：" + entry.record.startedAt.formatted(date: .complete, time: .standard))
                    .font(.caption).foregroundStyle(.secondary)
                if let end = entry.record.endedAt {
                    Text("结束：" + end.formatted(date: .complete, time: .standard)).font(.caption).foregroundStyle(.secondary)
                }
                if let issue = entry.record.logError { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                Divider()
                if let error = model.pageError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if model.pageRecordID == entry.id, let page = model.page {
                    GeometryReader { geometry in
                        ScrollView([.vertical, .horizontal]) {
                            Text(page.text.isEmpty ? "（暂无输出）" : page.text)
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .padding(12)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .id(entry.id + "-" + String(page.index))
                    HStack {
                        Button("上一页") { Task { await model.load(entry, page: page.index - 1) } }.disabled(page.index == 0 || model.loadingPage)
                        Text("第 \(page.index + 1) / \(page.total) 页").font(.caption).foregroundStyle(.secondary)
                        Button("下一页") { Task { await model.load(entry, page: page.index + 1) } }.disabled(page.index + 1 == page.total || model.loadingPage)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: page.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        Button("打开完整日志") { NSWorkspace.shared.open(entry.logURL) }
                    }
                } else if model.loadingPage { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { Spacer() }
            }.padding(18)
        } else {
            WorkspaceEmptyState(symbol: "doc.text.magnifyingglass", title: "执行日志", message: "选择左侧记录，查看执行结果、耗时和完整输出。")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func refresh() async {
        guard !model.deleting else { return }
        await model.reload(directories: HistoryDirectories.shared.candidates(workspaces: workspaces))
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
        await refreshPage()
    }
    private func refreshPage() async {
        guard let selected, !model.loadingPage else { return }
        let page = model.pageRecordID == selected.id ? model.page : nil
        let requested = page.flatMap { $0.index + 1 == $0.total ? nil : $0.index }
        await model.load(selected, page: requested)
    }
}

private struct HistoryDeletionRequest {
    enum Scope { case selected, filtered, all }
    let entries: [HistoryEntry]
    let scope: Scope
    let criteria: String

    var title: String {
        switch scope {
        case .selected: return "删除此执行记录？"
        case .filtered: return "清空当前筛选结果？"
        case .all: return "清空全部执行历史？"
        }
    }
    var message: String {
        let range: String
        switch scope {
        case .selected: range = "将删除“\(entries.first?.record.scriptName ?? "")”的这次执行记录。"
        case .filtered: range = "将删除当前筛选结果中的 \(entries.count) 条记录。\n" + (criteria.isEmpty ? "当前未设置筛选条件。" : criteria)
        case .all: range = "将删除所有 Workspace 中已加载的 \(entries.count) 条历史记录，不受当前筛选或搜索条件影响。"
        }
        return range + "\n\n对应的 .log 和 .json 文件将永久删除，无法撤销；脚本与配置文件保留。正在运行或正在保存日志的记录会跳过。暂不可用目录中的记录无法清理。"
    }
}
