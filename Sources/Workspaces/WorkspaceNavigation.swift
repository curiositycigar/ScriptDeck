import Combine

/// The displayed page is separate from each workspace's last selected script.
@MainActor
final class WorkspaceNavigation: ObservableObject {
    enum Destination { case scripts, schedules }
    @Published var destination: Destination = .scripts

    func highlightedScript(in session: WorkspaceSession) -> String? {
        destination == .scripts ? session.selectedID : nil
    }

    func selectScript(_ id: String, in session: WorkspaceSession) {
        session.selectedID = id
        destination = .scripts
    }
}
