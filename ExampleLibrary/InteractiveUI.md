# Interactive script panels

Enable **Interactive UI** in the script editor, or set `"interactiveUI": true` in its library entry. No additional UI app, web server, or language SDK is required. Script runtimes and business dependencies still need to be installed normally.

Each manual run has **Interactive UI** and **Terminal Log** tabs in its execution window. The UI tab opens by default. Tab selection is retained per execution. Standard output/error continue to use the existing terminal and persisted logs; protocol payloads and selections are not added to logs. Scripts can explicitly print operation results for history. Background schedules reject interactive UI scripts.

## Terminal hidden input and saved credentials

When the running terminal disables input echo, the Interactive UI tab shows a notice and offers a native **Terminal Hidden Input** dialog. The dialog accepts manual masked input or a saved Keychain credential; credentials associated with the script appear first. Nothing is sent automatically: the user chooses a source and clicks Send, with an optional Return (enabled by default). The app reads a saved secret only after Send, revalidates the selected terminal and ECHO state, and sends bytes directly to that PTY without UI protocol traffic, clipboard use, or logging the input. Scripts can still explicitly print what they read.

ECHO-off is only a hint for hidden input, not proof of a password prompt. Detection runs every 0.5 seconds. Automatic presentation applies to the selected interactive session while the expanded output shows Interactive UI and the app is active; other sheets defer it. Each observed hidden-input interval offers the dialog once. Cancel keeps the notice, whose **Enter Hidden Input…** button reopens it. Restored echo, stopping, completion, switching records, or switching to Terminal Log dismisses the prompt. Tabs never switch automatically. Credential creation and editing remain in the existing Credentials manager. No script changes or new protocol fields are needed.


### Using the dialog

1. Save a credential with the key button beside the script name or in **Settings → Credentials**. Associating it with the script is optional and moves it ahead of other credentials in the chooser.
2. Run a script with Interactive UI enabled and keep its Interactive UI tab selected. When a terminal prompt disables input echo, the app offers the hidden-input dialog.
3. Choose **Enter manually** and type into the masked field, or select a saved credential under **Input source**. Selecting a credential does not reveal or send its password.
4. Click **Send**. **Press Return after filling** is enabled by default; turn it off to fill without submitting the terminal prompt.
5. If you cancel, use **Enter Hidden Input…** in the notice to reopen the dialog, or switch to **Terminal Log** to continue in the terminal.

### Guidance for script authors

Keep existing terminal password prompts unchanged, such as Bash `read -s` or a command's normal terminal authentication prompt. Do not add a UI button, JSON password field, credential ID, or Keychain lookup just to enable this capability. The app handles detection and credential delivery; credentials and script associations stay on the user's Mac and are not included in workspace exports.

This capability responds to terminal ECHO state, not stdout text matching. A visible-input prompt, a command reading from a separate input source, or an authentication UI outside the run's terminal will not trigger it. Some terminal programs disable echo for other reasons, so the dialog deliberately describes hidden input rather than claiming to identify a particular password prompt. Scheduled background executions do not support this flow.

The protocol's `input` block with `secure: true` is a separate script-owned form field: its value is returned in the JSON callback. The automatic terminal dialog sends directly to the PTY and contributes nothing to callback `values`. Never print password values from either path.

## Exchange

The environment provides:

- `SCRIPTDECK_UI`: the absolute path to ScriptDeck's bundled executable.
- `SCRIPTDECK_UI_SESSION`: the private mailbox for this execution. Treat this as opaque.
- `SCRIPTDECK_LANGUAGE`: the app language (`en` or `zh-Hans`), available for script-owned labels.

