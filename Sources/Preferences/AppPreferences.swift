import Foundation
import Combine

enum SettingsTab: Hashable { case general, terminal, credentials }

struct FavoriteScript: Codable, Hashable {
    let workspaceID: String
    let scriptID: String
}

final class AppPreferences: ObservableObject {
    @Published private(set) var favorites: [FavoriteScript] = []

    func isFavorite(workspaceID: String, scriptID: String) -> Bool {
        favorites.contains(FavoriteScript(workspaceID: workspaceID, scriptID: scriptID))
    }

    func toggleFavorite(workspaceID: String, scriptID: String) {
        let favorite = FavoriteScript(workspaceID: workspaceID, scriptID: scriptID)
        if favorites.contains(favorite) { favorites.removeAll { $0 == favorite } }
        else { favorites.append(favorite) }
        saveFavorites()
    }

    func moveFavorite(_ favorite: FavoriteScript, by offset: Int) {
        guard let index = favorites.firstIndex(of: favorite), favorites.indices.contains(index + offset) else { return }
        favorites.swapAt(index, index + offset)
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) { preferences.set(data, forKey: "favoriteScripts.v1") }
    }

    @Published var language: AppLanguage {
        didSet {
            preferences.set(language.rawValue, forKey: "appLanguage")
            if language == .system { preferences.removeObject(forKey: "AppleLanguages") }
            else { preferences.set([language.rawValue], forKey: "AppleLanguages") }
        }
    }
    @Published var sidebarVisible: Bool {
        didSet { preferences.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    @Published var settingsTab: SettingsTab = .general
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
        let saved = preferences.data(forKey: "favoriteScripts.v1").flatMap {
            try? JSONDecoder().decode([FavoriteScript].self, from: $0)
        } ?? []
        var seen = Set<FavoriteScript>()
        favorites = saved.filter { seen.insert($0).inserted }
        language = AppLanguage(rawValue: preferences.string(forKey: "appLanguage") ?? "") ?? .system
        sidebarVisible = preferences.object(forKey: "sidebarVisible") as? Bool ?? true
        let font = preferences.object(forKey: "terminalFontSize") as? Double ?? 12
        terminalFontSize = font.isFinite ? min(24, max(10, font)) : 12
        let history = preferences.integer(forKey: "terminalScrollback")
        terminalScrollback = Self.historyOptions.contains(history) ? history : 10_000
    }
}
