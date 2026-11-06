# ScriptDeck

A native macOS app for organizing local scripts, running parallel interactive sessions, and scheduling background tasks.

## Install

Download the latest ZIP from [GitHub Releases](https://github.com/curiositycigar/ScriptDeck/releases/latest), extract it, and move **ScriptDeck.app** to Applications.

- macOS 13 or later. Release binaries currently support Apple Silicon (arm64).
- The app is ad hoc signed and is not notarized by Apple. If macOS blocks it, review it in **System Settings → Privacy & Security** before opening.
- Install any runtimes your scripts need, such as Python or Node.js.

## Get started

1. Click **Add Workspace…** (⌘O) and select the included `ExampleLibrary` folder or your own script folder.
2. Import scripts (⌘I), drag them into the sidebar, or create a script configuration. An empty folder can be initialized as a new library.
3. Select a script, fill in its parameters, and click **Run** (⌘Return).
4. Expand **Run Output** (⌘J) to switch between sessions, use the terminal, and browse execution history.

The interface supports **English** and **Simplified Chinese**, following the system by default. Change it in **Settings → General → App Language**, then quit and reopen the app. User-defined names, configuration values, and script output stay in their original language. All project documentation is in English.

## Features

- Independent workspaces with nested folders, search, script import, and configuration editing.
- Positional arguments, named arguments, boolean flags, file/folder pickers, and labeled selection options.
- Multiple simultaneous runs, each with its own interactive terminal, status, duration, and log. Interrupt and stop actions apply to the selected session.
- One-time, daily, weekly, and fixed-interval schedules backed by macOS `launchd`. Create them from **All Scheduled Tasks** or **Schedule…** on a script's run bar.
- Menu bar access. Closing the window keeps the app running; scheduled tasks can also run after the app quits.
- Local execution history with filters, paginated logs, export, and deletion. Removing a completed session from the output list preserves its history.

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

`file` and `cwd` resolve relative to the workspace; omitted `cwd` uses the script's folder. Supported interpreters include Bash, Zsh, Python, Node.js, `direct` (shebang), and an absolute executable path. Arguments are passed separately, in configuration order. See the [schema](Resources/library.schema.json) and [script authoring guide](ExampleLibrary/AI-INSTRUCTIONS.md) for all fields and parameter styles.

External configuration edits are detected automatically. Invalid or conflicting edits produce a warning and preserve the last valid in-memory configuration. Importing a script from outside the library copies it into `scripts/`; removing a script configuration or workspace registration preserves the underlying files.

Logs and metadata are saved beside each script in `logs/<script filename>/`. Log creation must succeed before execution starts. History deletion permanently removes the corresponding `.log` and `.json` files after confirmation, skipping active or still-saving records. Arguments and keystrokes are not separately recorded, but script output and echoed input appear in logs. Avoid storing or printing passwords.

Schedule definitions and the standalone helper live in `~/Library/Application Support/ScriptDeck/Schedules/`; LaunchAgent files live in `~/Library/LaunchAgents/com.lucasyou.ScriptDeck.schedule.<ID>.plist`. Moving the app does not invalidate existing schedules. Moving scripts requires updating their schedules.

## Build

Use Xcode or Command Line Tools with Swift 6.3 or later. Dependencies are pinned in `Package.resolved`; the first build needs network access.

```bash
bash package.sh  # Build, ad hoc sign, and create the release ZIP
bash test.sh     # Run self-checks with temporary fixtures
```

Outputs are `dist/ScriptDeck.app` and `dist/ScriptDeck-<version>.zip`. Packaging includes the app, example library, and English documentation. It does not launch scripts or install schedules.

See [Architecture](Docs/Architecture.md) for maintenance and testing details, [Localization](Docs/Localization.md) for translation guidance, and [Icon Design](Docs/Icon-design.md) for icon assets.