Invoke `"$SCRIPTDECK_UI" --ui`, write one JSON view to its standard input, and close that input. The helper renders the view, waits for a button click, then writes one JSON event to standard output and exits successfully. Without buttons, it returns immediately after the app accepts the view, with no output. This supports progress/status updates before slow operations. Each exchange supplies the complete panel content. Without `pageID`, form values and list selections reset; compatible file controls retain paths across consecutive views. With a nonempty `pageID`, compatible controls on consecutive views of the same page retain state unless explicitly assigned or reset. Changing or removing the page ID starts fresh. Stable block and button IDs allow in-place view reuse; omitted IDs fall back to array positions. Only one helper exchange may be active per execution; a concurrent call fails rather than sharing events.

The helper uses an isolated directory with mode 0700, atomic JSON files and a 100 ms app polling interval. The script does not implement this transport. Stop or process completion removes the mailbox, disables the final panel, and causes waiting helpers to fail. Closing the app window retains the existing app/session lifecycle. Historical logs do not restore interactive panels.

## View format

```json
{
  "blocks": [
    {"type": "text", "text": "Files in /uploads"},
    {
      "type": "list",
      "id": "files",
      "multiple": true,
      "items": [
        {"id": "backup", "text": "backup.zip — 125 MB"},
        {"id": "report", "text": "report.pdf — 2 MB"}
      ]
    },
    {
      "type": "buttons",
      "items": [
        {"text": "Refresh", "data": "refresh"},
        {"text": "Delete selected", "data": "delete"}
      ]
    }
  ]
}
```

Blocks render vertically within their region in a compact layout with 12 pt horizontal insets, 8 pt block spacing, and small native buttons separated by 6 pt. List rows have a 26 pt minimum height and grow for wrapped labels. A `buttons` block lays out actions horizontally and wraps them onto additional rows as needed; long labels wrap within their button. Add more button blocks for separate action groups. Text and list rows grow to fit wrapped content. Lists expand to fit all their rows, with no internal scroll container or height limit. The body fills the space between optional fixed header/footer regions and scrolls as one surface when its contents exceed the available height. The tab strip and hidden-input notice remain fixed above the panel. For large datasets, use script-controlled Previous/Next buttons to paginate and keep actions easy to reach. All interactive UI scroll indicators are hidden; trackpad and mouse-wheel scrolling remain available. List headers show the item and selection counts. Text is plain, selectable text. There are no HTML, coordinates, arbitrary nesting, or executable callbacks.

`list.id` is required and unique across the view. Item IDs are required and unique within their list. `multiple` defaults to false. Lists start unselected on a new page; same-page retention is described below. Clicking an already selected single-selection item clears it. Button labels are required strings; callback buttons require `data`, while local assignment buttons require `action`. Labels and data are always treated as content, never executed by the app.

## Page identity and retained state

Optional top-level `pageID` identifies one logical page; it must be nonempty when supplied. Every message still includes the complete `blocks` array. A request UUID identifies one exchange and rejects stale callbacks; `pageID` instead scopes component state and view reuse. It does not cache pages: leaving and returning starts fresh.

On consecutive views with the same explicit `pageID`:

- Input, select, and toggle values persist by control ID when their type remains compatible. Explicit `value` (including an empty string) or `checked` overrides retained state.
- Password inputs never retain edits across views. An explicit `value` initializes the new password field.
- File choices persist only when ID, mode, and multiplicity match. Lists preserve only selected IDs still present, with the same multiplicity. Invalid retained select values fall back to the first current option.
- `reset: true` on an input, file, list, select, or toggle discards previous state before applying explicit defaults. It clears file/list selections. Omitted or false means normal retention rules.
- Removing a control discards its state. Changing input multiline/secure configuration clears incompatible edits. Changing `pageID`, including adding or removing it, clears state and resets the rendered page.

Without `pageID`, existing initialization behavior remains: form/list state resets on every message, while compatible file choices persist across consecutive views. `reset: true` can also clear a legacy file picker.

All blocks accept an optional nonempty `id`, unique across the entire view. Button items accept optional nonempty IDs unique within their button block. Declare stable IDs for components that should survive insertions or reordering; omitted IDs fall back to their array positions. Same-page updates retain compatible native views and scrolling where content permits. This does not guarantee focus or scroll retention after incompatible structural changes.

## Local field assignments

