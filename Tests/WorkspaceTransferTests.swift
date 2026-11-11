import Foundation

@MainActor func runWorkspaceTransferSelfTests(root: URL) throws {
    let manager = FileManager.default
    let source = root.appendingPathComponent("share-source")
    let store = ScriptStore(restoreLastDirectory: false)
    try store.initialize(source, remember: false)
    let scriptFile = source.appendingPathComponent("scripts/test script.sh")
    let contents = Data("#!/bin/bash\nexit 0\n".utf8)
    try contents.write(to: scriptFile)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
    let externalFile = root.appendingPathComponent("external.sh")
    try contents.write(to: externalFile)
    let item = ScriptItem(name: "Example", category: "Examples/Nested", path: "scripts/test script.sh",
                          interpreter: "direct", workingDirectory: ".",
                          parameters: [
                              ScriptParameter(id: "text", name: "Text", defaultValue: "Saved"),
                              ScriptParameter(id: "file", name: "File", kind: .file, defaultValue: externalFile.path)
                          ])
    let external = ScriptItem(name: "External", path: externalFile.path)
    check(store.upsert(item) && store.upsert(external), "Prepare internal and external script references for export")
    let packageURL = root.appendingPathComponent("Shared.scriptdeck")
    let package = try WorkspaceTransfer(store: store, values: [item.id: ["text": "Current 中文"]])
    try package.write(to: packageURL)
    let received = try WorkspaceTransfer.read(from: packageURL)
    let destination = try received.install(in: root, named: "Shared")
    let second = try received.install(in: root, named: "Shared")
    check(second.lastPathComponent == "Shared 2", "Import creates a new folder when the name is already taken")
    let imported = ScriptStore(restoreLastDirectory: false)
    try imported.open(destination, remember: false)
    let script = imported.items[0]
    let path = imported.resolved(script).path
    let copied = try Data(contentsOf: URL(fileURLWithPath: path))
    check(script.path == item.path && script.workingDirectory == "." && script.category == item.category
          && copied == contents && manager.isExecutableFile(atPath: path),
          "Workspace transfer preserves relative script paths, categories, contents, and executable permissions")
    check(script.parameters[0].defaultValue == "Current 中文" && script.parameters[1].defaultValue.isEmpty
          && store.items[0].parameters[0].defaultValue == "Saved",
          "Current values become imported defaults, while external input paths are cleared and the source is unchanged")
    let externalCopy = imported.resolved(imported.items[1]).path
    check(externalCopy.hasPrefix(destination.path + "/") && manager.fileExists(atPath: externalCopy),
          "An explicitly registered external script is copied into the imported workspace")

    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: packageURL)) as! [String: Any]
    var files = json["files"] as! [[String: Any]]
    files[0]["path"] = "../escaped.sh"
    json["files"] = files
    try JSONSerialization.data(withJSONObject: json).write(to: packageURL)
    check((try? WorkspaceTransfer.read(from: packageURL)) == nil,
          "Workspace packages reject script paths that escape the new workspace")

    let suite = "ScriptDeck.WorkspaceTransferTests.\(UUID())"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let workspaces = WorkspaceStore(preferences: preferences)
    check(!WorkspaceDialogs.importDroppedPackage([scriptFile], to: workspaces) && workspaces.error == nil,
          "An ordinary dropped script stays on the script import path")
    check(WorkspaceDialogs.importDroppedPackage([scriptFile, packageURL], to: workspaces)
          && workspaces.error != nil && workspaces.items.isEmpty,
          "A dropped workspace package is validated even when mixed with ordinary files")
}
