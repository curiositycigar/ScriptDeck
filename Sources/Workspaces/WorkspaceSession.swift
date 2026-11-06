import Combine

/// Ephemeral UI state is scoped to a workspace, including duplicate script/parameter IDs.
final class WorkspaceSession: ObservableObject {
    @Published var selectedID: String?
    @Published var values: [String: [String: String]] = [:]
}
