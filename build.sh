#!/bin/bash
# Project entry point; implementation lives in Scripts/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec bash "$ROOT/Scripts/build.sh" "$@"
