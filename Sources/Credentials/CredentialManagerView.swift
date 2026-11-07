import SwiftUI

struct CredentialManagerView: View {
    @ObservedObject var runner: ProcessRunner
    var target: CredentialTarget? = nil
    var scriptName: String? = nil
    var session: ExecutionSession? = nil
    var canDismiss = true
    @ObservedObject var store = CredentialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var showEditor = false
    @State private var editing: SavedCredential?
    @State private var deleting: SavedCredential?
    @State private var appendReturn = true
    @State private var filling = false
    @State private var error: String?

    private var selected: SavedCredential? { store.items.first { $0.id == selectedID } }
    private var busy: Bool { store.busy || filling }
    private var canFill: Bool {
        guard let session else { return false }
        return runner.selectedSessionID == session.id && session.isRunning && !session.stopping && !session.isBackgroundExecution
    }
    private var sorted: [SavedCredential] {
        store.items.sorted { lhs, rhs in
            let a = target.map { lhs.scripts.contains($0) } ?? false
            let b = target.map { rhs.scripts.contains($0) } ?? false
            return a == b ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : a
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Credentials"), systemImage: "key").font(.title3.weight(.semibold))
                Spacer()
                Button { editing = nil; showEditor = true } label: { Label(L("Add Credential…"), systemImage: "plus") }
                if canDismiss { Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
            }
            if let scriptName {
                Text(L("Script: ") + scriptName).font(.callout).textSelection(.enabled)
            }
            Text(L("Passwords are stored in macOS Keychain. Script associations stay on this Mac."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) {
                List(selection: $selectedID) {
                    ForEach(sorted) { credential in
                        HStack {
                            Text(credential.name).lineLimit(1)
                            Spacer()
                            if let target, credential.scripts.contains(target) {
                                Image(systemName: "link").foregroundStyle(.secondary)
                                    .accessibilityLabel(L("Associated with this script"))
                            }
                        }.padding(.vertical, 6).tag(credential.id)
                    }
                }
                .listStyle(.inset).frame(width: 220)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let selected {
                            Text(selected.name).font(.headline).textSelection(.enabled)
                            Label(L("Password saved in Keychain"), systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(.secondary)
                            if let target {
                                Toggle(L("Associate with this script"), isOn: Binding(
                                    get: { selected.scripts.contains(target) },
                                    set: { store.associate(selected.id, with: target, enabled: $0) }
                                ))
                            }
                            HStack {
                                Button(L("Edit…")) { editing = selected; showEditor = true }
                                Button(L("Delete…"), role: .destructive) { deleting = selected }
                            }
                            if session != nil {
                                Divider()
                                Toggle(L("Press Return after filling"), isOn: $appendReturn)
                                Text(L("Fill when the script is waiting for a password with input echo disabled."))
                                    .font(.caption).foregroundStyle(.secondary)
                                Button {
                                    fill(selected.id)
                                } label: {
                                    Label(filling ? L("Filling…") : L("Fill Password"), systemImage: "key.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canFill)
                                if !canFill {
                                    Text(L("Select this running terminal to fill its password."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(L("Select or add a credential."))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(20).frame(width: 680, height: session == nil ? 440 : 520)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .onAppear { selectedID = sorted.first?.id }
        .sheet(isPresented: $showEditor) {
            CredentialEditor(credential: editing, target: target, onSave: { selectedID = $0 }, store: store)
        }
        .alert(L("Delete Credential?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("Cancel"), role: .cancel) { deleting = nil }
            Button(L("Delete"), role: .destructive) {
                guard let credential = deleting else { return }
                deleting = nil
                Task {
                    do {
                        try await store.remove(credential.id)
                        selectedID = sorted.first?.id
                    } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text(L("Delete “{0}” from Keychain and remove all its script associations?", deleting?.name ?? ""))
        }
        .alert(L("Credential Error"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func fill(_ credentialID: String) {
        guard canFill, let session else { return }
        filling = true
        Task {
            defer { filling = false }
            do {
                try runner.validateCredentialTarget(session.id)
                let password = try await store.password(for: credentialID)
                try await runner.fillPassword(password, sessionID: session.id, appendReturn: appendReturn)
                dismiss()
                session.focusTerminal()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct CredentialEditor: View {
    let credential: SavedCredential?
    let target: CredentialTarget?
    let onSave: (String) -> Void
    @ObservedObject var store = CredentialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(credential == nil ? L("Add Credential…") : L("Edit Credential")).font(.headline)
            TextField(L("Credential Name"), text: $name)
            SecureField(credential == nil ? L("Password") : L("New password (leave blank to keep current)"), text: $password)
            if target != nil && credential == nil {
                Text(L("This credential will be associated with the current script."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Cancel"), role: .cancel) { password = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            let id = try await store.save(id: credential?.id, name: name, password: password,
                                                          target: credential == nil ? target : nil)
                            password = ""
                            onSave(id)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (credential == nil && password.isEmpty))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 440)
        .disabled(saving).interactiveDismissDisabled(saving)
        .onAppear { name = credential?.name ?? "" }
        .onDisappear { password = "" }
    }
}
