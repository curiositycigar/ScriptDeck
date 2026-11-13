import Foundation

@MainActor func checkScriptClientVersion(root: URL) throws {
    let source = root.appendingPathComponent("versioned.sh")
    try """
    #!/bin/sh
    # scriptdeck: version = >=1.14.0 <2.0.0 || ~2.1.0
    exit 0
    # scriptdeck: version = 1.0.0
    """.write(to: source, atomically: true, encoding: .utf8)
    let requirement = try ScriptClientVersion.requirement(at: source.path)
    check(requirement == ">=1.14.0 <2.0.0 || ~2.1.0", "Only the script header supplies client version metadata")
    try ScriptClientVersion.check(requirement!, current: "1.14.0")
    try ScriptClientVersion.check(requirement!, current: "2.1.9")
    try ScriptClientVersion.check("1.14.0", current: "1.14.0")
    try ScriptClientVersion.check("^0.2.1", current: "0.2.9")
    for (range, current) in [(requirement!, "2.0.0"), ("1.14.0", "1.14.1"), ("^0.2.1", "0.3.0"),
                             ("1.14.0 ||", "1.14.0"), (">=1.14", "1.14.0")] {
        check((try? ScriptClientVersion.check(range, current: current)) == nil,
              "Rejects invalid or unmatched client requirement: \(range) for \(current)")
    }

    try "// scriptdeck: version = >=999999.0.0\nconsole.log('unexpected')\n"
        .write(to: source, atomically: true, encoding: .utf8)
    let runner = ProcessRunner()
    var item = ScriptItem.importing(source)
    item.interactiveUI = true
    let session = try runner.run(item: item, arguments: [])
    check(session.outcome == .launchFailed && !session.isRunning && session.showingTerminalLog,
          "Incompatible interactive scripts stop before interpreter launch and show Terminal Log")
    pump(until: { !session.hasPendingHistoryWrites })
}
