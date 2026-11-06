import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ScriptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ScriptItem
    let resolve: (ScriptItem) -> ScriptItem
    let save: (ScriptItem) -> Bool
    @State private var error: String?
    @State private var editingParameters = false
    private let interpreters = ["/bin/bash", "/bin/zsh", "python3", "node", "direct"]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Script Configuration")).font(.title3.weight(.semibold))
                    Text(item.name.isEmpty ? L("Add a script and its parameters") : item.name)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker(L("Configuration Page"), selection: $editingParameters) {
                    Text(L("General")).tag(false)
                    Text(L("Parameters ({0})", "\(item.parameters.count)")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }.padding(22).background(.bar)
            Divider()
            Form {
                if !editingParameters {
                    Section {
                        TextField(L("Name"), text: $item.name)
                        TextField(L("Group"), text: Binding(get: { item.category == "未分组" ? "" : item.category }, set: { item.category = $0 }), prompt: Text(L("For example: Deployment / Production")))
                        TextField(L("Description"), text: $item.notes, axis: .vertical).lineLimit(2...5)
                    } header: { Text(L("General")) } footer: { Text(L("Separate group levels with /. The description appears on the run page.")) }
                    Section {
                        HStack {
                            TextField(L("Script Path"), text: $item.path, prompt: Text(L("Path relative to the library folder")))
                            Button(L("Choose…")) { choosePath { item.path = $0 } }
                        }
                        Picker(L("Interpreter"), selection: Binding(get: { interpreters.contains(item.interpreter) ? item.interpreter : "custom" }, set: { item.interpreter = $0 == "custom" ? "" : $0 })) {
                            Text("Bash").tag("/bin/bash")
                            Text("Zsh").tag("/bin/zsh")
                            Text("Python 3").tag("python3")
                            Text("Node.js").tag("node")
                            Text(L("Run directly (use shebang)")).tag("direct")
                            Text(L("Custom Interpreter")).tag("custom")
                        }
                        if !interpreters.contains(item.interpreter) {
                            TextField(L("Absolute interpreter path"), text: $item.interpreter)
                        }
                        HStack {
                            TextField(L("Working Directory"), text: $item.workingDirectory, prompt: Text(L("Leave empty to use the script's folder")))
                            Button(L("Choose…")) { choosePath(directory: true) { item.workingDirectory = $0 } }
                        }
                    } header: { Text(L("Execution")) } footer: { Text(L("Relative paths are resolved against the current workspace.")) }
                } else {
                    Section {
                        HStack {
                            Text(L("Arguments are passed in list order. Edit their configuration below."))
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(ParameterPassing.allCases) { passing in
                                    Button(passing.title) { addParameter(passing) }
                                }
                            } label: { Label(L("Add Parameter"), systemImage: "plus") }
                        }
                    }
                    Section {
                        if item.parameters.isEmpty {
                            Text(L("No parameters yet. Click “Add Parameter” to add a positional argument, named argument, or flag."))
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        ForEach(item.parameters) { parameter in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                        HStack(spacing: 10) {
                                            Text("\((item.parameters.firstIndex { $0.id == parameter.id } ?? 0) + 1)")
                                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                            Text(parameter.name.isEmpty ? L("Unnamed Parameter") : parameter.name)
                                                .font(.callout.weight(.medium)).lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text(parameter.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    HStack(spacing: 10) {
                                        Button { moveParameter(parameter.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                            .disabled(item.parameters.first?.id == parameter.id).help(L("Move parameter up")).accessibilityLabel(L("Move parameter up"))
                                        Button { moveParameter(parameter.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                            .disabled(item.parameters.last?.id == parameter.id).help(L("Move parameter down")).accessibilityLabel(L("Move parameter down"))
                                        Button(role: .destructive) {
                                            item.parameters.removeAll { $0.id == parameter.id }
                                        } label: { Image(systemName: "trash") }
                                            .help(L("Delete parameter")).accessibilityLabel(L("Delete parameter"))
                                    }.buttonStyle(.borderless)
                                }.padding(.vertical, 4)
                                parameterDetails(parameterBinding(parameter)).padding(.leading, 32).padding(.bottom, 10)
                            }
                        }
                    }

                }
            }.formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) { saveItem() }.keyboardShortcut(.defaultAction).workspacePrimaryAction()
            }.padding(18).background(.bar)
        }.frame(width: 760, height: 660)
    }
    // SwiftUI may read a retiring row after deletion. Resolve by ID on every access;
    // never retain the array-index bindings produced by ForEach($array).
    private func parameterBinding(_ snapshot: ScriptParameter) -> Binding<ScriptParameter> {
        Binding(
            get: { item.parameters.first { $0.id == snapshot.id } ?? snapshot },
            set: { updated in
                guard let index = item.parameters.firstIndex(where: { $0.id == snapshot.id }) else { return }
                item.parameters[index] = updated
            }
        )
    }

    private func optionBinding(_ parameter: Binding<ScriptParameter>, index: Int, fallback: ParameterOption) -> Binding<ParameterOption> {
        Binding(
            get: {
                let options = parameter.wrappedValue.options
                return options.indices.contains(index) ? options[index] : fallback
            },
            set: { option in
                var updated = parameter.wrappedValue
                guard updated.options.indices.contains(index) else { return }
                updated.options[index] = option
                parameter.wrappedValue = updated
            }
        )
    }

    private func addParameter(_ passing: ParameterPassing) {
        var parameter = ScriptParameter(name: L("Parameter {0}", "\(item.parameters.count + 1)"))
        parameter.passing = passing
        item.parameters.append(parameter)
    }

    private func parameterDetails(_ parameter: Binding<ScriptParameter>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(L("Name")).foregroundStyle(.secondary)
                    TextField(L("Parameter Name"), text: parameter.name).labelsHidden()
                }
                GridRow {
                    Text(L("Passing Style")).foregroundStyle(.secondary)
                    Picker(L("Passing Style"), selection: Binding(get: { parameter.wrappedValue.passing }, set: { passing in
                        var updated = parameter.wrappedValue
                        let wasFlag = updated.passing == .flag
                        updated.passing = passing
                        if passing == .flag {
                            updated.defaultValue = "false"
                            updated.required = false
                            updated.kind = .text
                        } else if wasFlag { updated.defaultValue = "" }
                        parameter.wrappedValue = updated
                    })) {
                        ForEach(ParameterPassing.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented)
                }
                if parameter.wrappedValue.passing != .positional {
                    GridRow {
                        Text(L("Argument Name")).foregroundStyle(.secondary)
                        TextField(L("Argument Name"), text: parameter.argumentName, prompt: Text(L("For example: --output or -o")))
                            .labelsHidden()
                    }
                }
                if parameter.wrappedValue.passing == .named {
                    GridRow {
                        Text(L("Value Format")).foregroundStyle(.secondary)
                        Picker(L("Value Format"), selection: parameter.argumentFormat) {
                            ForEach(NamedArgumentFormat.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                }
                if parameter.wrappedValue.passing == .flag {
                    GridRow {
                        Text(L("Default State")).foregroundStyle(.secondary)
                        Toggle(L("Enabled by Default"), isOn: Binding(
                            get: { parameter.wrappedValue.defaultValue == "true" },
                            set: { parameter.wrappedValue.defaultValue = $0 ? "true" : "false" }
                        ))
                    }
                } else {
                    GridRow {
                        Text(L("Input Type")).foregroundStyle(.secondary)
                        HStack {
                            Picker(L("Input Type"), selection: parameter.kind) {
                                ForEach(ParameterKind.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Toggle(L("Required"), isOn: parameter.required).fixedSize()
                        }
                    }
                    GridRow {
                        Text(L("Placeholder")).foregroundStyle(.secondary)
                        TextField(L("Placeholder"), text: parameter.placeholder, prompt: Text(L("Optional"))).labelsHidden()
                    }
                    if parameter.wrappedValue.kind != .select {
                        GridRow {
                            Text(L("Default Value")).foregroundStyle(.secondary)
                            TextField(L("Default Value"), text: parameter.defaultValue, prompt: Text(L("Optional; do not save passwords"))).labelsHidden()
                        }
                    }
                }
            }.textFieldStyle(.roundedBorder).font(.callout)
            if parameter.wrappedValue.passing == .flag {
                Text(L("Passes the argument name when enabled and omits it when disabled; does not pass true or false."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if parameter.wrappedValue.kind == .select {
                optionFields(parameter)
            }
        }
    }

    private func optionFields(_ parameter: Binding<ScriptParameter>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Labels appear in the interface; values are passed to the script."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(L("Display Label")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Argument Value")).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 28, height: 1)
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(parameter.wrappedValue.options.enumerated()), id: \.offset) { index, option in
                let binding = optionBinding(parameter, index: index, fallback: option)
                HStack {
                    TextField(L("Display Label"), text: binding.label, prompt: Text(L("For example: Production")))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L("Option label"))
                    TextField(L("Argument Value"), text: binding.value, prompt: Text(L("For example: production")))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L("Option value"))
                    Button(role: .destructive) {
                        var updated = parameter.wrappedValue
                        guard updated.options.indices.contains(index) else { return }
                        updated.options.remove(at: index)
                        parameter.wrappedValue = updated
                    } label: {
                        Image(systemName: "minus.circle")
                    }.help(L("Delete option")).accessibilityLabel(L("Delete option"))
                }
            }
            HStack {
                Button(L("Add Option")) { parameter.wrappedValue.options.append(ParameterOption()) }
                Spacer()
                Text(L("Default Value")).font(.callout).foregroundStyle(.secondary)
                TextField(L("Default Value"), text: parameter.defaultValue, prompt: Text(L("Enter an option value, or leave empty")))
                    .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L("Default option value"))
            }
        }
    }
    private func moveParameter(_ id: String, by offset: Int) {
        guard let index = item.parameters.firstIndex(where: { $0.id == id }), item.parameters.indices.contains(index + offset) else { return }
        item.parameters.swapAt(index, index + offset)
    }
    private func saveItem() {
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        item.path = (item.path as NSString).expandingTildeInPath
        item.workingDirectory = (item.workingDirectory as NSString).expandingTildeInPath
        item.interpreter = (item.interpreter as NSString).expandingTildeInPath
        guard !item.name.isEmpty else { error = L("Enter a script name."); return }
        guard item.parameters.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = L("Enter a name for every parameter."); return
        }
        for index in item.parameters.indices {
            item.parameters[index].argumentName = item.parameters[index].argumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            _ = try executionCommand(resolve(item), arguments: [])
            try LibraryDocument(scripts: [item]).validate()
        }
        catch { self.error = error.localizedDescription; return }
        if item.category.isEmpty { item.category = "未分组" }
        if save(item) { dismiss() } else { error = L("Unable to save. The configuration may have changed externally. Cancel and reopen the editor, or check the library warning.") }
    }
}
