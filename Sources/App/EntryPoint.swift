import Foundation
import Darwin

@main
enum EntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--ui" {
            guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--action-only") else {
                FileHandle.standardError.write(Data("Usage: ScriptDeck --ui [--action-only] < view.json\n".utf8))
                exit(2)
            }
            exit(InteractiveClient.run(actionOnly: CommandLine.arguments.contains("--action-only")))
        }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--run-schedule" {
            do { try ScheduleExecutor.run(definitionURL: URL(fileURLWithPath: CommandLine.arguments[2])) }
            catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
            return
        }
        if CommandLine.arguments.count >= 4 && CommandLine.arguments[1] == "--execute-script" {
            if setpgid(0, 0) != 0 && getpgrp() != getpid() {
                FileHandle.standardError.write(Data(L("Unable to create the script process group.\n").utf8))
                exit(126)
            }
            let arguments = ["/bin/zsh", "-l", "-c", "cd -- \"$1\" && shift && exec \"$@\"", "scriptdeck"] + Array(CommandLine.arguments.dropFirst(2))
            var pointers = arguments.map { strdup($0) } + [nil]
            execv("/bin/zsh", &pointers)
            FileHandle.standardError.write(Data(L("Unable to start the interpreter: {0}\n", "\(String(cString: strerror(errno)))").utf8))
            exit(126)
        }
        #if SELF_TEST
        runSelfTests()
        #else
        ScriptRunnerApp.main()
        #endif
    }
}
