import Foundation
import Combine

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var items: [Workspace] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var availability: [String: String] = [:]
    @Published var error: String?
    private let preferences: UserDefaults
    private let registryKey = "workspaceRegistry.v1"
    private var registryIssue: String?
    private var stores: [String: ScriptStore] = [:]
    private var sessions: [String: WorkspaceSession] = [:]
    private var monitor: Timer?
    var selected: Workspace? { items.first { $0.id == selectedID } }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: registryKey) {
            do {
                let registry = try JSONDecoder().decode(WorkspaceRegistry.self, from: data)
                guard registry.version == 1,
                      Set(registry.workspaces.map(\.id)).count == registry.workspaces.count,
                      registry.workspaces.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.directory.hasPrefix("/") }) else {
                    throw RunnerError(message: "Workspace 登记格式无效。")
                }
                items = registry.workspaces
                selectedID = items.contains(where: { $0.id == registry.selectedID }) ? registry.selectedID : items.first?.id
            } catch {
                registryIssue = "无法读取本机 Workspace 登记，已有数据未覆盖。\n\(error.localizedDescription)"
                self.error = registryIssue
            }
        }
        refreshAvailability()
        monitor = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAvailability() }
        }
        RunLoop.main.add(monitor!, forMode: .common)
    }
    deinit { monitor?.invalidate() }

    func library(for workspace: Workspace) -> ScriptStore {
        if let store = stores[workspace.id] { return store }
        let store = ScriptStore(restoreLastDirectory: false)
        store.loadDirectory(workspace.directoryURL)
        stores[workspace.id] = store
        return store
    }
    func session(for workspace: Workspace) -> WorkspaceSession {
        if let session = sessions[workspace.id] { return session }
        let session = WorkspaceSession()
        sessions[workspace.id] = session
        return session
    }
    func existing(at url: URL) -> Workspace? {
        let path = canonical(url).path
        return items.first { canonical($0.directoryURL).path == path }
    }
    func select(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }
    @discardableResult
    func register(_ url: URL) throws -> String {
        try checkRegistry()
        if let existing = existing(at: url) { select(existing.id); return existing.id }
        let directory = canonical(url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RunnerError(message: "请选择可访问的 Workspace 文件夹。")
        }
        let item = Workspace(name: directory.lastPathComponent, directory: directory.path)
        items.append(item)
        selectedID = item.id
        persist()
        refreshAvailability()
        return item.id
    }
    func rename(_ id: String, to name: String) throws {
        try checkRegistry()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RunnerError(message: "Workspace 名称不能为空。") }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = name
        persist()
    }
    func move(_ id: String, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
        persist()
    }
    func relocate(_ id: String, to url: URL, protectedID: String?) throws {
        try checkRegistry()
        guard id != protectedID else { throw RunnerError(message: "请先结束此 Workspace 的任务，再重新定位目录。") }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let existing = existing(at: url), existing.id != id {
            throw RunnerError(message: "这个目录已经登记为“\(existing.name)”。")
        }
        let directory = canonical(url)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path) else {
            throw RunnerError(message: "所选目录中没有 library.json，请选择原脚本库的新位置。")
        }
        items[index].directory = directory.path
        stores[id]?.loadDirectory(directory)
        persist()
        refreshAvailability()
    }
    func remove(_ id: String, protectedID: String?) throws {
        try checkRegistry()
        guard id != protectedID else { throw RunnerError(message: "请先结束此 Workspace 的任务，再移除登记。") }
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = items.first?.id }
        stores[id] = nil
        sessions[id] = nil
        persist()
        refreshAvailability()
    }
    private func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
    func checkRegistry() throws {
        if let registryIssue { throw RunnerError(message: registryIssue) }
    }
    private func persist() {
        guard registryIssue == nil else { return }
        do {
            let data = try JSONEncoder().encode(WorkspaceRegistry(workspaces: items, selectedID: selectedID))
            preferences.set(data, forKey: registryKey)
        } catch { self.error = "Workspace 登记保存失败：\(error.localizedDescription)" }
    }
    private func refreshAvailability() {
        var issues: [String: String] = [:]
        for item in items {
            var directory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: item.directory, isDirectory: &directory) || !directory.boolValue {
                issues[item.id] = "目录不可用"
            } else if !FileManager.default.fileExists(atPath: item.directoryURL.appendingPathComponent("library.json").path) {
                issues[item.id] = "缺少 library.json"
            }
        }
        if issues != availability { availability = issues }
    }
}
