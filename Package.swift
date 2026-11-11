// swift-tools-version: 6.2
import PackageDescription
import Foundation

// The explicit self-check command builds the existing checks into the helper entry point.
let selfChecks = ProcessInfo.processInfo.environment["RUNNER_SELF_CHECKS"] == "1"

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let excludedPaths = ["Assets", "ExampleLibrary", "Scripts", "dist",
                     "README.md", "README.zh-CN.md", "AGENTS.md", "build.sh", "package.sh", "test.sh"].filter {
    FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent($0).path)
}

// Workspace authoring resources are also available in unbundled SwiftPM runs.
let documentationExclusions = ["Docs", "Resources"].flatMap { folder in
    (try? FileManager.default.contentsOfDirectory(atPath: packageRoot.appendingPathComponent(folder).path))?
        .filter { !(folder == "Docs" && $0 == "Workspace") && !(folder == "Resources" && $0 == "library.schema.json") }
        .map { folder + "/" + $0 } ?? []
}

let package = Package(
    name: "ScriptDeck",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.2", traits: [])
    ],
    targets: [
        .executableTarget(
            name: "ScriptDeck",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: ".",
            exclude: excludedPaths + documentationExclusions + (selfChecks ? [] : ["Tests"]),
            sources: selfChecks ? ["Sources", "Tests"] : ["Sources"],
            resources: [.process("Localization"), .copy("Docs/Workspace"), .copy("Resources/library.schema.json")],
            swiftSettings: [.swiftLanguageMode(.v5)] + (selfChecks ? [.define("SELF_TEST")] : [])
        )
    ]
)
