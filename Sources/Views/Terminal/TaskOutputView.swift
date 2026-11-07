import SwiftUI
import AppKit

struct TaskOutputView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var workspaces: WorkspaceStore
    @Binding var outputExpanded: Bool
    @State private var showHistory = false
    @State private var showTaskList = true
    @State private var completedExpanded = true
    @State private var credentialSession: ExecutionSession?

    var body: some View {
        Group {
            if outputExpanded { logView } else { outputHeader }
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
                if !outputExpanded { runningSummary }
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
        .controlSize(.small)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.bar)
    }

    private var outputTitle: some View {
        Button { outputExpanded.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: outputExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: "terminal").foregroundStyle(.tint)
                Text(L("Run Output")).font(.callout.weight(.semibold))
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
            .font(.caption).foregroundStyle(runner.isRunning ? Color.orange : Color.secondary)
    }

    private var outputActions: some View {
        HStack(spacing: 12) {
            if outputExpanded {
                Button { showTaskList.toggle() } label: {
                    Image(systemName: "sidebar.left")
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
                if !runner.runningSessions.isEmpty {
                    Text(L("Running · {0}", "\(runner.runningSessions.count)"))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    ForEach(runner.runningSessions) { session in
                        taskButton(session)
                    }
                }
                if !runner.completedSessions.isEmpty {
                    DisclosureGroup(isExpanded: $completedExpanded) {
                        ForEach(runner.completedSessions) { session in
                            taskButton(session)
                        }
                    } label: {
                        Text(L("Completed · {0}", "\(runner.completedSessions.count)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disclosureGroupStyle(WorkspaceDisclosureStyle())
                    .padding(.top, 6)
                }
            }.padding(12)
        }
        .overlay {
            if runner.sessions.isEmpty {
                Text(L("Select a script to run"))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(L("This Session")).foregroundStyle(.secondary)
                Spacer()
                Button { runner.dismissSession(runner.sessionID) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(runner.selectedSessionID == nil || runner.selectedIsRunning || runner.selectedSession.hasPendingHistoryWrites)
                .help(L("Remove the selected task record while preserving history and logs"))
                .accessibilityLabel(L("Remove selected task record"))
                Button { runner.dismissCompletedSessions() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .disabled(!runner.sessions.contains { !$0.isRunning && !$0.hasPendingHistoryWrites })
                .help(L("Remove completed tasks while preserving history and logs"))
                .accessibilityLabel(L("Remove completed tasks"))
            }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
    }

    private func taskButton(_ session: ExecutionSession) -> some View {
        Button { runner.select(session.id) } label: {
            ExecutionSessionRow(session: session)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(runner.selectedSessionID == session.id ? WorkspaceStyle.selectionColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .accessibilityValue(runner.selectedSessionID == session.id ? L("Selected") : L("Not selected"))
        .contextMenu {
            Button(L("Remove This Record"), role: .destructive) { runner.dismissSession(session.id) }
                .disabled(session.isRunning || session.hasPendingHistoryWrites)
            if session.isRunning {
                Text(L("Stop the task before removing its record"))
            } else if session.hasPendingHistoryWrites {
                Text(L("Saving log, please wait"))
            }
        }
    }

    private var terminalActions: some View {
        HStack(spacing: 10) {
            Button { credentialSession = runner.selectedSession } label: { Image(systemName: "key") }
                .help(L("Fill Password from Keychain (⇧⌘K)"))
                .accessibilityLabel(L("Fill Password from Keychain"))
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!runner.selectedIsRunning || runner.selectedSession.isBackgroundExecution || runner.stopping)
            if let issue = runner.historyIssue {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(issue).accessibilityLabel(issue)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runner.exportText(), forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .help(L("Copy Selected Task Log")).accessibilityLabel(L("Copy Selected Task Log")).disabled(!runner.hasOutput)
            if runner.selectedIsRunning {
                Button(L("Interrupt")) { runner.interrupt() }.help(L("Send Ctrl+C to the selected task"))
                    .disabled(runner.selectedSession.isBackgroundExecution)
                Button(runner.stopping ? L("Force Stop") : L("Stop"), role: .destructive) {
                    runner.stop(force: runner.stopping)
                }.help(L("Stop only the selected task")).fixedSize()
            }
        }
        .controlSize(.small)
    }

    private var terminalPane: some View {
        EmbeddedTerminalView(session: runner.selectedSession)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if !runner.hasOutput && !runner.selectedIsRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Terminal Ready")).font(.callout.weight(.medium))
                        Text(L("Run a script to view output and type here. Password input usually does not display characters."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(20).allowsHitTesting(false)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logView: some View {
        VStack(spacing: 0) {
            outputHeader
            Divider()
            if showTaskList {
                HSplitView {
                    taskList
                    terminalPane
                }
            } else {
                terminalPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
    }


}

private struct ExecutionSessionRow: View {
    @ObservedObject var session: ExecutionSession

    private var symbol: String {
        switch session.outcome {
        case .running: return "circle.inset.filled"
        case .succeeded: return "checkmark.circle"
        case .failed, .launchFailed: return "exclamationmark.circle"
        case .stopped: return "stop.circle"
        case nil: return "circle"
        }
    }
    private var resultColor: Color {
        switch session.outcome {
        case .running: return .orange
        case .succeeded: return .green
        case .failed, .launchFailed: return .red
        default: return .secondary
        }
    }

    private var workspaceTag: String {
        let name = session.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    private func duration(at date: Date) -> String {
        let seconds = max(0, Int((session.endedAt ?? date).timeIntervalSince(session.startedAt)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(workspaceTag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .help(session.workspaceName.isEmpty ? L("Unspecified Workspace") : session.workspaceName)
                        .accessibilityLabel(session.workspaceName.isEmpty ? L("Unspecified Workspace") : session.workspaceName)
                    Text(session.activeName)
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Image(systemName: symbol).foregroundStyle(resultColor)
                        .accessibilityLabel(session.status)
                    Text(session.status).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(duration(at: context.date))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityLabel(L("Elapsed ") + duration(at: context.date))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .help(L("{0} / {1}\n{2} · elapsed {3}\nStarted: {4}", "\(session.workspaceName)", "\(session.activeName)", "\(session.status)", "\(duration(at: context.date))", "\(L10n.date(session.startedAt))"))
        }
    }
}
