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
    var interactiveUI = false
    var allowsMultipleInstances = false

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
        case id, name, group, file, interpreter, cwd, description, execution, parameters, interactiveUI, allowsMultipleInstances
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
        interactiveUI = try c.decodeIfPresent(Bool.self, forKey: .interactiveUI) ?? false
        parameters = try c.decodeIfPresent([ScriptParameter].self, forKey: .parameters) ?? []
        allowsMultipleInstances = try c.decodeIfPresent(Bool.self, forKey: .allowsMultipleInstances) ?? false
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
        if interactiveUI { try c.encode(true, forKey: .interactiveUI) }
        try c.encode(allowsMultipleInstances, forKey: .allowsMultipleInstances)
        try c.encode(parameters, forKey: .parameters)
    }
}
