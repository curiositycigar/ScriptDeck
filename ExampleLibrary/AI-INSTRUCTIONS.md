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
8. Parameters follow array order. Each needs `id` and `label`; `type` is `text`, `file`, `folder`, or `select`. `required` defaults to false. Positional arguments cannot skip an empty argument before a later nonempty one.
9. Select options can be objects such as `{"label":"Production","value":"production"}` or strings. The app displays labels and passes values. Values must be nonempty and unique; a default must match an option value.
10. Use `passing: "named"` with `argumentName: "--output"` for named arguments. `argumentFormat` is `separated` (default) or `equals`. Use `passing: "flag"` for a switch that passes only its name when enabled; its default is `true`, `false`, or empty.
11. Return zero on success and nonzero on failure. Print useful progress, flush output for long tasks, and quote arguments correctly. Do not store passwords in defaults or print them in logs.
12. Do not automatically execute scripts after editing configuration. The user chooses when to run them in the app.

Example request:

> Add a log archival script in Operations/Logs with a folder picker and a compression selection defaulting to gzip. Update library.json without running the script.

The app automatically saves execution output under `logs/<script filename>/` beside each script, retaining the filename extension. Do not duplicate the app's logging infrastructure. Use **History** in the output panel to inspect each run.

## Private configuration

Never commit real server addresses, account names, deployment directories, passwords, tokens, or private keys in shared scripts or library configuration. Keep private scripts outside the public example library and keep host details in `~/.ssh/config`. Use SSH keys or the SSH agent for authentication.

`.env`, `.env.*`, and `.private/` are ignored by Git and excluded from release packages. Keep actual credentials outside the project even when these exclusions exist. Script output can still disclose private information in local run logs.
