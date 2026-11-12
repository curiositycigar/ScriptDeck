import Combine

/// The displayed page is separate from each workspace's last selected script.
@MainActor
final class WorkspaceNavigation: ObservableObject {
    enum Destination: CaseIterable { case home, scripts, schedules, logs, settings }
    @Published var destination: Destination = .home
    @Published var managingWorkspaces = false
    @Published var logScope: ScheduleHistoryScope?

    func showHistory(_ scope: ScheduleHistoryScope? = nil) {
        logScope = scope
        destination = .logs
    }

    func highlightedScript(in session: WorkspaceSession) -> String? {
        destination == .scripts ? session.selectedID : nil
    }

    func selectScript(_ id: String, in session: WorkspaceSession) {
        session.selectedID = id
        destination = .scripts
    }
}
