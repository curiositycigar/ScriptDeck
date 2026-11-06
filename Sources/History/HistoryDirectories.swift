import Foundation

/// Only directory locations are indexed locally; log contents stay beside the scripts.
@MainActor
final class HistoryDirectories {
    static let shared = HistoryDirectories()
    private let key = "executionLogDirectories.v1"
    private let preferences: UserDefaults
    init(preferences: UserDefaults = .standard) { self.preferences = preferences }
    var urls: [URL] { (preferences.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) } }
    func remember(_ directory: URL) {
        let path = directory.standardizedFileURL.path
        var paths = preferences.stringArray(forKey: key) ?? []
        guard !paths.contains(path) else { return }
        paths.append(path)
        preferences.set(paths, forKey: key)
    }
    func candidates(workspaces: WorkspaceStore) -> [URL] {
        var paths = Set(urls.map(\.path))
        for workspace in workspaces.items {
            for item in workspaces.library(for: workspace).items {
                paths.insert(RunLogWriter.directory(for: URL(fileURLWithPath: workspaces.library(for: workspace).resolved(item).path)).path)
            }
        }
        return paths.sorted().map { URL(fileURLWithPath: $0) }
    }
}
