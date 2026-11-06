import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runner: ProcessRunner?
    var mainWindow: NSWindow?
    func configureMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        mainWindow = window
        // Keep nested native split views in the content area, including when the
        // output panel changes the root layout. The titlebar owns its own space.
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if runner?.foregroundRunningSessions.isEmpty == false {
            let alert = NSAlert()
            alert.messageText = "仍有 \(runner?.foregroundRunningSessions.count ?? 0) 个手动脚本在运行"
            alert.informativeText = "请先停止手动运行的任务或等待执行完成。后台定时任务可在退出 App 后继续运行。"
            alert.addButton(withTitle: "返回应用")
            alert.runModal()
            mainWindow?.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        if let runner, runner.hasPendingHistoryWrites {
            runner.afterHistorySaved { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        return .terminateNow
    }
}
