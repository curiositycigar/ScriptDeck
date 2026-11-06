import Foundation
import AppKit
import SwiftUI

@MainActor func runLocalizationSelfTests() throws {
    guard let bundle = L10n.resourceBundle else { fatalError("Localization bundle is missing") }
    func catalog(_ language: String) throws -> [String: String] {
        let url = bundle.bundleURL.appendingPathComponent(language + ".lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: String]
    }
    let english = try catalog("en")
    let chinese = try catalog("zh-hans")
    check(english.count > 400 && Set(english.keys) == Set(chinese.keys), "English and Chinese catalogs cover the same interface keys")
    let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
    func placeholders(_ value: String) -> [String] {
        regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
            String(value[Range($0.range, in: value)!])
        }.sorted()
    }
    check(english.allSatisfy { key, value in value == key && placeholders(value) == placeholders(chinese[key]!) },
          "Translations preserve every interpolation placeholder and English fallback")
    check(L10n.text("Run", language: "en") == "Run" && L10n.text("Run", language: "zh-Hans") == "运行",
          "Both languages load from the bundled string tables")
    check(L10n.text("Untranslated fallback", language: "xx") == "Untranslated fallback",
          "Missing translations fall back to readable English")
    check(L10n.text("Failed (exit code {0})", arguments: ["7"], language: "zh-Hans") == "执行失败（退出码 7）",
          "Dynamic Chinese errors interpolate correctly")
    check(L10n.text("{0} / {1}", arguments: ["{1}", "literal"], language: "en") == "{1} / literal",
          "User values containing placeholder syntax remain unchanged")
    check(AppLanguage.resolve(nil, preferredLanguages: ["zh-TW", "en"]) == "zh-Hans" &&
          AppLanguage.resolve("system", preferredLanguages: ["fr", "zh-Hans"]) == "en" &&
          AppLanguage.resolve("en", preferredLanguages: ["zh-Hans"]) == "en" &&
          AppLanguage.resolve("zh-Hans", preferredLanguages: ["en"]) == "zh-Hans",
          "System matching, unsupported-language fallback, and explicit selection work")
    let suite = "ScriptDeck.LocalizationTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(preferences: defaults)
    check(preferences.language == .system, "New preferences follow the system language")
    preferences.language = .chinese
    check(AppPreferences(preferences: defaults).language == .chinese && defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hans"],
          "Language selection persists and configures native dialogs for the next launch")
    preferences.language = .system
    check(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil, "Follow System removes the native language override")
    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1" {
        let settings = AppSettingsView(workspaces: WorkspaceStore(preferences: defaults), preferences: preferences,
                                       runner: ProcessRunner(preferences: preferences)).environment(\.locale, L10n.locale)
        let host = NSHostingView(rootView: settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/scriptdeck-settings-\(L10n.language).png"))
        }
    }
    var script = ScriptItem()
    script.name = "User-defined 名称"
    script.category = ""
    let group = ScriptGroup.tree([script])[0]
    check(group.id == "未分组" && group.displayName == L("Ungrouped") && group.scripts[0].name == script.name,
          "Localization preserves group identity and user-defined names")
}
