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
        panel.message = "选择 Workspace 目录；已有 library.json 时直接添加，没有时可初始化。"
        panel.prompt = "添加 Workspace"
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
                    alert.messageText = "初始化 Workspace？"
                    alert.informativeText = "将创建 library.json 和 scripts 文件夹，保留已有文件。"
                    alert.addButton(withTitle: "创建空脚本库")
                    alert.addButton(withTitle: "取消")
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
        panel.message = "选择包含 library.json 的新目录，不会移动或复制文件。"
        panel.prompt = "重新定位"
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            do { try workspaces.relocate(workspace.id, to: directory, protectedID: runner.protectedWorkspaceID(for: workspace.id)) }
            catch { workspaces.error = error.localizedDescription }
        }
    }
}
