import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TaskOutputView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var workspaces: WorkspaceStore
    @Binding var outputExpanded: Bool
    var onRevealScript: () -> Void = {}
    @State private var showHistory = false
    @State private var showTaskList = true
    @State private var completedExpanded = true
    @State private var error: String?

    var body: some View {
        Group {
            if outputExpanded { logView } else { outputHeader }
        }
        .sheet(isPresented: $showHistory) {
            ExecutionHistoryView(workspaces: workspaces, runner: runner)
        }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var outputHeader: some View {
        HStack(spacing: 12) {
            Button { outputExpanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: outputExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                    Text("运行输出").font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .help(outputExpanded ? "收起运行输出" : "展开运行输出")
            .accessibilityLabel(outputExpanded ? "收起运行输出" : "展开运行输出")
            Text(runner.isRunning ? "\(runner.runningSessions.count) 个运行中" : "暂无运行任务")
                .font(.caption).foregroundStyle(runner.isRunning ? Color.orange : Color.secondary)
            Spacer(minLength: 8)
            if outputExpanded {
                Button { showTaskList.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showTaskList ? "隐藏任务列表" : "显示任务列表")
                .accessibilityLabel(showTaskList ? "隐藏任务列表" : "显示任务列表")
            }
            Button { showHistory = true } label: {
                Label("历史记录", systemImage: "clock.arrow.circlepath")
            }.help("查看所有脚本的执行记录和本地日志")
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.bar)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text("运行中 · \(runner.runningSessions.count)")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                ForEach(runner.runningSessions) { session in
                    taskButton(session)
                }
                if runner.runningSessions.isEmpty {
                    Text("暂无运行任务").font(.caption).foregroundStyle(.secondary)
                        .padding(8)
                }
                if !runner.completedSessions.isEmpty {
                    DisclosureGroup(isExpanded: $completedExpanded) {
                        ForEach(runner.completedSessions) { session in
                            taskButton(session)
                        }
                    } label: {
                        Text("已完成 · \(runner.completedSessions.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 6)
                }
            }.padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("本次会话").foregroundStyle(.secondary)
                Spacer()
                Button { runner.dismissSession(runner.sessionID) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(runner.selectedSessionID == nil || runner.selectedIsRunning || runner.selectedSession.hasPendingHistoryWrites)
                .help("删除所选任务记录，保留执行历史和日志")
                .accessibilityLabel("删除所选任务记录")
                Button { runner.dismissCompletedSessions() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .disabled(!runner.sessions.contains { !$0.isRunning && !$0.hasPendingHistoryWrites })
                .help("移出已完成任务，保留执行历史和日志")
                .accessibilityLabel("移出已完成任务")
            }.font(.caption).padding(10).background(.bar)
        }
        .frame(minWidth: 160, idealWidth: 200, maxWidth: 280, maxHeight: .infinity)
    }

    private func taskButton(_ session: ExecutionSession) -> some View {
        Button { runner.select(session.id) } label: {
            ExecutionSessionRow(session: session)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(runner.selectedSessionID == session.id ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityValue(runner.selectedSessionID == session.id ? "已选中" : "未选中")
        .contextMenu {
            Button("删除此记录", role: .destructive) { runner.dismissSession(session.id) }
                .disabled(session.isRunning || session.hasPendingHistoryWrites)
            if session.isRunning {
                Text("请先停止任务再删除记录")
            } else if session.hasPendingHistoryWrites {
                Text("正在保存日志，请稍候")
            }
        }
    }

    private var selectedHeader: some View {
        HStack(spacing: 10) {
            if !runner.activeName.isEmpty {
                Button(action: revealSelectedScript) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runner.activeName).font(.callout.weight(.medium)).lineLimit(1)
                        Text(runner.workspaceName.isEmpty ? "未指定 Workspace" : runner.workspaceName)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回任务所属的 Workspace 和脚本")
                .disabled(!workspaces.items.contains { $0.id == runner.workspaceID })
                Text(runner.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("选择任务查看输出").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let issue = runner.historyIssue {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(issue).accessibilityLabel(issue)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runner.exportText(), forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .help("复制所选任务日志").accessibilityLabel("复制所选任务日志").disabled(!runner.hasOutput)
            Menu {
                Button("保存日志…", action: saveLog).disabled(!runner.hasOutput)
                Button("清空终端") { runner.clearOutput() }.disabled(runner.selectedIsRunning || !runner.hasOutput)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("所选任务日志选项").accessibilityLabel("所选任务日志选项")
            if runner.selectedIsRunning {
                Button("中断") { runner.interrupt() }.help("向所选任务发送 Ctrl+C")
                    .disabled(runner.selectedSession.isBackgroundExecution)
                Button(runner.stopping ? "强制停止" : "停止", role: .destructive) {
                    runner.stop(force: runner.stopping)
                }.help("仅停止所选任务").fixedSize()
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 45)
        .background(.bar)
    }

    private var terminalPane: some View {
        VStack(spacing: 0) {
            selectedHeader
            Divider()
            EmbeddedTerminalView(runner: runner)
                .id(runner.sessionID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if !runner.hasOutput {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("终端已就绪").font(.callout.weight(.medium))
                            Text("运行脚本后在此查看输出和输入。密码输入通常不显示字符。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(20).allowsHitTesting(false)
                    }
                }
        }.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
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

    private func revealSelectedScript() {
        guard let id = runner.workspaceID,
              let workspace = workspaces.items.first(where: { $0.id == id }) else { return }
        workspaces.select(id)
        if let scriptID = runner.scriptID,
           workspaces.library(for: workspace).items.contains(where: { $0.id == scriptID }) {
            workspaces.session(for: workspace).selectedID = scriptID
            onRevealScript()
        }
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "脚本运行日志.txt"
        panel.allowedContentTypes = [.plainText]
        let text = runner.exportText()
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
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
                        .help(session.workspaceName.isEmpty ? "未指定 Workspace" : session.workspaceName)
                        .accessibilityLabel(session.workspaceName.isEmpty ? "未指定 Workspace" : session.workspaceName)
                    Text(session.activeName)
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(duration(at: context.date))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityLabel("运行时长 " + duration(at: context.date))
                }
                HStack(spacing: 5) {
                    Image(systemName: symbol).foregroundStyle(resultColor)
                        .accessibilityLabel(session.status)
                    Text(session.startedAt.formatted(date: .numeric, time: .standard))
                        .monospacedDigit().lineLimit(1)
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .help("\(session.workspaceName) / \(session.activeName)\n\(session.status) · 运行时长 \(duration(at: context.date))\n开始：\(session.startedAt.formatted())")
        }
    }
}