A button item may use `action` instead of `data` to update a nonsecure input without completing the exchange or calling the script:

```json
{"pageID":"upload","blocks":[
  {"type":"input","id":"name","label":"Remote filename"},
  {"type":"buttons","id":"presets","items":[
    {"id":"example","text":"example.zip","action":{"type":"setValue","target":"name","value":"example.zip"}}
  ]},
  {"type":"buttons","id":"actions","items":[
    {"id":"upload","text":"Upload","data":"upload"},
    {"id":"cancel","text":"Cancel","data":"cancel"}
  ]}
]}
```

Each button requires exactly one of `data` or `action`. The only local action is `setValue`, with a `target` matching a nonsecure input in the current view and a string `value`. Local actions obey `disabled`, `requiresSelection`, session lifecycle, and stale-request checks. They do not submit form values, lock controls, show processing feedback, or rebuild the page. The next callback includes the updated value. They cannot select files, fill secure inputs, or execute code. Every button-based view must also contain a callback button so the script can continue or cancel.

These fields require an updated ScriptDeck client. Existing scripts without them continue to use the previous protocol behavior.

## Optional fixed regions

Every block accepts optional `region`: `header`, `body`, or `footer`. Omission means `body`, so existing scripts need no changes. The app groups blocks by region, preserving their original array order **within each region**. No nesting, coordinates, heights, or flex settings are required.

- Header: fixed at the top, with natural content height.
- Body: fills all remaining height, even when empty or containing only a short list. Its contents keep their natural heights. This is the only scrolling region; indicators remain hidden.
- Footer: fixed at the bottom, with natural content height. Button wrapping increases its height automatically.
- Missing header/footer regions reserve no space and show no separator. Separators appear only next to present fixed regions.

```json
{"blocks":[
  {"type":"text","text":"/uploads","style":"title","region":"header"},
  {"type":"text","text":"Page 1/1","style":"secondary","region":"header"},
  {"type":"list","id":"files","items":[{"id":"report","text":"report.pdf","detail":"2 MB"}]},
  {"type":"buttons","region":"footer","items":[
    {"text":"Refresh","data":"refresh"},
    {"text":"Delete selected","data":"delete","style":"destructive","requiresSelection":"files"},
    {"text":"Exit","data":"exit"}
  ]}
]}
```

With neither fixed region, the body fills the panel; with only one, it fills the space above or below that region. The example deliberately omits `region` on the list to demonstrate the default. Put long lists and forms in the body and keep fixed regions compact so they leave room for it. No region has its own nested scroll view. Events collect control values across all three regions, and buttons in any region can depend on a body list's selection. Regions change layout only, not the exchange protocol or control IDs.

## Text hierarchy and list metadata

Text blocks accept optional `style`: `title`, `body`, or `secondary`. Use a separate title block for a path and a secondary block for counts, page numbers, or guidance. When omitted, the first block keeps the legacy title appearance and later text uses body style; the app never parses newlines or file names to infer semantic roles.

List items accept optional `detail`, a plain string for size, date, or other metadata. On wide panels the name stays left and detail aligns right in a smaller secondary font. When both do not fit, detail moves below the wrapping name. Existing items containing only `text` render as before. The live item/selection count appears above each list so it is available before scrolling through rows. Lists in the body share its single scroll container.

```json
{"blocks":[
  {"type":"text","text":"/uploads","style":"title"},
  {"type":"text","text":"2 files · Page 1/1","style":"secondary"},
  {"type":"buttons","items":[
    {"text":"Refresh","data":"refresh"},
    {"text":"Delete selected","data":"delete","style":"destructive","requiresSelection":"files"},
    {"text":"Previous","data":"previous","disabled":true},
    {"text":"Next","data":"next","disabled":true}
  ]},
  {"type":"list","id":"files","multiple":true,"items":[
    {"id":"backup","text":"backup.zip","detail":"125 MB"},
    {"id":"report","text":"report.pdf","detail":"2 MB"}
  ]}
]}
```

