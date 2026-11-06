import Foundation

struct ScriptGroup: Identifiable {
    var id: String
    var name: String
    var children: [ScriptGroup]
    var scripts: [ScriptItem]

    var displayName: String { id == "未分组" ? L("Ungrouped") : name }

    static func contains(_ category: String, in folder: String) -> Bool {
        let path = category.split(separator: "/").map(String.init).joined(separator: "/")
        let pathOrDefault = path.isEmpty ? "未分组" : path
        return pathOrDefault == folder || pathOrDefault.hasPrefix(folder + "/")
    }

    static func tree(_ scripts: [ScriptItem], folders: [String] = [], prefix: [String] = []) -> [ScriptGroup] {
        func components(_ item: ScriptItem) -> [String] {
            let parts = item.category.split(separator: "/").map(String.init)
            return parts.isEmpty ? ["未分组"] : parts
        }
        let matching = scripts.filter { Array(components($0).prefix(prefix.count)) == prefix && components($0).count > prefix.count }
        let folderPaths = folders.map { $0.split(separator: "/").map(String.init) }
            .filter { Array($0.prefix(prefix.count)) == prefix && $0.count > prefix.count }
        let names = Set(matching.map { components($0)[prefix.count] } + folderPaths.map { $0[prefix.count] }).sorted()
        return names.map { name in
            let path = prefix + [name]
            return ScriptGroup(id: path.joined(separator: "/"), name: name,
                               children: tree(matching, folders: folders, prefix: path),
                               scripts: matching.filter { components($0) == path })
        }
    }
}
