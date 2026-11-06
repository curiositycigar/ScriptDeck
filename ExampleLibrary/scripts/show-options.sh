#!/usr/bin/env bash
set -euo pipefail

printf '[%s] Starting parameter demo\n' "$(date '+%H:%M:%S')"
printf 'Environment: %s\n' "${1:?Missing environment}"
printf 'Mode: %s\n' "${2:?Missing mode}"
printf 'Note: %s\n' "${3-Not provided}"
printf 'Current directory: %s\n' "$PWD"
printf 'Parameter demo complete.\n'
