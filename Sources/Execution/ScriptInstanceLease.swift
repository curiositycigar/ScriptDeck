import Foundation
import CryptoKit
import Darwin

/// Shared locks allow parallel runs. Exclusive locks serialize a single-instance script.
/// Stable lock files are never removed, so other processes always lock the same inode.
final class ScriptInstanceLease {
    private let descriptor: Int32

    static var root: URL {
        #if SELF_TEST
        if let path = ProcessInfo.processInfo.environment["SCRIPTDECK_INSTANCE_ROOT"] {
            return URL(fileURLWithPath: path)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScriptDeck/Instances", isDirectory: true)
    }

    static func allowsMultipleInstances(for item: ScriptItem, workspaceDirectory: String?) throws -> Bool {
        guard let workspaceDirectory else { return item.allowsMultipleInstances }
        let url = URL(fileURLWithPath: workspaceDirectory).appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return item.allowsMultipleInstances }
        let library = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf: url))
        return library.scripts.first { $0.id == item.id }?.allowsMultipleInstances ?? item.allowsMultipleInstances
    }

    init(item: ScriptItem, workspaceID: String?, allowsMultipleInstances: Bool) throws {
        let identity = [workspaceID ?? "", workspaceID == nil
                        ? URL(fileURLWithPath: item.path).standardizedFileURL.resolvingSymlinksInPath().path : item.id]
        let hash = SHA256.hash(data: try JSONEncoder().encode(identity))
        let filename = hash.map { String(format: "%02x", $0) }.joined() + ".lock"
        let root = Self.root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(root.appendingPathComponent(filename).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw RunnerError(message: L("Unable to acquire the script instance lock.")) }
        guard flock(descriptor, (allowsMultipleInstances ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else {
            let issue = errno
            close(descriptor)
            if issue == EWOULDBLOCK { throw RunnerError(message: L("This script already has a running instance. Open its current instance to view progress.")) }
            throw RunnerError(message: L("Unable to acquire the script instance lock."))
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}