Button items accept `style` (`default` or `destructive`), `disabled` (boolean, default false), and `requiresSelection` (the ID of a list in the same view). Destructive uses the native destructive button role; it does not execute or confirm anything by itself. A selection-dependent button enables immediately when at least one valid item in that list is selected and disables again when the selection is cleared. `disabled: true` always takes precedence. Disabled actions are rejected by the channel as well as disabled visually. Explicitly disable or omit unavailable page actions. Keep an enabled action available so a button-based view can be completed.

These optional fields are backward compatible; existing scripts must add them to opt into structured metadata and explicit styling. The app does not split a combined `filename — size` string or guess destructive actions from labels.

## Form and progress blocks

All input controls use a nonempty `id`, unique across all blocks with IDs in the view. `label` is optional plain text. Changes stay in the app until a callback button is clicked; switching output tabs preserves them. Named pages retain compatible control state as described below. Views without `pageID` initialize text, select, and toggle controls from defaults and reset list selections, while compatible file controls retain selected paths. Controls require a button block in the same view to accept user interaction. Without buttons, a view is a status update and returns immediately.

| Type | Fields | Initial state | Submitted `values[id]` |
| --- | --- | --- | --- |
| `input` | `id`, optional `label`, `placeholder`, `value` (string), `multiline` (boolean), `secure` (boolean) | `value` or empty string | One string, including `[""]` when empty |
| `file` | `id`, optional `label`, `mode` (`file` or `directory`), `multiple` (boolean) | Previous selection for the same compatible control, otherwise empty; `mode` defaults to `file` | Absolute local paths; `[]` when empty |
| `select` | `id`, `items` (`id`/`text`), optional `label`, `value` (item ID) | `value` or first item | One selected item ID |
| `toggle` | `id`, optional `label`, `checked` (boolean) | `checked` or false | `["true"]` or `["false"]` |
| `progress` | Optional `label`, `progress` (number from 0 to 1) | Determinate if a number is supplied; otherwise a waiting spinner | No value submitted |

Example:

```json
{
  "blocks": [
    {"type":"input","id":"destination","label":"Remote directory","value":"/uploads"},
    {"type":"input","id":"notes","label":"Notes","multiline":true},
    {"type":"input","id":"secret","label":"Password","secure":true},
    {"type":"file","id":"uploads","label":"Local files","multiple":true},
    {"type":"file","id":"folder","label":"Local directory","mode":"directory"},
    {"type":"select","id":"environment","label":"Environment","value":"test","items":[
      {"id":"test","text":"Test"},{"id":"staging","text":"Staging"}
    ]},
    {"type":"toggle","id":"overwrite","label":"Overwrite existing files","checked":false},
    {"type":"buttons","items":[{"text":"Upload","data":"upload"},{"text":"Cancel","data":"cancel"}]}
  ]
}
```

A click can return:

```json
{"data":"upload","values":{"destination":["/uploads"],"notes":[""],"secret":[""],"uploads":["/Users/example/report.pdf"],"folder":[],"environment":["test"],"overwrite":["false"]}}
```

File selection supports a native macOS chooser and dragging local files or folders onto the control. Both methods follow `mode` and `multiple`: incompatible or unavailable paths are ignored, a single-selection control takes the first compatible path, and a multi-selection control takes all compatible paths. A successful drop replaces the previous selection; a rejected drop or chooser cancellation retains it, and Clear removes it. Drops are disabled while processing or after completion. Selected paths display in full and are submitted in sorted order. `multiple` defaults to false and applies to both file and directory modes. File contents are never loaded or uploaded by the UI. Remote files still use a script-populated `list`. Scripts must handle paths that have changed or disappeared after selection.

Single-line and multiline inputs use native expanding fields, without an embedded scrolling editor. `secure` masks a single-line field and cannot be combined with `multiline`. Masking affects display only: the entered string is returned to the script. Do not print callbacks containing passwords or store them in logs. Validation, required fields, and cancellation behavior belong to the script; every button returns all current input values, including Cancel. Select items require nonempty unique IDs and 1–1,000 options; an explicit `value` must match one. Toggles always return strings to preserve the existing string-array event format.

