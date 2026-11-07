import Foundation
import Combine
import Security

struct CredentialTarget: Codable, Equatable {
    let workspaceID: String
    let scriptID: String
}

struct SavedCredential: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var scripts: [CredentialTarget] = []
}

protocol SecretVault: Sendable {
    func save(_ password: String, id: String) throws
    func read(id: String) throws -> String
    func remove(id: String) throws
}

struct KeychainSecretVault: SecretVault {
    var service = "ScriptDeck.ScriptCredentials"

    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    func save(_ password: String, id: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(id)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "ScriptDeck Credential"
            try validate(SecItemAdd(attributes as CFDictionary, nil))
        } else { try validate(status) }
    }

    func read(id: String) throws -> String {
        var attributes = query(id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try validate(SecItemCopyMatching(attributes as CFDictionary, &result))
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw RunnerError(message: L("Unable to read this credential from Keychain."))
        }
        return password
    }

    func remove(id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        if status != errSecItemNotFound { try validate(status) }
    }

    private func validate(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw RunnerError(message: L("Keychain operation failed ({0}).", "\(status)"))
        }
    }
}

@MainActor
final class CredentialStore: ObservableObject {
    static let shared = CredentialStore()
    @Published private(set) var items: [SavedCredential]
    @Published private(set) var busy = false
    private let preferences: UserDefaults
    private let vault: any SecretVault
    private let storageKey = "scriptCredentialMetadata"

    init(preferences: UserDefaults = .standard, vault: any SecretVault = KeychainSecretVault()) {
        self.preferences = preferences
        self.vault = vault
        items = preferences.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([SavedCredential].self, from: $0) } ?? []
    }

    static func validatePassword(_ password: String) throws {
        guard !password.isEmpty, !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw RunnerError(message: L("Enter a password without line breaks or control characters."))
        }
    }

    @discardableResult
    func save(id: String? = nil, name: String, password: String, target: CredentialTarget? = nil) async throws -> String {
        guard !busy else { throw RunnerError(message: L("A credential operation is already in progress.")) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RunnerError(message: L("Enter a credential name.")) }
        let existing = items.first { $0.id == id }
        guard id == nil || existing != nil else {
            throw RunnerError(message: L("This credential is no longer available."))
        }
        if existing == nil || !password.isEmpty { try Self.validatePassword(password) }
        busy = true
        defer { busy = false }
        let credentialID = existing?.id ?? UUID().uuidString
        if existing == nil || !password.isEmpty {
            let vault = vault
            try await Task.detached { try vault.save(password, id: credentialID) }.value
        }
        var credential = existing ?? SavedCredential(id: credentialID, name: name)
        credential.name = name
        if let target, !credential.scripts.contains(target) { credential.scripts.append(target) }
        if let index = items.firstIndex(where: { $0.id == credentialID }) { items[index] = credential }
        else { items.append(credential) }
        persist()
        return credentialID
    }

    func associate(_ id: String, with target: CredentialTarget, enabled: Bool) {
        guard !busy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].scripts.removeAll { $0 == target }
        if enabled { items[index].scripts.append(target) }
        persist()
    }

    func password(for id: String) async throws -> String {
        guard items.contains(where: { $0.id == id }) else {
            throw RunnerError(message: L("This credential is no longer available."))
        }
        let vault = vault
        let password = try await Task.detached { try vault.read(id: id) }.value
        guard items.contains(where: { $0.id == id }) else {
            throw RunnerError(message: L("This credential is no longer available."))
        }
        return password
    }

    func remove(_ id: String) async throws {
        guard !busy else { throw RunnerError(message: L("A credential operation is already in progress.")) }
        busy = true
        defer { busy = false }
        let vault = vault
        try await Task.detached { try vault.remove(id: id) }.value
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        preferences.set(try? JSONEncoder().encode(items), forKey: storageKey)
    }
}
