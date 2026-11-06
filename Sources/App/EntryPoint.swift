import Foundation
import Darwin

@main
enum EntryPoint {
    @MainActor static func main() {
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
                FileHandle.standardError.write(Data("无法创建脚本进程组。\n".utf8))
                exit(126)
            }
            let arguments = ["/bin/zsh", "-l", "-c", "cd -- \"$1\" && shift && exec \"$@\"", "scriptdeck"] + Array(CommandLine.arguments.dropFirst(2))
            var pointers = arguments.map { strdup($0) } + [nil]
            execv("/bin/zsh", &pointers)
            FileHandle.standardError.write(Data("无法启动解释器：\(String(cString: strerror(errno)))\n".utf8))
            exit(126)
        }
        #if SELF_TEST
        runSelfTests()
        #else
        ScriptRunnerApp.main()
        #endif
    }
}