For progress, publish views without buttons between portions of work:

```json
{"blocks":[{"type":"progress","label":"Uploading…","progress":0.5}]}
```

Omit `progress` for an indeterminate spinner. These updates describe the complete panel and update it in place; they do not create background work or emit input events. Display-only views do not show an additional waiting indicator. The script runs the operation and chooses when to publish the next update.

Limits: 256 KiB input, 100 blocks, 1,000 items per list or select, and 1–8 buttons per button block. Use script-controlled pagination for larger datasets. Unknown block types, invalid IDs, and invalid JSON fail with a nonzero helper exit status and a diagnostic on stderr.

## Events and confirmation

A callback button click returns its opaque `data` plus current control values (list IDs in item order):

```json
{"data":"delete","values":{"files":["report"]}}
```

All input control IDs appear in `values`, including empty selections. Text and progress blocks do not contribute values. Changes to selection and local field assignments do not send events. Controls disable immediately after a callback click until the script publishes its next view, preventing duplicate submissions. Text remains readable and scrollable. If the next view takes longer than 250 ms, a compact waiting indicator overlays the body without moving content; faster exchanges do not show it. The app rejects callbacks from replaced views.

Confirmation is another view with Confirm and Cancel buttons. The script stores the selected IDs before showing it, checks the chosen action, performs deletion, and publishes a fresh list. Use stable opaque file IDs and verify the target before destructive operations; do not concatenate callbacks into shell commands. Confirmation and business operations belong to the script.

## Shell

For button-only flows, `--action-only` prints the callback string instead of JSON:

```bash
action=$("$SCRIPTDECK_UI" --ui --action-only <<'JSON'
{"blocks":[{"type":"text","text":"Continue?"},{"type":"buttons","items":[{"text":"Continue","data":"continue"},{"text":"Cancel","data":"cancel"}]}]}
JSON
) || exit 1
case "$action" in
  continue) printf 'Continuing…\n' ;;
  cancel) exit 0 ;;
esac
```

For arbitrary filenames, use a JSON encoder rather than interpolating unescaped strings. Shell scripts that need list selections can parse the normal JSON response with their chosen tooling. The bundled **Interactive UI Demo** reuses `interactive-demo.sh` for a fictional file browser and confirmation flow, plus a **Basic controls** form and simulated progress using the macOS-bundled `plutil` JSON reader without third-party dependencies; the original terminal demo remains available.

## Python and other languages

Any supported language can invoke the same executable. For example, Python uses only its standard library:

```python
import json
import os
import subprocess


def show(blocks):
    result = subprocess.run(
        [os.environ["SCRIPTDECK_UI"], "--ui"],
        input=json.dumps({"blocks": blocks}),
        text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


files = [{"id": "backup", "text": "backup.zip"}]
while True:
    event = show([
        {"type": "text", "text": "Fictional files"},
        {"type": "list", "id": "files", "multiple": True, "items": files},
        {"type": "buttons", "items": [
            {"text": "Delete selected", "data": "delete"},
            {"text": "Exit", "data": "exit"},
        ]},
    ])
    if event["data"] == "exit":
        break
    selected = set(event["values"]["files"])
    if not selected:
        continue
    confirmation = show([
        {"type": "text", "text": f"Delete {len(selected)} fictional files?"},
        {"type": "buttons", "items": [
            {"text": "Confirm", "data": "confirm"},
            {"text": "Cancel", "data": "cancel"},
        ]},
    ])
    if confirmation["data"] == "confirm":
        files = [item for item in files if item["id"] not in selected]
        print("Updated fictional files", flush=True)
```

Node.js, Ruby, and other interpreters can use their normal subprocess APIs. Their runtime dependencies are unchanged. Keep personal upload scripts, credentials, VPS addresses, and real deletion examples outside the public repository and release packages.
