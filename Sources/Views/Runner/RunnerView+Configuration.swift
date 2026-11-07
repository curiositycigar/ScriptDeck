import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension RunnerView {
    var configurationPane: some View {
        VStack(spacing: 0) {
            if let item = selected {
                configuration(item)
            } else if store.configurationIssue != nil {
                VStack(spacing: 0) {
                    WorkspaceEmptyState(symbol: "folder.badge.questionmark", title: L("Workspace Unavailable"),
                                        message: L("Check library.json. If the folder has moved, relocate it in Settings."))
                    Button(L("Manage Workspaces…"), action: manageWorkspaces)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                VStack(spacing: 0) {
                    WorkspaceEmptyState(symbol: "terminal", title: store.directoryURL == nil ? L("Open a Script Library") : store.items.isEmpty ? L("Add Your First Script") : L("Select a Script"),
                                        message: store.directoryURL == nil ? L("Choose a folder for your scripts and configuration.") : store.items.isEmpty ? L("Import local scripts or drag them into the sidebar to get started.") : L("Select a script in the sidebar, enter its parameters, and run it."))
                    if store.directoryURL == nil {
                        Button(L("Open Script Library…"), action: addWorkspace)
                            .buttonStyle(.borderedProminent).disabled(runner.isRunning)
                    } else if store.items.isEmpty {
                        Button(L("Import Scripts…"), action: importScripts)
                            .buttonStyle(.borderedProminent).disabled(store.configurationIssue != nil)
                    } else if !preferences.sidebarVisible {
                        Button(L("Show Sidebar")) { preferences.sidebarVisible = true }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(36)
            }
        }
        .frame(minWidth: 490, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    func configuration(_ item: ScriptItem) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        scriptHeader(item)
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if item.parameters.isEmpty {
                            Label(L("This script has no parameters and is ready to run."), systemImage: "checkmark.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text(L("Run Parameters")).font(.headline)
                            parameterFields(item)
                        }
                        scriptDetails(item)
                    }
                    .frame(maxWidth: 800, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
                .onChange(of: focusedParameter) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .id(item.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            executionBar(item)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scriptHeader(_ item: ScriptItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text((item.category.isEmpty || item.category == "未分组") ? L("Ungrouped") : item.category.replacingOccurrences(of: "/", with: "  ›  "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(item.category)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { openEditor(item) } label: { Label(L("Edit"), systemImage: "slider.horizontal.3") }
                .disabled(isActive(item))
        }
    }

    private func scriptDetails(_ item: ScriptItem) -> some View {
        DisclosureGroup(L("Script Details"), isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.resolved(item).path).font(.caption.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent(L("Interpreter"), value: item.interpreter == "direct" ? L("Run directly") : item.interpreter)
                LabeledContent(L("Working Directory"), value: store.resolved(item).workingDirectory.isEmpty ? L("Script's folder") : store.resolved(item).workingDirectory)
                    .textSelection(.enabled)
                HStack {
                    Button(L("Copy Path")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.resolved(item).path, forType: .string)
                    }
                    Button(L("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.resolved(item).path)])
                    }
                }
            }.padding(.top, 10)
        }.font(.caption).foregroundStyle(.secondary)
    }

    func parameterFields(_ item: ScriptItem) -> some View {
        let issues = validatedScripts.contains(item.id) ? parameterIssues(for: item, values: suppliedValues(for: item)) : [:]
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(item.parameters) { parameter in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text(parameter.name).font(.callout.weight(.medium))
                                .lineLimit(1).truncationMode(.tail)
                            if parameter.required {
                                Text("*").foregroundStyle(.red)
                                    .help(L("Required"))
                                    .accessibilityLabel(L("Required"))
                            }
                        }
                        .frame(width: 140, alignment: .leading)
                        .help(parameter.argumentName.isEmpty ? parameter.name : "\(parameter.name) (\(parameter.argumentName))")
                        if parameter.passing == .flag {
                            Toggle(parameter.name, isOn: Binding(
                                get: { binding(for: parameter, scriptID: item.id).wrappedValue == "true" },
                                set: { binding(for: parameter, scriptID: item.id).wrappedValue = $0 ? "true" : "false" }
                            )).toggleStyle(.switch).labelsHidden().accessibilityLabel(parameter.name)
                                .focused($focusedParameter, equals: parameter.id)
                            Spacer(minLength: 0)
                        } else {
                            if parameter.kind == .select {
                                Picker("", selection: binding(for: parameter, scriptID: item.id)) {
                                    Text(parameter.placeholder.isEmpty ? L("Choose…") : parameter.placeholder).tag("")
                                    ForEach(parameter.options) { option in Text(option.label).tag(option.value) }
                                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                                .focused($focusedParameter, equals: parameter.id)
                                .accessibilityLabel(parameter.name)
                            } else {
                                TextField(parameter.placeholder.isEmpty ? (parameter.kind == .text ? L("Enter a parameter value") : L("Choose a path or drag a file")) : parameter.placeholder, text: binding(for: parameter, scriptID: item.id))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedParameter, equals: parameter.id)
                                .accessibilityLabel(parameter.name)
                                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                                    guard parameter.kind != .text, let provider = providers.first else { return false }
                                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                        guard let url else { return }
                                        DispatchQueue.main.async { session.values[item.id, default: [:]][parameter.id] = url.path }
                                    }
                                    return true
                                }
                            }
                            if parameter.kind == .file || parameter.kind == .folder {
                                Button(L("Choose…")) { choosePath(directory: parameter.kind == .folder) { session.values[item.id, default: [:]][parameter.id] = $0 } }
                            }
                        }
                    }
                    if let issue = issues[parameter.id] {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }.id(parameter.id)
            }
        }.controlSize(.regular)
    }

    func executionBar(_ item: ScriptItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                executionStatus(item)
                Spacer(minLength: 12)
                executionActions(item).fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                executionStatus(item)
                HStack { Spacer(); executionActions(item) }
            }
        }
    }

    private func executionStatus(_ item: ScriptItem) -> some View {
        Label(isActive(item) ? L("This script is running") : L("Ready"), systemImage: isActive(item) ? "waveform" : "checkmark.circle")
            .font(.callout.weight(.medium))
            .foregroundStyle(isActive(item) ? Color.accentColor : Color.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .help(isActive(item) ? L("Switch terminals in the task list below, or run again") : L("⌘ Return to run script"))
    }

    private func executionActions(_ item: ScriptItem) -> some View {
        HStack(spacing: 12) {
            Button {
                do {
                    let supplied = suppliedValues(for: item)
                    _ = try scriptArguments(for: item, values: supplied)
                    schedulingItem = ScheduledTask(name: item.name, workspaceID: workspaceInfo.id,
                                                   workspaceName: workspaceInfo.name, item: store.resolved(item), values: supplied)
                } catch { self.error = error.localizedDescription }
            } label: { Label(L("Schedule…"), systemImage: "clock.badge.plus") }
            Button {
                execute(item)
            } label: {
                Label(L("Run"), systemImage: "play.fill").frame(minWidth: 68)
            }
            .workspacePrimaryAction()
            .controlSize(.regular)
            .help(L("⌘ Return to run script"))
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
