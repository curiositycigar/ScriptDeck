import AppKit
import SwiftUI

/// A session outlives its window. Reopening always presents the same terminal and UI.
@MainActor
final class ExecutionWindowController: NSWindowController, NSWindowDelegate {
    let session: ExecutionSession
    private weak var runner: ProcessRunner?

    init(session: ExecutionSession, runner: ProcessRunner) {
        self.session = session
        self.runner = runner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = session.activeName + " — " + session.instanceLabel
        window.minSize = NSSize(width: 680, height: 420)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            ExecutionWindowView(runner: runner, session: session, windowProvider: { [weak window] in window }).environment(\.locale, L10n.locale))
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(session:runner:)") }

    func present() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        session.focusTerminal()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Menu actions target the key execution window.
        runner?.select(session.id)
        runner?.objectWillChange.send()
    }

    func windowDidResignKey(_ notification: Notification) {
        runner?.objectWillChange.send()
    }
}

struct ExecutionWindowView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var session: ExecutionSession
    var windowProvider: () -> NSWindow? = { nil }
    @StateObject private var hiddenInput = HiddenInputPromptController()
    @State private var showingCredentials = false
    @State private var showingDetails = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            executionToolbar
            Divider()
            SessionOutputPane(session: session, onHiddenInput: { hiddenInput.open(session) }, showsViewPicker: false)
            if let issue = session.historyIssue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(WorkspaceTypography.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(WorkspaceStyle.chrome)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 360)
        .background(WorkspaceStyle.canvas)
        .workspaceTypography()
        .sheet(isPresented: $showingCredentials) {
            CredentialManagerView(runner: runner, target: credentialTarget,
                                  scriptName: session.activeName, session: session)
        }
        .sheet(item: $hiddenInput.session) { target in HiddenInputPrompt(runner: runner, session: target) }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            hiddenInput.poll(sessions: [session], selected: session,
                             canPresent: !showingCredentials && NSApp.isActive &&
                                 NSApp.keyWindow != nil && NSApp.keyWindow === windowProvider() &&
                                 NSApp.keyWindow?.attachedSheet == nil)
        }
        .alert(L("Operation Failed"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(L("OK"), role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var executionToolbar: some View {
        HStack(spacing: 4) {
            if session.interactiveChannel != nil {
                Picker(L("Output View"), selection: $session.showingTerminalLog) {
                    Text(L("Interactive UI")).tag(false)
                    Text(L("Terminal Log")).tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            if !session.isBackgroundExecution {
                Button { showingCredentials = true } label: {
                    WorkspaceSymbol("key", size: .toolbar)
                        .frame(width: 30, height: 30)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!session.isRunning || session.stopping)
                .help(L("Fill Password from Keychain")).accessibilityLabel(L("Fill Password from Keychain"))
            }
            Button(action: copyLog) {
                WorkspaceSymbol("doc.on.doc", size: .toolbar).frame(width: 30, height: 30)
            }
            .disabled(!session.hasOutput)
            .help(L("Copy Log")).accessibilityLabel(L("Copy Log"))
            Button(action: exportLog) {
                WorkspaceSymbol("square.and.arrow.up", size: .toolbar).frame(width: 30, height: 30)
            }
            .disabled(!session.hasOutput)
            .help(L("Export Log")).accessibilityLabel(L("Export Log"))
            if session.isRunning && !session.isBackgroundExecution {
                Button { session.interrupt() } label: {
                    WorkspaceSymbol("hand.raised", size: .toolbar).frame(width: 30, height: 30)
                }
                .disabled(session.stopping)
                .help(L("Interrupt")).accessibilityLabel(L("Interrupt"))
            }
            if session.isRunning {
                Divider().frame(height: 16).padding(.horizontal, 4)
                Button(role: .destructive) { session.stop(force: session.stopping) } label: {
                    WorkspaceSymbol(session.stopping ? "xmark.octagon.fill" : "stop.fill", size: .toolbar)
                        .foregroundStyle(.red).frame(width: 30, height: 30)
                }
                .keyboardShortcut(".", modifiers: .command)
                .help(session.stopping ? L("Force Stop") : L("Stop"))
                .accessibilityLabel(session.stopping ? L("Force Stop") : L("Stop"))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).frame(height: 40)
        .background(WorkspaceStyle.chrome)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(session.status)
                .foregroundStyle(session.isRunning ? Color.orange : Color.secondary)
                .lineLimit(1).help(session.status)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(until: session.endedAt ?? (session.isRunning ? context.date : session.startedAt)))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel(L("Elapsed"))
            }
            Button { showingDetails.toggle() } label: {
                Image(systemName: "info.circle").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L("Execution Details")).accessibilityLabel(L("Execution Details"))
            .popover(isPresented: $showingDetails, arrowEdge: .top) { executionDetails }
        }
        .font(WorkspaceTypography.caption)
        .padding(.horizontal, 12).frame(height: 28)
        .background(WorkspaceStyle.chrome)
    }

    private var executionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Execution Details")).font(WorkspaceTypography.sectionTitle)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow(L("Script"), session.activeName)
                detailRow(L("Workspace"), session.workspaceName)
                detailRow(L("Instance ID"), session.recordID ?? session.id.uuidString)
                detailRow(L("Execution Source"), session.isBackgroundExecution ? L("Scheduled Task") : L("Manual Task"))
                detailRow(L("Start Time"), L10n.date(session.startedAt))
                if let endedAt = session.endedAt { detailRow(L("End Time"), L10n.date(endedAt)) }
                detailRow(L("Status"), session.status)
            }
        }
        .padding(16).frame(width: 400, alignment: .leading)
        .background(WorkspaceStyle.canvas).workspaceTypography()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(WorkspaceTypography.caption)
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.exportText(), forType: .string)
    }

    private var credentialTarget: CredentialTarget? {
        guard let workspaceID = session.workspaceID, let scriptID = session.scriptID else { return nil }
        return CredentialTarget(workspaceID: workspaceID, scriptID: scriptID)
    }

    private func elapsed(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(session.startedAt)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func exportLog() {
        guard let window = windowProvider() ?? session.terminalView.window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "execution.log"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try session.exportText().write(to: url, atomically: true, encoding: .utf8) }
            catch { exportError = error.localizedDescription }
        }
    }
}
