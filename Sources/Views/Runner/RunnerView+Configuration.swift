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
                    WorkspaceEmptyState(symbol: "folder.badge.questionmark", title: "Workspace 暂不可用",
                                        message: "检查 library.json；如果目录已移动，请在设置中重新定位。")
                    Button("管理 Workspaces…", action: manageWorkspaces)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                VStack(spacing: 0) {
                    WorkspaceEmptyState(symbol: "terminal", title: store.directoryURL == nil ? "打开脚本库" : store.items.isEmpty ? "添加第一个脚本" : "选择一个脚本",
                                        message: store.directoryURL == nil ? "选择保存配置和脚本的文件夹。" : store.items.isEmpty ? "导入本地脚本，或拖入侧栏开始使用。" : "从侧栏选择脚本，填写参数后即可运行。")
                    if store.directoryURL == nil {
                        Button("打开脚本库…", action: addWorkspace)
                            .buttonStyle(.borderedProminent).disabled(runner.isRunning)
                    } else if store.items.isEmpty {
                        Button("导入脚本…", action: importScripts)
                            .buttonStyle(.borderedProminent).disabled(store.configurationIssue != nil)
                    } else if !preferences.sidebarVisible {
                        Button("显示侧栏") { preferences.sidebarVisible = true }
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
                        Text(item.category.isEmpty ? "未分组" : item.category.replacingOccurrences(of: "/", with: "  ›  "))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { openEditor(item) } label: { Label("编辑", systemImage: "slider.horizontal.3") }
                        .disabled(isActive(item))
                }
                if !item.notes.isEmpty {
                    Text(item.notes).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                DisclosureGroup("脚本详情", isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.resolved(item).path).font(.caption.monospaced()).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).help(store.resolved(item).path)
                        LabeledContent("解释器", value: item.interpreter == "direct" ? "直接执行" : item.interpreter)
                        LabeledContent("工作目录", value: store.resolved(item).workingDirectory.isEmpty ? "脚本所在目录" : store.resolved(item).workingDirectory)
                            .lineLimit(1).truncationMode(.middle)
                        HStack {
                            Button("复制路径") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(store.resolved(item).path, forType: .string)
                            }
                            Button("在 Finder 中显示") {
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
                        WorkspaceSectionTitle(title: "运行参数", subtitle: item.parameters.isEmpty ? "此脚本无需参数，可直接运行。" : "支持位置参数、命名参数与开关；修改仅在本次会话中保留。")
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
                        Text(parameter.passing == .flag ? parameter.argumentName : parameter.passing == .named ? parameter.argumentName + (parameter.required ? " · 必填" : " · 可选") : parameter.required ? "必填" : "可选").font(.caption).foregroundStyle(.secondary)
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
                                Text(parameter.placeholder.isEmpty ? "请选择…" : parameter.placeholder).tag("")
                                ForEach(parameter.options) { option in Text(option.label).tag(option.value) }
                            }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                            .focused($focusedParameter, equals: parameter.id)
                            .accessibilityLabel(parameter.name)
                        } else {
                            TextField(parameter.placeholder.isEmpty ? (parameter.kind == .text ? "输入参数值" : "选择路径或拖入文件") : parameter.placeholder, text: binding(for: parameter, scriptID: item.id))
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
                            Button("选择…") { choosePath(directory: parameter.kind == .folder) { session.values[item.id, default: [:]][parameter.id] = $0 } }
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
                Label(isActive(item) ? "此脚本正在运行" : "准备就绪", systemImage: isActive(item) ? "waveform" : "checkmark.circle")
                    .font(.callout.weight(.medium))
                Text(isActive(item) ? "可在下方任务列表切换终端，或再次运行" : "⌘ Return 运行脚本")
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
            } label: { Label("定时…", systemImage: "clock.badge.plus") }
            Button {
                execute(item)
            } label: {
                Label("运行", systemImage: "play.fill").frame(minWidth: 68)
            }
            .workspacePrimaryAction()
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
        .workspaceGlass()
    }
}
