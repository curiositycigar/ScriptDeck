import Foundation
import Combine

enum SettingsTab: Hashable { case workspaces, terminal }

final class AppPreferences: ObservableObject {
    @Published var sidebarVisible: Bool {
        didSet { preferences.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    @Published var settingsTab: SettingsTab = .workspaces
    @Published var terminalFontSize: Double {
        didSet { preferences.set(terminalFontSize, forKey: "terminalFontSize") }
    }
    @Published var terminalScrollback: Int {
        didSet { preferences.set(terminalScrollback, forKey: "terminalScrollback") }
    }
    private let preferences: UserDefaults
    static let historyOptions = [1_000, 5_000, 10_000, 20_000, 50_000]

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        sidebarVisible = preferences.object(forKey: "sidebarVisible") as? Bool ?? true
        let font = preferences.object(forKey: "terminalFontSize") as? Double ?? 12
        terminalFontSize = font.isFinite ? min(24, max(10, font)) : 12
        let history = preferences.integer(forKey: "terminalScrollback")
        terminalScrollback = Self.historyOptions.contains(history) ? history : 10_000
    }
}
