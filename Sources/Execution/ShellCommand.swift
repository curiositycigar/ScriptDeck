import Foundation

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func scriptArguments(for item: ScriptItem, values: [String: String]) throws -> [String] {
    let issues = parameterIssues(for: item, values: values)
    if let parameter = item.parameters.first(where: { issues[$0.id] != nil }), let message = issues[parameter.id] {
        throw RunnerError(message: "“\(parameter.name)”：\(message)")
    }
    var arguments: [String] = []
    for parameter in item.parameters {
        let value = values[parameter.id] ?? parameter.defaultValue
        switch parameter.passing {
        case .positional:
            if !value.isEmpty { arguments.append(value) }
        case .named:
            if !value.isEmpty {
                if parameter.argumentFormat == .equals { arguments.append(parameter.argumentName + "=" + value) }
                else { arguments += [parameter.argumentName, value] }
            }
        case .flag:
            if value == "true" { arguments.append(parameter.argumentName) }
        }
    }
    return arguments
}

func executionCommand(_ item: ScriptItem, arguments: [String]) throws -> (argv: [String], directory: String) {
    guard item.path.hasPrefix("/"), item.workingDirectory.isEmpty || item.workingDirectory.hasPrefix("/") else {
        throw RunnerError(message: L("The script and working directory must use absolute paths. Use “Choose…” to select them."))
    }
    var directoryFlag: ObjCBool = false
    guard FileManager.default.fileExists(atPath: item.path, isDirectory: &directoryFlag), !directoryFlag.boolValue else {
        throw RunnerError(message: L("Script not found: {0}", "\(item.path)"))
    }
    guard FileManager.default.isReadableFile(atPath: item.path) else {
        throw RunnerError(message: L("Unable to read the script: {0}", "\(item.path)"))
    }
    let directory = item.workingDirectory.isEmpty ? URL(fileURLWithPath: item.path).deletingLastPathComponent().path : item.workingDirectory
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &directoryFlag), directoryFlag.boolValue else {
        throw RunnerError(message: L("Working directory not found: {0}", "\(directory)"))
    }
    let prefix: [String]
    switch item.interpreter {
    case "direct":
        guard FileManager.default.isExecutableFile(atPath: item.path) else {
            throw RunnerError(message: L("The script is not executable. Choose an interpreter or grant execute permission."))
        }
        prefix = [item.path]
    case "python3": prefix = ["/usr/bin/env", "python3", "-u", item.path]
    case "node": prefix = ["/usr/bin/env", "node", item.path]
    default:
        guard item.interpreter.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: item.interpreter) else {
            throw RunnerError(message: L("The interpreter must be an absolute path to an executable file."))
        }
        prefix = [item.interpreter, item.path]
    }
    return (prefix + arguments, directory)
}
