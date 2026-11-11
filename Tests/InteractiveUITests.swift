import AppKit
import SwiftUI
import Foundation
import QuartzCore

@MainActor
func runInteractiveUISelfTests(root: URL) throws {
    try checkInteractiveFormControls()
    try checkInteractiveControlsDemo(root: root)
    let valid = Data(#"{"blocks":[{"type":"list","id":"files","multiple":true,"items":[{"id":"a","text":"a ' $(literal).zip"}]},{"type":"buttons","items":[{"text":"Delete","data":"delete"}]}]}"#.utf8)
    let view = try InteractiveView.decode(valid)
    check(view.hasButtons, "Interactive views decode lists and button rows")
    let invalid = [
        #"{"blocks":[{"type":"html","text":"bad"}]}"#,
        #"{"blocks":[{"type":"list","id":"files","items":[{"id":"a","text":"A"},{"id":"a","text":"B"}]}]}"#,
        #"{"blocks":[{"type":"list","id":"files","items":[]},{"type":"list","id":"files","items":[]}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"text":"Missing callback"}]}]}"#,
        #"{"blocks":[{"type":"text"}]}"#
    ]
    for json in invalid {
        do { _ = try InteractiveView.decode(Data(json.utf8)); fatalError("Invalid UI accepted") }
        catch { check(true, "Malformed UI is rejected before publication") }
    }
    do {
        _ = try InteractiveView.decode(Data(repeating: 32, count: InteractiveView.maximumBytes + 1))
        fatalError("Oversized UI accepted")
    } catch { check(true, "UI input has a bounded size") }

    let source = root.appendingPathComponent("native-ui.sh")
    try """
    #!/bin/bash
    set -euo pipefail
    event=$("$SCRIPTDECK_UI" --ui <<'JSON'
    \(String(decoding: valid, as: UTF8.self))
    JSON
    )
    printf 'EVENT:%s\\n' "$event"
    "$SCRIPTDECK_UI" --ui <<'JSON'
    {"blocks":[{"type":"text","text":"Working"}]}
    JSON
    action=$("$SCRIPTDECK_UI" --ui --action-only <<'JSON'
    {"blocks":[{"type":"text","text":"Confirm deletion?"},{"type":"buttons","items":[{"text":"Confirm","data":"confirm"},{"text":"Cancel","data":"cancel"}]}]}
    JSON
    )
    printf 'ACTION:%s\\n' "$action"
    "$SCRIPTDECK_UI" --ui <<'JSON'
    {"blocks":[{"type":"text","text":"Finished"}]}
    JSON
    """.write(to: source, atomically: true, encoding: .utf8)
    var item = ScriptItem.importing(source)
    item.interactiveUI = true
    let encoded = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(ScriptItem.self, from: encoded)
    check(decoded.interactiveUI, "Interactive UI configuration survives library and workspace serialization")
    var oldItem = item
    oldItem.interactiveUI = false
    let oldData = try JSONEncoder().encode(oldItem)
    check(!String(decoding: oldData, as: UTF8.self).contains("interactiveUI"), "Ordinary scripts keep their existing configuration")
    let schedule = ScheduledTask(name: "Interactive", workspaceID: "test", workspaceName: "Test", item: item, values: [:])
    do { try schedule.validate(); fatalError("Interactive schedule accepted") }
    catch { check(true, "Interactive UI scripts cannot be scheduled") }

    let session = ExecutionSession()
    let other = ExecutionSession()
    try session.run(item: item, arguments: [])
    try other.run(item: item, arguments: [])
    guard let channel = session.interactiveChannel, let otherChannel = other.interactiveChannel else { fatalError("No channels") }
    check(channel.directory != otherChannel.directory, "Concurrent executions use isolated UI mailboxes")
    let permissions = try FileManager.default.attributesOfItem(atPath: channel.directory.path)[.posixPermissions] as? NSNumber
    check(permissions?.intValue == 0o700, "UI mailbox is private to the current user")
    pump(until: { channel.waiting && otherChannel.waiting })
    let firstID = channel.request!.id

    // A second caller fails without replacing the active interface or receiving its event.
    let duplicate = Process()
    duplicate.executableURL = Bundle.main.executableURL
    duplicate.arguments = ["--ui"]
    duplicate.environment = ProcessInfo.processInfo.environment.merging(["SCRIPTDECK_UI_SESSION": channel.directory.path]) { _, new in new }
    let duplicateInput = Pipe()
    duplicate.standardInput = duplicateInput
    duplicate.standardOutput = Pipe()
    duplicate.standardError = Pipe()
    try duplicate.run()
    duplicateInput.fileHandleForWriting.write(valid)
    try duplicateInput.fileHandleForWriting.close()
    pump(until: { !duplicate.isRunning })
    check(duplicate.terminationStatus != 0 && channel.request?.id == firstID, "Overlapping requests fail without replacing the active view")

    let host = NSHostingView(rootView: SessionOutputPane(session: session))
    host.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
    host.layoutSubtreeIfNeeded()
    check(!session.showingTerminalLog, "Interactive executions initially show the native panel")
    session.showingTerminalLog = true
    check(session.isRunning && channel.waiting, "Switching to terminal logs leaves the interactive request alive")
    session.showingTerminalLog = false

    channel.selections["files"] = ["a"]
    session.showingTerminalLog = true
    session.showingTerminalLog = false
    check(channel.selections["files"] == ["a"], "List selections survive terminal tab switching")
    if let path = ProcessInfo.processInfo.environment["SCRIPTDECK_UI_PREVIEW"] {
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    channel.submit("delete", values: ["files": ["a", "unknown"], "unknown": ["a"]], requestID: firstID)
    check(!channel.waiting && otherChannel.waiting, "Submitting one execution does not unblock another")
    // A duplicate click cannot generate a second operation.
    channel.submit("delete", values: [:], requestID: firstID)
    pump(until: { channel.waiting && channel.request?.id != firstID })
    check(channel.request?.view.blocks.first?.text == "Confirm deletion?", "The script can publish status and then request confirmation")
    let confirmID = channel.request!.id
    channel.submit("confirm", values: [:], requestID: firstID)
    check(channel.waiting, "Callbacks from a replaced view are ignored")
    channel.submit("confirm", values: [:], requestID: confirmID)
    pump(until: { !session.isRunning })
    check(session.outcome == .succeeded && channel.ended && !channel.waiting, "Completion disables the retained final panel: \(session.outcome?.rawValue ?? "none") \(session.outcome == .succeeded ? "" : session.output)")
    check(channel.request?.view.blocks.first?.text == "Finished", "The final status update remains visible after completion")
    check(!FileManager.default.fileExists(atPath: channel.directory.path), "Completion removes the private UI mailbox")
    check(session.output.contains("ACTION:confirm"), "Shell scripts receive action-only callback values")
    let line = session.output.components(separatedBy: .newlines).first { $0.hasPrefix("EVENT:") }!
    let event = try JSONDecoder().decode(InteractiveEvent.self, from: Data(line.dropFirst(6).utf8))
    check(event == InteractiveEvent(data: "delete", values: ["files": ["a"]]), "The callback returns only valid list IDs and selections")
    check(!session.output.contains("Confirm deletion?") && !session.output.contains("Finished"), "UI payloads do not leak into ordinary terminal logs")
    other.stop()
    pump(until: { !other.isRunning })
    check(other.outcome == .stopped && otherChannel.ended, "Stopping an execution also ends its pending UI exchange")
    check(!FileManager.default.fileExists(atPath: otherChannel.directory.path), "Stopping cleans up an isolated mailbox")
    // The same protocol is usable from independent language runtimes without an SDK.
    let languageFixtures: [(String, String, String)] = [
        ("py", "python3", #"""
        import json, os, subprocess
        view = {"blocks": [{"type": "text", "text": "Python → UI"}, {"type": "buttons", "items": [{"text": "OK", "data": "ok"}]}]}
        result = subprocess.run([os.environ["SCRIPTDECK_UI"], "--ui"], input=json.dumps(view), text=True, capture_output=True, check=True)
        assert json.loads(result.stdout) == {"data": "ok", "values": {}}
        print("PYTHON_OK")
        """#),
        ("js", "node", #"""
        const {spawnSync} = require('node:child_process');
        const view = {blocks: [{type: 'text', text: 'JavaScript → UI'}, {type: 'buttons', items: [{text: 'OK', data: 'ok'}]}]};
        const result = spawnSync(process.env.SCRIPTDECK_UI, ['--ui'], {input: JSON.stringify(view), encoding: 'utf8'});
        if (result.status !== 0 || JSON.parse(result.stdout).data !== 'ok') process.exit(1);
        console.log('NODE_OK');
        """#)
    ]
    for (ext, interpreter, contents) in languageFixtures {
        let fixture = root.appendingPathComponent("ui-language.\(ext)")
        try contents.write(to: fixture, atomically: true, encoding: .utf8)
        var languageItem = ScriptItem.importing(fixture)
        languageItem.interpreter = interpreter
        languageItem.interactiveUI = true
        let languageSession = ExecutionSession()
        try languageSession.run(item: languageItem, arguments: [])
        guard let languageChannel = languageSession.interactiveChannel else { fatalError("Missing language channel") }
        pump(until: { languageChannel.waiting || !languageSession.isRunning }, timeout: 15)
        // Missing optional runtimes should not prevent contributors from running self-checks.
        if !languageChannel.waiting {
            check(languageSession.output.contains("command not found"), "Optional \(interpreter) runtime is absent")
        } else {
            languageChannel.submit("ok", values: [:], requestID: languageChannel.request!.id)
            pump(until: { !languageSession.isRunning })
            check(languageSession.outcome == .succeeded, "\(interpreter) exchanges native UI events without a language SDK: \(languageSession.outcome?.rawValue ?? "none") \(languageSession.outcome == .succeeded ? "" : languageSession.output)")
        }
        pump(until: { !languageSession.hasPendingHistoryWrites })
    }
    session.afterHistorySaved {}
    pump(until: { !session.hasPendingHistoryWrites && !other.hasPendingHistoryWrites })
}

@MainActor
func checkInteractiveControlsDemo(root: URL) throws {
    // Copy only the known public fixture; never run scripts from user workspaces.
    let example = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ExampleLibrary/scripts/interactive-demo.sh")
    let fixture = root.appendingPathComponent("controls-demo.sh")
    try FileManager.default.copyItem(at: example, to: fixture)
    var item = ScriptItem.importing(fixture)
    item.interactiveUI = true
    let session = ExecutionSession()
    try session.run(item: item, arguments: [])
    guard let channel = session.interactiveChannel else { fatalError("Missing demo channel") }
    pump(until: { channel.waiting })
    let browserID = channel.request!.id
    channel.submit("next", values: [:], requestID: browserID)
    channel.submit("delete", values: [:], requestID: browserID)
    channel.submit("delete", values: ["files": ["unknown"]], requestID: browserID)
    check(channel.waiting, "Disabled pagination and selection-dependent actions reject callbacks without valid selections")
    channel.selections["files"] = ["report"]
    let deleteButton = channel.request!.view.blocks.flatMap { $0.items ?? [] }.first { $0.data == "delete" }!
    check(channel.canSubmit(deleteButton, values: channel.selections), "Selecting a valid row enables its dependent action")
    channel.submit("controls", values: [:], requestID: channel.request!.id)
    pump(until: { channel.waiting && channel.inputs["environment"] != nil })
    check(channel.request?.view.blocks.contains(where: { $0.type == .file && $0.mode == .directory }) == true,
          "Public demo offers local file and directory selection")
    channel.inputs["environment"] = "staging"
    channel.inputs["secret"] = "synthetic secret never logged"
    channel.submit("preview", values: [:], requestID: channel.request!.id)
    pump(until: { channel.request?.view.blocks.contains(where: { $0.type == .progress }) == true })
    check(!channel.waiting, "Progress-only demo views do not block the script")
    pump(until: { channel.waiting }, timeout: 10)
    channel.submit("delete", values: ["files": ["report"]], requestID: channel.request!.id)
    pump(until: { channel.waiting && channel.request?.view.blocks.first?.text?.contains("Delete the fictional file") == true })
    channel.submit("confirm", values: [:], requestID: channel.request!.id)
    pump(until: { channel.waiting && channel.request?.view.blocks.contains(where: { $0.type == .list }) == true })
    let files = channel.request!.view.blocks.first { $0.type == .list }!.items!
    check(files.map(\.id) == ["backup"] && files.first?.detail == "125 MB", "Demo deletion refreshes structured list details")
    channel.submit("exit", values: [:], requestID: channel.request!.id)
    pump(until: { !session.isRunning })
    check(session.outcome == .succeeded && session.output.contains("environment: staging"),
          "Public shell demo parses submitted form values with macOS plutil and completes")
    check(!session.output.contains("synthetic secret never logged"), "Demo never logs password values")
    pump(until: { !session.hasPendingHistoryWrites })
}

@MainActor
func checkInteractiveFormControls() throws {
    let json = #"""
    {"blocks":[
      {"type":"input","id":"name","value":"Initial"},
      {"type":"input","id":"notes","multiline":true},
      {"type":"input","id":"secret","secure":true},
      {"type":"file","id":"files","multiple":true},
      {"type":"file","id":"folder","mode":"directory"},
      {"type":"select","id":"env","value":"b","items":[{"id":"a","text":"A"},{"id":"b","text":"B"}]},
      {"type":"toggle","id":"overwrite","checked":true},
      {"type":"progress","progress":0.5},
      {"type":"progress","label":"Waiting"},
      {"type":"buttons","items":[{"text":"Submit","data":"submit"}]}
    ]}
    """#
    let view = try InteractiveView.decode(Data(json.utf8))
    let roundTrip = try JSONDecoder().decode(InteractiveView.self, from: JSONEncoder().encode(view))
    check(roundTrip == view,
          "All basic controls round-trip through the protocol")
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    func publish() throws -> UUID {
        let request = InteractiveRequest(id: UUID(), view: view)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        return request.id
    }
    let first = try publish()
    check(channel.inputs["name"] == "Initial" && channel.inputs["env"] == "b" && channel.inputs["overwrite"] == "true",
          "Form defaults initialize when the view arrives")
    channel.inputs["name"] = "Quotes \" and Unicode 中文"
    channel.inputs["notes"] = "Line one\nLine two"
    channel.inputs["secret"] = "synthetic fixture"
    channel.inputs["overwrite"] = "false"
    channel.submit("submit", values: ["files": ["/tmp/b ' test.txt", "/tmp/a.txt", "relative"], "folder": ["/tmp"], "unknown": ["bad"]], requestID: first)
    let result = try JSONDecoder().decode(InteractiveResponse.self, from: Data(contentsOf: channel.directory.appendingPathComponent("response-\(first).json"))).event!
    check(result.values == ["name": ["Quotes \" and Unicode 中文"], "notes": ["Line one\nLine two"],
                            "secret": ["synthetic fixture"], "files": ["/tmp/a.txt", "/tmp/b ' test.txt"],
                            "folder": ["/tmp"], "env": ["b"], "overwrite": ["false"]],
          "A single callback submits typed values and absolute paths with correct JSON escaping")
    _ = try publish()
    check(channel.inputs["name"] == "Initial" && channel.inputs["secret"] == "" && channel.selections.isEmpty,
          "Replacing a view resets edits, passwords, and file selections")
    let invalid = [
        #"{"blocks":[{"type":"input","id":"same"},{"type":"toggle","id":"same"}]}"#,
        #"{"blocks":[{"type":"file"}]}"#,
        #"{"blocks":[{"type":"file","id":"f","mode":"bad"}]}"#,
        #"{"blocks":[{"type":"input","id":"x","secure":true,"multiline":true}]}"#,
        #"{"blocks":[{"type":"select","id":"x","items":[]}]}"#,
        #"{"blocks":[{"type":"select","id":"x","value":"bad","items":[{"id":"a","text":"A"}]}]}"#,
        #"{"blocks":[{"type":"progress","progress":1.1}]}"#,
        #"{"blocks":[{"type":"progress","progress":-0.1}]}"#,
        #"{"blocks":[{"type":"text","text":"X","style":"unknown"}]}"#,
        #"{"blocks":[{"type":"text","text":"X","region":"unknown"}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"text":"Delete","data":"delete","requiresSelection":"missing"}]}]}"#
    ]
    for json in invalid {
        do { _ = try InteractiveView.decode(Data(json.utf8)); fatalError("Invalid form accepted") }
        catch { check(true, "Invalid form configuration is rejected") }
    }
}

@MainActor
func checkInteractiveAdaptiveLayout() throws {
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let host = NSHostingView(rootView: InteractivePanel(channel: channel)
        .background(WorkspaceStyle.canvas).workspaceTypography())
    // The fixture supplies a viewport; do not resize its window to GeometryReader's zero ideal height.
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let viewport = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 350))
    host.frame = viewport.bounds
    host.autoresizingMask = [.width, .height]
    viewport.addSubview(host)
    window.contentView = viewport
    window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    for count in [0, 1, 40] {
        let items = (0..<count).map { InteractiveItem(id: "file-\($0)", text: "Report \($0) — a longer filename that wraps in a narrow panel.zip", data: nil, detail: "125 MB") }
        let view = InteractiveView(blocks: [
            InteractiveBlock(type: .text, text: "Remote files · /uploads", style: .title),
            InteractiveBlock(type: .text, text: "Select files to manage. Long descriptions wrap naturally without clipping or reserving extra empty space.", style: .secondary),
            InteractiveBlock(type: .input, id: "path", label: "Destination", value: "/uploads"),
            InteractiveBlock(type: .input, id: "notes", label: "Notes", value: "First line\nSecond line", multiline: true),
            InteractiveBlock(type: .input, id: "secret", label: "Password", secure: true),
            InteractiveBlock(type: .file, id: "local", label: "Local files"),
            InteractiveBlock(type: .select, id: "environment", items: [InteractiveItem(id: "test", text: "Test")], label: "Environment"),
            InteractiveBlock(type: .toggle, id: "overwrite", label: "Overwrite"),
            InteractiveBlock(type: .progress, label: "Progress", progress: 0.5),
            InteractiveBlock(type: .progress, label: "Waiting"),
            InteractiveBlock(type: .list, id: "files", multiple: true, items: items),
            InteractiveBlock(type: .buttons, items: ["Upload a new file", "Download selected files", "Delete selected files", "Refresh"].map {
                InteractiveItem(text: $0, data: $0)
            })
        ])
        let request = InteractiveRequest(id: UUID(), view: view)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        for (width, height) in [(360, 350), (880, 620)] {
            window.setContentSize(NSSize(width: width, height: height))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
                check((scrolls.first?.documentView?.bounds.width ?? 0) <= CGFloat(width) + 1, "Interactive content fits a \(width)-point panel")
                check(scrolls.count == 1, "Interactive lists share the panel's single scroll container")
                if count == 40, let panel = scrolls.first {
                    check((panel.documentView?.bounds.height ?? 0) > panel.bounds.height,
                          "Long lists expand fully and scroll with the entire panel")
                }
                if let base = ProcessInfo.processInfo.environment["SCRIPTDECK_UI_PREVIEW"] {
                    let preview = NSHostingView(rootView: InteractivePanel(channel: channel)
                        .background(WorkspaceStyle.canvas).workspaceTypography()
                        .environment(\.colorScheme, appearance == .aqua ? .light : .dark))
                    preview.appearance = NSAppearance(named: appearance)
                    preview.frame = host.bounds
                    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                    preview.layoutSubtreeIfNeeded()
                    CATransaction.flush()
                    if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                     pixelsWide: Int(preview.bounds.width), pixelsHigh: Int(preview.bounds.height),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                        preview.cacheDisplay(in: preview.bounds, to: bitmap)
                        let path = String(base.dropLast(4)) + "-\(count)-\(width)-\(appearance.rawValue).png"
                        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
        }
    }
    // Verify all optional-region combinations, including an empty body and a long list.
    for header in [false, true] {
        for footer in [false, true] {
            for count in [0, 40] {
                var blocks = [InteractiveBlock(type: .list, id: "files", items: (0..<count).map {
                    InteractiveItem(id: "item-\($0)", text: "File \($0)", detail: "125 MB")
                })]
                // Regions may appear anywhere in the JSON; order within each region is retained.
                if footer {
                    blocks.insert(InteractiveBlock(type: .buttons, items: [
                        InteractiveItem(text: "Refresh", data: "refresh"),
                        InteractiveItem(text: "Delete selected", data: "delete", style: .destructive, requiresSelection: "files")
                    ], region: .footer), at: 0)
                }
                if header { blocks.append(InteractiveBlock(type: .text, text: "Files", region: .header)) }
                let request = InteractiveRequest(id: UUID(), view: InteractiveView(blocks: blocks))
                let encoded = try JSONEncoder().encode(request)
                let decoded = try JSONDecoder().decode(InteractiveRequest.self, from: encoded)
                check(decoded.view == request.view, "Optional regions survive protocol transport")
                try encoded.write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
                channel.receive()
                for width in [360, 880] {
                    window.setContentSize(NSSize(width: width, height: 350))
                    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 350)
                    host.layoutSubtreeIfNeeded()
                    let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
                    check(scrolls.count == 1, "Fixed regions do not introduce nested scrolling")
                    let scroll = scrolls[0]
                    let rect = host.convert(scroll.bounds, from: scroll)
                    let topGap = host.isFlipped ? rect.minY : host.bounds.height - rect.maxY
                    let bottomGap = host.isFlipped ? host.bounds.height - rect.maxY : rect.minY
                    check(header ? topGap > 20 : abs(topGap) <= 1, "Only an explicit header reserves top space")
                    check(footer ? bottomGap > 20 : abs(bottomGap) <= 1, "Only an explicit footer reserves bottom space")
                    check(scroll.bounds.height > 200, "Body fills remaining space even with no list items: header=\(header) footer=\(footer) count=\(count) width=\(width) scroll=\(scroll.bounds) host=\(host.bounds)")
                    if count == 40 {
                        check((scroll.documentView?.bounds.height ?? 0) > scroll.bounds.height, "Long body content scrolls between fixed regions")
                        let fixedRect = rect
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        check(host.convert(scroll.bounds, from: scroll) == fixedRect, "Scrolling keeps fixed regions and the viewport in place")
                    }
                }
            }
        }
    }

}

@MainActor
func checkHiddenInputNotice(root: URL) throws {
    let source = root.appendingPathComponent("hidden-input-notice.sh")
    try """
    #!/bin/bash
    set -euo pipefail
    stty -echo
    printf 'HIDDEN_READY\\n'
    read -r input
    stty echo
    printf 'ECHO_RESTORED\\n'
    read -r input
    """.write(to: source, atomically: true, encoding: .utf8)
    var item = ScriptItem.importing(source)
    item.interactiveUI = true
    let session = ExecutionSession()
    check(!session.needsHiddenInputNotice, "Idle terminals do not show a hidden-input notice")
    try session.run(item: item, arguments: [])
    pump(until: { session.needsHiddenInputNotice })
    let prompts = HiddenInputPromptController()
    prompts.poll(sessions: [session], selected: session, canPresent: false)
    check(prompts.session == nil, "Other sheets and inactive output defer the hidden-input dialog")
    prompts.poll(sessions: [session], selected: session, canPresent: true)
    check(prompts.session?.id == session.id, "Selected interactive hidden input offers a password dialog")
    prompts.session = nil
    prompts.poll(sessions: [session], selected: session, canPresent: true)
    check(prompts.session == nil, "Cancelling does not reopen the dialog in the same hidden-input interval")
    prompts.open(session)
    check(prompts.session?.id == session.id, "The reminder can explicitly reopen a cancelled dialog")
    prompts.poll(sessions: [session], selected: nil, canPresent: true)
    check(prompts.session == nil, "Changing selection dismisses a pending hidden-input dialog")
    prompts.open(session)

    check(!session.showingTerminalLog, "Detecting hidden input does not switch the selected tab")
    // Synthetic fixture input only; no password or credential is read or saved.
    session.terminalView.process.send(data: Array("demo\n".utf8)[...])
    pump(until: { session.output.contains("ECHO_RESTORED") && !session.needsHiddenInputNotice })
    prompts.poll(sessions: [session], selected: session, canPresent: true)
    check(prompts.session == nil, "Restoring echo dismisses the hidden-input dialog")
    check(session.isRunning, "Restoring echo removes the notice before the script ends")
    session.terminalView.process.send(data: Array("\n".utf8)[...])
    pump(until: { !session.isRunning })
    check(!session.needsHiddenInputNotice, "Completed scripts do not retain hidden-input notices")

    let stopped = ExecutionSession()
    try stopped.run(item: item, arguments: [])
    pump(until: { stopped.needsHiddenInputNotice })
    prompts.poll(sessions: [stopped], selected: stopped, canPresent: true)
    check(prompts.session?.id == stopped.id, "A different run can offer its own hidden-input dialog")
    stopped.stop()
    prompts.poll(sessions: [stopped], selected: stopped, canPresent: true)
    check(prompts.session == nil, "Stopping dismisses any hidden-input dialog")
    check(!stopped.needsHiddenInputNotice, "Stopping clears the hidden-input notice immediately")
    pump(until: { !stopped.isRunning })
    pump(until: { !session.hasPendingHistoryWrites && !stopped.hasPendingHistoryWrites })
}
