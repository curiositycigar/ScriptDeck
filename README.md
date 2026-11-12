# ScriptDeck

**English** | [简体中文](README.zh-CN.md)

A native macOS app for organizing local scripts, running parallel interactive sessions, and scheduling background tasks.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/curiositycigar/ScriptDeck/releases/latest), open it, and drag **ScriptDeck.app** onto **Applications**. Eject the disk image after copying. A ZIP download is also available.

The DMG includes the example library and documentation in **Extras**. Copy `Extras/ExampleLibrary` to a writable folder, such as Documents, before adding it as a workspace. Each download includes a `.sha256` checksum file.

- macOS 13 or later. Release binaries currently support Apple Silicon (arm64).
- The app is ad hoc signed and is not notarized by Apple. If macOS blocks it, review it in **System Settings → Privacy & Security** before opening.
- Install any runtimes your scripts need, such as Python or Node.js.

## Interactive script UI

Scripts can drive a native panel with text, selectable lists, button rows, text/password inputs, local file/directory pickers, dropdowns, toggles, and progress indicators using a small Bot-style JSON protocol. Enable **Interactive UI** in the script editor, then switch between **Interactive UI** and **Terminal Log** in the execution window. Optional header/footer regions keep titles and actions fixed around the scrolling content. Hidden terminal input can open a native dialog for manual entry or saved Keychain credentials without script changes. No separate UI application is needed. The included **Interactive UI Demo** browses and deletes fictional files, and includes a basic-controls form with simulated progress. It does not change real files. See [Interactive script panels](Docs/Workspace/InteractiveUI.md) for the protocol and Shell/Python examples. Interactive UI scripts run manually and cannot be scheduled.

New and imported workspaces automatically receive `AGENTS.md`, `AI-INSTRUCTIONS.md`, `InteractiveUI.md`, and `library.schema.json` from the app. These local references help AI tools author scripts without access to the ScriptDeck source repository. Existing files are preserved.

## Get started

1. Open **Workspaces**, then click **Add Workspace…** (⌘O) and select the included `ExampleLibrary` folder or your own script folder.
2. Import scripts (⌘I), drag them into the sidebar, or create a script configuration. An empty folder can be initialized as a new library.
3. Select a script, fill in its parameters, and click **Run** (⌘Return).
4. Each run opens its own execution window. Close and reopen it from **Home → Running Tasks** to continue viewing output. **⌘J** reopens the last selected execution.
5. Star scripts to add them to **Home → Favorite Scripts**. The Home dashboard also shows running manual/background tasks and upcoming schedules. Browse completed results in **Logs**.

The interface supports **English** and **Simplified Chinese**, following the system by default. Change it in **Settings → General → App Language**, then quit and reopen the app. User-defined names, configuration values, and script output stay in their original language. This README is available in English and Simplified Chinese; other project documentation is in English.

## Sharing a workspace

Choose **File → Export Workspace Package…** to create a `.scriptdeck` file. It contains registered script files, their parameter definitions, and the values currently entered in the run form as defaults. The recipient drags the package into the main window or chooses **File → Import Workspace Package…**, then picks a location for a new workspace folder. Review your scripts and parameter values before sharing. The package excludes Keychain credentials, logs, schedules, parameter history, and files referenced only as inputs. Paths outside the workspace must be selected again, and the recipient needs any required runtimes and dependencies.

## Features

- Independent workspaces with nested folders, search, script import, and configuration editing. A fixed icon rail opens Home, Workspaces, Scheduled Tasks, Logs, and Settings. Switch or manage workspaces inside Workspaces. Use **⌘F** to focus script search and **⌘N** to create a script.
- Positional arguments, named arguments, boolean flags, file/folder pickers, and labeled selection options.
- Adaptive parameter forms fill the available width, size the label column automatically, and stack labels above fields in narrow panels. Required fields use `*`. File and folder inputs include a **Show in Finder** button; script details are in the information popover beside the script name.
- The history button beside Edit restores one of the last five distinct parameter calls per script and workspace; snapshots stay in local app preferences and can be cleared.
- Theme-aware system surfaces shared by the parameter view and terminal, with independent, resizable execution windows.
- **Allow Multiple Instances** in Script Configuration controls parallel execution per workspace and script. It defaults to off, including older configurations. Single-instance scripts open their current instance while running. Multi-instance scripts offer **Run Another Instance** and an instance chooser with start times, IDs, output, and stop controls. The limit covers Home, Workspaces, and scheduled executions. Conflicting scheduled occurrences are skipped and recorded in Logs.
- Multiple simultaneous runs, each with its own interactive terminal, status, duration, and log. Each window binds its interrupt, stop, and credential actions to its own session.
- One-time, daily, weekly, and fixed-interval schedules backed by macOS `launchd`. Create them from **Scheduled Tasks** or **Schedule…** on a script's run bar.
- Menu bar access. Closing the window keeps the app running; scheduled tasks can also run after the app quits.
- Local execution history with filters, paginated logs, export, and deletion, including clearing records older than 24 hours, seven days, or one calendar month. Live records can reopen their execution window. Closing a window preserves the task and its output.
- macOS Keychain password storage, local script associations, and explicit password filling into the window’s interactive session with **⇧⌘K**.

Scheduled tasks save a snapshot of the script configuration and parameters, run without keyboard input, and prevent overlapping instances of the same schedule. The Mac must be powered on and the user logged in. Tasks do not wake the Mac or run during sleep; at most one missed occurrence is caught up afterward. Pausing cancels future runs; stopping the current run is a separate action. Edit or delete a schedule after its active run ends.

## Script libraries

Each workspace is a folder containing `library.json` and your scripts:

```text
MyScripts/
├── library.json
├── library.schema.json
└── scripts/
    └── deploy.sh
```

