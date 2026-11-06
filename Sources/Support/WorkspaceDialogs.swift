import AppKit

@MainActor
enum WorkspaceDialogs {
    static func add(to workspaces: WorkspaceStore) {
        do { try workspaces.checkRegistry() }
        catch { workspaces.error = error.localizedDescription; return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("Choose a workspace folder. An existing library.json will be loaded; otherwise you can initialize a library.")
        panel.prompt = L("Add Workspace")
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            do {
                if let existing = workspaces.existing(at: directory) {
                    workspaces.select(existing.id)
                    return
                }
                if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path) {
                    let store = ScriptStore(restoreLastDirectory: false)
                    let alert = NSAlert()
                    alert.messageText = L("Initialize Workspace?")
                    alert.informativeText = L("Create library.json and a scripts folder while preserving existing files.")
                    alert.addButton(withTitle: L("Create Empty Library"))
                    alert.addButton(withTitle: L("Cancel"))
                    let choice = alert.runModal()
                    if choice == .alertFirstButtonReturn {
                        try store.initialize(directory, remember: false)
                    } else { return }
                }
                try workspaces.register(directory)
            } catch { workspaces.error = error.localizedDescription }
        }
    }

    static func relocate(_ workspace: Workspace, in workspaces: WorkspaceStore, runner: ProcessRunner) {
        guard !runner.isWorkspaceRunning(workspace.id) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("Choose the new folder containing library.json. Files will not be moved or copied.")
        panel.prompt = L("Relocate")
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            do { try workspaces.relocate(workspace.id, to: directory, protectedID: runner.protectedWorkspaceID(for: workspace.id)) }
            catch { workspaces.error = error.localizedDescription }
        }
    }
}
