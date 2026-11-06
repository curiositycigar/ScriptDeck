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
            WorkspaceRootView(workspaces: workspaces, preferences: preferences, runner: runner, schedules: schedules).onAppear {
                delegate.runner = runner
                schedules.refresh()
                DispatchQueue.main.async { delegate.configureMainWindow(NSApp.keyWindow ?? NSApp.windows.first) }
            }
        }
        .defaultSize(width: 1120, height: 800)
        .windowToolbarStyle(.unified)
        .commands { RunnerCommands(workspaces: workspaces, runner: runner) }

        MenuBarExtra {
            RunnerMenuBarView(runner: runner, schedules: schedules)
        } label: {
            Label(runner.isRunning ? "\(runner.runningSessions.count)" : "",
                  systemImage: runner.isRunning ? "play.circle.fill" : "terminal")
                .accessibilityLabel(runner.isRunning ? "\(runner.runningSessions.count) 个任务运行中" : "ScriptDeck，空闲")
        }

        Window("设置", id: "settings") {
            AppSettingsView(workspaces: workspaces, preferences: preferences, runner: runner)
        }
        .windowResizability(.contentSize)
    }
}
