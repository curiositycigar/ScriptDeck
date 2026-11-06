import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", chinese = "zh-Hans"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L("Follow System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
    static func resolve(_ selection: String?, preferredLanguages: [String]) -> String {
        if let language = AppLanguage(rawValue: selection ?? ""), language != .system { return language.rawValue }
        // Unsupported system languages fall back to English.
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

enum L10n {
    static let defaults = UserDefaults(suiteName: "com.lucasyou.ScriptDeck") ?? .standard
    static let language = AppLanguage.resolve(
        ProcessInfo.processInfo.environment["SCRIPTDECK_LANGUAGE"] ?? defaults.string(forKey: "appLanguage"),
        preferredLanguages: Locale.preferredLanguages)
    static var locale: Locale { Locale(identifier: language) }

    // Locate resources without Bundle.module's fatal error when a standalone helper is missing its bundle.
    static let resourceBundle: Bundle? = {
        let name = "ScriptDeck_ScriptDeck.bundle"
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          Bundle.main.bundleURL.appendingPathComponent(name),
                          executable.deletingLastPathComponent().appendingPathComponent(name)]
        return candidates.compactMap { $0 }.compactMap { Bundle(url: $0) }.first
    }()

    static func text(_ key: String, arguments: [String] = [], language: String = language) -> String {
        let bundle = resourceBundle?.path(forResource: language.lowercased(), ofType: "lproj").flatMap(Bundle.init(path:))
        let template = bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        // Replace in one pass so braces in user-provided values are never interpreted as placeholders.
        let pattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        var result = template
        for match in pattern.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let indexRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[indexRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }

    static func weekday(_ day: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.weekdaySymbols[max(0, min(6, day - 1))]
    }
    static func date(_ date: Date, dateStyle: DateFormatter.Style = .medium,
                     timeStyle: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
}

func L(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments) }
