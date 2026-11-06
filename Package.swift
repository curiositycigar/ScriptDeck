// swift-tools-version: 6.2
import PackageDescription
import Foundation

// The explicit self-check command builds the existing checks into the helper entry point.
let selfChecks = ProcessInfo.processInfo.environment["RUNNER_SELF_CHECKS"] == "1"

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let excludedPaths = ["Assets", "Docs", "ExampleLibrary", "Resources", "Scripts", "dist",
                     "README.md", "build.sh", "package.sh", "test.sh"].filter {
    FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent($0).path)
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
            exclude: excludedPaths + (selfChecks ? [] : ["Tests"]),
            sources: selfChecks ? ["Sources", "Tests"] : ["Sources"],
            resources: [.process("Localization")],
            swiftSettings: [.swiftLanguageMode(.v5)] + (selfChecks ? [.define("SELF_TEST")] : [])
        )
    ]
)