```json
{
  "$schema": "library.schema.json",
  "version": 1,
  "scripts": [{
    "id": "deploy",
    "name": "Deploy",
    "group": "Deployment",
    "file": "scripts/deploy.sh",
    "interpreter": "/bin/bash",
    "parameters": [{
      "id": "environment",
      "label": "Environment",
      "type": "select",
      "required": true,
      "default": "staging",
      "options": ["staging", "production"]
    }]
  }]
}
```

Use **Editable Selection** in the parameter editor (JSON: `"type": "editableSelect"`) to choose a preset or type a custom value. Define `options` as for `select`; preset labels appear in the menu and their values are passed to the script. Typed values and custom defaults are accepted unchanged. This also works in scheduled task parameters. The existing `select` type continues to accept only predefined values.

`file` and `cwd` resolve relative to the workspace; omitted `cwd` uses the script's folder. Supported interpreters include Bash, Zsh, Python, Node.js, `direct` (shebang), and an absolute executable path. Arguments are passed separately, in configuration order. See the [schema](Resources/library.schema.json) and [script authoring guide](ExampleLibrary/AI-INSTRUCTIONS.md) for all fields and parameter styles.

You can give an AI coding assistant access to your workspace folder to create, edit, and organize scripts and their `library.json` configurations. Point it to the [script authoring guide](ExampleLibrary/AI-INSTRUCTIONS.md) for the configuration format.

External configuration edits are detected automatically. Invalid or conflicting edits produce a warning and preserve the last valid in-memory configuration. Importing a script from outside the library copies it into `scripts/`; removing a script configuration or workspace registration preserves the underlying files.

Logs and metadata are saved beside each script in `logs/<script filename>/`. Log creation must succeed before execution starts. History deletion permanently removes the corresponding `.log` and `.json` files after confirmation, skipping active or still-saving records. For individual records, select **Do not ask again** when confirming deletion to skip future single-record prompts; bulk clearing still requires confirmation. Each log starts with the assembled execution command, including the interpreter, script path, and shell-quoted arguments. Keystrokes are not separately recorded, but script output and echoed input appear in logs. Avoid putting passwords in script arguments or printing them.

Scheduled task cards use an adaptive grid with equal heights and bottom-aligned controls. Each card includes an execution-history button scoped to that task. New log metadata stores the schedule ID; older records can only be linked when the task still identifies its latest run. Clearing filtered results in this view only removes that task’s records.

The history **Clear** menu can remove filtered results, all loaded history, or records older than 24 hours, seven days, or one calendar month. Age is measured from each run's start time. Age-based cleanup applies across all loaded workspaces regardless of filters; confirmation shows the cutoff and record count. Logs lists execution records newest first. Select a record to read its saved log after reopening the app. Records with a retained session can also reopen their execution window.

Use the key button beside a script's name to save a password in macOS Keychain and associate it with that script. Settings → Credentials manages saved credentials; names and workspace/script associations stay in local app preferences, outside the script library. A credential can be associated with several scripts. In a running manual session, click the execution window’s key button or press **⇧⌘K**, select a credential, and choose **Fill Password**. Associated credentials appear first. The optional Return submits the input immediately. Filling requires the window’s original session to remain running, with terminal input echo disabled (for example, Bash `read -s`); scheduled background runs cannot receive input. Keychain may request system authorization. Filled passwords go directly to the PTY, without the clipboard or command arguments, but a script that prints the password can still expose it in output and logs.

While **Interactive UI** is selected, hidden terminal input can also open a dialog automatically. Choose **Enter manually** or a saved credential, then click **Send**; associated credentials appear first and Return is optional. Cancel does not repeatedly reopen the dialog: use **Enter Hidden Input…** in the notice to retry. Existing terminal password prompts require no script changes. See [Terminal hidden input and saved credentials](Docs/Workspace/InteractiveUI.md#terminal-hidden-input-and-saved-credentials) for the trigger conditions and usage.

Schedule definitions and the standalone helper live in `~/Library/Application Support/ScriptDeck/Schedules/`; LaunchAgent files live in `~/Library/LaunchAgents/com.lucasyou.ScriptDeck.schedule.<ID>.plist`. Moving the app does not invalidate existing schedules. Moving scripts requires updating their schedules.

## Build

Use Xcode or Command Line Tools with Swift 6.3 or later. Swift dependencies are pinned in `Package.resolved`; the first build needs network access. DMG packaging also requires Python 3 with pip and installs the pinned tools from `Scripts/dmg-requirements.txt` into `.build/dmg-python` on first use. Installer layout settings live in `Scripts/dmg-settings.py`.

```bash
bash package.sh  # Build, ad hoc sign, and create release ZIP and DMG files
bash test.sh     # Run self-checks with temporary fixtures
```

Outputs are `dist/ScriptDeck.app`, `dist/ScriptDeck-<version>.zip`, and `dist/ScriptDeck-<version>.dmg`, with a `.sha256` checksum file for each archive. The DMG provides an Applications shortcut for drag-to-install and places supporting files in Extras. Packaging includes the app, example library, both README languages, and English maintenance documentation. It does not launch scripts or install schedules.

`Resources/Info.plist` is the version source: `CFBundleShortVersionString` is the public version and `CFBundleVersion` is the build number. Update both manually for a release; building does not increment either value. The build copies this file into the app, and packaging uses the public version in the ZIP and DMG filenames.

See [Architecture](Docs/Architecture.md) for maintenance and testing, [Localization](Docs/Localization.md) for translations, [Icon Design](Docs/Icon-design.md) for icon assets, and [Interface Guidelines](Docs/Interface-guidelines.md) for typography, symbol sizes, and grouping.
