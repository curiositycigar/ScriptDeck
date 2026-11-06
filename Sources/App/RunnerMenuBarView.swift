import SwiftUI
import AppKit

struct RunnerMenuBarView: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 ScriptDeck") { showMainWindow() }
        Divider()
        if runner.runningSessions.isEmpty {
            Text("暂无运行中的任务")
        } else {
            Text("运行中 · \(runner.runningSessions.count)")
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
            Text("最近结束：\(latest.activeName)")
            Text(latest.status)
        }
        Divider()
        Text("定时任务 · \(schedules.enabledTaskCount) 个启用")
        if schedules.failedTaskCount > 0 { Text("\(schedules.failedTaskCount) 个定时任务有异常，请在主窗口查看") }
        if let (task, date) = schedules.nextTask {
            Text("下次：\(task.name)")
            Text(date.formatted(date: .numeric, time: .shortened))
        }
        Divider()
        Button("设置…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("退出 ScriptDeck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
