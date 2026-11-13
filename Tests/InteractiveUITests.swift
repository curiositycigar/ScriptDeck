import AppKit
import SwiftUI
import Foundation
import QuartzCore

@MainActor
func runInteractiveUISelfTests(root: URL) throws {
    try checkInteractiveFileSelection(root: root)
    try checkInteractiveRefreshLifecycle()
    try checkInteractivePageState()
    try checkInteractiveStableIdentity()
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
    item.allowsMultipleInstances = true
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
func checkInteractiveRefreshLifecycle() throws {
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    let actions = InteractiveView(blocks: [
        InteractiveBlock(type: .text, text: "Files"),
        InteractiveBlock(type: .buttons, items: [InteractiveItem(text: "Refresh", data: "refresh")])
    ])
    func publish(_ view: InteractiveView) throws -> UUID {
        let request = InteractiveRequest(id: UUID(), view: view)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        return request.id
    }
    let first = try publish(actions)
    channel.submit("refresh", values: [:], requestID: first)
    check(!channel.waiting && !channel.showsProcessingIndicator, "Submission locks controls without immediately flashing loading")
    let second = try publish(actions)
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    check(channel.waiting && !channel.showsProcessingIndicator, "A fast replacement cancels the previous loading indicator")
    channel.submit("refresh", values: [:], requestID: first)
    check(channel.waiting, "Retaining rendered views still rejects stale request callbacks")
    channel.submit("refresh", values: [:], requestID: second)
    pump(until: { channel.showsProcessingIndicator })
    check(!channel.waiting, "Slow actions display loading while preventing duplicate submission")
    let response = channel.directory.appendingPathComponent("response-\(second).json")
    let original = try Data(contentsOf: response)
    channel.submit("refresh", values: [:], requestID: second)
    let afterDuplicate = try Data(contentsOf: response)
    check(original == afterDuplicate, "Repeated clicks cannot replace the submitted response")
    for progress in [0.1, 0.5, 1.0] {
        _ = try publish(InteractiveView(blocks: [InteractiveBlock(type: .progress, progress: progress)]))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        check(!channel.waiting && !channel.showsProcessingIndicator, "Display-only progress does not imply a pending action")
    }
    let final = try publish(actions)
    channel.submit("refresh", values: [:], requestID: final)
    channel.finish()
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    check(channel.ended && !channel.showsProcessingIndicator, "Ending a session cancels delayed loading")
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
func checkInteractiveFileSelection(root: URL) throws {
    let folder = root.appendingPathComponent("drop-fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let firstFile = folder.appendingPathComponent("a ' 中文.txt")
    let secondFile = folder.appendingPathComponent("b.txt")
    try Data().write(to: firstFile)
    try Data().write(to: secondFile)
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    let view = try InteractiveView.decode(Data(#"{"blocks":[{"type":"file","id":"single"},{"type":"file","id":"multi","multiple":true},{"type":"file","id":"folder","mode":"directory"},{"type":"buttons","items":[{"text":"Submit","data":"submit"}]}]}"#.utf8))
    func publish(_ nextView: InteractiveView? = nil) throws -> UUID {
        let request = InteractiveRequest(id: UUID(), view: nextView ?? view)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        return request.id
    }
    let id = try publish()
    check(channel.selectFiles([folder, firstFile, secondFile], controlID: "single", requestID: id)
          && channel.selections["single"] == [firstFile.path],
          "Single-file drops skip directories and keep the first compatible path")
    check(channel.selectFiles([firstFile, secondFile, firstFile, folder], controlID: "multi", requestID: id)
          && channel.selections["multi"] == [firstFile.path, secondFile.path],
          "Multi-file drops accept local Unicode paths and remove duplicates")
    check(channel.selectFiles([firstFile, folder], controlID: "folder", requestID: id)
          && channel.selections["folder"] == [folder.path],
          "Directory controls accept folders and reject files")
    check(!channel.selectFiles([folder, URL(string: "https://example.com/file")!, folder.appendingPathComponent("missing")], controlID: "single", requestID: id)
          && channel.selections["single"] == [firstFile.path],
          "Rejected drops preserve the existing selection")
    check(channel.selectFiles([secondFile], controlID: "multi", requestID: id)
          && channel.selections["multi"] == [secondFile.path],
          "A successful drop replaces previous paths")
    _ = try publish()
    check(!channel.selectFiles([firstFile], controlID: "single", requestID: id)
          && channel.selections["single"] == [firstFile.path]
          && channel.selections["multi"] == [secondFile.path]
          && channel.selections["folder"] == [folder.path],
          "Compatible file pickers preserve choices across refresh and reject stale drops")
    channel.selections["single"] = []
    _ = try publish()
    check(channel.selections["single", default: []].isEmpty, "Clearing a file picker persists across refresh")
    var changed = view
    changed.blocks[1].multiple = false
    changed.blocks[2].mode = .file
    _ = try publish(changed)
    check(channel.selections["multi"] == nil && channel.selections["folder"] == nil,
          "Changing picker mode or multiplicity resets incompatible choices")
    _ = try publish(InteractiveView(blocks: [InteractiveBlock(type: .text, text: "Different page")]))
    _ = try publish()
    check(channel.selections.values.allSatisfy(\.isEmpty),
          "Returning from another page starts with empty file pickers")
    let currentID = channel.request!.id
    channel.submit("submit", values: channel.selections, requestID: currentID)
    check(!channel.selectFiles([firstFile], controlID: "single", requestID: currentID),
          "Drops cannot edit a submitted request")
    _ = try publish()
    let finalID = channel.request!.id
    channel.finish()
    check(!channel.selectFiles([firstFile], controlID: "single", requestID: finalID),
          "Drops cannot edit a completed session")
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
            InteractiveBlock(type: .select, id: "environment", items: (0..<12).map {
                InteractiveItem(id: "option-\($0)", text: "Option \($0)", detail: "Environment description", disabled: $0 == 11)
            }, label: "Environment"),
            InteractiveBlock(type: .toggle, id: "overwrite", label: "Overwrite"),
            InteractiveBlock(type: .progress, text: "2 of 4 complete", label: "Progress", progress: 0.5),
            InteractiveBlock(type: .progress, label: "Waiting"),
            InteractiveBlock(type: .text, text: "Check your selection before deleting.", notice: .warning),
            InteractiveBlock(type: .list, id: "files", multiple: true, items: items),
            InteractiveBlock(type: .text, text: "Recent tasks", section: true),
            InteractiveBlock(type: .list, id: "tasks", items: [
                InteractiveItem(id: "backup", text: "Backup task with a long name", cells: ["Storage", "24 s"], badge: .completed)
            ], columns: ["Task", "Server", "Duration"]),
            InteractiveBlock(type: .buttons, items: ["Upload a new file", "Download selected files", "Delete selected files", "Refresh"].map {
                InteractiveItem(text: $0, data: $0)
            })
        ])
        let decoded = try InteractiveView.decode(JSONEncoder().encode(view))
        check(decoded == view, "Section, table cells, and badges survive protocol transport")
        var malformed = view
        let tableIndex = malformed.blocks.firstIndex { $0.id == "tasks" }!
        malformed.blocks[tableIndex].items?[0].cells = ["Storage"]
        check((try? malformed.validate()) == nil, "Tables reject rows with mismatched column counts")
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

    // A pending action and a compatible refresh must not move the scrolled document.
    let refreshView = InteractiveView(blocks: [
        InteractiveBlock(type: .text, text: "Files", region: .header),
        InteractiveBlock(type: .list, id: "files", items: (0..<60).map {
            InteractiveItem(id: "file-\($0)", text: "File \($0)")
        }),
        InteractiveBlock(type: .buttons, items: [InteractiveItem(text: "Refresh", data: "refresh")], region: .footer)
    ])
    let refreshRequest = InteractiveRequest(id: UUID(), view: refreshView)
    try JSONEncoder().encode(refreshRequest).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
    channel.receive()
    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    host.layoutSubtreeIfNeeded()
    let scroll = descendants(host).compactMap { $0 as? NSScrollView }.first!
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
    scroll.reflectScrolledClipView(scroll.contentView)
    let origin = scroll.contentView.bounds.origin
    let documentHeight = scroll.documentView!.bounds.height
    let viewportRect = host.convert(scroll.bounds, from: scroll)
    channel.submit("refresh", values: [:], requestID: refreshRequest.id)
    pump(until: { channel.showsProcessingIndicator })
    host.layoutSubtreeIfNeeded()
    check(scroll.contentView.bounds.origin == origin && scroll.documentView!.bounds.height == documentHeight,
          "Loading feedback preserves document height and scroll position")
    check(host.convert(scroll.bounds, from: scroll) == viewportRect,
          "Loading does not move fixed regions or resize the viewport")
    var updatedView = refreshView
    updatedView.blocks[1].items?[0].text = "Updated file"
    let updatedRequest = InteractiveRequest(id: UUID(), view: updatedView)
    try JSONEncoder().encode(updatedRequest).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
    channel.receive()
    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    host.layoutSubtreeIfNeeded()
    let updatedScroll = descendants(host).compactMap { $0 as? NSScrollView }.first!
    check(updatedScroll === scroll && updatedScroll.contentView.bounds.origin == origin,
          "Compatible request updates retain the native scroll view and its position")
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


@MainActor
func checkInteractivePageState() throws {
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    let source = #"""
    {"pageID":"upload","blocks":[
      {"type":"input","id":"name"},
      {"type":"input","id":"secret","secure":true},
      {"type":"select","id":"env","items":[{"id":"a","text":"A"},{"id":"b","text":"B"}]},
      {"type":"toggle","id":"enabled"},
      {"type":"file","id":"local"},
      {"type":"list","id":"files","multiple":true,"items":[{"id":"a","text":"A"},{"id":"b","text":"B"}]},
      {"type":"buttons","id":"actions","items":[
        {"id":"preset","text":"Example","action":{"type":"setValue","target":"name","value":"example.txt"}},
        {"text":"Disabled","disabled":true,"action":{"type":"setValue","target":"name","value":"disabled"}},
        {"text":"Selected only","requiresSelection":"files","action":{"type":"setValue","target":"name","value":"selected.txt"}},
        {"text":"Submit","data":"submit"}
      ]}
    ]}
    """#
    let view = try InteractiveView.decode(Data(source.utf8))
    let decoded = try InteractiveView.decode(JSONEncoder().encode(view))
    check(decoded == view, "Page IDs and local actions round-trip through JSON")
    @discardableResult func publish(_ next: InteractiveView) throws -> UUID {
        let request = InteractiveRequest(id: UUID(), view: next)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        check(channel.issue == nil, "Page-state fixture is accepted")
        return request.id
    }
    let id = try publish(view)
    channel.inputs["name"] = "typed.txt"
    channel.inputs["secret"] = "synthetic secret"
    channel.inputs["env"] = "b"
    channel.inputs["enabled"] = "true"
    channel.selections["local"] = ["/tmp/synthetic.txt"]
    channel.selections["files"] = ["a", "b"]
    var next = view
    next.blocks[5].items?.removeLast()
    let refreshed = try publish(next)
    check(channel.inputs["name"] == "typed.txt" && channel.inputs["env"] == "b" && channel.inputs["enabled"] == "true",
          "Same named page preserves unassigned input, select, and toggle values")
    check(channel.inputs["secret"] == "" && channel.selections["files"] == ["a"] && channel.selections["local"] == ["/tmp/synthetic.txt"],
          "Passwords clear and list retention intersects remaining IDs while file choices persist")
    let preset = next.blocks[6].items![0]
    channel.activate(preset, requestID: id)
    check(channel.inputs["name"] == "typed.txt", "Stale local actions cannot alter a refreshed page")
    channel.activate(next.blocks[6].items![1], requestID: refreshed)
    check(channel.inputs["name"] == "typed.txt", "Disabled local actions do not assign values")
    channel.activate(preset, requestID: refreshed)
    check(channel.inputs["name"] == "example.txt" && channel.waiting && channel.request?.id == refreshed
          && channel.selections["local"] == ["/tmp/synthetic.txt"] && !channel.showsProcessingIndicator,
          "Local presets change only their target and keep the current interactive request active")
    check(!FileManager.default.fileExists(atPath: channel.directory.appendingPathComponent("response-\(refreshed).json").path),
          "Local assignments do not send callbacks or complete the helper exchange")
    channel.selections["files"] = []
    channel.activate(next.blocks[6].items![2], requestID: refreshed)
    check(channel.inputs["name"] == "example.txt", "Selection requirements also guard local actions")
    channel.activate(InteractiveItem(text: "Forged", action: InteractiveLocalAction(type: .setValue, target: "name", value: "forged")), requestID: refreshed)
    check(channel.inputs["name"] == "example.txt", "Unpublished local actions are rejected")
    channel.activate(next.blocks[6].items![3], requestID: refreshed)
    let response = try JSONDecoder().decode(InteractiveResponse.self, from: Data(contentsOf: channel.directory.appendingPathComponent("response-\(refreshed).json")))
    check(response.event?.values["name"] == ["example.txt"] && !channel.waiting,
          "Ordinary submission includes locally assigned values and locks controls")
    channel.activate(preset, requestID: refreshed)
    check(!channel.waiting, "Local actions cannot unlock a submitted view")

    next.blocks[0].value = ""
    next.blocks[2].value = "a"
    next.blocks[3].checked = false
    next.blocks[4].reset = true
    next.blocks[5].reset = true
    _ = try publish(next)
    check(channel.inputs["name"] == "" && channel.inputs["env"] == "a" && channel.inputs["enabled"] == "false"
          && channel.selections.isEmpty, "Explicit defaults and reset clear retained state")
    let resetRoundTrip = try InteractiveView.decode(JSONEncoder().encode(next))
    check(resetRoundTrip == next, "Explicit reset survives JSON transport")
    channel.inputs["name"] = "edited"
    channel.inputs["env"] = "b"
    channel.inputs["enabled"] = "true"
    channel.selections["local"] = ["/tmp/synthetic.txt"]
    channel.selections["files"] = ["a"]
    var reset = view
    for index in [0, 2, 3, 4, 5] { reset.blocks[index].reset = true }
    _ = try publish(reset)
    check(channel.inputs["name"] == "" && channel.inputs["env"] == "a" && channel.inputs["enabled"] == "false"
          && channel.selections.isEmpty, "Reset without explicit defaults uses each control's initial state")

    _ = try publish(view)
    channel.inputs["name"] = "other page"
    channel.selections["local"] = ["/tmp/synthetic.txt"]
    next = view
    next.pageID = "another-page"
    _ = try publish(next)
    check(channel.inputs["name"] == "" && channel.selections.isEmpty, "Changing page identity clears all form and file state")
    _ = try publish(view)
    check(channel.inputs["name"] == "" && channel.selections.isEmpty, "Returning to a page starts fresh rather than restoring a hidden cache")
    channel.inputs["name"] = "removed"
    next = view
    next.blocks.removeFirst()
    next.blocks[5].items = [InteractiveItem(text: "Submit", data: "submit")]
    _ = try publish(next)
    _ = try publish(view)
    check(channel.inputs["name"] == "", "Removed controls do not resurrect stale input on return")
    channel.inputs["name"] = "single line"
    next = view
    next.blocks[0].multiline = true
    _ = try publish(next)
    check(channel.inputs["name"] == "", "Changing input compatibility clears retained content")
    channel.inputs["env"] = "b"
    next.blocks[2].items?.removeLast()
    _ = try publish(next)
    check(channel.inputs["env"] == "a", "Removed select options fall back to a valid current option")
    channel.selections["files"] = ["a"]
    next.blocks[5].multiple = false
    _ = try publish(next)
    check(channel.selections["files"] == nil, "Changing list multiplicity resets its selections")
    channel.finish()
    channel.activate(preset, requestID: channel.request!.id)
    check(channel.ended && !channel.waiting, "Local actions cannot modify an ended session")

    let invalid = [
        #"{"pageID":"","blocks":[]}"#,
        #"{"blocks":[{"type":"text","id":"same","text":"A"},{"type":"input","id":"same"}]}"#,
        #"{"blocks":[{"type":"text","id":"","text":"A"}]}"#,
        #"{"blocks":[{"type":"text","text":"A","reset":true}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"text":"A","data":"a","action":{"type":"setValue","target":"name","value":"x"}}]}]}"#,
        #"{"blocks":[{"type":"input","id":"name"},{"type":"buttons","items":[{"text":"A","action":{"type":"setValue","target":"name","value":"x"}}]}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"text":"A","action":{"type":"setValue","target":"missing","value":"x"}},{"text":"OK","data":"ok"}]}]}"#,
        #"{"blocks":[{"type":"input","id":"secret","secure":true},{"type":"buttons","items":[{"text":"A","action":{"type":"setValue","target":"secret","value":"x"}},{"text":"OK","data":"ok"}]}]}"#,
        #"{"blocks":[{"type":"file","id":"local"},{"type":"buttons","items":[{"text":"A","action":{"type":"setValue","target":"local","value":"/tmp/x"}},{"text":"OK","data":"ok"}]}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"id":"same","text":"A","data":"a"},{"id":"same","text":"B","data":"b"}]}]}"#,
        #"{"blocks":[{"type":"buttons","items":[{"text":"A","action":{"type":"execute","target":"name","value":"x"}},{"text":"OK","data":"ok"}]}]}"#
    ]
    for json in invalid {
        do { _ = try InteractiveView.decode(Data(json.utf8)); fatalError("Invalid page or local action accepted") }
        catch { check(true, "Invalid identities and local actions are rejected before rendering") }
    }
}

@MainActor
func checkInteractiveStableIdentity() throws {
    let channel = try InteractiveChannel()
    defer { channel.finish() }
    var view = InteractiveView(blocks: [
        InteractiveBlock(type: .input, id: "name", value: "example.txt"),
        InteractiveBlock(type: .file, id: "local"),
        InteractiveBlock(type: .buttons, id: "actions", items: [
            InteractiveItem(id: "preset", text: "Example", action: InteractiveLocalAction(type: .setValue, target: "name", value: "changed.txt")),
            InteractiveItem(id: "submit", text: "Submit", data: "submit")
        ])
    ], pageID: "upload")
    @discardableResult func publish() throws -> UUID {
        let request = InteractiveRequest(id: UUID(), view: view)
        try JSONEncoder().encode(request).write(to: channel.directory.appendingPathComponent("request.json"), options: .atomic)
        channel.receive()
        return request.id
    }
    let id = try publish()
    let host = NSHostingView(rootView: InteractivePanel(channel: channel))
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func layout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        host.layoutSubtreeIfNeeded()
    }
    layout()
    let field = descendants(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "example.txt" && $0.isEditable }!
    window.makeFirstResponder(field)
    let editor = window.firstResponder
    let preset = view.blocks[2].items![0]
    channel.activate(preset, requestID: id)
    layout()
    let localField = descendants(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "changed.txt" && $0.isEditable }
    check(localField === field && window.firstResponder === editor && channel.request?.id == id,
          "Local assignment preserves the native field, focus, and current request")
    view.blocks[0].value = nil
    view.blocks.insert(InteractiveBlock(type: .text, id: "notice", text: "A new notice"), at: 0)
    view.blocks[3].items?.reverse()
    _ = try publish()
    layout()
    let refreshedField = descendants(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "changed.txt" && $0.isEditable }
    check(refreshedField === field && window.firstResponder === editor,
          "Stable block IDs preserve the native input and focus when preceding content is inserted")
    check(view.elements[1].id == .named("name") && view.blocks[3].elements[1].id == .named("preset"),
          "Block and button identities follow declared IDs when their positions change")
    let legacy = InteractiveView(blocks: [InteractiveBlock(type: .text, text: "Legacy")])
    check(legacy.elements[0].id == .position(0), "Legacy blocks retain positional identity without requiring IDs")
}
