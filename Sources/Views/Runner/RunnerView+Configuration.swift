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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "terminal")
                        .font(.system(size: 24, weight: .medium)).foregroundStyle(.tint)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.system(size: 23, weight: .semibold)).lineLimit(2)
                        Text((item.category.isEmpty || item.category == "未分组") ? L("Ungrouped") : item.category.replacingOccurrences(of: "/", with: "  ›  "))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { openEditor(item) } label: { Label(L("Edit"), systemImage: "slider.horizontal.3") }
                        .disabled(isActive(item))
                }
                if !item.notes.isEmpty {
                    Text(item.notes).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                DisclosureGroup(L("Script Details"), isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.resolved(item).path).font(.caption.monospaced()).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).help(store.resolved(item).path)
                        LabeledContent(L("Interpreter"), value: item.interpreter == "direct" ? L("Run directly") : item.interpreter)
                        LabeledContent(L("Working Directory"), value: store.resolved(item).workingDirectory.isEmpty ? L("Script's folder") : store.resolved(item).workingDirectory)
                            .lineLimit(1).truncationMode(.middle)
                        HStack {
                            Button(L("Copy Path")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(store.resolved(item).path, forType: .string)
                            }
                            Button(L("Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.resolved(item).path)])
                            }
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(28)
            Divider().padding(.horizontal, 28)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        WorkspaceSectionTitle(title: L("Run Parameters"), subtitle: item.parameters.isEmpty ? L("This script has no parameters and is ready to run.") : L("Supports positional arguments, named arguments, and flags. Changes are kept only for this app session."))
                        if !item.parameters.isEmpty { parameterFields(item) }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }
                .onChange(of: focusedParameter) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            executionBar(item).padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func parameterFields(_ item: ScriptItem) -> some View {
        let issues = validatedScripts.contains(item.id) ? parameterIssues(for: item, values: suppliedValues(for: item)) : [:]
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(item.parameters) { parameter in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(parameter.name).font(.callout.weight(.medium))
                        Spacer()
                        Text(parameter.passing == .flag ? parameter.argumentName : parameter.passing == .named ? parameter.argumentName + (parameter.required ? L(" · required") : L(" · optional")) : parameter.required ? L("Required") : L("Optional")).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if parameter.passing == .flag {
                            Toggle(parameter.name, isOn: Binding(
                                get: { binding(for: parameter, scriptID: item.id).wrappedValue == "true" },
                                set: { binding(for: parameter, scriptID: item.id).wrappedValue = $0 ? "true" : "false" }
                            )).toggleStyle(.switch).labelsHidden().accessibilityLabel(parameter.name)
                                .focused($focusedParameter, equals: parameter.id)
                        } else if parameter.kind == .select {
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
                        if parameter.passing != .flag && (parameter.kind == .file || parameter.kind == .folder) {
                            Button(L("Choose…")) { choosePath(directory: parameter.kind == .folder) { session.values[item.id, default: [:]][parameter.id] = $0 } }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(isActive(item) ? L("This script is running") : L("Ready"), systemImage: isActive(item) ? "waveform" : "checkmark.circle")
                    .font(.callout.weight(.medium))
                Text(isActive(item) ? L("Switch terminals in the task list below, or run again") : L("⌘ Return to run script"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
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
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
        .workspaceGlass()
    }
}
