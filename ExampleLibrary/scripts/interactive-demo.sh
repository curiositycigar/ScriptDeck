#!/bin/bash
set -euo pipefail
# Native UI mode uses ScriptDeck's helper, Bash, and macOS plutil.
# All files below are fictional; deletion changes only this process's variables.
if [[ -n "${SCRIPTDECK_UI_SESSION:-}" ]]; then
    DEMO_BACKUP=true
    DEMO_REPORT=true
    while true; do
        DEMO_ITEMS=''
        DEMO_COUNT=0
        if [[ "$DEMO_BACKUP" == true ]]; then
            DEMO_ITEMS='{"id":"backup","text":"backup.zip","detail":"125 MB"}'
            DEMO_COUNT=$((DEMO_COUNT + 1))
        fi
        if [[ "$DEMO_REPORT" == true ]]; then
            [[ -z "$DEMO_ITEMS" ]] || DEMO_ITEMS+=','
            DEMO_ITEMS+='{"id":"report","text":"report.pdf","detail":"2 MB"}'
            DEMO_COUNT=$((DEMO_COUNT + 1))
        fi
        DEMO_EVENT=$("$SCRIPTDECK_UI" --ui <<JSON
{"blocks":[{"type":"text","text":"Fictional files","style":"title","region":"header"},{"type":"text","text":"$DEMO_COUNT files · Page 1/1 · Preview only","style":"secondary","region":"header"},{"type":"buttons","region":"footer","items":[{"text":"Refresh","data":"refresh"},{"text":"Details","data":"details","requiresSelection":"files"},{"text":"Delete selected","data":"delete","style":"destructive","requiresSelection":"files"},{"text":"Basic controls","data":"controls"},{"text":"Previous","data":"previous","disabled":true},{"text":"Next","data":"next","disabled":true},{"text":"Exit","data":"exit"}]},{"type":"list","id":"files","items":[$DEMO_ITEMS]}]}
JSON
        )
        DEMO_ACTION=$(printf '%s' "$DEMO_EVENT" | /usr/bin/plutil -extract data raw -o - -)
        DEMO_SELECTED=$(printf '%s' "$DEMO_EVENT" | /usr/bin/plutil -extract values.files.0 raw -o - - 2>/dev/null) || DEMO_SELECTED=''
        unset DEMO_EVENT
        case "$DEMO_ACTION" in
            exit) break ;;
            controls)
                # plutil ships with macOS; no third-party JSON parser is required.
                DEMO_EVENT=$("$SCRIPTDECK_UI" --ui <<'JSON'
{"blocks":[{"type":"text","text":"Basic controls — preview only, no upload or file changes"},{"type":"input","id":"destination","label":"Remote directory","placeholder":"/uploads","value":"/uploads"},{"type":"input","id":"notes","label":"Notes","multiline":true,"value":"Optional notes"},{"type":"input","id":"secret","label":"Demo password (never printed)","secure":true},{"type":"file","id":"uploads","label":"Local files","multiple":true},{"type":"file","id":"folder","label":"Local directory","mode":"directory"},{"type":"select","id":"environment","label":"Environment","value":"test","items":[{"id":"test","text":"Test"},{"id":"staging","text":"Staging"}]},{"type":"toggle","id":"overwrite","label":"Overwrite existing files","checked":false},{"type":"buttons","items":[{"text":"Preview progress","data":"preview"},{"text":"Back","data":"back"}]}]}
JSON
                )
                DEMO_ACTION=$(printf '%s' "$DEMO_EVENT" | /usr/bin/plutil -extract data raw -o - -)
                if [[ "$DEMO_ACTION" == preview ]]; then
                    # Read structured values without executing user-provided content.
                    DEMO_ENV=$(printf '%s' "$DEMO_EVENT" | /usr/bin/plutil -extract values.environment.0 raw -o - -)
                    printf 'Previewing simulated progress for environment: %s\n' "$DEMO_ENV"
                    for DEMO_PROGRESS in 0 0.25 0.5 0.75 1; do
                        "$SCRIPTDECK_UI" --ui <<JSON
{"blocks":[{"type":"text","text":"Simulated upload — no files are read or transferred"},{"type":"progress","label":"Preview progress","progress":$DEMO_PROGRESS}]}
JSON
                        sleep 0.25
                    done
                    "$SCRIPTDECK_UI" --ui <<'JSON'
{"blocks":[{"type":"progress","label":"Finishing preview…"}]}
JSON
                    sleep 0.25
                fi
                unset DEMO_EVENT
                ;;
            refresh) printf 'Refreshed the fictional file list.\n'; continue ;;
            details)
                "$SCRIPTDECK_UI" --ui <<JSON
{"blocks":[{"type":"text","text":"Fictional file details","style":"title"},{"type":"text","text":"Selected ID: $DEMO_SELECTED. This is an in-memory example, not a real file.","style":"secondary"},{"type":"buttons","items":[{"text":"Back","data":"back"}]}]}
JSON
                ;;
            delete)
                [[ "$DEMO_SELECTED" == backup || "$DEMO_SELECTED" == report ]] || continue
                DEMO_CONFIRM=$("$SCRIPTDECK_UI" --ui --action-only <<JSON
{"blocks":[{"type":"text","text":"Delete the fictional file: $DEMO_SELECTED?","notice":"warning"},{"type":"buttons","items":[{"text":"Confirm deletion","data":"confirm","style":"destructive"},{"text":"Cancel","data":"cancel"}]}]}
JSON
                )
                if [[ "$DEMO_CONFIRM" == confirm ]]; then
                    if [[ "$DEMO_SELECTED" == backup ]]; then DEMO_BACKUP=false; else DEMO_REPORT=false; fi
                    printf 'Deleted fictional file: %s\n' "$DEMO_SELECTED"
                fi ;;
        esac
    done
    "$SCRIPTDECK_UI" --ui <<'JSON'
{"blocks":[{"type":"text","text":"Demo complete. No files were changed."}]}
JSON
    exit 0
fi

printf '\033[36mEmbedded Interactive Terminal Demo\033[0m\n'
printf 'This demo does not upload files or connect to remote services.\n\n'
read -r -p 'Enter a display name: ' DEMO_NAME
printf 'Hello, %s.\n' "$DEMO_NAME"
read -r -s -p 'Enter demo text (hidden and not saved): ' DEMO_SECRET
printf '\nHidden input received; its contents will not be printed.\n'
unset DEMO_SECRET
read -r -p 'Start the progress demo? [y/N] ' DEMO_CONFIRM
case "$DEMO_CONFIRM" in
    y|Y)
        for DEMO_PROGRESS in 0 20 40 60 80 100; do
            printf '\r\033[2KProgress: %s%%' "$DEMO_PROGRESS"
            sleep 0.3
        done
        printf '\n\033[32mDemo complete.\033[0m\n'
        ;;
    *) printf 'Progress demo cancelled.\n' ;;
esac
