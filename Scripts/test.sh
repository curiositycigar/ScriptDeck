#!/bin/bash
# Explicit opt-in only. Building or packaging never invokes this command.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
RUNNER_SELF_CHECKS=1 swift build --build-system native --package-path "$ROOT" \
    --scratch-path "$ROOT/.build/self-checks" \
    --cache-path "$ROOT/.build/package-cache" \
    --config-path "$ROOT/.build/package-config" \
    --security-path "$ROOT/.build/package-security" \
    --experimental-prune-unused-dependencies --disable-prefetching --disable-sandbox --product ScriptDeck
SCRIPTDECK_LANGUAGE="${SCRIPTDECK_LANGUAGE:-zh-Hans}" "$ROOT/.build/self-checks/debug/ScriptDeck"
