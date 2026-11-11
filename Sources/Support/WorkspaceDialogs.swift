import AppKit
import UniformTypeIdentifiers

@MainActor
enum WorkspaceDialogs {
    private static let packageType = UTType(filenameExtension: WorkspaceTransfer.fileExtension) ?? .data

    static func export(_ workspace: Workspace, from workspaces: WorkspaceStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [packageType]
        panel.nameFieldStringValue = workspace.name.replacingOccurrences(of: "/", with: "-") + "." + WorkspaceTransfer.fileExtension
        panel.message = L("Exports registered scripts and their current parameter values. Review script contents and parameter values before sharing.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let package = try WorkspaceTransfer(store: workspaces.library(for: workspace),
                                                    values: workspaces.session(for: workspace).values)
                try package.write(to: url)
            } catch { workspaces.error = error.localizedDescription }
        }
    }

    static func importPackage(to workspaces: WorkspaceStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [packageType]
        panel.prompt = L("Import")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importPackage(at: url, to: workspaces)
        }
    }

    @discardableResult
    static func importDroppedPackage(_ urls: [URL], to workspaces: WorkspaceStore) -> Bool {
        guard let url = urls.first(where: WorkspaceTransfer.isPackageURL) else { return false }
        importPackage(at: url, to: workspaces)
        return true
    }

    private static func importPackage(at url: URL, to workspaces: WorkspaceStore) {
        do {
            try workspaces.checkRegistry()
            let package = try WorkspaceTransfer.read(from: url)
            let destination = NSOpenPanel()
            destination.canChooseFiles = false
            destination.canChooseDirectories = true
            destination.canCreateDirectories = true
            destination.directoryURL = url.deletingLastPathComponent()
            destination.message = L("Choose where to create a new workspace folder.")
            destination.prompt = L("Import")
            destination.begin { response in
                guard response == .OK, let parent = destination.url else { return }
                do {
                    try workspaces.checkRegistry()
                    let folder = try package.install(in: parent, named: url.deletingPathExtension().lastPathComponent)
                    try workspaces.register(folder)
                } catch { workspaces.error = error.localizedDescription }
            }
        } catch { workspaces.error = error.localizedDescription }
    }

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
