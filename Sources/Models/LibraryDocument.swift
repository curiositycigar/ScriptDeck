import Foundation

struct LibraryDocument: Codable {
    var version = 1
    var scripts: [ScriptItem] = []
    var folders: [String] = []
    var schema: String? = "library.schema.json"
    enum CodingKeys: String, CodingKey { case version, scripts, folders; case schema = "$schema" }

    init(scripts: [ScriptItem] = [], folders: [String] = []) {
        self.scripts = scripts
        self.folders = folders
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        scripts = try values.decode([ScriptItem].self, forKey: .scripts)
        folders = try values.decodeIfPresent([String].self, forKey: .folders) ?? []
        schema = try values.decodeIfPresent(String.self, forKey: .schema)
    }

    func validate() throws {
        var paths = Set<String>()
        for folder in folders {
            guard !folder.isEmpty, folder.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "." && $0 != ".." && !$0.contains(where: { $0.isNewline || $0 == "\0" })
            }), paths.insert(folder).inserted else {
                throw RunnerError(message: L("Empty, invalid, or duplicate folder path: {0}", "\(folder)"))
            }
        }
        guard version == 1 else { throw RunnerError(message: L("Unsupported configuration version: {0}. Only version: 1 is supported.", "\(version)")) }
        var ids = Set<String>()
        for script in scripts {
            guard !script.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ids.insert(script.id).inserted else {
                throw RunnerError(message: L("Empty or duplicate script id: {0}", "\(script.id)"))
            }
            guard !script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !script.path.isEmpty else {
                throw RunnerError(message: L("Script {0} must have a name and file.", "\(script.id)"))
            }
            guard !script.interpreter.isEmpty else { throw RunnerError(message: L("Script {0} must have an interpreter.", "\(script.id)")) }
            var argumentNames = Set<String>()
            var parameterIDs = Set<String>()
            for parameter in script.parameters {
                let context = L("Script {0}, parameter {1}", "\(script.name)", "\(parameter.id)")
                guard !parameter.id.isEmpty, parameterIDs.insert(parameter.id).inserted, !parameter.name.isEmpty else {
                    throw RunnerError(message: L("{0}: parameter id is empty or duplicated, or label is empty.", "\(context)"))
                }
                if let issue = parameter.configurationIssue { throw RunnerError(message: "\(context)：\(issue)") }
                if parameter.passing != .positional && !argumentNames.insert(parameter.argumentName).inserted {
                    throw RunnerError(message: L("{0}: duplicate named argument or flag name.", "\(context)"))
                }
                if parameter.kind == .select && parameter.passing != .flag {
                    guard !parameter.options.isEmpty else { throw RunnerError(message: L("{0}: select parameters must define options.", "\(context)")) }
                    var values = Set<String>()
                    for option in parameter.options {
                        guard !option.value.isEmpty, !option.label.isEmpty, values.insert(option.value).inserted else {
                            throw RunnerError(message: L("{0}: option labels and values must be nonempty, and values must be unique.", "\(context)"))
                        }
                    }
                    guard parameter.defaultValue.isEmpty || values.contains(parameter.defaultValue) else {
                        throw RunnerError(message: L("{0}: default must match an option value.", "\(context)"))
                    }
                }
            }
        }
    }
}
