import SwiftUI
import AppKit

@MainActor
struct ScriptRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var workspaces = WorkspaceStore()
    @StateObject private var navigation = WorkspaceNavigation()
    @StateObject private var preferences: AppPreferences
    @StateObject private var runner: ProcessRunner
    @StateObject private var schedules: ScheduleStore

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        let runner = ProcessRunner(preferences: preferences)
        _runner = StateObject(wrappedValue: runner)
        _schedules = StateObject(wrappedValue: ScheduleStore(runner: runner))
    }

    var body: some Scene {
        Window("ScriptDeck", id: "main") {
            WorkspaceRootView(workspaces: workspaces, preferences: preferences, runner: runner, schedules: schedules, navigation: navigation)
                .background(MainWindowReference { delegate.configureMainWindow($0) })
                .environment(\.locale, L10n.locale)
                .onAppear {
                    delegate.runner = runner
                    schedules.synchronizeWorkspaces(workspaces.items)
                    schedules.refresh()
                }
        }
        .defaultSize(width: 1120, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands { RunnerCommands(workspaces: workspaces, runner: runner, navigation: navigation) }

        MenuBarExtra {
            RunnerMenuBarView(runner: runner, schedules: schedules, navigation: navigation).environment(\.locale, L10n.locale)
        } label: {
            Label(runner.isRunning ? "\(runner.runningSessions.count)" : "",
                  systemImage: runner.isRunning ? "play.circle.fill" : "terminal")
                .accessibilityLabel(runner.isRunning ? L("{0} tasks running", "\(runner.runningSessions.count)") : L("ScriptDeck, idle"))
        }

    }
}

private struct MainWindowReference: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReferenceView {
        let view = ReferenceView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: ReferenceView, context: Context) { nsView.configure = configure }

    final class ReferenceView: NSView {
        var configure: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure?(window) }
        }
    }
}
