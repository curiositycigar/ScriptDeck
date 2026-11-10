import Foundation
import Combine

/// Local parameter snapshots are separate from the library and execution logs.
@MainActor final class ParameterCallHistory: ObservableObject {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var calledAt = Date()
        var values: [String: String]
    }

    static let shared = ParameterCallHistory()
    private let preferences: UserDefaults
    private let key = "parameterCallHistory.v1"
    @Published private var records: [String: [String: [Entry]]]

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        records = preferences.data(forKey: key).flatMap {
            try? JSONDecoder().decode([String: [String: [Entry]]].self, from: $0)
        } ?? [:]
    }

    func entries(workspaceID: String, item: ScriptItem) -> [Entry] {
        let ids = Set(item.parameters.map(\.id))
        return (records[workspaceID]?[item.id] ?? []).filter { Set($0.values.keys) == ids }
    }

    static func values(for item: ScriptItem, supplied: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: item.parameters.map { parameter in
            let value = supplied[parameter.id] ?? parameter.defaultValue
            return (parameter.id, parameter.passing == .flag ? (value == "true" ? "true" : "false") : value)
        })
    }

    func remember(workspaceID: String, item: ScriptItem, supplied: [String: String]) {
        guard !item.parameters.isEmpty else { return }
        let values = Self.values(for: item, supplied: supplied)
        var entries = entries(workspaceID: workspaceID, item: item)
        entries.removeAll { $0.values == values }
        entries.insert(Entry(values: values), at: 0)
        records[workspaceID, default: [:]][item.id] = Array(entries.prefix(5))
        save()
    }

    func clear(workspaceID: String, scriptID: String) {
        records[workspaceID]?[scriptID] = nil
        if records[workspaceID]?.isEmpty == true { records[workspaceID] = nil }
        save()
    }

    func remove(id: UUID, workspaceID: String, scriptID: String) {
        records[workspaceID]?[scriptID]?.removeAll { $0.id == id }
        if records[workspaceID]?[scriptID]?.isEmpty == true {
            records[workspaceID]?[scriptID] = nil
        }
        if records[workspaceID]?.isEmpty == true { records[workspaceID] = nil }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { preferences.set(data, forKey: key) }
    }
}
