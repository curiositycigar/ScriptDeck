import Foundation

struct ScriptItem: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = L("New Script")
    var category = L("Favorites")
    var path = ""
    var interpreter = "/bin/bash"
    var workingDirectory = ""
    var notes = ""
    var execution: ExecutionMode = .embedded
    var parameters: [ScriptParameter] = []

    static func importing(_ url: URL) -> ScriptItem {
        var item = ScriptItem()
        item.name = url.deletingPathExtension().lastPathComponent
        item.path = url.path
        switch url.pathExtension.lowercased() {
        case "py": item.interpreter = "python3"
        case "js", "mjs", "cjs": item.interpreter = "node"
        case "zsh": item.interpreter = "/bin/zsh"
        default: break
        }
        return item
    }
}

extension ScriptItem {
    enum CodingKeys: String, CodingKey {
        case id, name, group, file, interpreter, cwd, description, execution, parameters
        case oldCategory = "category", oldPath = "path", oldDirectory = "workingDirectory", oldNotes = "notes"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .group) ?? c.decodeIfPresent(String.self, forKey: .oldCategory) ?? "未分组"
        path = try c.decodeIfPresent(String.self, forKey: .file) ?? c.decode(String.self, forKey: .oldPath)
        interpreter = try c.decodeIfPresent(String.self, forKey: .interpreter) ?? "/bin/bash"
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .cwd) ?? c.decodeIfPresent(String.self, forKey: .oldDirectory) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .description) ?? c.decodeIfPresent(String.self, forKey: .oldNotes) ?? ""
        execution = try c.decodeIfPresent(ExecutionMode.self, forKey: .execution) ?? .embedded
        parameters = try c.decodeIfPresent([ScriptParameter].self, forKey: .parameters) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .group)
        try c.encode(path, forKey: .file)
        try c.encode(interpreter, forKey: .interpreter)
        if !workingDirectory.isEmpty { try c.encode(workingDirectory, forKey: .cwd) }
        if !notes.isEmpty { try c.encode(notes, forKey: .description) }
        try c.encode(parameters, forKey: .parameters)
    }
}
