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
                    Text("脚本配置").font(.title3.weight(.semibold))
                    Text(item.name.isEmpty ? "添加脚本与运行参数" : item.name)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("配置页面", selection: $editingParameters) {
                    Text("基本信息").tag(false)
                    Text("参数（\(item.parameters.count)）").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }.padding(22).background(.bar)
            Divider()
            Form {
                if !editingParameters {
                    Section {
                        TextField("名称", text: $item.name)
                        TextField("分组", text: $item.category, prompt: Text("例如：部署 / 生产环境"))
                        TextField("说明", text: $item.notes, axis: .vertical).lineLimit(2...5)
                    } header: { Text("基本信息") } footer: { Text("分组使用 / 分隔层级，说明会显示在运行页面。") }
                    Section {
                        HStack {
                            TextField("脚本路径", text: $item.path, prompt: Text("相对于脚本库目录的路径"))
                            Button("选择…") { choosePath { item.path = $0 } }
                        }
                        Picker("解释器", selection: Binding(get: { interpreters.contains(item.interpreter) ? item.interpreter : "custom" }, set: { item.interpreter = $0 == "custom" ? "" : $0 })) {
                            Text("Bash").tag("/bin/bash")
                            Text("Zsh").tag("/bin/zsh")
                            Text("Python 3").tag("python3")
                            Text("Node.js").tag("node")
                            Text("直接执行（使用 shebang）").tag("direct")
                            Text("自定义解释器").tag("custom")
                        }
                        if !interpreters.contains(item.interpreter) {
                            TextField("解释器绝对路径", text: $item.interpreter)
                        }
                        HStack {
                            TextField("工作目录", text: $item.workingDirectory, prompt: Text("留空使用脚本所在目录"))
                            Button("选择…") { choosePath(directory: true) { item.workingDirectory = $0 } }
                        }
                    } header: { Text("执行配置") } footer: { Text("相对路径基于当前 Workspace 解析。") }
                } else {
                    Section {
                        HStack {
                            Text("按列表顺序传入，可直接编辑下方参数配置。")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(ParameterPassing.allCases) { passing in
                                    Button(passing.title) { addParameter(passing) }
                                }
                            } label: { Label("添加参数", systemImage: "plus") }
                        }
                    }
                    Section {
                        if item.parameters.isEmpty {
                            Text("暂无参数，点击“添加参数”选择位置参数、命名参数或开关。")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        ForEach(item.parameters) { parameter in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                        HStack(spacing: 10) {
                                            Text("\((item.parameters.firstIndex { $0.id == parameter.id } ?? 0) + 1)")
                                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                            Text(parameter.name.isEmpty ? "未命名参数" : parameter.name)
                                                .font(.callout.weight(.medium)).lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text(parameter.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    HStack(spacing: 10) {
                                        Button { moveParameter(parameter.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                            .disabled(item.parameters.first?.id == parameter.id).help("上移参数").accessibilityLabel("上移参数")
                                        Button { moveParameter(parameter.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                            .disabled(item.parameters.last?.id == parameter.id).help("下移参数").accessibilityLabel("下移参数")
                                        Button(role: .destructive) {
                                            item.parameters.removeAll { $0.id == parameter.id }
                                        } label: { Image(systemName: "trash") }
                                            .help("删除参数").accessibilityLabel("删除参数")
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
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { saveItem() }.keyboardShortcut(.defaultAction).workspacePrimaryAction()
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
        var parameter = ScriptParameter(name: "参数 \(item.parameters.count + 1)")
        parameter.passing = passing
        item.parameters.append(parameter)
    }

    private func parameterDetails(_ parameter: Binding<ScriptParameter>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("名称").foregroundStyle(.secondary)
                    TextField("参数名称", text: parameter.name).labelsHidden()
                }
                GridRow {
                    Text("传递方式").foregroundStyle(.secondary)
                    Picker("传递方式", selection: Binding(get: { parameter.wrappedValue.passing }, set: { passing in
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
                        Text("参数名").foregroundStyle(.secondary)
                        TextField("参数名", text: parameter.argumentName, prompt: Text("例如 --output 或 -o"))
                            .labelsHidden()
                    }
                }
                if parameter.wrappedValue.passing == .named {
                    GridRow {
                        Text("传值格式").foregroundStyle(.secondary)
                        Picker("传值格式", selection: parameter.argumentFormat) {
                            ForEach(NamedArgumentFormat.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                }
                if parameter.wrappedValue.passing == .flag {
                    GridRow {
                        Text("默认状态").foregroundStyle(.secondary)
                        Toggle("默认开启", isOn: Binding(
                            get: { parameter.wrappedValue.defaultValue == "true" },
                            set: { parameter.wrappedValue.defaultValue = $0 ? "true" : "false" }
                        ))
                    }
                } else {
                    GridRow {
                        Text("输入类型").foregroundStyle(.secondary)
                        HStack {
                            Picker("输入类型", selection: parameter.kind) {
                                ForEach(ParameterKind.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Toggle("必填", isOn: parameter.required).fixedSize()
                        }
                    }
                    GridRow {
                        Text("占位提示").foregroundStyle(.secondary)
                        TextField("占位提示", text: parameter.placeholder, prompt: Text("可选")).labelsHidden()
                    }
                    if parameter.wrappedValue.kind != .select {
                        GridRow {
                            Text("默认值").foregroundStyle(.secondary)
                            TextField("默认值", text: parameter.defaultValue, prompt: Text("可选，请勿保存密码")).labelsHidden()
                        }
                    }
                }
            }.textFieldStyle(.roundedBorder).font(.callout)
            if parameter.wrappedValue.passing == .flag {
                Text("开启时传入参数名，关闭时省略；不传 true 或 false。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if parameter.wrappedValue.kind == .select {
                optionFields(parameter)
            }
        }
    }

    private func optionFields(_ parameter: Binding<ScriptParameter>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("左侧为界面显示名称，右侧为实际传给脚本的值。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("显示名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("实际传值").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 28, height: 1)
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(parameter.wrappedValue.options.enumerated()), id: \.offset) { index, option in
                let binding = optionBinding(parameter, index: index, fallback: option)
                HStack {
                    TextField("显示名称", text: binding.label, prompt: Text("例如：生产环境"))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel("选项显示名称")
                    TextField("实际传值", text: binding.value, prompt: Text("例如：production"))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel("选项实际传值")
                    Button(role: .destructive) {
                        var updated = parameter.wrappedValue
                        guard updated.options.indices.contains(index) else { return }
                        updated.options.remove(at: index)
                        parameter.wrappedValue = updated
                    } label: {
                        Image(systemName: "minus.circle")
                    }.help("删除选项").accessibilityLabel("删除选项")
                }
            }
            HStack {
                Button("添加选项") { parameter.wrappedValue.options.append(ParameterOption()) }
                Spacer()
                Text("默认值").font(.callout).foregroundStyle(.secondary)
                TextField("默认值", text: parameter.defaultValue, prompt: Text("填写选项的实际传值，可留空"))
                    .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel("选项默认值")
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
        guard !item.name.isEmpty else { error = "请填写脚本名称。"; return }
        guard item.parameters.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = "请填写每个参数的名称。"; return
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
        if save(item) { dismiss() } else { error = "保存失败。配置可能已被外部修改，请取消并重新打开编辑，或查看脚本库提示。" }
    }
}
