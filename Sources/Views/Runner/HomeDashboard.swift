import SwiftUI

struct HomeDashboard: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    let openScript: (Workspace, ScriptItem) -> Void
    let openWorkspaces: () -> Void
    let openSchedules: () -> Void
    let editSchedule: (ScheduledTask) -> Void

    private var upcoming: [(task: ScheduledTask, date: Date)] {
        schedules.tasks.compactMap { task in
            guard task.enabled, let date = schedules.state(for: task)?.nextFireAt else { return nil }
            return (task, date)
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        let running = runner.runningSessions.sorted { $0.startedAt > $1.startedAt }
        let upcoming = self.upcoming
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(L("Favorite Scripts"), action: L("Browse Scripts"), perform: openWorkspaces)
                    if preferences.favorites.isEmpty {
                        emptyMessage(L("Add scripts to Favorites using the star beside a script's name."), symbol: "star")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], spacing: 12) {
                            ForEach(preferences.favorites, id: \.self) { favorite in
                                if let workspace = workspaces.items.first(where: { $0.id == favorite.workspaceID }) {
                                    FavoriteScriptCard(favorite: favorite, workspace: workspace,
                                                       store: workspaces.library(for: workspace),
                                                       preferences: preferences, runner: runner, schedules: schedules,
                                                       openScript: { openScript(workspace, $0) })
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label(L("Workspace Unavailable"), systemImage: "folder.badge.questionmark")
                                        Button(L("Remove from Favorites")) {
                                            preferences.toggleFavorite(workspaceID: favorite.workspaceID, scriptID: favorite.scriptID)
                                        }
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Running Tasks")).font(WorkspaceTypography.sectionTitle)
                    if running.isEmpty {
                        emptyMessage(L("No running tasks"), symbol: "play.circle")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(running) { session in
                                RunningTaskRow(session: session, runner: runner)
                                if session.id != running.last?.id { Divider().padding(.horizontal, 16) }
                            }
                        }.background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(L("Upcoming Scheduled Tasks"), action: L("View All"), perform: openSchedules)
                    if upcoming.isEmpty {
                        emptyMessage(L("No upcoming scheduled tasks"), symbol: "calendar")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(upcoming, id: \.task.id) { entry in
                                HStack(spacing: 16) {
                                    Image(systemName: "calendar.badge.clock").foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.task.name).font(WorkspaceTypography.bodyStrong).lineLimit(1)
                                        Text(entry.task.workspaceName + " · " + entry.task.item.name)
                                            .font(WorkspaceTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if let issue = schedules.issue(for: entry.task) {
                                            Text(issue).font(WorkspaceTypography.caption).foregroundStyle(.red)
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(L10n.date(entry.date, dateStyle: .short, timeStyle: .short))
                                            .font(WorkspaceTypography.body).monospacedDigit()
                                        if entry.task.kind != .once {
                                            Text(entry.task.summary).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Button(L("Edit")) { editSchedule(entry.task) }
                                        .disabled(schedules.runningIDs.contains(entry.task.id))
                                }.padding(16)
                                if entry.task.id != upcoming.last?.task.id { Divider().padding(.horizontal, 16) }
                            }
                        }.background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WorkspaceStyle.canvas)
    }

    private func sectionHeader(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(WorkspaceTypography.sectionTitle)
            Spacer()
            Button(action, action: perform).buttonStyle(.link)
        }
    }

    private func emptyMessage(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(WorkspaceTypography.body).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FavoriteScriptCard: View {
    let favorite: FavoriteScript
    let workspace: Workspace
    @ObservedObject var store: ScriptStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var schedules: ScheduleStore
    let openScript: (ScriptItem) -> Void
    @State private var issue: String?

    private var item: ScriptItem? { store.items.first { $0.id == favorite.scriptID } }
    private var unavailable: Bool { store.configurationIssue != nil || item == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "terminal").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item?.name ?? L("Script Unavailable")).font(WorkspaceTypography.sectionTitle).lineLimit(2)
                    Text(workspace.name).font(WorkspaceTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(L("Open Script")) {
                        if let item { openScript(item) }
                    }
                    .disabled(item == nil)
                    Divider()
                    Button(L("Move up")) { preferences.moveFavorite(favorite, by: -1) }
                        .disabled(preferences.favorites.first == favorite)
                    Button(L("Move down")) { preferences.moveFavorite(favorite, by: 1) }
                        .disabled(preferences.favorites.last == favorite)
                    Divider()
                    Button(L("Remove from Favorites")) {
                        preferences.toggleFavorite(workspaceID: favorite.workspaceID, scriptID: favorite.scriptID)
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L("Favorite Actions")).accessibilityLabel(L("Favorite Actions"))
            }
            Text(unavailable ? L("Open the workspace to check this script.") : item?.notes ?? "")
                .font(WorkspaceTypography.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            if let item {
                let running = runner.isActive(workspaceID: workspace.id, scriptID: item.id)
                let runTitle = item.parameters.isEmpty
                    ? (running ? L("Run Another Instance") : L("Run")) : L("Configure & Run")
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if running {
                        ScriptInstancesButton(runner: runner, workspaceID: workspace.id, scriptID: item.id)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    if !running || item.allowsMultipleInstances {
                        Button {
                            if item.parameters.isEmpty { run(item) } else { openScript(item) }
                        } label: {
                            WorkspaceSymbol("play.fill", size: .toolbar)
                        }
                        .buttonStyle(WorkspaceIconButtonStyle(prominent: true))
                        .help(runTitle).accessibilityLabel(runTitle)
                        .disabled(unavailable)
                    }
                }
            }

        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
        .alert(L("Operation Failed"), isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
            Button(L("OK"), role: .cancel) { issue = nil }
        } message: { Text(issue ?? "") }
    }

    private func run(_ item: ScriptItem) {
        schedules.refresh(registerSystem: false)
        do {
            let session = try runner.run(item: store.resolved(item), arguments: scriptArguments(for: item, values: [:]),
                                         workspaceID: workspace.id, workspaceName: workspace.name, workspaceDirectory: workspace.directory)
            runner.showExecution(session)
        } catch { issue = error.localizedDescription }
    }
}

private struct RunningTaskRow: View {
    @ObservedObject var session: ExecutionSession
    @ObservedObject var runner: ProcessRunner

    var body: some View {
        HStack(spacing: 16) {
            RunningTaskIndicator(stopping: session.stopping)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.activeName).font(WorkspaceTypography.bodyStrong).lineLimit(1)
                Text(session.workspaceName + " · " + (session.isBackgroundExecution ? L("Scheduled Task") : L("Manual Task")))
                    .font(WorkspaceTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(session.instanceLabel + " · " + session.status)
                    .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(session.startedAt, style: .timer).font(WorkspaceTypography.body.monospacedDigit()).fixedSize()
                .accessibilityLabel(L("Elapsed"))
            Button(L("View Output")) { runner.showExecution(session) }
            Button(session.stopping ? L("Force Stop") : L("Stop"), role: .destructive) {
                runner.stopAndCloseExecution(session)
            }
        }.padding(16)
    }
}

private struct RunningTaskIndicator: View {
    let stopping: Bool

    private var color: Color { stopping ? .orange : .blue }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.12))
            if stopping {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
            } else {
                RunningWaveform()
            }
        }
        .foregroundStyle(color)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true) // The adjacent session status supplies the accessible text.
    }

}
