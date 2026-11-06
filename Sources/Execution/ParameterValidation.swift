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
            if !["", "true", "false"].contains(value) { issues[parameter.id] = L("Choose a switch state.") }
            continue
        }
        if value.isEmpty {
            if parameter.required { issues[parameter.id] = L("Enter a value for this required parameter.") }
            else if parameter.passing == .positional, let last, index < last { issues[parameter.id] = L("A later parameter has a value, so this position cannot be empty.") }
            continue
        }
        if parameter.kind == .select && !parameter.options.contains(where: { $0.value == value }) {
            issues[parameter.id] = L("Choose a valid option.")
        }
        if parameter.kind == .file || parameter.kind == .folder {
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: value, isDirectory: &directory)
            if !exists || (parameter.kind == .folder ? !directory.boolValue : directory.boolValue) {
                issues[parameter.id] = parameter.kind == .folder ? L("The folder does not exist or its path is invalid.") : L("The file does not exist or its path is invalid.")
            }
        }
    }
    return issues
}
