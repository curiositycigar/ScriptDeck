import Foundation
import Combine

final class ScriptStore: ObservableObject {
    @Published private(set) var items: [ScriptItem] = []
    @Published private(set) var folders: [String] = []
    @Published private(set) var directoryURL: URL?
    @Published private(set) var configurationIssue: String?
    @Published private(set) var revision = 0
    @Published var error: String?
    var fileURL: URL? { directoryURL?.appendingPathComponent("library.json") }
    private let preferences: UserDefaults
    private var loadedData: Data?
    private var lastSeenData: Data?
    private var monitor: Timer?

    init(preferences: UserDefaults = .standard, restoreLastDirectory: Bool = true) {
        self.preferences = preferences
        if restoreLastDirectory, let saved = preferences.string(forKey: "libraryDirectory") {
            do { try open(URL(fileURLWithPath: saved), remember: false) }
            catch {
                directoryURL = URL(fileURLWithPath: saved).standardizedFileURL.resolvingSymlinksInPath()
                configurationIssue = L("Unable to load the previous script library. Fix library.json or select another folder.\n{0}", "\(configurationError(error))")
            }
        }
        monitor = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.reloadFromDisk() }
        RunLoop.main.add(monitor!, forMode: .common)
    }
    deinit { monitor?.invalidate() }

    /// Load a specific workspace without ever showing another workspace's cached content.
    func loadDirectory(_ directory: URL) {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        if directoryURL != directory {
            directoryURL = directory
            items = []
            folders = []
            loadedData = nil
            lastSeenData = nil
            revision += 1
        }
        do { try open(directory, remember: false) }
        catch { configurationIssue = L("Unable to load this workspace. Fix its configuration or relocate the folder.\n{0}", "\(configurationError(error))") }
    }

    func open(_ directory: URL, remember: Bool = true) throws {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: directory.appendingPathComponent("library.json"))
        let document = try decode(data)
        directoryURL = directory
        items = document.scripts
        folders = document.folders
        loadedData = data
        lastSeenData = data
        configurationIssue = nil
        revision += 1
        if remember { preferences.set(directory.path, forKey: "libraryDirectory") }
    }

    func initialize(_ directory: URL, remember: Bool = true) throws {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let configuration = directory.appendingPathComponent("library.json")
        guard !FileManager.default.fileExists(atPath: configuration.path) else {
            throw RunnerError(message: L("This folder already contains library.json. Open it directly to preserve its configuration."))
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        let data = try encode(LibraryDocument(scripts: []))
        try data.write(to: configuration, options: .withoutOverwriting)
        if let schema = Bundle.main.url(forResource: "library.schema", withExtension: "json") {
            let target = directory.appendingPathComponent("library.schema.json")
            if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: schema, to: target) }
        }
        try open(directory, remember: remember)
    }

    func reloadFromDisk(force: Bool = false) {
        guard let fileURL else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard force || data != lastSeenData else { return }
            lastSeenData = data
            let document = try decode(data)
            if data != loadedData {
                items = document.scripts
                folders = document.folders
                loadedData = data
                revision += 1
            }
            configurationIssue = nil
        } catch {
            configurationIssue = L("Unable to load library.json; showing the last valid configuration.\n{0}", "\(configurationError(error))")
        }
    }

    func resolved(_ item: ScriptItem) -> ScriptItem {
        guard let directoryURL else { return item }
        var resolved = item
        resolved.path = absolutePath(item.path, in: directoryURL)
        if !item.workingDirectory.isEmpty { resolved.workingDirectory = absolutePath(item.workingDirectory, in: directoryURL) }
        return resolved
    }

    func resolvedParameterPath(_ path: String) -> String {
        guard let directoryURL else { return path }
        return absolutePath(path, in: directoryURL)
    }

    private func absolutePath(_ path: String, in directory: URL) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appendingPathComponent(expanded)).standardizedFileURL.path
    }
    private func relativePath(_ path: String, in directory: URL) -> String {
        let path = absolutePath(path, in: directory)
        if path == directory.path { return "." }
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
    private func normalized(_ item: ScriptItem) -> ScriptItem {
        guard let directoryURL else { return item }
        var item = item
        item.path = relativePath(item.path, in: directoryURL)
        if !item.workingDirectory.isEmpty { item.workingDirectory = relativePath(item.workingDirectory, in: directoryURL) }
        return item
    }
    private func decode(_ data: Data) throws -> LibraryDocument {
        // JSONSerialization provides the parser's byte/line diagnostics for malformed JSON.
        _ = try JSONSerialization.jsonObject(with: data)
        let document = try JSONDecoder().decode(LibraryDocument.self, from: data)
        try document.validate()
        return document
    }
    private func encode(_ document: LibraryDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
    private func currentFileUnchanged(expectedRevision: Int? = nil) throws {
        guard let fileURL else { throw RunnerError(message: L("Open or initialize a script library first.")) }
        if let expectedRevision, expectedRevision != revision {
            throw RunnerError(message: L("The library was modified externally. Cancel and reopen the editor to avoid overwriting newer changes."))
        }
        guard configurationIssue == nil, try Data(contentsOf: fileURL) == loadedData else {
            reloadFromDisk(force: true)
            throw RunnerError(message: L("library.json has changed or cannot be read. Resolve the configuration issue and try again. The original file was preserved."))
        }
    }
    @discardableResult
    private func persist(_ proposed: [ScriptItem], folders proposedFolders: [String]? = nil, expectedRevision: Int? = nil) -> Bool {
        do {
            try currentFileUnchanged(expectedRevision: expectedRevision)
            guard let fileURL else { return false }
            let normalized = proposed.map(normalized)
            let data = try encode(LibraryDocument(scripts: normalized, folders: proposedFolders ?? folders))
            try data.write(to: fileURL, options: .atomic)
            items = normalized
            folders = proposedFolders ?? folders
            loadedData = data
            lastSeenData = data
            configurationIssue = nil
            revision += 1
            return true
        } catch { self.error = L("Unable to save: {0}", "\(configurationError(error))"); return false }
    }
    @discardableResult
    func upsert(_ item: ScriptItem, expectedRevision: Int? = nil) -> Bool {
        var proposed = items
        if let index = proposed.firstIndex(where: { $0.id == item.id }) { proposed[index] = item }
        else { proposed.append(item) }
        return persist(proposed, expectedRevision: expectedRevision)
    }
    func remove(_ id: String) { persist(items.filter { $0.id != id }) }

    @discardableResult
    func createFolder(name: String, parent: String = "", expectedRevision: Int? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains(where: { $0.isNewline || $0 == "\0" }) else {
            error = L("A folder name cannot be empty, contain / or newlines, or be . or ...")
            return false
        }
        let path = parent.isEmpty ? name : parent + "/" + name
        let existing = Set(folders + items.map { $0.category.isEmpty ? "未分组" : $0.category })
        guard !existing.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) else {
            error = L("A folder with this name already exists here.")
            return false
        }
        return persist(items, folders: folders + [path], expectedRevision: expectedRevision)
    }

    @discardableResult
    func removeFolder(_ path: String, expectedRevision: Int? = nil) -> Bool {
        guard path != "未分组" else { error = L("“Ungrouped” holds scripts without a folder and cannot be deleted."); return false }
        // Retain empty ancestors even when the deleted child was their only content.
        let parts = path.split(separator: "/").map(String.init)
        let ancestors = (1..<max(1, parts.count)).map { parts.prefix($0).joined(separator: "/") }
        let retained = Set(folders.filter { !ScriptGroup.contains($0, in: path) } + ancestors).sorted()
        let proposed = items.map { item in
            var item = item
            if ScriptGroup.contains(item.category, in: path) { item.category = "未分组" }
            return item
        }
        return persist(proposed, folders: retained, expectedRevision: expectedRevision)
    }

    private func copiedScript(_ url: URL, into directory: URL) throws -> URL {
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        if source.path.hasPrefix(directory.path + "/") { return source }
        let folder = directory.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
            destination = folder.appendingPathComponent("\(stem)-\(suffix)\(ext)")
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
    func importURLs(_ urls: [URL]) -> String? {
        do {
            try currentFileUnchanged()
            guard let directoryURL else { return nil }
            var proposed = items
            var firstID: String?
            for url in urls {
                var directory: ObjCBool = false
                guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { continue }
                if let existing = proposed.first(where: { absolutePath($0.path, in: directoryURL) == url.standardizedFileURL.path }) {
                    firstID = firstID ?? existing.id; continue
                }
                var item = ScriptItem.importing(url)
                item.path = try copiedScript(url, into: directoryURL).path
                proposed.append(item)
                firstID = firstID ?? item.id
            }
            return persist(proposed) ? firstID : nil
        } catch { self.error = L("Unable to import: {0}", "\(configurationError(error))"); return nil }
    }
}
