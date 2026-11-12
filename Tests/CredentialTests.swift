import Foundation
import AppKit
import SwiftUI

private final class TestSecretVault: SecretVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    var failWrites = false

    func save(_ password: String, id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failWrites { throw RunnerError(message: "Simulated vault failure") }
        values[id] = password
    }
    func read(id: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let password = values[id] else { throw RunnerError(message: "Missing test credential") }
        return password
    }
    func remove(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: id)
    }
}

@MainActor func runCredentialSelfTests(root: URL) throws {
    let suite = "ScriptDeck.CredentialTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let vault = TestSecretVault()
    let store = CredentialStore(preferences: defaults, vault: vault)
    let target = CredentialTarget(workspaceID: "workspace-one", scriptID: "same-script")
    let other = CredentialTarget(workspaceID: "workspace-two", scriptID: "same-script")
    var finished = false
    var failure: Error?
    Task { @MainActor in
        defer { finished = true }
        do {
            let secret = "credential-test-秘密 ' $()"
            let id = try await store.save(name: "Test password", password: secret, target: target)
            let restored = CredentialStore(preferences: defaults, vault: vault)
            let recovered = try await restored.password(for: id)
            check(recovered == secret && restored.items.first?.scripts == [target],
                  "Credentials restore metadata and retrieve their secret from the vault")
            let persisted = defaults.data(forKey: "scriptCredentialMetadata")!
            check(!String(decoding: persisted, as: UTF8.self).contains(secret) &&
                  !String(decoding: persisted, as: UTF8.self).contains("password\":"),
                  "Credential metadata never contains the password")
            store.associate(id, with: other, enabled: true)
            store.associate(id, with: target, enabled: false)
            check(store.items.first?.scripts == [other],
                  "Associations distinguish identical script IDs in different workspaces")
            try await store.save(id: id, name: "Renamed", password: "")
            let unchanged = try await store.password(for: id)
            check(unchanged == secret && store.items.first?.name == "Renamed",
                  "Renaming a credential with a blank password preserves its secret")
            try await store.save(id: id, name: "Renamed", password: "replacement")
            let updated = try await store.password(for: id)
            check(updated == "replacement", "Editing a credential updates the vault secret")
            for invalid in ["", "one\ntwo", "one\rtwo", "one\u{1b}two", "one\0two"] {
                do {
                    try CredentialStore.validatePassword(invalid)
                    check(false, "Invalid credential must be rejected")
                } catch { }
            }
            check(true, "Credential fills reject empty passwords and terminal control characters")
            vault.failWrites = true
            do {
                try await store.save(name: "Failed", password: "not-saved")
                check(false, "Vault failures must be reported")
            } catch { }
            check(store.items.count == 1, "Failed vault writes do not publish phantom credentials")
            try await store.remove(id)
            check(store.items.isEmpty && CredentialStore(preferences: defaults, vault: vault).items.isEmpty,
                  "Deleting a credential removes its metadata and associations")
            do {
                _ = try vault.read(id: id)
                check(false, "Deleted vault secret must be absent")
            } catch { }
        } catch { failure = error }
    }
    pump(until: { finished })
    if let failure { throw failure }

    if ProcessInfo.processInfo.environment["RUNNER_TEST_KEYCHAIN"] == "1" {
        let keychain = KeychainSecretVault(service: "ScriptDeck.SelfChecks.\(UUID())")
        let id = UUID().uuidString
        defer { try? keychain.remove(id: id) }
        try keychain.save("temporary-keychain-fixture", id: id)
        let initial = try keychain.read(id: id)
        check(initial == "temporary-keychain-fixture", "Real Keychain stores and retrieves an isolated fixture")
        try keychain.save("updated-keychain-fixture", id: id)
        let updated = try keychain.read(id: id)
        check(updated == "updated-keychain-fixture", "Real Keychain updates a saved fixture")
        try keychain.remove(id: id)
        do {
            _ = try keychain.read(id: id)
            check(false, "Deleted Keychain fixture must be absent")
        } catch { }
        check(true, "Real Keychain deletes the isolated fixture")
    }

    let scriptURL = root.appendingPathComponent("credential-input.sh")
    try """
    #!/bin/bash
    printf 'VISIBLE_INPUT_READY\n'
    read -r visible
    IFS= read -r -s -p 'HIDDEN_INPUT_READY' secret
    if [ "$secret" = 'fixture-secret-密码' ]; then printf '\nCREDENTIAL_ACCEPTED\n'; else exit 1; fi
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    var item = ScriptItem()
    item.path = scriptURL.path
    let runner = ProcessRunner(preferences: AppPreferences(preferences: defaults))
    let session = try runner.run(item: item, arguments: [], workspaceID: target.workspaceID)
    pump(until: { session.output.contains("VISIBLE_INPUT_READY") })
    do {
        try runner.validateCredentialTarget(session.id)
        check(false, "Visible input must refuse a credential fill")
    } catch { }
    check(true, "Credential fills refuse terminals with input echo enabled")
    session.terminalView.process.send(data: Array("continue\r".utf8)[...])
    pump(until: { session.terminalView.isInputEchoDisabled && session.output.contains("HIDDEN_INPUT_READY") })
    do {
        try runner.validateCredentialTarget(UUID())
        check(false, "A stale target must refuse a credential fill")
    } catch { }
    check(true, "Credential fills reject a different execution record")
    if ProcessInfo.processInfo.environment["RUNNER_CAPTURE_UI"] == "1" {
        finished = false
        failure = nil
        vault.failWrites = false
        Task { @MainActor in
            defer { finished = true }
            do { try await store.save(name: "Test SSH Password", password: "layout-fixture", target: target) }
            catch { failure = error }
        }
        pump(until: { finished })
        if let failure { throw failure }
        let view = CredentialManagerView(runner: runner, target: target, scriptName: "Credential input test", session: session, store: store)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/credential-manager-layout.png"))
        }
        window.contentView = nil
    }
    finished = false
    failure = nil
    Task { @MainActor in
        defer { finished = true }
        do {
            vault.failWrites = false
            let id = try await store.save(name: "Hidden input fixture", password: "fixture-secret-密码", target: target)
            try await HiddenInputSubmission.send(credentialID: id, password: "", appendReturn: false,
                                                 runner: runner, sessionID: session.id, store: store)
        }
        catch { failure = error }
    }
    pump(until: { finished })
    if let failure { throw failure }
    check(session.isRunning, "Fill without Return leaves the password prompt awaiting submission")
    session.terminalView.process.send(data: [UInt8(13)][...])
    pump(until: { !session.isRunning })
    var logSaved = false
    runner.afterHistorySaved { logSaved = true }
    pump(until: { logSaved })
    let logs = try FileManager.default.contentsOfDirectory(at: RunLogWriter.directory(for: scriptURL), includingPropertiesForKeys: nil)
    let log = try String(contentsOf: logs.first { $0.pathExtension == "log" }!, encoding: .utf8)
    check(session.outcome == .succeeded && session.output.contains("CREDENTIAL_ACCEPTED") &&
          !session.output.contains("fixture-secret-密码") && !log.contains("fixture-secret-密码"),
          "Hidden credential fills reach the script without entering terminal exports or logs")
    do {
        try runner.validateCredentialTarget(session.id)
        check(false, "Completed executions must refuse credential fills")
    } catch { }
    check(true, "Completed executions cannot receive a credential fill")

    let next = try runner.run(item: item, arguments: [], workspaceID: target.workspaceID)
    pump(until: { next.output.contains("VISIBLE_INPUT_READY") })
    next.terminalView.process.send(data: Array("continue\r".utf8)[...])
    pump(until: { next.terminalView.isInputEchoDisabled && next.output.contains("HIDDEN_INPUT_READY") })
    runner.select(session.id)
    try runner.validateCredentialTarget(next.id)
    check(runner.selectedSessionID == session.id,
          "A window-bound credential target remains valid when another session is selected")
    runner.select(next.id)
    finished = false
    failure = nil
    Task { @MainActor in
        defer { finished = true }
        do {
            try await HiddenInputSubmission.send(credentialID: "", password: "fixture-secret-密码", appendReturn: true,
                                                 runner: runner, sessionID: next.id, store: store)
        }
        catch { failure = error }
    }
    pump(until: { finished })
    if let failure { throw failure }
    pump(until: { !next.isRunning })
    check(next.outcome == .succeeded && next.output.contains("CREDENTIAL_ACCEPTED"),
          "Fill with Return submits the password to the selected hidden prompt")
    logSaved = false
    runner.afterHistorySaved { logSaved = true }
    pump(until: { logSaved })
}
