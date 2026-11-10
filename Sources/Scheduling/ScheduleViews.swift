import SwiftUI

struct ScheduleDashboard: View {
    @ObservedObject var schedules: ScheduleStore
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    var showOutput: () -> Void
    @State private var creating = false
    @State private var editing: ScheduledTask?
    @State private var deleting: ScheduledTask?
    @State private var historyTask: ScheduledTask?
    @State private var showingSchedulingNotes = false
    private let cardMinimumWidth: CGFloat = 360
    private let cardSpacing: CGFloat = 12
    private let listInset: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            GeometryReader { geometry in
                ScrollView {
                    if schedules.tasks.isEmpty {
                        WorkspaceEmptyState(symbol: "calendar.badge.clock", title: L("No scheduled tasks yet"),
                                            message: L("Choose a workspace and script, then set a time or repeat interval. You can also create a schedule from the script's run bar to save its current parameters."))
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    } else {
                        ScheduleCardGrid(minimumCardWidth: cardMinimumWidth, spacing: cardSpacing) {
                            ForEach(schedules.tasks) { task in taskRow(task) }
                        }
                        .padding(.horizontal, listInset).padding(.bottom, listInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            dashboardActions
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .workspaceActionSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkspaceStyle.canvas)
        .workspaceTypography()
        .sheet(isPresented: $creating) {
            ScheduleEditor(workspaces: workspaces, initial: nil) { try schedules.save($0) }
        }
        .sheet(item: $historyTask) { task in
            let state = schedules.state(for: task)
            ExecutionHistoryView(workspaces: workspaces, runner: runner,
                                 scheduleScope: ScheduleHistoryScope(task: task, latestRunID: state?.runID,
                                                                     metadataPath: state?.metadataPath))
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
    private var dashboardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            WorkspaceSymbol("calendar.badge.clock", size: .header).foregroundStyle(.tint)
                .frame(width: WorkspaceControlMetrics.headerTile, height: WorkspaceControlMetrics.headerTile)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 2) {
                    Text(L("Scheduled Tasks")).font(WorkspaceTypography.pageTitle)
                    Button { showingSchedulingNotes.toggle() } label: {
                        WorkspaceSymbol("info.circle", size: .toolbar)
                            .frame(width: WorkspaceControlMetrics.titleActionTarget, height: WorkspaceControlMetrics.titleActionTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WorkspaceIconButtonStyle(targetSize: WorkspaceControlMetrics.titleActionTarget)).foregroundStyle(.secondary)
                    .help(L("Scheduling Notes")).accessibilityLabel(L("Scheduling Notes"))
                    .popover(isPresented: $showingSchedulingNotes, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Scheduling Notes")).font(WorkspaceTypography.sectionTitle)
                            Text(L("Your Mac must be on and you must be logged in. Tasks do not run during sleep; at most one missed run is caught up afterward. Each schedule prevents overlapping runs. Background tasks do not support keyboard input."))
                                .font(WorkspaceTypography.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(width: 360)
                    }
                }
                Text(L("Runs in the macOS background, even after you quit the app."))
                    .font(WorkspaceTypography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var taskStatistics: some View {
        HStack(spacing: 12) {
            Text(L("{0} scheduled tasks", "\(schedules.tasks.count)"))
            Label(L("Enabled") + " · \(schedules.tasks.filter { $0.enabled }.count)", systemImage: "clock")
            Label(L("Paused") + " · \(schedules.tasks.filter { !$0.enabled }.count)", systemImage: "pause.circle")
        }
        .font(WorkspaceTypography.caption).monospacedDigit()
        .foregroundStyle(.secondary).fixedSize()
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
                taskStatistics
                Spacer(minLength: 12)
                createButton.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                taskStatistics
                HStack { Spacer(); createButton }
            }
        }
    }

    private func taskRow(_ task: ScheduledTask) -> some View {
        let state = schedules.state(for: task)
        let running = schedules.runningIDs.contains(task.id)
        let completed = task.kind == .once && state?.runID != nil && state?.nextFireAt == nil
        let failed = state?.outcome == .launchFailed || state?.outcome == .failed
        let status = running ? L("Executing") : !task.enabled ? L("Paused") : completed ? L("Triggered") : L("Enabled")
        let statusSymbol = running ? "play.fill" : !task.enabled ? "pause.fill" : completed ? "checkmark" : "clock"
        let tint: Color = running ? .orange : task.enabled && !completed ? .accentColor : .secondary
        let issue = schedules.issue(for: task)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                taskIdentity(task, running: running, tint: tint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.summary)
                        .font(WorkspaceTypography.bodyStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    taskTiming(task, state: state, failed: failed)
                        .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(WorkspaceTypography.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 12) {
                if running {
                    runningActions(runID: state?.runID)
                        .controlSize(.small)
                }
                taskControls(task, status: status, symbol: statusSymbol, running: running, completed: completed)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func taskIdentity(_ task: ScheduledTask, running: Bool, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            WorkspaceSymbol(running ? "play.fill" : task.kind == .once ? "calendar" : "repeat", size: .navigation)
                .foregroundStyle(tint)
                .frame(width: WorkspaceControlMetrics.navigationTarget, height: WorkspaceControlMetrics.navigationTarget)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name).font(WorkspaceTypography.sectionTitle)
                    .lineLimit(2).truncationMode(.middle).help(task.name)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("\(task.workspaceName) · \(task.item.name)")
                    .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help("\(task.workspaceName) · \(task.item.name)")
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func taskTiming(_ task: ScheduledTask, state: ScheduleRuntime?, failed: Bool) -> some View {
        let next = task.enabled ? state?.nextFireAt : nil
        let nextRun = next.map { L10n.date($0, dateStyle: .short, timeStyle: .short) } ?? "—"
        let lastRun = state?.startedAt.map { started in
            L("Last: {0} · {1}", L10n.date(started, dateStyle: .short),
              state?.message ?? state?.outcome?.title ?? "")
        }
        Text(L("Next: {0}", nextRun))
            .lineLimit(1)
            .help(L("Next: {0}", nextRun))
        if let lastRun {
            Text(lastRun)
                .foregroundStyle(failed ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func taskControls(_ task: ScheduledTask, status: String, symbol: String,
                              running: Bool, completed: Bool) -> some View {
        HStack(spacing: 6) {
            Label(status, systemImage: symbol)
                .font(WorkspaceTypography.captionStrong)
                .foregroundStyle(running ? Color.orange : Color.secondary)
                .lineLimit(1)
                .padding(.trailing, 4)
            Toggle(L("Enabled"), isOn: Binding(get: { task.enabled }, set: { enabled in
                schedules.perform { try schedules.setEnabled(task, enabled) }
            }))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            .disabled(!task.enabled && completed)
            .accessibilityLabel(task.enabled ? L("Pause") : L("Enable"))
            .help(L("Pausing affects future runs only. Edit a triggered one-time task to set a new execution time."))
            Spacer(minLength: 8)
            Button { historyTask = task } label: { WorkspaceSymbol("clock.arrow.circlepath", size: .toolbar) }
                .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                .help(L("Execution History")).accessibilityLabel(L("Execution History"))
            Button { editing = task } label: { WorkspaceSymbol("slider.horizontal.3", size: .toolbar) }
                .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
                .disabled(running).help(L("Edit")).accessibilityLabel(L("Edit"))
            Menu {
                Button(L("Delete Scheduled Task"), systemImage: "trash", role: .destructive) { deleting = task }
                    .disabled(running)
            } label: {
                WorkspaceSymbol("ellipsis", size: .toolbar)
                    .frame(width: WorkspaceControlMetrics.iconTarget, height: WorkspaceControlMetrics.iconTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .help(L("More Actions")).accessibilityLabel(L("More Actions"))
            .foregroundStyle(.secondary)
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


}

private struct ScheduleCardGrid: Layout {
    let minimumCardWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumCardWidth
        let grid = measure(width: width, subviews: subviews)
        let rows = (subviews.count + grid.columns - 1) / grid.columns
        return CGSize(width: width, height: CGFloat(rows) * grid.height + CGFloat(max(0, rows - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = measure(width: bounds.width, subviews: subviews)
        let cardSize = ProposedViewSize(width: grid.width, height: grid.height)
        for (index, card) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index % grid.columns) * (grid.width + spacing)
            let y = bounds.minY + CGFloat(index / grid.columns) * (grid.height + spacing)
            card.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: cardSize)
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (columns: Int, width: CGFloat, height: CGFloat) {
        let columns = max(1, Int((width + spacing) / (minimumCardWidth + spacing)))
        let cardWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let proposal = ProposedViewSize(width: cardWidth, height: nil)
        let cardHeight = subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
        return (columns, cardWidth, cardHeight)
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
            HStack { Text(initial == nil ? L("New Scheduled Task") : L("Configure Scheduled Task")).font(WorkspaceTypography.dialogTitle); Spacer() }.padding(24)
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
                        .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save and Enable")) { commit() }.keyboardShortcut(.defaultAction).disabled(item == nil)
            }.padding(20)
        }.frame(width: 580, height: 650).workspaceTypography()
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
