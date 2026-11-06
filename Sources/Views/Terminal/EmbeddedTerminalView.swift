import SwiftUI
import AppKit
import SwiftTerm
import Darwin

/// Terminal input goes directly to the PTY; the app never intercepts passwords.
final class RunnerTerminalView: TerminalView, TerminalViewDelegate, LocalProcessDelegate {
    var acceptsInput = false
    private(set) var process: LocalProcess!
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32?) -> Void)?
    var onFailure: ((LocalProcessError) -> Void)?

    init(frame: CGRect, fontSize: CGFloat, scrollback: Int) {
        super.init(frame: frame, font: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
                   options: TerminalOptions(scrollback: scrollback))
        terminalDelegate = self
        // Ordered main-queue delivery lets us tee every output byte before rendering.
        process = LocalProcess(delegate: self, dispatchQueue: .main)
        configureAppearance()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configureAppearance()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateProcessSize()
    }
    private func configureAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeBackgroundColor = NSColor.textBackgroundColor.usingColorSpace(.deviceRGB) ?? .textBackgroundColor
            nativeForegroundColor = NSColor.textColor.usingColorSpace(.deviceRGB) ?? .textColor
        }
    }
    func startProcess(executable: String, args: [String], environment: [String], currentDirectory: String) {
        process.startProcess(executable: executable, args: args, environment: environment, currentDirectory: currentDirectory)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard acceptsInput else { return }
        process.send(data: data)
    }
    func dataReceived(slice: ArraySlice<UInt8>) {
        onOutput?(Data(slice))
        feed(byteArray: slice)
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        programStatusProcessExited()
        onExit?(exitCode)
    }
    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) { onFailure?(error) }
    func getWindowSize() -> winsize {
        let size = terminalDimensions
        return winsize(ws_row: UInt16(clamping: size.rows), ws_col: UInt16(clamping: size.cols), ws_xpixel: 0, ws_ypixel: 0)
    }
    private func updateProcessSize() {
        guard let process else { return }
        var size = getWindowSize()
        _ = process.updateWindowSize(&size)
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { updateProcessSize() }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities { [] }
    func kittyClipboardAvailableMimeTypes(source: TerminalView, location: KittyClipboardLocation) -> [String]? { nil }
    func kittyClipboardRead(source: TerminalView, location: KittyClipboardLocation, mimeType: String) -> KittyClipboardReadResult? { nil }
    func kittyClipboardWrite(source: TerminalView, location: KittyClipboardLocation, content: KittyClipboardWriteContent) -> KittyClipboardWriteResult { .unsupported }
    func kittyClipboardRequestPermission(source: TerminalView, request: KittyClipboardPermissionRequest) -> KittyClipboardPermissionResult { .deny }
}

struct EmbeddedTerminalView: NSViewRepresentable {
    @ObservedObject var runner: ProcessRunner

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: runner.terminalView.frame)
        attachTerminal(to: host)
        runner.focusTerminal()
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attachTerminal(to: nsView)
    }

    private func attachTerminal(to host: NSView) {
        let terminal = runner.terminalView
        guard terminal.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: host.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }
}
