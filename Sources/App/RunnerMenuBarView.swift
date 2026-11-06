import SwiftUI
import AppKit

struct RunnerMenuBarView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("Open ScriptDeck")) { showMainWindow() }
        Divider()
        if runner.runningSessions.isEmpty {
            Text(L("No running tasks"))
        } else {
            Text(L("Running · {0}", "\(runner.runningSessions.count)"))
            ForEach(runner.runningSessions) { session in
                Button {
                    runner.select(session.id)
                    showMainWindow()
                } label: {
                    Text("\(session.workspaceName) · \(session.activeName)")
                }
            }
        }
        if let latest = runner.completedSessions.first {
            Divider()
            Text(L("Last finished: {0}", "\(latest.activeName)"))
            Text(latest.status)
        }
        Divider()
        Text(L("Schedules · {0} enabled", "\(schedules.enabledTaskCount)"))
        if schedules.failedTaskCount > 0 { Text(L("{0} schedules need attention. Check the main window.", "\(schedules.failedTaskCount)")) }
        if let (task, date) = schedules.nextTask {
            Text(L("Next: {0}", "\(task.name)"))
            Text(L10n.date(date, dateStyle: .short, timeStyle: .short))
        }
        Divider()
        Button(L("Settings…")) {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(L("Quit ScriptDeck")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
