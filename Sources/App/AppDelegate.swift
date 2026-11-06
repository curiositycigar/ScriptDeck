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
            alert.messageText = L("{0} manual scripts are still running", "\(runner?.foregroundRunningSessions.count ?? 0)")
            alert.informativeText = L("Stop manual tasks or wait for them to finish. Scheduled tasks can continue after you quit the app.")
            alert.addButton(withTitle: L("Return to App"))
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
