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
                throw RunnerError(message: "文件夹路径为空、无效或重复：\(folder)")
            }
        }
        guard version == 1 else { throw RunnerError(message: "不支持的配置版本：\(version)，当前支持 version: 1。") }
        var ids = Set<String>()
        for script in scripts {
            guard !script.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ids.insert(script.id).inserted else {
                throw RunnerError(message: "脚本 id 为空或重复：\(script.id)")
            }
            guard !script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !script.path.isEmpty else {
                throw RunnerError(message: "脚本 \(script.id) 的 name 和 file 不能为空。")
            }
            guard !script.interpreter.isEmpty else { throw RunnerError(message: "脚本 \(script.id) 的 interpreter 不能为空。") }
            var argumentNames = Set<String>()
            var parameterIDs = Set<String>()
            for parameter in script.parameters {
                let context = "脚本 \(script.name) 的参数 \(parameter.id)"
                guard !parameter.id.isEmpty, parameterIDs.insert(parameter.id).inserted, !parameter.name.isEmpty else {
                    throw RunnerError(message: "\(context)：参数 id 为空、重复，或 label 为空。")
                }
                if let issue = parameter.configurationIssue { throw RunnerError(message: "\(context)：\(issue)") }
                if parameter.passing != .positional && !argumentNames.insert(parameter.argumentName).inserted {
                    throw RunnerError(message: "\(context)：命名参数或开关名称重复。")
                }
                if parameter.kind == .select && parameter.passing != .flag {
                    guard !parameter.options.isEmpty else { throw RunnerError(message: "\(context)：下拉参数必须配置 options。") }
                    var values = Set<String>()
                    for option in parameter.options {
                        guard !option.value.isEmpty, !option.label.isEmpty, values.insert(option.value).inserted else {
                            throw RunnerError(message: "\(context)：选项名称和传值不能为空，传值不能重复。")
                        }
                    }
                    guard parameter.defaultValue.isEmpty || values.contains(parameter.defaultValue) else {
                        throw RunnerError(message: "\(context)：default 必须匹配某个选项的 value。")
                    }
                }
            }
        }
    }
}
