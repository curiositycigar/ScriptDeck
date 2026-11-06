import Foundation
import Darwin

protocol ScheduleService {
    func installHelper() throws
    func register(_ task: ScheduledTask) throws
    func isLoaded(_ id: String) -> Bool
    func unregister(_ id: String) throws
}

struct LaunchAgentService: ScheduleService {
    let root: URL
    var agentsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    var helper: URL { root.appendingPathComponent("bin/ScriptDeck Helper") }
    func label(_ id: String) -> String { "com.lucasyou.ScriptDeck.schedule." + id }
    func plistURL(_ id: String) -> URL { agentsDirectory.appendingPathComponent(label(id) + ".plist") }
    var domain: String { "gui/\(getuid())" }

    func installHelper() throws {
        let source = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        if let resources = L10n.resourceBundle {
            let destination = helper.deletingLastPathComponent().appendingPathComponent("ScriptDeck_ScriptDeck.bundle")
            for language in ["en", "zh-hans"] {
                if let source = resources.path(forResource: language, ofType: "lproj") {
                    let folder = destination.appendingPathComponent(language + ".lproj")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                           attributes: [.posixPermissions: 0o700])
                    try Data(contentsOf: URL(fileURLWithPath: source).appendingPathComponent("Localizable.strings"))
                        .write(to: folder.appendingPathComponent("Localizable.strings"), options: .atomic)
                }
            }
            if let info = resources.url(forResource: "Info", withExtension: "plist") {
                try Data(contentsOf: info).write(to: destination.appendingPathComponent("Info.plist"), options: .atomic)
            }
        }
        let temp = helper.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: source, to: temp)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.path)
        guard rename(temp.path, helper.path) == 0 else { throw RunnerError(message: L("Unable to install the background executor: {0}", "\(String(cString: strerror(errno)))")) }
    }
    func propertyList(for task: ScheduledTask) -> [String: Any] {
        var plist: [String: Any] = [
            "Label": label(task.id),
            "ProgramArguments": [helper.path, "--run-schedule", ScheduleFiles.definition(root, task.id).path],
            "RunAtLoad": true,
            "Umask": 0o077,
            "ProcessType": "Background",
            "StandardErrorPath": root.appendingPathComponent(task.id + ".error.log").path,
            "EnvironmentVariables": ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        ]
        if task.kind == .interval {
            plist["StartInterval"] = task.intervalMinutes * 60
        } else {
            let components = task.calendar.dateComponents([.month, .day, .hour, .minute], from: task.date)
            var trigger = ["Hour": components.hour!, "Minute": components.minute!]
            if task.kind == .weekly { trigger["Weekday"] = task.weekday - 1 }
            if task.kind == .once {
                trigger["Month"] = components.month!
                trigger["Day"] = components.day!
            }
            // launchd calendars follow the system timezone; the executor also verifies the full date.
            plist["StartCalendarInterval"] = trigger
            // Reconcile full dates and timezone changes at most one minute late, including
            // one-time dates whose year cannot be represented by launchd's calendar fields.
            plist["StartInterval"] = 60
        }
        return plist
    }
    func register(_ task: ScheduledTask) throws {
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList(for: task), format: .xml, options: 0)
        try data.write(to: plistURL(task.id), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL(task.id).path)
        try command(["bootstrap", domain, plistURL(task.id).path])
    }
    func isLoaded(_ id: String) -> Bool { (try? command(["print", domain + "/" + label(id)])) != nil }
    func unregister(_ id: String) throws {
        if isLoaded(id) { try command(["bootout", domain + "/" + label(id)]) }
        if FileManager.default.fileExists(atPath: plistURL(id).path) { try FileManager.default.removeItem(at: plistURL(id)) }
    }
    @discardableResult
    private func command(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw RunnerError(message: L("System scheduling service failed: {0}", "\(text)")) }
        return text
    }
}
