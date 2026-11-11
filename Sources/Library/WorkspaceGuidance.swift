import Foundation

/// All files in the bundled Workspace directory are distributed together.
/// Add workspace-facing development guides there rather than maintaining a copy list.
enum WorkspaceGuidance {
    static func install(in directory: URL) throws {
        let manager = FileManager.default
        guard let guides = Bundle.module.url(forResource: "Workspace", withExtension: nil),
              let schema = Bundle.module.url(forResource: "library.schema", withExtension: "json"),
              let enumerator = manager.enumerator(at: guides, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw RunnerError(message: L("Workspace development guidance is missing from the app resources."))
        }
        var files: [(URL, URL)] = [(schema, directory.appendingPathComponent("library.schema.json"))]
        for case let source as URL in enumerator {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = source.path.dropFirst(guides.path.count + 1)
            files.append((source, directory.appendingPathComponent(String(relative))))
        }
        for (source, target) in files {
            // Never replace instructions customized by the workspace owner.
            if manager.fileExists(atPath: target.path) { continue }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try Data(contentsOf: source).write(to: target, options: .withoutOverwriting) }
            catch CocoaError.fileWriteFileExists { continue }
        }
    }
}
