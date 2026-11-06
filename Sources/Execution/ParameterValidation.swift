import Foundation

// Shared by inline feedback and execution so both enforce the same rules.
func parameterIssues(for item: ScriptItem, values: [String: String]) -> [String: String] {
    let entries = item.parameters.map { values[$0.id] ?? $0.defaultValue }
    let last = item.parameters.indices.last(where: { item.parameters[$0].passing == .positional && !entries[$0].isEmpty })
    var issues: [String: String] = [:]
    for (index, parameter) in item.parameters.enumerated() {
        let value = entries[index]
        if let issue = parameter.configurationIssue { issues[parameter.id] = issue; continue }
        if parameter.passing == .flag {
            if !["", "true", "false"].contains(value) { issues[parameter.id] = "请选择开关状态。" }
            continue
        }
        if value.isEmpty {
            if parameter.required { issues[parameter.id] = "请填写此必填参数。" }
            else if parameter.passing == .positional, let last, index < last { issues[parameter.id] = "后续参数已有值，此位置不能留空。" }
            continue
        }
        if parameter.kind == .select && !parameter.options.contains(where: { $0.value == value }) {
            issues[parameter.id] = "请选择有效选项。"
        }
        if parameter.kind == .file || parameter.kind == .folder {
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: value, isDirectory: &directory)
            if !exists || (parameter.kind == .folder ? !directory.boolValue : directory.boolValue) {
                issues[parameter.id] = parameter.kind == .folder ? "文件夹不存在或路径无效。" : "文件不存在或路径无效。"
            }
        }
    }
    return issues
}
