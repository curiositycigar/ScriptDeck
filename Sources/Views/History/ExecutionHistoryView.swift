import SwiftUI
import AppKit
import Combine

struct ExecutionHistoryView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    var scheduleScope: ScheduleHistoryScope? = nil
    @StateObject private var model = HistoryViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var workspaceFilter = ""
    @State private var scriptFilter = ""
    @State private var search = ""
    @State private var deletionRequest: HistoryDeletionRequest?
    @State private var deletionError: String?
    @AppStorage("skipSingleHistoryDeletionConfirmation") private var skipSingleDeletionConfirmation = false
    @State private var confirmingSingleDeletion = false
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var scopedEntries: [HistoryEntry] {
        model.entries.filter { scheduleScope?.contains($0.record) ?? true }
    }
    private var selected: HistoryEntry? { scopedEntries.first { $0.id == selectedID } }
    private func workspaceKey(_ entry: HistoryEntry) -> String { entry.record.workspaceID ?? "unassigned" }
    private func scriptKey(_ entry: HistoryEntry) -> String { workspaceKey(entry) + "/" + entry.record.scriptID }
    private var workspaceChoices: [(id: String, name: String)] {
        var seen = Set<String>()
        return scopedEntries.compactMap { entry in
            let key = workspaceKey(entry)
            guard seen.insert(key).inserted else { return nil }
            return (key, entry.record.workspaceName.isEmpty ? L("Unspecified Workspace") : entry.record.workspaceName)
        }
    }
    private var scriptChoices: [(id: String, name: String)] {
        var seen = Set<String>()
        return scopedEntries.compactMap { entry in
            guard workspaceFilter.isEmpty || workspaceKey(entry) == workspaceFilter else { return nil }
            let key = scriptKey(entry)
            guard seen.insert(key).inserted else { return nil }
            return (key, entry.record.scriptName + (workspaceFilter.isEmpty && !entry.record.workspaceName.isEmpty ? " · " + entry.record.workspaceName : ""))
        }
    }
    private var filtered: [HistoryEntry] {
        scopedEntries.filter { entry in
            (workspaceFilter.isEmpty || workspaceKey(entry) == workspaceFilter) &&
            (scriptFilter.isEmpty || scriptKey(entry) == scriptFilter) &&
            (search.isEmpty || "\(entry.record.scriptName) \(entry.record.workspaceName) \(entry.record.scriptFile)".localizedCaseInsensitiveContains(search))
        }
    }

    private var busy: Bool { model.loading || model.deleting || confirmingSingleDeletion }
    private func deletable(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.filter { !runner.protectedHistoryRecordIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SettingsPaneHeader(
                    title: scheduleScope?.task.name ?? L("Execution History"),
                    subtitle: scheduleScope == nil ? L("Browse results and complete logs stored on this Mac") : L("Execution History"),
                    symbol: "clock.arrow.circlepath"
                )
                .lineLimit(1).truncationMode(.middle)
                if busy { ProgressView().controlSize(.small) }
                Button {
                    if let selected { requestDeletion([selected], scope: .selected) }
                } label: { WorkspaceSymbol("trash", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("Delete Record")).accessibilityLabel(L("Delete Record"))
                    .disabled(busy || selected == nil || runner.protectedHistoryRecordIDs.contains(selectedID ?? ""))
                Menu {
                    Button(L("Clear Filtered Results…"), role: .destructive) { requestDeletion(filtered, scope: .filtered) }
                        .disabled(deletable(filtered).isEmpty)
                    if scheduleScope == nil {
                        Divider()
                        ForEach(HistoryClearAge.allCases, id: \.self) { age in
                            Button(age.title, role: .destructive) {
                                let cutoff = age.cutoff()
                                requestDeletion(model.entries.filter { $0.record.startedAt < cutoff }, scope: .olderThan(cutoff))
                            }
                            .disabled(deletable(model.entries.filter { $0.record.startedAt < age.cutoff() }).isEmpty)
                        }
                        Divider()
                        Button(L("Clear All History…"), role: .destructive) { requestDeletion(model.entries, scope: .all) }
                            .disabled(deletable(model.entries).isEmpty)
                    }
                } label: {
                    WorkspaceSymbol("trash.slash", size: .toolbar)
                        .frame(width: WorkspaceControlMetrics.iconTarget, height: WorkspaceControlMetrics.iconTarget)
                        .contentShape(Rectangle())
                }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).foregroundStyle(.secondary)
                    .help(L("Clear")).accessibilityLabel(L("Clear"))
                    .disabled(busy || scopedEntries.isEmpty)
                Button { Task { await refresh() } } label: { WorkspaceSymbol("arrow.clockwise", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("Refresh")).accessibilityLabel(L("Refresh"))
                    .disabled(busy)
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.deleting)
            }.padding(20)
            if scheduleScope == nil {
                HStack(spacing: 12) {
                    Picker(L("Workspace"), selection: $workspaceFilter) {
                        Text(L("All Workspaces")).tag("")
                        ForEach(workspaceChoices, id: \.id) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 240)
                    Picker(L("Script"), selection: $scriptFilter) {
                        Text(L("All Scripts")).tag("")
                        ForEach(scriptChoices, id: \.id) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 260)
                    TextField(L("Search scripts, workspaces, or paths"), text: $search).textFieldStyle(.roundedBorder)
                }.padding(.horizontal, 20).padding(.vertical, 14).disabled(model.deleting)
            }
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(filtered) { entry in
                        historyRow(entry).tag(entry.id)
                            .workspaceListSelection(selectedID == entry.id)
                            .contextMenu {
                                Button(L("Delete This Record…"), role: .destructive) { requestDeletion([entry], scope: .selected) }
                                    .disabled(busy || runner.protectedHistoryRecordIDs.contains(entry.id))
                            }
                    }
                }
                .onDeleteCommand {
                    if let selected, !busy { requestDeletion([selected], scope: .selected) }
                }
                .listStyle(.inset)
                .workspaceListAppearance()
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(WorkspaceStyle.sidebar)
                .frame(minWidth: 270, idealWidth: 310, maxWidth: 370)
                .overlay {
                    if filtered.isEmpty && !model.loading {
                        VStack(spacing: 10) {
                            WorkspaceSymbol("clock", size: .emptyState).foregroundStyle(.tertiary)
                            Text(scopedEntries.isEmpty ? L("No execution records yet") : L("No matching records")).font(WorkspaceTypography.body)
                            if scopedEntries.isEmpty { Text(scheduleScope == nil ? L("Logs are saved automatically when you run a script") : L("New runs are linked to this scheduled task. Older records may not be identifiable.")).font(WorkspaceTypography.caption) }
                        }
                        .multilineTextAlignment(.center)
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                detail.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(L("{0} records", "\(filtered.count)")).monospacedDigit().foregroundStyle(.secondary)
                if let warning = model.warning { Text(warning).foregroundStyle(.orange).lineLimit(1).help(warning) }
                Spacer()
                Text(L("Logs are stored in logs/<script filename>/ beside each script."))
                    .foregroundStyle(.secondary).lineLimit(1)
                    .help(L("Logs are stored in logs/<script filename>/ beside each script."))
            }.font(WorkspaceTypography.caption).padding(.horizontal, 20).padding(.vertical, 10).background(WorkspaceStyle.chrome)
        }
        .frame(minWidth: 960, idealWidth: 1040, minHeight: 620, idealHeight: 700)
        .background(WorkspaceStyle.canvas)
        .workspaceTypography()
        .interactiveDismissDisabled(model.deleting || confirmingSingleDeletion)
        .alert(deletionRequest?.title ?? L("Delete History Records?"), isPresented: Binding(
            get: { deletionRequest != nil }, set: { if !$0 { deletionRequest = nil } }
        )) {
            Button(L("Cancel"), role: .cancel) { deletionRequest = nil }
            Button(L("Delete"), role: .destructive) {
                guard let request = deletionRequest else { return }
                deletionRequest = nil
                performDeletion(request)
            }
        } message: { Text(deletionRequest?.message ?? "") }
        .alert(L("Some History Records Could Not Be Deleted"), isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) {
            Button(L("OK"), role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
        .task {
            selectedID = scheduleScope?.latestRunID ?? runner.recordID
            await refresh()
        }
        .task(id: selectedID) { if let selected { await model.load(selected) } }
        .onChange(of: workspaceFilter) { _ in scriptFilter = "" }
        .onChange(of: filtered.map(\.id)) { ids in
            if !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: runner.historyRevision) { _ in Task { await refresh() } }
        .onReceive(refreshTimer) { _ in
            if scheduleScope != nil { Task { await refresh() } }
            else if let selectedID, runner.activeRecordIDs.contains(selectedID) { Task { await refreshPage() } }
        }
    }

    private func requestDeletion(_ entries: [HistoryEntry], scope: HistoryDeletionRequest.Scope) {
        guard !busy else { return }
        let targets = deletable(entries)
        guard !targets.isEmpty else { return }
        let criteria = [
            workspaceChoices.first { $0.id == workspaceFilter }.map { "Workspace：" + $0.name },
            scriptChoices.first { $0.id == scriptFilter }.map { L("Script: ") + $0.name },
            search.isEmpty ? nil : L("Search: ") + search
        ].compactMap { $0 }.joined(separator: "；")
        let request = HistoryDeletionRequest(entries: targets, scope: scope, criteria: criteria)
        if case .selected = scope {
            if skipSingleDeletionConfirmation {
                performDeletion(request)
            } else {
                confirmSingleDeletion(request)
            }
        } else {
            deletionRequest = request
        }
    }

    private func confirmSingleDeletion(_ request: HistoryDeletionRequest) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = request.title
        alert.informativeText = request.message
        alert.addButton(withTitle: L("Delete")).hasDestructiveAction = true
        alert.addButton(withTitle: L("Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Do not ask again")
        confirmingSingleDeletion = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            confirmingSingleDeletion = false
            guard response == .alertFirstButtonReturn else { return }
            skipSingleDeletionConfirmation = alert.suppressionButton?.state == .on
            performDeletion(request)
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func performDeletion(_ request: HistoryDeletionRequest) {
        Task {
            deletionError = await model.remove(request.entries, protectedIDs: runner.protectedHistoryRecordIDs)
            runner.historyDidRemove(Set(request.entries.map(\.id)).subtracting(model.entries.map(\.id)))
            await refresh()
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        let failed = entry.record.outcome == .failed || entry.record.outcome == .launchFailed
        let color: Color = entry.record.outcome == .succeeded ? .green : failed ? .red : .secondary
        let symbol = entry.record.outcome == .succeeded ? "checkmark.circle.fill" : failed ? "exclamationmark.circle.fill" : "clock"
        return VStack(alignment: .leading, spacing: 6) {
            if scheduleScope != nil {
                Text(L10n.date(entry.record.startedAt, dateStyle: .short, timeStyle: .medium))
                    .font(WorkspaceTypography.sectionTitle).monospacedDigit().lineLimit(1)
                    .help(L10n.date(entry.record.startedAt, dateStyle: .full, timeStyle: .medium))
                HStack(spacing: 12) {
                    Label(entry.status(activeRecordID: runner.activeRecordIDs.contains(entry.id) ? entry.id : nil), systemImage: symbol)
                        .font(WorkspaceTypography.captionStrong).foregroundStyle(color)
                    if let end = entry.record.endedAt {
                        Text(L("Elapsed {0} seconds", "\(max(0, Int(end.timeIntervalSince(entry.record.startedAt))))"))
                            .foregroundStyle(.secondary)
                    }
                }.font(WorkspaceTypography.caption)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.record.scriptName)
                        .font(WorkspaceTypography.sectionTitle).lineLimit(1)
                        .help(entry.record.scriptName)
                    Spacer(minLength: 8)
                    Label(entry.status(activeRecordID: runner.activeRecordIDs.contains(entry.id) ? entry.id : nil), systemImage: symbol)
                        .font(WorkspaceTypography.captionStrong).foregroundStyle(color).fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(entry.record.workspaceName.isEmpty ? L("Unspecified Workspace") : entry.record.workspaceName,
                          systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle).help(entry.record.workspaceName)
                    Spacer(minLength: 8)
                    Text(L10n.date(entry.record.startedAt, dateStyle: .short, timeStyle: .short))
                        .monospacedDigit().fixedSize()
                }.font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var detail: some View {
        if let entry = selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheduleScope == nil ? entry.record.scriptName : L10n.date(entry.record.startedAt, dateStyle: .short, timeStyle: .medium))
                            .font(WorkspaceTypography.dialogTitle).monospacedDigit()
                            .lineLimit(1).truncationMode(.middle)
                            .help(scheduleScope == nil ? entry.record.scriptName : L10n.date(entry.record.startedAt, dateStyle: .full, timeStyle: .medium))
                        Text(entry.record.scriptFile).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(entry.record.scriptFile)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([entry.logURL]) } label: {
                        WorkspaceSymbol("folder", size: .toolbar)
                    }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("Show in Finder")).accessibilityLabel(L("Show in Finder"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { executionSummary(entry) }
                        VStack(alignment: .leading, spacing: 6) { executionSummary(entry) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Started: ") + L10n.date(entry.record.startedAt, dateStyle: .full, timeStyle: .medium))
                        if let end = entry.record.endedAt {
                            Text(L("Ended: ") + L10n.date(end, dateStyle: .full, timeStyle: .medium))
                        }
                    }.foregroundStyle(.secondary)
                }
                .font(WorkspaceTypography.caption).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 10))
                if let issue = entry.record.logError { Text(issue).font(WorkspaceTypography.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if let error = model.pageError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if model.pageRecordID == entry.id, let page = model.page {
                    GeometryReader { geometry in
                        ScrollView([.vertical, .horizontal]) {
                            Text(page.text.isEmpty ? L("(No output yet)") : page.text)
                                .font(WorkspaceTypography.code).textSelection(.enabled)
                                .padding(12)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        }
                    }
                    .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 10))
                    .id(entry.id + "-" + String(page.index))
                    HStack {
                        Button { Task { await model.load(entry, page: page.index - 1) } } label: {
                            WorkspaceSymbol("chevron.left", size: .toolbar)
                        }
                        .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                        .help(L("Previous")).accessibilityLabel(L("Previous"))
                        .disabled(page.index == 0 || model.loadingPage)
                        Text(L("Page {0} / {1}", "\(page.index + 1)", "\(page.total)")).monospacedDigit().font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        Button { Task { await model.load(entry, page: page.index + 1) } } label: {
                            WorkspaceSymbol("chevron.right", size: .toolbar)
                        }
                        .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                        .help(L("Next")).accessibilityLabel(L("Next"))
                        .disabled(page.index + 1 == page.total || model.loadingPage)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: page.size), countStyle: .file)).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        Button(L("Open Full Log")) { NSWorkspace.shared.open(entry.logURL) }
                    }
                } else if model.loadingPage { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { Spacer() }
            }.padding(20)
        } else {
            WorkspaceEmptyState(symbol: "doc.text.magnifyingglass", title: L("Execution Log"), message: L("Select a record on the left to view its result, duration, and complete output."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private func executionSummary(_ entry: HistoryEntry) -> some View {
        let active = runner.activeRecordIDs.contains(entry.id)
        let failed = entry.record.outcome == .failed || entry.record.outcome == .launchFailed
        let symbol = active ? "play.circle" : entry.record.outcome == .succeeded ? "checkmark.circle.fill" : failed ? "exclamationmark.circle.fill" : "clock"
        let color: Color = active ? .orange : entry.record.outcome == .succeeded ? .green : failed ? .red : .secondary
        Label(entry.status(activeRecordID: active ? entry.id : nil), systemImage: symbol)
            .font(WorkspaceTypography.captionStrong).foregroundStyle(color)
        if let code = entry.record.exitCode {
            Text(L("Exit code {0}", "\(code)")).foregroundStyle(.secondary)
        }
        if let end = entry.record.endedAt {
            Text(L("Elapsed {0} seconds", "\(max(0, Int(end.timeIntervalSince(entry.record.startedAt))))"))
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        guard !model.deleting else { return }
        await model.reload(directories: HistoryDirectories.shared.candidates(workspaces: workspaces) + (scheduleScope?.directories ?? []))
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
    enum Scope { case selected, filtered, all, olderThan(Date) }
    let entries: [HistoryEntry]
    let scope: Scope
    let criteria: String

    var title: String {
        switch scope {
        case .selected: return L("Delete This Execution Record?")
        case .filtered: return L("Clear Filtered Results?")
        case .all: return L("Clear All Execution History?")
        case .olderThan: return L("Clear Older Execution History?")
        }
    }
    var message: String {
        let range: String
        switch scope {
        case .selected: range = L("Delete this execution record for “{0}”.", "\(entries.first?.record.scriptName ?? "")")
        case .filtered: range = L("Delete {0} records matching the current filters.\n", "\(entries.count)") + (criteria.isEmpty ? L("No filters are currently set.") : criteria)
        case .all: range = L("Delete all {0} loaded history records across workspaces, regardless of current filters or search.", "\(entries.count)")
        case .olderThan(let cutoff):
            range = L("Delete {0} loaded history records started before {1} across workspaces, regardless of current filters or search.",
                      "\(entries.count)", L10n.date(cutoff, dateStyle: .full, timeStyle: .short))
        }
        return range + L("\n\nThe corresponding .log and .json files will be permanently deleted. Scripts and configuration files will be preserved. Running tasks and logs still being saved will be skipped. Records in unavailable folders cannot be removed.")
    }
}
