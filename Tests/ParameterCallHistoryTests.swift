import Foundation

@MainActor func runParameterCallHistorySelfTests() {
    let suite = "ScriptDeck.ParameterCallHistoryTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let history = ParameterCallHistory(preferences: defaults)
    var item = ScriptItem(id: "script")
    item.parameters = [ScriptParameter(id: "text", defaultValue: "default"),
                       ScriptParameter(id: "flag", passing: .flag, argumentName: "--verbose")]
    for value in 0...5 {
        history.remember(workspaceID: "workspace", item: item, supplied: ["text": "value \(value)"])
    }
    var entries = history.entries(workspaceID: "workspace", item: item)
    check(entries.count == 5 && entries.first?.values["text"] == "value 5" && entries.last?.values["text"] == "value 1",
          "Parameter history retains only the five most recent distinct calls")
    history.remember(workspaceID: "workspace", item: item, supplied: ["text": "value 2", "flag": "false", "removed": "ignored"])
    entries = history.entries(workspaceID: "workspace", item: item)
    check(entries.count == 5 && entries.first?.values == ["text": "value 2", "flag": "false"],
          "Duplicate effective parameters move to the front, normalize flags, and omit removed fields")
    history.remember(workspaceID: "workspace", item: item, supplied: [:])
    check(history.entries(workspaceID: "workspace", item: item).first?.values["text"] == "default",
          "Parameter history captures defaults explicitly for complete restoration")
    let reloaded = ParameterCallHistory(preferences: defaults)
    check(reloaded.entries(workspaceID: "workspace", item: item).map(\.values) == history.entries(workspaceID: "workspace", item: item).map(\.values),
          "Parameter history survives recreating the store")
    check(reloaded.entries(workspaceID: "other", item: item).isEmpty, "Parameter history is isolated by workspace")
    var other = item
    other.id = "other-script"
    check(reloaded.entries(workspaceID: "workspace", item: other).isEmpty, "Parameter history is isolated by script")
    other = item
    other.parameters.append(ScriptParameter(id: "new"))
    check(reloaded.entries(workspaceID: "workspace", item: other).isEmpty, "Changed parameter sets do not offer incomplete snapshots")
    history.remember(workspaceID: "other", item: item, supplied: [:])
    let beforeRemoval = history.entries(workspaceID: "workspace", item: item)
    history.remove(id: beforeRemoval[1].id, workspaceID: "workspace", scriptID: item.id)
    check(ParameterCallHistory(preferences: defaults).entries(workspaceID: "workspace", item: item).map(\.id) ==
          beforeRemoval.filter { $0.id != beforeRemoval[1].id }.map(\.id),
          "Deleting one parameter record persists and preserves remaining records and their order")
    check(!history.entries(workspaceID: "other", item: item).isEmpty,
          "Deleting one parameter record preserves other workspaces")
    history.clear(workspaceID: "workspace", scriptID: item.id)
    check(ParameterCallHistory(preferences: defaults).entries(workspaceID: "workspace", item: item).isEmpty &&
          !history.entries(workspaceID: "other", item: item).isEmpty,
          "Clearing parameter history persists and preserves other workspaces")
    var empty = item
    empty.parameters = []
    history.remember(workspaceID: "empty", item: empty, supplied: [:])
    check(history.entries(workspaceID: "empty", item: empty).isEmpty, "Scripts without parameters do not create history")
}
