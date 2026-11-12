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
                                        message: L("Check library.json. If the folder has moved, relocate it in workspace management."))
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
                            Text(item.notes).font(WorkspaceTypography.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if item.parameters.isEmpty {
                            Label(L("This script has no parameters and is ready to run."), systemImage: "checkmark.circle")
                                .font(WorkspaceTypography.body).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(L("Run Parameters")).font(WorkspaceTypography.sectionTitle)
                                    Spacer()
                                    Text("\(item.parameters.count)")
                                        .font(WorkspaceTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                parameterFields(item)
                                    .padding(16)
                                    .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onChange(of: focusedParameter) { id in
                    if let id { withAnimation(WorkspaceMotion.layout.animation(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .id(item.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            executionBar(item)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .workspaceActionSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scriptHeader(_ item: ScriptItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            WorkspaceSymbol("terminal", size: .header).foregroundStyle(.tint)
                .frame(width: WorkspaceControlMetrics.headerTile, height: WorkspaceControlMetrics.headerTile)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 2) {
                    Text(item.name).font(WorkspaceTypography.scriptTitle)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .help(item.name)
                    Button { showScriptDetails.toggle() } label: {
                        WorkspaceSymbol("info.circle", size: .toolbar)
                            .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget)).foregroundStyle(.secondary)
                    .help(L("Script Details")).accessibilityLabel(L("Script Details"))
                    .popover(isPresented: $showScriptDetails, arrowEdge: .bottom) {
                        scriptDetails(item)
                    }
                    Button { credentialScript = item } label: {
                        WorkspaceSymbol("key", size: .toolbar)
                            .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget).contentShape(Rectangle())
                    }
                    .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget)).foregroundStyle(.secondary)
                    .help(L("Script Credentials")).accessibilityLabel(L("Script Credentials"))
                }
                .frame(height: WorkspaceControlMetrics.titleActionTarget)
                if !item.category.isEmpty && item.category != "未分组" {
                    Text(item.category.replacingOccurrences(of: "/", with: "  /  "))
                        .font(WorkspaceTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(height: 14)
                        .help(item.category)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: WorkspaceControlMetrics.headerTile)
            HStack(spacing: 4) {
                Button { preferences.toggleFavorite(workspaceID: workspaceInfo.id, scriptID: item.id) } label: {
                    WorkspaceSymbol(preferences.isFavorite(workspaceID: workspaceInfo.id, scriptID: item.id) ? "star.fill" : "star", size: .toolbar)
                        .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget)
                }
                .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget))
                .help(preferences.isFavorite(workspaceID: workspaceInfo.id, scriptID: item.id) ? L("Remove from Favorites") : L("Add to Favorites"))
                .accessibilityLabel(preferences.isFavorite(workspaceID: workspaceInfo.id, scriptID: item.id) ? L("Remove from Favorites") : L("Add to Favorites"))
                Button { showParameterHistory.toggle() } label: {
                    WorkspaceSymbol("clock.arrow.circlepath", size: .toolbar)
                        .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget)).foregroundStyle(.secondary)
                .help(L("Recent Parameters")).accessibilityLabel(L("Recent Parameters"))
                .disabled(item.parameters.isEmpty)
                .popover(isPresented: $showParameterHistory, arrowEdge: .bottom) {
                    parameterHistoryPicker(item)
                }
                Button { openEditor(item) } label: {
                    WorkspaceSymbol("slider.horizontal.3", size: .toolbar)
                        .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget)).foregroundStyle(.secondary)
                    .help(L("Edit")).accessibilityLabel(L("Edit"))
                    .disabled(isActive(item))
            }
        }
    }

    private func parameterHistoryPicker(_ item: ScriptItem) -> some View {
        let entries = parameterHistory.entries(workspaceID: workspaceInfo.id, item: item)
        let currentValues = ParameterCallHistory.values(for: item, supplied: suppliedValues(for: item))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Recent Parameters")).font(WorkspaceTypography.sectionTitle)
                Spacer()
                if !entries.isEmpty {
                    Button(L("Clear")) { parameterHistory.clear(workspaceID: workspaceInfo.id, scriptID: item.id) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if entries.isEmpty {
                Text(L("Run this script to remember up to five recent parameter sets."))
                    .font(WorkspaceTypography.body).foregroundStyle(.secondary)
                    .padding(.vertical, 20).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(entries) { entry in
                            ParameterHistoryRow(entry: entry, parameters: item.parameters, selected: entry.values == currentValues) {
                                session.values[item.id] = entry.values
                                validatedScripts.remove(item.id)
                                showParameterHistory = false
                            } remove: {
                                parameterHistory.remove(id: entry.id, workspaceID: workspaceInfo.id, scriptID: item.id)
                            }
                        }
                    }
                }.frame(maxHeight: 300)
                Text(L("Selecting a record fills the form without running the script."))
                    .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(width: 380).workspaceTypography()
    }

    private func scriptDetails(_ item: ScriptItem) -> some View {
        let resolved = store.resolved(item)
        return VStack(alignment: .leading, spacing: 16) {
            Label(L("Script Details"), systemImage: "info.circle")
                .font(WorkspaceTypography.sectionTitle)
            Text(item.name).font(WorkspaceTypography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    scriptDetailRow(L("Script Path"), value: resolved.path)
                    HStack(spacing: 10) {
                        Button {
                            NSPasteboard.general.clearContents()
                            scriptPathCopied = NSPasteboard.general.setString(resolved.path, forType: .string)
                        } label: {
                            WorkspaceSymbol(scriptPathCopied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(scriptPathCopied ? Color.green : Color.secondary)
                        }
                            .help(scriptPathCopied ? L("Copied") : L("Copy Path"))
                            .accessibilityLabel(L("Copy Path"))
                            .accessibilityValue(scriptPathCopied ? L("Copied") : "")
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: resolved.path)])
                        } label: { WorkspaceSymbol("folder") }
                            .help(L("Show in Finder")).accessibilityLabel(L("Show in Finder"))
                    }
                    .buttonStyle(WorkspaceIconButtonStyle())
                    .foregroundStyle(.secondary)
                }
                scriptDetailRow(L("Interpreter"), value: item.interpreter == "direct" ? L("Run directly") : item.interpreter)
                scriptDetailRow(L("Working Directory"), value: resolved.workingDirectory.isEmpty ? L("Script's folder") : resolved.workingDirectory)
            }
        }
        .padding(20)
        .frame(width: 560, alignment: .leading)
        .task(id: scriptPathCopied) {
            guard scriptPathCopied else { return }
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                scriptPathCopied = false
            } catch { }
        }
        .onDisappear { scriptPathCopied = false }
    }

    private func scriptDetailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value).font(WorkspaceTypography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func parameterFields(_ item: ScriptItem) -> some View {
        let issues = validatedScripts.contains(item.id) ? parameterIssues(for: item, values: suppliedValues(for: item)) : [:]
        let labelFont = WorkspaceTypography.parameterLabelNSFont
        let labelWidth = min(200, ceil(item.parameters.map { parameter in
            let nameWidth = (parameter.name as NSString).size(withAttributes: [.font: labelFont]).width
            let requiredWidth = parameter.required ? ("*" as NSString).size(withAttributes: [.font: WorkspaceTypography.bodyNSFont]).width + 4 : 0
            return nameWidth + requiredWidth + 8
        }.max() ?? 0))
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(item.parameters) { parameter in
                ParameterRowLayout(labelWidth: labelWidth) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parameter.name).font(WorkspaceTypography.bodyStrong)
                            .fixedSize(horizontal: false, vertical: true)
                        if parameter.required {
                            Text("*").font(WorkspaceTypography.body).foregroundStyle(.red)
                                .help(L("Required")).accessibilityLabel(L("Required"))
                        }
                    }
                    .help(parameter.argumentName.isEmpty ? parameter.name : "\(parameter.name) (\(parameter.argumentName))")
                    parameterControl(parameter, item: item)
                    if let issue = issues[parameter.id] {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(WorkspaceTypography.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .id(parameter.id)
            }
        }
        .controlSize(.regular)
        .workspaceAnimation(value: validatedScripts.contains(item.id), motion: .layout)
    }

    @ViewBuilder private func parameterControl(_ parameter: ScriptParameter, item: ScriptItem) -> some View {
        if parameter.passing == .flag {
            HStack {
                Toggle(parameter.name, isOn: Binding(
                    get: { binding(for: parameter, scriptID: item.id).wrappedValue == "true" },
                    set: { binding(for: parameter, scriptID: item.id).wrappedValue = $0 ? "true" : "false" }
                ))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .accessibilityLabel(parameter.name)
                .focused($focusedParameter, equals: parameter.id)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                if parameter.kind == .editableSelect {
                    EditableSelectionField(parameter: parameter, text: binding(for: parameter, scriptID: item.id))
                        .focused($focusedParameter, equals: parameter.id)
                } else if parameter.kind == .select {
                    Picker("", selection: binding(for: parameter, scriptID: item.id)) {
                        Text(parameter.placeholder.isEmpty ? L("Choose…") : parameter.placeholder).tag("")
                        ForEach(parameter.options) { option in Text(option.label).tag(option.value) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    .focused($focusedParameter, equals: parameter.id)
                    .accessibilityLabel(parameter.name)
                } else {
                    TextField(parameter.placeholder.isEmpty ? (parameter.kind == .text ? L("Enter a parameter value") : L("Choose a path or drag a file")) : parameter.placeholder, text: binding(for: parameter, scriptID: item.id))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedParameter, equals: parameter.id)
                        .accessibilityLabel(parameter.name)
                }
                if parameter.kind == .file || parameter.kind == .folder {
                    Button {
                        choosePath(directory: parameter.kind == .folder) { session.values[item.id, default: [:]][parameter.id] = $0 }
                    } label: { WorkspaceSymbol("folder", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("Choose…")).accessibilityLabel(L("Choose…"))
                    let value = binding(for: parameter, scriptID: item.id).wrappedValue
                    let path = store.resolvedParameterPath(value)
                    Button {
                        guard !value.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: { WorkspaceSymbol("arrow.up.forward.square", size: .toolbar) }
                    .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                    .help(L("Show in Finder")).accessibilityLabel(L("Show in Finder"))
                    .disabled(value.isEmpty || !FileManager.default.fileExists(atPath: path))
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: parameter.kind == .file || parameter.kind == .folder ? [UTType.fileURL] : [],
                    isTargeted: nil) { providers in
                loadDroppedFileURLs(providers) { urls in
                    guard !WorkspaceDialogs.importDroppedPackage(urls, to: workspaces),
                          let url = urls.first,
                          let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                          isDirectory == (parameter.kind == .folder) else { return }
                    binding(for: parameter, scriptID: item.id).wrappedValue = url.path
                }
            }
        }
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

    @ViewBuilder
    private func executionStatus(_ item: ScriptItem) -> some View {
        let count = runner.activeSessions(workspaceID: workspaceInfo.id, scriptID: item.id).count
        if count > 0 {
            let button = ScriptInstancesButton(runner: runner, workspaceID: workspaceInfo.id,
                                               scriptID: item.id, showsStatus: true)
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            if item.allowsMultipleInstances {
                button
            } else {
                button.keyboardShortcut(.return, modifiers: .command)
            }
        } else {
            Label(L("Ready"), systemImage: "checkmark.circle")
                .font(WorkspaceTypography.bodyStrong)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func executionActions(_ item: ScriptItem) -> some View {
        let running = isActive(item)
        return HStack(alignment: .center, spacing: 4) {
            Button {
                do {
                    let supplied = suppliedValues(for: item)
                    _ = try scriptArguments(for: item, values: supplied)
                    schedulingItem = ScheduledTask(name: item.name, workspaceID: workspaceInfo.id,
                                                   workspaceName: workspaceInfo.name, item: store.resolved(item), values: supplied,
                                                   workspaceDirectory: workspaceInfo.directory)
                } catch { self.error = error.localizedDescription }
            } label: { WorkspaceSymbol("clock.badge.plus", size: .toolbar) }
            .buttonStyle(WorkspaceIconButtonStyle())
            .foregroundStyle(.secondary)
            .help(L("Schedule…"))
            .accessibilityLabel(L("Schedule…"))

            if !running || item.allowsMultipleInstances {
                Button {
                    execute(item)
                } label: {
                    WorkspaceSymbol("play.fill", size: .toolbar)
                }
                .buttonStyle(WorkspaceIconButtonStyle(prominent: true))
                .help(running ? L("Run Another Instance") : L("⌘ Return to run script"))
                .accessibilityLabel(running ? L("Run Another Instance") : L("Run"))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}
