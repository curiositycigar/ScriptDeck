import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension RunnerView {
    func binding(for parameter: ScriptParameter, scriptID: String) -> Binding<String> {
        Binding(get: { session.values[scriptID]?[parameter.id] ?? parameter.defaultValue }, set: { session.values[scriptID, default: [:]][parameter.id] = $0 })
    }
    func importScripts() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("Choose local scripts. Files outside the library will be copied into scripts; nothing will be executed.")
        panel.begin { result in if result == .OK, let id = store.importURLs(panel.urls) { navigation.selectScript(id, in: session) } }
    }
    func suppliedValues(for item: ScriptItem) -> [String: String] {
        var supplied = session.values[item.id] ?? [:]
        for parameter in item.parameters where parameter.passing != .flag && (parameter.kind == .file || parameter.kind == .folder) {
            let value = supplied[parameter.id] ?? parameter.defaultValue
            if !value.isEmpty { supplied[parameter.id] = store.resolvedParameterPath(value) }
        }
        return supplied
    }
    func execute(_ item: ScriptItem) {
        validatedScripts.insert(item.id)
        let supplied = suppliedValues(for: item)
        let issues = parameterIssues(for: item, values: supplied)
        if let first = item.parameters.first(where: { issues[$0.id] != nil }) {
            focusedParameter = first.id
            return
        }
        do {
            let arguments = try scriptArguments(for: item, values: supplied)
            let resolved = store.resolved(item)
            outputExpanded = true
            try runner.run(item: resolved, arguments: arguments, workspaceID: workspaceInfo.id, workspaceName: workspaceInfo.name)
        } catch { self.error = error.localizedDescription }
    }
}
