import Foundation

enum ParameterKind: String, Codable, CaseIterable, Identifiable {
    case text, file, folder, select
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "文本"
        case .file: return "文件"
        case .folder: return "文件夹"
        case .select: return "下拉选项"
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
        case .positional: return "位置参数"
        case .named: return "命名参数"
        case .flag: return "布尔开关"
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
    var name = "参数"
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
        if kind == .select { try c.encode(options, forKey: .options) }
    }
}

extension ScriptParameter {
    var configurationIssue: String? {
        if passing != .positional {
            guard argumentName.range(of: "^-{1,2}[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil else {
                return "参数名需以 - 或 -- 开头，例如 -o 或 --output，且不能含空格或等号。"
            }
        }
        if passing == .flag && !["", "true", "false"].contains(defaultValue) {
            return "开关默认值只能为 true、false 或留空。"
        }
        return nil
    }
    var summary: String {
        if passing == .flag { return "开关 · \(argumentName)" }
        if passing == .named { return "\(kind.title) · \(argumentName)\(argumentFormat == .equals ? "=值" : " 值")" }
        return "\(kind.title) · 位置参数\(required ? " · 必填" : "")"
    }
}
