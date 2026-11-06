#!/bin/bash
set -euo pipefail
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
