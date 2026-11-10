import SwiftUI
import AppKit

@MainActor
struct ScriptRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var workspaces = WorkspaceStore()
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
            WorkspaceRootView(workspaces: workspaces, preferences: preferences, runner: runner, schedules: schedules)
                .environment(\.locale, L10n.locale).onAppear {
                delegate.runner = runner
                schedules.refresh()
                DispatchQueue.main.async { delegate.configureMainWindow(NSApp.keyWindow ?? NSApp.windows.first) }
            }
        }
        .defaultSize(width: 1120, height: 800)
        .windowToolbarStyle(.unifiedCompact)
        .commands { RunnerCommands(workspaces: workspaces, runner: runner) }

        MenuBarExtra {
            RunnerMenuBarView(runner: runner, schedules: schedules).environment(\.locale, L10n.locale)
        } label: {
            Label(runner.isRunning ? "\(runner.runningSessions.count)" : "",
                  systemImage: runner.isRunning ? "play.circle.fill" : "terminal")
                .accessibilityLabel(runner.isRunning ? L("{0} tasks running", "\(runner.runningSessions.count)") : L("ScriptDeck, idle"))
        }

        Window(L("Settings"), id: "settings") {
            AppSettingsView(workspaces: workspaces, preferences: preferences, runner: runner).environment(\.locale, L10n.locale)
        }
        .windowResizability(.contentSize)
    }
}
