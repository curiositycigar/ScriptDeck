# Script Library Authoring Guide

Each workspace corresponds to an independent folder. Do not add machine-specific workspace IDs or registration data to its library configuration.

Write scripts in `scripts/` and configure them in `library.json`. ScriptDeck detects configuration changes automatically. See `library.schema.json` for field constraints.

1. Use UTF-8. JSON must not contain comments or trailing commas.
2. The document format is `{"version":1,"scripts":[...]}`. Preserve existing entries and unrelated content. Keep `$schema` for editor validation.
3. Scripts require `id`, `name`, and `file`. Use stable readable IDs such as `database-backup`; preserve them when renaming. Parameter IDs must be unique within each script.
4. Resolve `file` and `cwd` relative to this folder. Omitted `cwd` uses the script's folder; `cwd: "."` uses the library root. Prefer relative paths for portability.
5. Separate nested groups with `/`, such as `Operations/Backups`. Optional `folders` entries preserve empty sidebar folders.
6. Interpreters include `/bin/bash`, `/bin/zsh`, `python3`, `node`, `direct`, or an absolute executable path. Direct execution requires a valid shebang and execute permission.
7. Manual runs use the app's interactive terminal and support prompts and hidden password input. The deprecated `execution` field is unnecessary. Scheduled scripts must work unattended with null standard input.
8. Parameters follow array order. Each needs `id` and `label`; `type` is `text`, `file`, `folder`, `select`, or `editableSelect`. `required` defaults to false. Positional arguments cannot skip an empty argument before a later nonempty one.
9. Select options can be objects such as `{"label":"Production","value":"production"}` or strings. The app displays labels and passes values. Values must be nonempty and unique; a `select` default must match an option value. Use `editableSelect` for a text field with a preset menu: it requires options but accepts custom input and custom defaults. Selecting a preset passes its value; typed text is passed unchanged.
10. Use `passing: "named"` with `argumentName: "--output"` for named arguments. `argumentFormat` is `separated` (default) or `equals`. Use `passing: "flag"` for a switch that passes only its name when enabled; its default is `true`, `false`, or empty.
11. Return zero on success and nonzero on failure. Print useful progress, flush output for long tasks, and quote arguments correctly. Do not store passwords in defaults or print them in logs.
12. Do not automatically execute scripts after editing configuration. The user chooses when to run them in the app.

Example request:

> Add a log archival script in Operations/Logs with a folder picker and a compression selection defaulting to gzip. Update library.json without running the script.

The app automatically saves execution output under `logs/<script filename>/` beside each script, retaining the filename extension. Do not duplicate the app's logging infrastructure. Use **History** in the output panel to inspect each run.

## Private configuration

Never commit real server addresses, account names, deployment directories, passwords, tokens, or private keys in shared scripts or library configuration. Keep private scripts outside the public example library and keep host details in `~/.ssh/config`. Use SSH keys or the SSH agent for authentication.

When using version control or sharing a workspace, exclude `.env`, `.env.*`, `.private/`, and `logs/`. ScriptDeck workspace exports include registered scripts, not arbitrary private files. Keep actual credentials outside the project even when these exclusions exist. Script output can still disclose private information in local run logs.

## Native interactive panels

Set `"interactiveUI": true` for manually run scripts that use the bundled `SCRIPTDECK_UI` executable with `--ui`. Send a complete `blocks` JSON document on stdin and read the callback JSON on stdout. Supported block types are `text`, `list`, `buttons`, `input`, `file`, `select`, `toggle`, and `progress`. Optional block `region` fixes content in `header` or `footer`; unmarked blocks belong to the remaining scrollable `body`. Use text `style` for hierarchy, list item `detail` for metadata, and button `style`, `disabled`, and `requiresSelection` for action states. Inputs submit string arrays in `values` when a button is clicked. File controls select local paths; scripts provide remote lists. Progress-only views return immediately. Terminal hidden input can use the app's automatic manual/Keychain dialog without script changes. Keep ordinary diagnostic output separate and never print password values. See [Interactive UI protocol](InteractiveUI.md) for the complete protocol and Shell/Python examples. Interactive UI scripts cannot be scheduled.

## Terminal passwords and saved credentials

Interactive UI scripts can keep their existing terminal password prompts. The app detects disabled terminal echo and offers a native dialog with manual masked input or saved Keychain credentials; no additional protocol blocks, credential IDs, or script changes are needed. Users explicitly choose Send and whether to append Return. After cancellation, the pinned notice can reopen the dialog. The same selected execution must still be running with echo disabled when input is delivered.

Save and associate credentials through the app, never through workspace JSON or script defaults. Do not replace ordinary terminal authentication with a `secure` form field merely to obtain credential filling: form inputs return in JSON, while terminal hidden input goes directly to the PTY. See [Terminal hidden input and saved credentials](InteractiveUI.md#terminal-hidden-input-and-saved-credentials) for setup, trigger conditions, and limitations.
