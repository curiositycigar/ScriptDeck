import SwiftUI
import AppKit

struct TaskOutputView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var workspaces: WorkspaceStore
    @Binding var outputExpanded: Bool
    @State private var showHistory = false
    @State private var showTaskList = true
    @State private var credentialSession: ExecutionSession?
    @StateObject private var history = HistoryViewModel()
    @State private var selectedSavedID: String?

    private var records: [RunOutputRecord] {
        RunOutputRecord.merge(sessions: runner.sessions, history: history.entries, hiding: runner.hiddenOutputRecordIDs)
    }

    private var selectedRecord: RunOutputRecord? {
        let record = runner.selectedSessionID != nil
            ? RunOutputRecord.live(runner.selectedSession)
            : history.entries.first { $0.id == selectedSavedID }.map(RunOutputRecord.saved)
        guard let record, !runner.hiddenOutputRecordIDs.contains(record.id) else { return nil }
        return record
    }

    private var savedLog: HistoryEntry? {
        guard let selectedRecord else { return nil }
        if case .saved(let entry) = selectedRecord { return entry }
        guard let session = selectedRecord.session, session.isBackgroundExecution, !session.isRunning else { return nil }
        return history.entries.first { $0.id == selectedRecord.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            outputHeader
            if outputExpanded {
                Divider()
                logView
            }
        }
        .workspaceTypography()
        .task(id: runner.historyRevision) { await reloadHistory() }
        .onChange(of: workspaces.items) { _ in Task { await reloadHistory() } }
        .onChange(of: records.map(\.id)) { _ in
            if selectedRecord == nil, let newest = records.first { select(newest) }
        }
        .onChange(of: runner.selectedSessionID) { id in
            if id != nil { selectedSavedID = nil }
        }
        .sheet(isPresented: $showHistory) {
            ExecutionHistoryView(workspaces: workspaces, runner: runner)
        }
        .sheet(item: $credentialSession) { session in
            CredentialManagerView(runner: runner,
                                  target: session.workspaceID.flatMap { workspace in
                                      session.scriptID.map { CredentialTarget(workspaceID: workspace, scriptID: $0) }
                                  }, scriptName: session.activeName, session: session)
        }
    }

    private var outputHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                outputTitle.fixedSize()
                if !outputExpanded {
                    runningSummary
                } else if let record = selectedRecord {
                    Text(record.workspaceName + " / " + record.name)
                        .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(record.workspaceName + " / " + record.name)
                }
                Spacer(minLength: 0)
                if outputExpanded { terminalActions.fixedSize() }
                outputActions.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    outputTitle
                    Spacer(minLength: 8)
                    outputActions
                }
                if outputExpanded {
                    HStack(spacing: 12) {
                        Spacer(minLength: 8)
                        terminalActions
                    }
                } else {
                    runningSummary
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(WorkspaceStyle.chrome)
    }

    private var outputTitle: some View {
        Button { outputExpanded.toggle() } label: {
            HStack(spacing: 7) {
                WorkspaceSymbol("chevron.right", size: .disclosure)
                    .rotationEffect(.degrees(outputExpanded ? 90 : 0))
                    .workspaceAnimation(value: outputExpanded).foregroundStyle(.secondary)
                WorkspaceSymbol("terminal").foregroundStyle(.tint)
                Text(L("Run Output")).font(WorkspaceTypography.sectionTitle)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(outputExpanded ? L("Collapse Output") : L("Expand Output"))
        .accessibilityLabel(outputExpanded ? L("Collapse Output") : L("Expand Output"))
    }

    private var runningSummary: some View {
        Text(runner.isRunning ? L("{0} running", "\(runner.runningSessions.count)") : L("No running tasks"))
            .font(WorkspaceTypography.caption).foregroundStyle(runner.isRunning ? Color.orange : Color.secondary)
    }

    private var outputActions: some View {
        HStack(spacing: 12) {
            if outputExpanded {
                Button { showTaskList.toggle() } label: {
                    WorkspaceSymbol("sidebar.left", size: .toolbar)
                }
                .help(showTaskList ? L("Hide task list") : L("Show task list"))
                .accessibilityLabel(showTaskList ? L("Hide task list") : L("Show task list"))
            }
            Button { showHistory = true } label: {
                Label(L("History"), systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.iconOnly)
            .help(L("View execution records and local logs for all scripts"))
            .accessibilityLabel(L("History"))
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(records, id: \.id) { record in
                    taskButton(record)
                }
            }.padding(12)
        }
        .overlay {
            if records.isEmpty && !history.loading {
                Text(L("Select a script to run"))
                    .font(WorkspaceTypography.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .background(WorkspaceStyle.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(L("{0} records", "\(records.count)")).monospacedDigit().foregroundStyle(.secondary)
                if let warning = history.warning {
                    WorkspaceSymbol("exclamationmark.triangle").foregroundStyle(.orange)
                        .help(warning).accessibilityLabel(warning)
                }
                Spacer()
                Button { if let selectedRecord { hide(selectedRecord) } } label: {
                    WorkspaceSymbol("trash").workspaceCompactTarget()
                }
                .buttonStyle(.plain)
                .disabled(selectedRecord?.canHide != true)
                .help(L("Remove the selected task record while preserving history and logs"))
                .accessibilityLabel(L("Remove selected task record"))
                Button {
                    let savedIDs = records.filter { $0.session == nil }.map(\.id)
                    runner.dismissCompletedSessions(savedIDs: Set(savedIDs))
                } label: {
                    WorkspaceSymbol("xmark.circle").workspaceCompactTarget()
                }
                .buttonStyle(.plain)
                .disabled(!records.contains(where: \.canHide))
                .help(L("Remove completed tasks while preserving history and logs"))
                .accessibilityLabel(L("Remove completed tasks"))
            }.font(WorkspaceTypography.caption).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
    }

    private func reloadHistory() async {
        await history.reload(directories: HistoryDirectories.shared.candidates(workspaces: workspaces))
    }

    private func select(_ record: RunOutputRecord) {
        selectedSavedID = record.session == nil ? record.id : nil
        runner.select(record.session?.id)
    }

    private func hide(_ record: RunOutputRecord) {
        guard record.canHide else { return }
        if let session = record.session {
            runner.dismissSession(session.id)
        } else {
            runner.hideSavedOutputRecords([record.id])
        }
    }

    private func taskButton(_ record: RunOutputRecord) -> some View {
        let selected = selectedRecord?.id == record.id
        return Button { select(record) } label: {
            ExecutionSessionRow(record: record)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceTaskButtonStyle(selected: selected))
        .accessibilityValue(selected ? L("Selected") : L("Not selected"))
        .contextMenu {
            Button(L("Remove This Record"), role: .destructive) { hide(record) }
                .disabled(!record.canHide)
            if record.session?.isRunning == true {
                Text(L("Stop the task before removing its record"))
            } else if record.session?.hasPendingHistoryWrites == true {
                Text(L("Saving log, please wait"))
            }
        }
    }

    @ViewBuilder private var terminalActions: some View {
        if let savedLog {
            Button(L("Open Full Log")) { NSWorkspace.shared.open(savedLog.logURL) }
        } else {
            liveTerminalActions
        }
    }

    private var liveTerminalActions: some View {
        HStack(spacing: 10) {
            Button { credentialSession = runner.selectedSession } label: { WorkspaceSymbol("key", size: .toolbar) }
                .help(L("Fill Password from Keychain (⇧⌘K)"))
                .accessibilityLabel(L("Fill Password from Keychain"))
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!runner.selectedIsRunning || runner.selectedSession.isBackgroundExecution || runner.stopping)
            if let issue = runner.historyIssue {
                WorkspaceSymbol("exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(issue).accessibilityLabel(issue)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runner.exportText(), forType: .string)
            } label: { WorkspaceSymbol("doc.on.doc", size: .toolbar) }
            .help(L("Copy Selected Task Log")).accessibilityLabel(L("Copy Selected Task Log")).disabled(!runner.hasOutput)
            if runner.selectedIsRunning {
                Button(L("Interrupt")) { runner.interrupt() }.help(L("Send Ctrl+C to the selected task"))
                    .disabled(runner.selectedSession.isBackgroundExecution)
                Button(runner.stopping ? L("Force Stop") : L("Stop"), role: .destructive) {
                    runner.stop(force: runner.stopping)
                }.help(L("Stop only the selected task")).fixedSize()
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder private var terminalPane: some View {
        if let savedLog {
            savedLogPane(savedLog)
        } else {
            liveTerminalPane
        }
    }

    private func savedLogPane(_ entry: HistoryEntry) -> some View {
        VStack(spacing: 0) {
            if history.pageRecordID == entry.id, let page = history.page {
                GeometryReader { geometry in
                    ScrollView([.vertical, .horizontal]) {
                        Text(page.text.isEmpty ? L("(No output yet)") : page.text)
                            .font(WorkspaceTypography.code).textSelection(.enabled)
                            .padding(12)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
                .id("\(entry.id)-\(page.index)")
                if page.total > 1 {
                    HStack {
                        Button { Task { await history.load(entry, page: page.index - 1) } } label: {
                            WorkspaceSymbol("chevron.left")
                        }
                        .help(L("Previous")).accessibilityLabel(L("Previous"))
                        .disabled(page.index == 0 || history.loadingPage)
                        Text(L("Page {0} / {1}", "\(page.index + 1)", "\(page.total)")).monospacedDigit()
                        Button { Task { await history.load(entry, page: page.index + 1) } } label: {
                            WorkspaceSymbol("chevron.right")
                        }
                        .help(L("Next")).accessibilityLabel(L("Next"))
                        .disabled(page.index + 1 == page.total || history.loadingPage)
                    }
                    .font(WorkspaceTypography.caption).padding(6)
                }
            } else if history.pageRecordID == entry.id, let error = history.pageError {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled).padding(12)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .task(id: entry.id) { await history.load(entry) }
    }

    private var liveTerminalPane: some View {
        EmbeddedTerminalView(session: runner.selectedSession)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(WorkspaceStyle.canvas)
            .overlay {
                if !runner.hasOutput && !runner.selectedIsRunning {
                    VStack(spacing: 6) {
                        Text(L("Terminal Ready")).font(WorkspaceTypography.bodyStrong)
                        Text(L("Run a script to view output and type here. Password input usually does not display characters."))
                            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .padding(20).allowsHitTesting(false)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logView: some View {
        Group {
            if showTaskList {
                HSplitView {
                    taskList
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    terminalPane
                }
            } else {
                terminalPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas)
        .clipped()
        .workspaceAnimation(value: showTaskList, motion: .layout)
    }


}

@MainActor
enum RunOutputRecord {
    case live(ExecutionSession)
    case saved(HistoryEntry)

    static func merge(sessions: [ExecutionSession], history: [HistoryEntry], hiding hiddenIDs: Set<String>) -> [Self] {
        let live = sessions.reversed().map(Self.live)
        let liveIDs = Set(live.map(\.id))
        let saved = history.filter { !liveIDs.contains($0.id) }.map(Self.saved)
        return (live + saved).filter { !hiddenIDs.contains($0.id) }.sorted { $0.startedAt > $1.startedAt }
    }

    var session: ExecutionSession? {
        if case .live(let session) = self { return session }
        return nil
    }

    private var entry: HistoryEntry? {
        if case .saved(let entry) = self { return entry }
        return nil
    }

    var id: String {
        switch self {
        case .live(let session): return session.recordID ?? session.id.uuidString
        case .saved(let entry): return entry.id
        }
    }
    var name: String {
        switch self {
        case .live(let session): return session.activeName
        case .saved(let entry): return entry.record.scriptName
        }
    }
    var workspaceName: String {
        switch self {
        case .live(let session): return session.workspaceName
        case .saved(let entry): return entry.record.workspaceName
        }
    }
    var startedAt: Date {
        switch self {
        case .live(let session): return session.startedAt
        case .saved(let entry): return entry.record.startedAt
        }
    }
    var endedAt: Date? {
        if let session { return session.endedAt }
        return entry?.record.endedAt
    }
    var outcome: ExecutionOutcome? {
        if let session { return session.outcome }
        return entry?.record.outcome == .running ? .failed : entry?.record.outcome
    }
    var status: String {
        switch self {
        case .live(let session): return session.status
        case .saved(let entry): return entry.status(activeRecordID: nil)
        }
    }
    var isRunning: Bool { session?.isRunning == true }
    var canHide: Bool { !isRunning && session?.hasPendingHistoryWrites != true }
}

private struct ExecutionSessionRow: View {
    let record: RunOutputRecord

    private var symbol: String {
        switch record.outcome {
        case .running: return "circle.inset.filled"
        case .succeeded: return "checkmark.circle"
        case .failed, .launchFailed: return "exclamationmark.circle"
        case .stopped: return "stop.circle"
        case nil: return "circle"
        }
    }
    private var resultColor: Color {
        switch record.outcome {
        case .running: return .orange
        case .succeeded: return .green
        case .failed, .launchFailed: return .red
        default: return .secondary
        }
    }

    private func duration(at date: Date) -> String {
        guard let end = record.endedAt ?? (record.isRunning ? date : nil) else { return "—" }
        let seconds = max(0, Int(end.timeIntervalSince(record.startedAt)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = duration(at: context.date)
            HStack(spacing: 6) {
                WorkspaceSymbol(symbol).foregroundStyle(resultColor)
                    .accessibilityLabel(record.status)
                Text(record.name)
                    .font(WorkspaceTypography.bodyStrong).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(elapsed)
                    .font(WorkspaceTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel(L("Elapsed ") + elapsed)
            }
            .help(L("{0} / {1}\n{2} · elapsed {3}\nStarted: {4}", record.workspaceName, record.name, record.status, elapsed, L10n.date(record.startedAt)))
        }
    }
}

private struct WorkspaceTaskButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? WorkspaceStyle.selectionColor : Color.primary.opacity(configuration.isPressed ? 0.08 : hovered ? 0.04 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .workspaceAnimation(value: selected)
            .workspaceAnimation(value: hovered)
            .workspaceAnimation(value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}
