# Architecture and Maintenance

ScriptDeck is a single-module SwiftUI/AppKit macOS app built with Swift Package Manager. SwiftTerm provides the native interactive terminal; exact dependency versions are recorded in `Package.resolved`.

Build and self-check scripts explicitly select SwiftPM's native build system to preserve the executable and raw localization-resource layout expected by packaging and tests across Xcode versions, including Xcode 27.2's change of default build engine.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Sources/App/` | App composition, windows, menus, and helper entry points |
| `Sources/Models/` | Script, parameter, library, grouping, and execution data |
| `Sources/Library/` | Library persistence, import, validation, and external change detection |
| `Sources/Workspaces/` | Local workspace registry and per-workspace browsing state |
| `Sources/Interaction/` | Native interactive panels, Bot-style JSON protocol, and per-run helper mailboxes |
| `Sources/Execution/` | Argument validation, command construction, sessions, PTYs, and stop control |
| `Sources/Credentials/` | Keychain access, local credential metadata, script associations, and credential management UI |
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

The configuration pane presents one parameter per row with `*` markers for required values. `ParameterRowLayout` switches between measured label columns and stacked fields based on available width, preserving the same native inputs and aligning validation messages below them. The script-name information button opens a details popover with selectable paths and icon actions; path copying briefly displays a confirmation. Disclosure headers have enlarged hit areas and toggle from their names. The sidebar tree uses independent native list rows with explicit indentation and folder-state icons. The complete script split view remains mounted but hidden, disabled, and inaccessible during Scheduled Tasks; the dashboard fills the browser width. Switching back restores search, folder expansion and selection, native scroll positions, and parameter state without changing the sidebar visibility preference.

Typography, symbol sizes, and custom control hit areas are centralized in `WorkspaceTypography.swift`. Standalone screens establish the shared baseline with `workspaceTypography()`. See [Interface Guidelines](Interface-guidelines.md) for the scale, native-control exceptions, and minimal boundary rules.

Keep JSON operations in library/scheduling services and command construction in execution services. Update the models, canonical schema, example configuration, and documentation together when changing configuration fields. Extra JSON fields are not preserved by the app editor. Version and build numbers live in `Resources/Info.plist`.

## Workspaces and preferences

`WorkspaceStore` saves `workspaceRegistry.v1` in UserDefaults: stable IDs, display names, absolute folders, ordering, and selected workspace. Paths are standardized and symlinks resolved for duplicate detection. Registrations do not modify the library itself. Missing folders retain their registration for later relocation.

Each workspace lazily owns a `ScriptStore` and in-memory `WorkspaceSession`. Script selection and parameter values survive switching workspaces within the current app session, but parameter values are not persisted in preferences. Each loaded library independently monitors external changes and rejects conflicting saves.

Global preferences hold sidebar visibility, language, terminal font size, and scrollback size. Main and settings windows are singletons. `WorkspaceRootView` keeps the shared output panel outside the workspace browser. Workspace removal or relocation checks all active sessions for the affected workspace, including a second check when applying the change. Removal preserves files.

## Parallel execution and terminals

`ProcessRunner` manages independent `ExecutionSession` instances, the selected session, active record IDs, and pending log writes. There is no app-wide concurrency limit. Starting another task preserves the selected terminal if a task is already running. Every session can start only once and owns its PTY, terminal view, process state, signals, and log writer.

`RunnerTerminalView` uses SwiftTerm's terminal and `LocalProcess`; `EmbeddedTerminalView` mounts the persistent native view in SwiftUI. Collapsing output or switching sessions does not destroy terminals. Scrollback is configured when creating a session. Font size changes apply immediately.

The helper enters the requested directory and loads a login Zsh environment before executing the interpreter with separate argv values. User arguments are never concatenated into executable shell source. Ctrl+C follows terminal behavior; stop signals the root and current foreground process groups with TERM, and force stop uses KILL. Processes that detach from the session require separate management.

`TaskOutputView` merges current sessions with saved execution records by record ID and sorts them by start time. Current sessions retain their terminal buffers and process controls. Saved executions load a read-only, paginated log on selection. The task-list footer hides records until the app restarts and releases completed terminals after their logs finish saving. App quit is blocked by active manual sessions and waits for completed log writes. Background schedules run independently.

Interactive UI is opt-in per script via `interactiveUI`. Its per-session `InteractiveChannel` owns a private atomic-file mailbox and a main-run-loop timer. The bundled `--ui` helper exchanges one complete view for one action event without using the PTY for protocol traffic. `SessionOutputPane` switches between the native panel and the persistent terminal; UI tab preference, form strings, and selections belong to the execution. Native input, file/directory, select, toggle, and progress blocks extend the same protocol; all submitted values remain string arrays. File selection uses NSOpenPanel and applies results only to the originating active request. Optional block regions split the native panel into naturally sized fixed header/footer areas and a body that fills the remainder with one scroll container; unmarked blocks default to the body. Scripts own business state, pagination, and confirmation flows. Completion or stop cleans up the channel and leaves the final view disabled. See [Interactive script panels](Workspace/InteractiveUI.md) for the version-one format and examples.

SwiftTerm's MIT license is included in `Resources/ThirdPartyNotices.txt`. When upgrading it, update the exact package version, lockfile, notices, and toolchain requirements. PortableGraphics is disabled and unused dependencies are pruned; macOS uses native image support.

## Credentials

`CredentialStore` stores passwords as nonsynchronizing generic-password items in the macOS Keychain under the `ScriptDeck.ScriptCredentials` service, keyed by opaque UUIDs. Names and `(workspaceID, scriptID)` associations are encoded in local UserDefaults; neither secrets nor associations are added to library JSON, schedule definitions, or release packages. Secrets are retrieved only for an explicit fill action. Keychain operations run off the main actor; failed writes do not publish metadata, and edits with an empty password preserve the saved secret. Deleting a credential removes its Keychain item and local associations.

The script header and Settings expose credential management. Run Output captures a specific execution session when opening its credential sheet. `ProcessRunner` validates that the same manual session remains selected, running, and accepting input both before Keychain retrieval and immediately before sending. `tcgetattr` must report ECHO disabled; missing PTYs, completed tasks, switched records, and background schedules are rejected. Passwords cannot contain line breaks or terminal control characters. A fill sends UTF-8 bytes directly through SwiftTerm's PTY writer, optionally followed by Return, and checks the write result. It does not use the clipboard, command-line arguments, or log events. This does not prevent a script from explicitly printing its input. HiddenInputPromptController polls ECHO at 0.5-second intervals and offers one sheet per observed hidden-input interval for the selected interactive execution. The output must be expanded, the app active, and other sheets absent for automatic presentation. Cancelled prompts remain available via the pinned notice. HiddenInputPrompt supports manual input and associated-first Keychain selection, retrieving secrets only on explicit Send through HiddenInputSubmission and the existing validated PTY fill path. Changes of session, ECHO restoration, stopping, or terminal-tab selection dismiss the sheet; dismissal cancels pending Keychain submission before delivery.

## Logs and history

`RunLogWriter` creates `.log`/`.json` pairs in `logs/<original script filename>/` beside the script, using timestamps and UUIDs. Metadata includes workspace and script snapshots, times, outcome, exit code, and log filename; it omits command arguments. A log creation failure prevents execution. Later write failures appear in the output panel. Metadata is replaced atomically at completion.

Manual and scheduled logs begin with the actual interpreter, script path, and arguments, formatted with shell quoting. Manual sessions display the same command in the terminal before other execution events. PTY output is delivered in order to both the terminal parser and the log writer. Keystrokes go only to the PTY. `PlainLogDecoder` filters ANSI sequences across chunks, preserves UTF-8 byte order, and turns carriage-return progress updates into new lines. Disk logging uses a serial queue and is independent of terminal scrollback. Terminal export represents the active buffer; persistent logs represent the complete filtered stream.

`HistoryDirectories` indexes log locations in UserDefaults. `HistoryViewModel` also discovers logs for currently configured scripts, validates same-directory `.log` paths, deduplicates UUIDs, and sorts by start time. Logs use 256 KiB pages with UTF-8 boundary handling. Generation checks discard stale asynchronous responses. Nonactive records left with a running outcome are shown as interrupted.

History supports workspace/script filters, search, refresh, pagination, and Finder access. The Clear menu offers filtered results, all loaded history, and records started before cutoffs of 24 hours, seven elapsed days, or one calendar month. Age-based actions operate across loaded workspaces regardless of current filters, use a strict start-time comparison, and capture their cutoff and target list for confirmation. Permanent deletion requires confirmation, validates paths and record identity, skips active or saving records, and reports partial failures. Removing a session or workspace does not delete logs.

## System scheduling

`ScheduleStore` saves configuration and parameter snapshots under Application Support. `LaunchAgentService` installs a fixed-path helper and registers independent jobs in the current user's GUI domain using `launchctl bootstrap/bootout`. Calendar rules use `StartCalendarInterval`; fixed intervals use `StartInterval`. A 60-second reconciliation also handles full dates, time zones, and missed calendar occurrences. `RunAtLoad` enables at most one catch-up after login.

`EntryPoint --run-schedule <definition>` runs without creating NSApplication or a window. `ScheduleExecutor` holds a per-task `flock`, atomically consumes the occurrence, and starts a separate process group through `--execute-script`. It merges stdout/stderr into existing log/history files and uses null standard input rather than a PTY. A one-time task is consumed before launch and is not automatically retried after failure.

Definitions, runtime state, and stop requests are separate files. JSON dates use milliseconds since the epoch. Files are written through 0600 temporary files and atomic replacement; lock files keep a stable inode. UI recovery and background writes share the same lock. Invalid runtime state prevents execution to avoid duplicate side effects. Stop requests match the execution record ID and can escalate TERM to KILL.

The app refreshes task state every second, imports the most recent background run into `ProcessRunner`, and tails its read-only log. Earlier runs remain in history. Imported sessions participate in workspace and history deletion protection. If a completion transition was missed, history metadata supplies its result. The menu bar summarizes running tasks, enabled schedules, failures, and the next occurrence.

The Mac must be on and the user logged in; scheduling does not wake a sleeping Mac. Calendar rules preserve their configured time zone. Pause cancels future runs, while the current run continues. Editing/deleting requires the active run to finish. Build and packaging never register jobs.

## Build and validation

Use Swift 6.3 or later. `bash package.sh` builds, signs, and packages without running the app or tests. `bash test.sh` explicitly builds self-checks with `RUNNER_SELF_CHECKS=1` and runs temporary fixtures. Build caches remain inside `.build/`.

Release versions are maintained manually in `Resources/Info.plist`: update `CFBundleShortVersionString` and increment `CFBundleVersion` before packaging. `Scripts/build.sh` copies the plist into the application bundle; `Scripts/package.sh` reads the public version for the archive name. Before publishing with `gh`, verify the archived plist, code signature, ZIP integrity, public example allowlist, private-file exclusions, and SHA-256 checksum. Release assets contain the versioned ZIP and its checksum file.

Tests normally simulate system services. `RUNNER_TEST_LAUNCHD=1 bash test.sh` additionally registers, triggers, and unloads a temporary real LaunchAgent; it requires access to the current user's GUI domain. `RUNNER_TEST_KEYCHAIN=1 bash test.sh` verifies real Keychain add/read/update/delete operations in an isolated service and cleans up its fixture. Ordinary credential tests use an in-memory vault plus temporary PTY scripts. `RUNNER_CAPTURE_UI=1` captures native layout images in `/tmp`. No test should run a user's real scripts or register their schedules.

See [Localization](Localization.md) for string resources, language selection, and translation checks.

## Workspace development guidance

`Docs/Workspace/` is the canonical source for workspace-facing authoring guides, including the AI entry point and interactive UI protocol. SwiftPM copies the entire directory and `Resources/library.schema.json` into the resource bundle; the App build includes that bundle. `WorkspaceGuidance` installs every bundled guide and the schema when initializing or importing a workspace, without replacing existing files. A missing resource is an error rather than a silently incomplete initialization. Add future workspace development documents to this directory so they automatically ship and install. The checked-in ExampleLibrary guide copies must match these canonical files; release packaging also refreshes them from the canonical directory. App-internal architecture, icon, and interface maintenance documents remain in `Docs/`.
