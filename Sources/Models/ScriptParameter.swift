import Foundation

enum ParameterKind: String, Codable, CaseIterable, Identifiable {
    case text, file, folder, select, editableSelect
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return L("Text")
        case .file: return L("File")
        case .folder: return L("Folder")
        case .select: return L("Selection")
        case .editableSelect: return L("Editable Selection")
        }
    }
}

struct ParameterOption: Codable, Identifiable, Equatable {
    var label: String
    var value: String
    var id: String { value }
    init(label: String = "", value: String = "") { self.label = label; self.value = value }
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            label = text; value = text
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(String.self, forKey: .value)
            label = try container.decodeIfPresent(String.self, forKey: .label) ?? value
        }
    }
}

enum ParameterPassing: String, Codable, CaseIterable, Identifiable {
    case positional, named, flag
    var id: String { rawValue }
    var title: String {
        switch self {
        case .positional: return L("Positional Argument")
        case .named: return L("Named Argument")
        case .flag: return L("Boolean Flag")
        }
    }
}

enum NamedArgumentFormat: String, Codable, CaseIterable, Identifiable {
    case separated, equals
    var id: String { rawValue }
    var title: String { self == .separated ? "--name value" : "--name=value" }
}

struct ScriptParameter: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = L("Parameter")
    var kind: ParameterKind = .text
    var passing: ParameterPassing = .positional
    var argumentName = ""
    var argumentFormat: NamedArgumentFormat = .separated
    var required = false
    var defaultValue = ""
    var placeholder = ""
    var options: [ParameterOption] = []
}

extension ScriptParameter {
    enum CodingKeys: String, CodingKey {
        case id, label, type, required, placeholder, options, passing, argumentName, argumentFormat
        case defaultValue = "default"
        case oldName = "name", oldKind = "kind", oldDefault = "defaultValue"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .label) ?? c.decode(String.self, forKey: .oldName)
        kind = try c.decodeIfPresent(ParameterKind.self, forKey: .type) ?? c.decodeIfPresent(ParameterKind.self, forKey: .oldKind) ?? .text
        passing = try c.decodeIfPresent(ParameterPassing.self, forKey: .passing) ?? .positional
        argumentName = try c.decodeIfPresent(String.self, forKey: .argumentName) ?? ""
        argumentFormat = try c.decodeIfPresent(NamedArgumentFormat.self, forKey: .argumentFormat) ?? .separated
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue) ?? c.decodeIfPresent(String.self, forKey: .oldDefault) ?? ""
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        options = try c.decodeIfPresent([ParameterOption].self, forKey: .options) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .label)
        try c.encode(kind, forKey: .type)
        if passing != .positional {
            try c.encode(passing, forKey: .passing)
            try c.encode(argumentName, forKey: .argumentName)
            if passing == .named { try c.encode(argumentFormat, forKey: .argumentFormat) }
        }
        try c.encode(required, forKey: .required)
        if !defaultValue.isEmpty { try c.encode(defaultValue, forKey: .defaultValue) }
        if !placeholder.isEmpty { try c.encode(placeholder, forKey: .placeholder) }
        if kind == .select || kind == .editableSelect { try c.encode(options, forKey: .options) }
    }
}

extension ScriptParameter {
    var configurationIssue: String? {
        if passing != .positional {
            guard argumentName.range(of: "^-{1,2}[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil else {
                return L("Argument names must start with - or --, such as -o or --output, and contain no spaces or equals signs.")
            }
        }
        if passing == .flag && !["", "true", "false"].contains(defaultValue) {
            return L("A flag default must be true, false, or empty.")
        }
        return nil
    }
    var summary: String {
        if passing == .flag { return L("Flag · {0}", "\(argumentName)") }
        if passing == .named { return L("{0} · {1}{2}", "\(kind.title)", "\(argumentName)", "\(argumentFormat == .equals ? L("=value") : L(" value"))") }
        return L("{0} · positional argument{1}", "\(kind.title)", "\(required ? L(" · required") : "")")
    }
}
