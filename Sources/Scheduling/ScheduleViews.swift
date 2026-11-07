import SwiftUI

struct ScheduleDashboard: View {
    @ObservedObject var schedules: ScheduleStore
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    var showOutput: () -> Void
    @State private var creating = false
    @State private var editing: ScheduledTask?
    @State private var deleting: ScheduledTask?
    @State private var notesExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 19, weight: .medium)).foregroundStyle(.tint)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Scheduled Tasks")).font(.title2.weight(.semibold))
                            Text(L("Runs in the macOS background, even after you quit the app."))
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if schedules.tasks.isEmpty {
                        WorkspaceEmptyState(symbol: "calendar.badge.clock", title: L("No scheduled tasks yet"),
                                            message: L("Choose a workspace and script, then set a time or repeat interval. You can also create a schedule from the script's run bar to save its current parameters."))
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(schedules.tasks) { task in taskRow(task) }
                        }
                    }
                    DisclosureGroup(L("Scheduling Notes"), isExpanded: $notesExpanded) {
                        Text(L("Your Mac must be on and you must be logged in. Tasks do not run during sleep; at most one missed run is caught up afterward. Each schedule prevents overlapping runs. Background tasks do not support keyboard input."))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    .disclosureGroupStyle(WorkspaceDisclosureStyle())
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            dashboardActions
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(L("Scheduled Tasks"))
        .sheet(isPresented: $creating) {
            ScheduleEditor(workspaces: workspaces, initial: nil) { try schedules.save($0) }
        }
        .sheet(item: $editing) { task in
            ScheduleEditor(workspaces: workspaces, initial: task) { try schedules.save($0) }
        }
        .alert(L("Delete Scheduled Task?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("Cancel"), role: .cancel) { deleting = nil }
            Button(L("Delete"), role: .destructive) {
                if let task = deleting { schedules.perform { try schedules.remove(task) } }
                deleting = nil
            }
        } message: { Text(L("Remove this system schedule. Existing execution history and logs will be preserved.")) }
    }
    private var taskCount: some View {
        Text(L("{0} scheduled tasks", "\(schedules.tasks.count)"))
            .font(.callout).foregroundStyle(.secondary).fixedSize()
    }

    private var createButton: some View {
        Button { creating = true } label: { Label(L("New Scheduled Task"), systemImage: "plus") }
            .workspacePrimaryAction()
            .controlSize(.regular)
            .disabled(workspaces.items.isEmpty)
    }

    private var dashboardActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                taskCount
                Spacer(minLength: 12)
                createButton.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                taskCount
                HStack { Spacer(); createButton }
            }
        }
    }

    private func taskRow(_ task: ScheduledTask) -> some View {
        let state = schedules.state(for: task)
        let running = schedules.runningIDs.contains(task.id)
        let completed = task.kind == .once && state?.runID != nil && state?.nextFireAt == nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: running ? "play.circle.fill" : task.enabled && !completed ? "clock" : "pause.circle")
                    .foregroundStyle(running ? Color.orange : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.name).font(.headline)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("\(task.workspaceName) · \(task.item.name)")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(running ? L("Executing") : !task.enabled ? L("Paused") : completed ? L("Triggered") : L("Enabled"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(running ? Color.orange : Color.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(running ? Color.orange.opacity(0.1) : Color.secondary.opacity(0.08),
                                in: Capsule())
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(task.summary, systemImage: "calendar")
                    .font(.callout)
                if task.enabled, let next = state?.nextFireAt {
                    Text(L("Next: {0}", "\(L10n.date(next, dateStyle: .short, timeStyle: .short))"))
                        .font(.caption)
                }
                if let started = state?.startedAt {
                    Text(L("Last: {0} · {1}", "\(L10n.date(started, dateStyle: .short))", "\(state?.message ?? state?.outcome?.title ?? "")"))
                        .font(.caption).foregroundStyle(state?.outcome == .launchFailed || state?.outcome == .failed ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
                if let issue = schedules.issue(for: task) {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    taskActions(task, completed: completed).fixedSize()
                    Spacer(minLength: 8)
                    if running { runningActions(runID: state?.runID).fixedSize() }
                    deleteButton(task, running: running)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        taskActions(task, completed: completed)
                        Spacer()
                        deleteButton(task, running: running)
                    }
                    if running { runningActions(runID: state?.runID) }
                }
            }.controlSize(.small)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func taskActions(_ task: ScheduledTask, completed: Bool) -> some View {
        HStack(spacing: 10) {
            Button(L("Edit")) { editing = task }.disabled(schedules.runningIDs.contains(task.id))
            Button(task.enabled ? L("Pause") : L("Enable")) {
                schedules.perform { try schedules.setEnabled(task, !task.enabled) }
            }.disabled(!task.enabled && completed)
                .help(L("Pausing affects future runs only. Edit a triggered one-time task to set a new execution time."))
        }
    }

    private func runningActions(runID: String?) -> some View {
        HStack(spacing: 10) {
            Button(L("View Output")) {
                if let id = runner.sessions.first(where: { $0.recordID == runID })?.id {
                    runner.select(id)
                    showOutput()
                }
            }
            Button(L("Stop")) {
                runner.sessions.first(where: { $0.recordID == runID })?.stop()
            }
        }
    }

    private func deleteButton(_ task: ScheduledTask, running: Bool) -> some View {
        Button(role: .destructive) { deleting = task } label: { Image(systemName: "trash") }
            .disabled(running).help(L("Delete Scheduled Task"))
            .accessibilityLabel(L("Delete Scheduled Task"))
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
            HStack { Text(initial == nil ? L("New Scheduled Task") : L("Configure Scheduled Task")).font(.title2.bold()); Spacer() }.padding(24)
            Form {
                Section(L("Task")) {
                    TextField(L("Task Name"), text: $name)
                    if let initial {
                        LabeledContent(L("Workspace"), value: initial.workspaceName)
                        LabeledContent(L("Script"), value: initial.item.name)
                    } else {
                        Picker(L("Workspace"), selection: $workspaceID) {
                            ForEach(workspaces.items) { Text($0.name).tag($0.id) }
                        }.onChange(of: workspaceID) { _ in selectFirstScript() }
                        Picker(L("Script"), selection: $scriptID) {
                            ForEach(items) { Text($0.name).tag($0.id) }
                        }.onChange(of: scriptID) { _ in values = [:]; if let item { name = item.name } }
                    }
                }
                Section(L("Execution Time")) {
                    Picker(L("Type"), selection: $kind) { ForEach(ScheduleKind.allCases) { Text($0.title).tag($0) } }
                    if kind == .interval {
                        Stepper(L("Every {0} minutes", "\(minutes)"), value: $minutes, in: 1...525600)
                        TextField(L("Interval (minutes)"), value: $minutes, format: .number)
                    } else {
                        DatePicker(kind == .once ? L("Date and Time") : L("Time"), selection: $date,
                                   displayedComponents: kind == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                        if kind == .weekly {
                            Picker(L("Weekday"), selection: $weekday) {
                                ForEach(1...7, id: \.self) { Text(L10n.weekday($0)).tag($0) }
                            }
                        }
                    }
                }
                if let item, !item.parameters.isEmpty {
                    Section(L("Saved Parameters")) {
                        ForEach(item.parameters) { parameter in
                            if parameter.passing == .flag {
                                Toggle(parameter.name, isOn: Binding(get: { value(parameter) == "true" }, set: { values[parameter.id] = $0 ? "true" : "false" }))
                            } else if parameter.kind == .select {
                                Picker(parameter.name, selection: binding(parameter)) {
                                    Text(L("Choose an option")).tag("")
                                    ForEach(parameter.options) { Text($0.label).tag($0.value) }
                                }
                            } else {
                                HStack {
                                    TextField(parameter.name + (parameter.required ? " *" : ""), text: binding(parameter))
                                    if parameter.kind == .file || parameter.kind == .folder {
                                        Button(L("Choose…")) {
                                            choosePath(directory: parameter.kind == .folder) { values[parameter.id] = $0 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Text(L("Saves a snapshot of the script configuration and parameters. Later script configuration changes do not update this task. Parameters stay on this Mac; avoid passwords. The script must run without user input."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save and Enable")) { commit() }.keyboardShortcut(.defaultAction).disabled(item == nil)
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
