import Foundation

struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var directory: String
    var directoryURL: URL { URL(fileURLWithPath: directory) }
}

struct WorkspaceRegistry: Codable {
    var version = 1
    var workspaces: [Workspace] = []
    var selectedID: String?
}
