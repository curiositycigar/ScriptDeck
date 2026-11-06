# Architecture and Maintenance

ScriptDeck is a single-module SwiftUI/AppKit macOS app built with Swift Package Manager. SwiftTerm provides the native interactive terminal; exact dependency versions are recorded in `Package.resolved`.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Sources/App/` | App composition, windows, menus, and helper entry points |
| `Sources/Models/` | Script, parameter, library, grouping, and execution data |
| `Sources/Library/` | Library persistence, import, validation, and external change detection |
| `Sources/Workspaces/` | Local workspace registry and per-workspace browsing state |
| `Sources/Execution/` | Argument validation, command construction, sessions, PTYs, and stop control |
| `Sources/History/` | Streaming logs, ANSI filtering, metadata, discovery, pagination, and deletion |
| `Sources/Scheduling/` | Schedule rules, atomic storage, LaunchAgents, background execution, and management UI |
| `Sources/Preferences/` | Persistent app preferences |
| `Sources/Localization/` | Language selection, lookup, interpolation, and date formatting |
| `Sources/Views/` | Runner, terminal, editor, history, settings, and shared views |
| `Sources/Support/` | Shared errors and native path/workspace dialogs |
| `Localization/` | English and Simplified Chinese string tables |
| `Resources/` | App metadata, canonical library schema, and third-party notices |
| `Assets/` | Icon source images and generated ICNS |
| `Scripts/` | Build, packaging, testing, and icon tools |
| `Tests/` | Explicit self-checks and regression checks |
| `ExampleLibrary/` | Sample library, scripts, and authoring guide |
| `Docs/` | Maintenance and design documentation |

Root shell scripts forward to `Scripts/`. `.build/` and `dist/` are generated and ignored by Git. The project has its own repository and does not depend on its parent directory.

## Responsibility boundaries

`ScriptRunnerApp` composes `WorkspaceStore`, `AppPreferences`, `ProcessRunner`, and `ScheduleStore`. `EntryPoint` routes helper modes before starting SwiftUI. Models validate and encode configuration without depending on views or process management. Library and execution services own filesystem and process operations; views call those services.

`RunnerView.swift` owns browsing state, layout, and lifecycle. Its extensions separate workspace actions, navigation, configuration, and execution actions while sharing internal state. Extract reusable controls as independent views with values, bindings, or callbacks.

Keep JSON operations in library/scheduling services and command construction in execution services. Update the models, canonical schema, example configuration, and documentation together when changing configuration fields. Extra JSON fields are not preserved by the app editor. Version and build numbers live in `Resources/Info.plist`.

## Workspaces and preferences

`WorkspaceStore` saves `workspaceRegistry.v1` in UserDefaults: stable IDs, display names, absolute folders, ordering, and selected workspace. Paths are standardized and symlinks resolved for duplicate detection. Registrations do not modify the library itself. Missing folders retain their registration for later relocation.

Each workspace lazily owns a `ScriptStore` and in-memory `WorkspaceSession`. Script selection and parameter values survive switching workspaces within the current app session, but parameter values are not persisted in preferences. Each loaded library independently monitors external changes and rejects conflicting saves.

Global preferences hold sidebar visibility, language, terminal font size, and scrollback size. Main and settings windows are singletons. `WorkspaceRootView` keeps the shared output panel outside the workspace browser. Workspace removal or relocation checks all active sessions for the affected workspace, including a second check when applying the change. Removal preserves files.

## Parallel execution and terminals

`ProcessRunner` manages independent `ExecutionSession` instances, the selected session, active record IDs, and pending log writes. There is no app-wide concurrency limit. Starting another task preserves the selected terminal if a task is already running. Every session can start only once and owns its PTY, terminal view, process state, signals, and log writer.

`RunnerTerminalView` uses SwiftTerm's terminal and `LocalProcess`; `EmbeddedTerminalView` mounts the persistent native view in SwiftUI. Collapsing output or switching sessions does not destroy terminals. Scrollback is configured when creating a session. Font size changes apply immediately.

The helper enters the requested directory and loads a login Zsh environment before executing the interpreter with separate argv values. User arguments are never concatenated into executable shell source. Ctrl+C follows terminal behavior; stop signals the root and current foreground process groups with TERM, and force stop uses KILL. Processes that detach from the session require separate management.

`TaskOutputView` displays running and completed tasks beside the selected terminal. Duration freezes on completion. Removing a completed session releases its terminal after logs finish saving and preserves history. Actions apply only to the selected session. App quit is blocked by active manual sessions and waits for completed log writes; background schedules run independently.

SwiftTerm's MIT license is included in `Resources/ThirdPartyNotices.txt`. When upgrading it, update the exact package version, lockfile, notices, and toolchain requirements. PortableGraphics is disabled and unused dependencies are pruned; macOS uses native image support.

## Logs and history

`RunLogWriter` creates `.log`/`.json` pairs in `logs/<original script filename>/` beside the script, using timestamps and UUIDs. Metadata includes workspace and script snapshots, times, outcome, exit code, and log filename; it omits command arguments. A log creation failure prevents execution. Later write failures appear in the output panel. Metadata is replaced atomically at completion.

PTY output is delivered in order to both the terminal parser and the log writer. Keystrokes go only to the PTY. `PlainLogDecoder` filters ANSI sequences across chunks, preserves UTF-8 byte order, and turns carriage-return progress updates into new lines. Disk logging uses a serial queue and is independent of terminal scrollback. Terminal export represents the active buffer; persistent logs represent the complete filtered stream.

`HistoryDirectories` indexes log locations in UserDefaults. `HistoryViewModel` also discovers logs for currently configured scripts, validates same-directory `.log` paths, deduplicates UUIDs, and sorts by start time. Logs use 256 KiB pages with UTF-8 boundary handling. Generation checks discard stale asynchronous responses. Nonactive records left with a running outcome are shown as interrupted.

History supports workspace/script filters, search, refresh, pagination, and Finder access. Permanent deletion requires confirmation, validates paths and record identity, skips active or saving records, and reports partial failures. Clearing a terminal or removing a workspace does not delete logs.

## System scheduling

`ScheduleStore` saves configuration and parameter snapshots under Application Support. `LaunchAgentService` installs a fixed-path helper and registers independent jobs in the current user's GUI domain using `launchctl bootstrap/bootout`. Calendar rules use `StartCalendarInterval`; fixed intervals use `StartInterval`. A 60-second reconciliation also handles full dates, time zones, and missed calendar occurrences. `RunAtLoad` enables at most one catch-up after login.

`EntryPoint --run-schedule <definition>` runs without creating NSApplication or a window. `ScheduleExecutor` holds a per-task `flock`, atomically consumes the occurrence, and starts a separate process group through `--execute-script`. It merges stdout/stderr into existing log/history files and uses null standard input rather than a PTY. A one-time task is consumed before launch and is not automatically retried after failure.

Definitions, runtime state, and stop requests are separate files. JSON dates use milliseconds since the epoch. Files are written through 0600 temporary files and atomic replacement; lock files keep a stable inode. UI recovery and background writes share the same lock. Invalid runtime state prevents execution to avoid duplicate side effects. Stop requests match the execution record ID and can escalate TERM to KILL.

The app refreshes task state every second, imports the most recent background run into `ProcessRunner`, and tails its read-only log. Earlier runs remain in history. Imported sessions participate in workspace and history deletion protection. If a completion transition was missed, history metadata supplies its result. The menu bar summarizes running tasks, enabled schedules, failures, and the next occurrence.

The Mac must be on and the user logged in; scheduling does not wake a sleeping Mac. Calendar rules preserve their configured time zone. Pause cancels future runs, while the current run continues. Editing/deleting requires the active run to finish. Build and packaging never register jobs.

## Build and validation

Use Swift 6.3 or later. `bash package.sh` builds, signs, and packages without running the app or tests. `bash test.sh` explicitly builds self-checks with `RUNNER_SELF_CHECKS=1` and runs temporary fixtures. Build caches remain inside `.build/`.

Tests normally simulate system services. `RUNNER_TEST_LAUNCHD=1 bash test.sh` additionally registers, triggers, and unloads a temporary real LaunchAgent; it requires access to the current user's GUI domain. `RUNNER_CAPTURE_UI=1` captures native layout images in `/tmp`. No test should run a user's real scripts or register their schedules.

See [Localization](Localization.md) for string resources, language selection, and translation checks.
