# ScriptDeck Workspace Instructions

Read [AI-INSTRUCTIONS.md](AI-INSTRUCTIONS.md) before creating or modifying scripts or `library.json`.

- Use [library.schema.json](library.schema.json) for configuration fields and constraints.
- For native interactive scripts, read [InteractiveUI.md](InteractiveUI.md) for the complete protocol, lifecycle rules, limits, and Shell/Python examples.
- Preserve existing scripts, IDs, configuration, and user instructions. Do not execute scripts, connect to services, or delete files merely to validate edits; request execution only when the user authorizes it.
- Existing terminal password prompts can use the app's hidden-input dialog and saved Keychain credentials without script changes; see [the credential flow](InteractiveUI.md#terminal-hidden-input-and-saved-credentials).
- Keep credentials and personal connection details out of shared scripts and configuration.

ScriptDeck supplies these documents when creating or importing a workspace. Existing files are preserved. Additional ScriptDeck workspace development guides are distributed alongside them; follow links from the authoring guide for the relevant task.
