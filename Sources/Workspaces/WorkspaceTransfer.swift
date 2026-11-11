import Foundation

struct WorkspaceTransfer: Codable {
    private struct ScriptFile: Codable {
        let path: String
        let contents: Data
        let executable: Bool
    }

    static let fileExtension = "scriptdeck"

    static func isPackageURL(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
    }

    private var version = 1
    private var library: LibraryDocument
    private let files: [ScriptFile]

    init(store: ScriptStore, values: [String: [String: String]]) throws {
        var library = try store.exportDocument()
        guard let directory = store.directoryURL else { throw Self.invalidPackage }
        library.schema = nil
        var files: [ScriptFile] = []
        var pathsBySource: [String: String] = [:]
        for index in library.scripts.indices {
            var script = library.scripts[index]
            let resolved = store.resolved(script)
            let source = URL(fileURLWithPath: resolved.path).resolvingSymlinksInPath()
            if let path = pathsBySource[resolved.path] {
                script.path = path
            } else {
                guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw RunnerError(message: L("Unable to export the script file for “{0}”.", script.name))
                }
                let relative = Self.relativePath(resolved.path, in: directory)
                let path = relative.flatMap { Self.isScriptPath($0) ? $0 : nil }
                    ?? "scripts/\(UUID().uuidString)/\(source.lastPathComponent)"
                files.append(ScriptFile(path: path, contents: try Data(contentsOf: source),
                                        executable: FileManager.default.isExecutableFile(atPath: source.path)))
                pathsBySource[resolved.path] = path
                script.path = path
            }
            script.workingDirectory = Self.relativePath(resolved.workingDirectory, in: directory) ?? ""
            for parameterIndex in script.parameters.indices {
                var parameter = script.parameters[parameterIndex]
                let value = values[script.id]?[parameter.id] ?? parameter.defaultValue
                if !value.isEmpty && parameter.passing != .flag && (parameter.kind == .file || parameter.kind == .folder) {
                    parameter.defaultValue = Self.relativePath(store.resolvedParameterPath(value), in: directory) ?? ""
                } else {
                    parameter.defaultValue = value
                }
                script.parameters[parameterIndex] = parameter
            }
            library.scripts[index] = script
        }
        self.library = library
        self.files = files
        try validate()
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> WorkspaceTransfer {
        let package = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try package.validate()
        return package
    }

    func install(in parent: URL, named name: String) throws -> URL {
        try validate()
        guard Self.isRelativePath(name), !name.contains("/") else { throw Self.invalidPackage }
        let manager = FileManager.default
        let staging = parent.appendingPathComponent(".scriptdeck-import-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }

        var document = library
        document.schema = "library.schema.json"
        try document.encoded().write(to: staging.appendingPathComponent("library.json"), options: .withoutOverwriting)
        for file in files {
            let url = staging.appendingPathComponent(file.path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, options: .withoutOverwriting)
            if file.executable {
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        for script in document.scripts where !script.workingDirectory.isEmpty && script.workingDirectory != "." {
            try manager.createDirectory(at: staging.appendingPathComponent(script.workingDirectory),
                                        withIntermediateDirectories: true)
        }

        try WorkspaceGuidance.install(in: staging)

        var destination = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while manager.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        try manager.moveItem(at: staging, to: destination)
        return destination
    }

    private func validate() throws {
        guard version == 1 else { throw Self.invalidPackage }
        try library.validate()
        let paths = files.map(\.path)
        guard Set(paths).count == paths.count,
              paths.allSatisfy(Self.isScriptPath),
              Set(library.scripts.map(\.path)) == Set(paths),
              library.scripts.allSatisfy({
                  $0.workingDirectory.isEmpty || $0.workingDirectory == "." || Self.isRelativePath($0.workingDirectory)
              }) else { throw Self.invalidPackage }
    }

    private static func relativePath(_ path: String, in directory: URL) -> String? {
        if path == directory.path { return "." }
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let relative = String(path.dropFirst(prefix.count))
        return isRelativePath(relative) ? relative : nil
    }

    private static func isScriptPath(_ path: String) -> Bool {
        isRelativePath(path) && path.split(separator: "/").first?.lowercased() != "library.json"
    }

    private static func isRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("~") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static var invalidPackage: RunnerError {
        RunnerError(message: L("This workspace package is invalid or uses an unsupported version."))
    }
}
