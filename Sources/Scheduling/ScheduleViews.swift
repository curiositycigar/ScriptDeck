import SwiftUI

struct ScheduleDashboard: View {
    @ObservedObject var schedules: ScheduleStore
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    var showOutput: () -> Void
    @State private var creating = false
    @State private var editing: ScheduledTask?
    @State private var deleting: ScheduledTask?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("定时任务").font(.title2.bold())
                    Text("由 macOS 后台执行，退出 App 后仍然有效。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { creating = true } label: { Label("新建定时任务", systemImage: "plus") }
                    .disabled(workspaces.items.isEmpty)
            }
            if schedules.tasks.isEmpty {
                WorkspaceEmptyState(symbol: "calendar.badge.clock", title: "还没有定时任务",
                                    message: "选择 Workspace 和脚本，设置一次性时间或重复周期。也可从脚本运行栏创建，保存当前参数。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(schedules.tasks) { task in taskRow(task) }
                    }
                }
            }
            Text("电脑需开机且用户已登录；休眠期间不执行，恢复后最多补执行一次。同一定时任务不会重叠运行。后台任务不支持键盘交互。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("定时任务")
        .sheet(isPresented: $creating) {
            ScheduleEditor(workspaces: workspaces, initial: nil) { try schedules.save($0) }
        }
        .sheet(item: $editing) { task in
            ScheduleEditor(workspaces: workspaces, initial: task) { try schedules.save($0) }
        }
        .alert("删除定时任务？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let task = deleting { schedules.perform { try schedules.remove(task) } }
                deleting = nil
            }
        } message: { Text("移除系统定时配置，已生成的执行历史和日志会保留。") }
    }
    private func taskRow(_ task: ScheduledTask) -> some View {
        let state = schedules.state(for: task)
        let running = schedules.runningIDs.contains(task.id)
        let completed = task.kind == .once && state?.runID != nil && state?.nextFireAt == nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: running ? "play.circle.fill" : task.enabled && !completed ? "clock" : "pause.circle")
                    .foregroundStyle(running ? Color.orange : Color.secondary)
                Text(task.name).font(.headline).lineLimit(1)
                Spacer()
                Text(running ? "执行中" : !task.enabled ? "已暂停" : completed ? "已触发" : "已启用")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(task.workspaceName) · \(task.item.name) · \(task.summary)")
                .font(.callout).foregroundStyle(.secondary)
            if task.enabled, let next = state?.nextFireAt {
                Text("下次：\(next.formatted(date: .numeric, time: .shortened))").font(.caption)
            }
            if let started = state?.startedAt {
                Text("最近：\(started.formatted(date: .numeric, time: .standard)) · \(state?.message ?? state?.outcome?.title ?? "")")
                    .font(.caption).foregroundStyle(state?.outcome == .launchFailed || state?.outcome == .failed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            }
            if let issue = schedules.issue(for: task) { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("编辑") { editing = task }.disabled(running)
                Button(task.enabled ? "暂停" : "启用") {
                    schedules.perform { try schedules.setEnabled(task, !task.enabled) }
                }.disabled(!task.enabled && completed)
                    .help("暂停只影响后续计划，当前运行继续；已触发的一次性任务需编辑新的执行时间。")
                if running {
                    Button("查看输出") {
                        if let id = runner.sessions.first(where: { $0.recordID == state?.runID })?.id { runner.select(id); showOutput() }
                    }
                    Button("停止") {
                        runner.sessions.first(where: { $0.recordID == state?.runID })?.stop()
                    }
                }
                Spacer()
                Button(role: .destructive) { deleting = task } label: { Image(systemName: "trash") }
                    .disabled(running).help("删除定时任务")
            }.controlSize(.small)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ScheduleEditor: View {
    @ObservedObject var workspaces: WorkspaceStore
    let initial: ScheduledTask?
    let save: (ScheduledTask) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceID = ""
    @State private var scriptID = ""
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var kind: ScheduleKind = .once
    @State private var date = Date().addingTimeInterval(3600)
    @State private var weekday = 2
    @State private var minutes = 60
    @State private var error: String?

    private var workspace: Workspace? { workspaces.items.first { $0.id == workspaceID } }
    private var items: [ScriptItem] { workspace.map { workspaces.library(for: $0).items } ?? [] }
    private var item: ScriptItem? { initial?.item ?? items.first { $0.id == scriptID } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(initial == nil ? "新建定时任务" : "配置定时任务").font(.title2.bold()); Spacer() }.padding(24)
            Form {
                Section("执行内容") {
                    TextField("任务名称", text: $name)
                    if let initial {
                        LabeledContent("Workspace", value: initial.workspaceName)
                        LabeledContent("脚本", value: initial.item.name)
                    } else {
                        Picker("Workspace", selection: $workspaceID) {
                            ForEach(workspaces.items) { Text($0.name).tag($0.id) }
                        }.onChange(of: workspaceID) { _ in selectFirstScript() }
                        Picker("脚本", selection: $scriptID) {
                            ForEach(items) { Text($0.name).tag($0.id) }
                        }.onChange(of: scriptID) { _ in values = [:]; if let item { name = item.name } }
                    }
                }
                Section("执行时间") {
                    Picker("类型", selection: $kind) { ForEach(ScheduleKind.allCases) { Text($0.title).tag($0) } }
                    if kind == .interval {
                        Stepper("每 \(minutes) 分钟", value: $minutes, in: 1...525600)
                        TextField("间隔（分钟）", value: $minutes, format: .number)
                    } else {
                        DatePicker(kind == .once ? "日期与时刻" : "执行时刻", selection: $date,
                                   displayedComponents: kind == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                        if kind == .weekly {
                            Picker("星期", selection: $weekday) {
                                ForEach(1...7, id: \.self) { Text("周\(["日", "一", "二", "三", "四", "五", "六"][$0 - 1])").tag($0) }
                            }
                        }
                    }
                }
                if let item, !item.parameters.isEmpty {
                    Section("保存的运行参数") {
                        ForEach(item.parameters) { parameter in
                            if parameter.passing == .flag {
                                Toggle(parameter.name, isOn: Binding(get: { value(parameter) == "true" }, set: { values[parameter.id] = $0 ? "true" : "false" }))
                            } else if parameter.kind == .select {
                                Picker(parameter.name, selection: binding(parameter)) {
                                    Text("请选择").tag("")
                                    ForEach(parameter.options) { Text($0.label).tag($0.value) }
                                }
                            } else {
                                HStack {
                                    TextField(parameter.name + (parameter.required ? " *" : ""), text: binding(parameter))
                                    if parameter.kind == .file || parameter.kind == .folder {
                                        Button("选择…") {
                                            choosePath(directory: parameter.kind == .folder) { values[parameter.id] = $0 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("保存脚本配置与参数快照，之后修改脚本配置不会自动改变此任务。参数仅保存在本机；请避免填写密码。脚本必须能在无人输入的情况下执行。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并启用") { commit() }.keyboardShortcut(.defaultAction).disabled(item == nil)
            }.padding(20)
        }.frame(width: 580, height: 650)
        .onAppear {
            if let initial {
                workspaceID = initial.workspaceID; scriptID = initial.item.id; name = initial.name
                values = initial.values; kind = initial.kind; date = initial.date
                weekday = initial.weekday; minutes = initial.intervalMinutes
            } else {
                workspaceID = workspaces.selectedID ?? workspaces.items.first?.id ?? ""
                selectFirstScript()
            }
        }
    }
    private func value(_ parameter: ScriptParameter) -> String { values[parameter.id] ?? parameter.defaultValue }
    private func binding(_ parameter: ScriptParameter) -> Binding<String> {
        Binding(get: { value(parameter) }, set: { values[parameter.id] = $0 })
    }
    private func selectFirstScript() { scriptID = items.first?.id ?? ""; values = [:]; name = items.first?.name ?? "" }
    private func commit() {
        guard var item else { return }
        var supplied = values
        if initial == nil, let workspace {
            let library = workspaces.library(for: workspace)
            for parameter in item.parameters where parameter.passing != .flag && (parameter.kind == .file || parameter.kind == .folder) {
                let input = value(parameter)
                if !input.isEmpty { supplied[parameter.id] = library.resolvedParameterPath(input) }
            }
            item = library.resolved(item)
        }
        var task = initial ?? ScheduledTask(name: name, workspaceID: workspaceID,
                                            workspaceName: workspace?.name ?? "", item: item, values: supplied)
        task.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        task.item = item; task.values = supplied; task.kind = kind; task.date = date
        task.weekday = weekday; task.intervalMinutes = minutes; task.enabled = true
        task.timeZoneID = TimeZone.current.identifier
        do { try save(task); dismiss() } catch { self.error = error.localizedDescription }
    }
}
