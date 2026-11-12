import SwiftUI
import Combine

/// Offers one dialog per observed ECHO-off interval, without reading terminal contents.
@MainActor
final class HiddenInputPromptController: ObservableObject {
    @Published var session: ExecutionSession?
    private var offered = Set<UUID>()

    func poll(sessions: [ExecutionSession], selected: ExecutionSession?, canPresent: Bool) {
        let hidden = Set(sessions.filter(\.needsHiddenInputNotice).map(\.id))
        offered.formIntersection(hidden)
        if let current = session, current.id != selected?.id || !current.needsHiddenInputNotice || current.showingTerminalLog {
            session = nil
        }
        guard session == nil, canPresent, let selected, selected.needsHiddenInputNotice,
              !selected.showingTerminalLog, !offered.contains(selected.id) else { return }
        open(selected)
    }

    func open(_ selected: ExecutionSession) {
        guard selected.needsHiddenInputNotice, !selected.showingTerminalLog else { return }
        offered.insert(selected.id)
        session = selected
    }
}

@MainActor
enum HiddenInputSubmission {
    static func send(credentialID: String, password: String, appendReturn: Bool,
                     runner: ProcessRunner, sessionID: UUID, store: CredentialStore) async throws {
        try runner.validateCredentialTarget(sessionID)
        let secret = credentialID.isEmpty ? password : try await store.password(for: credentialID)
        try Task.checkCancellation()
        // Revalidates the bound execution and ECHO after any Keychain access.
        try await runner.fillPassword(secret, sessionID: sessionID, appendReturn: appendReturn)
    }
}

struct HiddenInputPrompt: View {
    @ObservedObject var runner: ProcessRunner
    @ObservedObject var session: ExecutionSession
    @ObservedObject var store = CredentialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var credentialID = ""
    @State private var password = ""
    @State private var appendReturn = true
    @State private var filling = false
    @State private var issue: String?
    @State private var fillTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    private var target: CredentialTarget? {
        guard let workspaceID = session.workspaceID, let scriptID = session.scriptID else { return nil }
        return CredentialTarget(workspaceID: workspaceID, scriptID: scriptID)
    }

    private var credentials: [SavedCredential] {
        store.items.sorted { a, b in
            let associatedA = target.map { a.scripts.contains($0) } ?? false
            let associatedB = target.map { b.scripts.contains($0) } ?? false
            return associatedA == associatedB ? a.name.localizedStandardCompare(b.name) == .orderedAscending : associatedA
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Terminal Hidden Input"), systemImage: "lock.fill").font(WorkspaceTypography.dialogTitle)
            Text(session.activeName).font(WorkspaceTypography.bodyStrong)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("The script may be waiting for a password or other hidden input."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker(L("Input source"), selection: $credentialID) {
                Text(L("Enter manually")).tag("")
                ForEach(credentials) { credential in
                    Text(credential.name).tag(credential.id)
                }
            }
            if credentialID.isEmpty {
                SecureField(L("Password"), text: $password).textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
            } else {
                Label(L("Password saved in Keychain"), systemImage: "key.fill")
                    .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            }
            Toggle(L("Press Return after filling"), isOn: $appendReturn).toggleStyle(.checkbox)
            if let issue {
                Text(issue).font(WorkspaceTypography.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L("Terminal Log")) { session.showingTerminalLog = true; dismiss() }
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(filling ? L("Filling…") : L("Send"), action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled((credentialID.isEmpty ? password.isEmpty : !store.items.contains { $0.id == credentialID }) ||
                              !session.needsHiddenInputNotice)
            }
        }
        .font(WorkspaceTypography.body).padding(20).frame(width: 420)
        .disabled(filling)
        .onAppear { inputFocused = true }
        .onChange(of: credentialID) { _ in password = ""; issue = nil; inputFocused = credentialID.isEmpty }
        .onDisappear { password = ""; fillTask?.cancel() }
    }

    private func send() {
        filling = true
        issue = nil
        fillTask = Task { @MainActor in
            defer { filling = false }
            do {
                try await HiddenInputSubmission.send(credentialID: credentialID, password: password,
                                                     appendReturn: appendReturn, runner: runner,
                                                     sessionID: session.id, store: store)
                password = ""
                dismiss()
            } catch is CancellationError { }
            catch { issue = error.localizedDescription }
        }
    }
}
