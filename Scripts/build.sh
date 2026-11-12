#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1-$(uname -m)}"
if [[ $# -gt 1 || ( "$ARCH" != arm64 && "$ARCH" != x86_64 ) ]]; then
    printf 'Usage: %s [arm64|x86_64]\n' "$0" >&2
    exit 2
fi

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
APP="$ROOT/dist/ScriptDeck.app"
if [[ $# -eq 1 ]]; then
    APP="$ROOT/dist/$ARCH/ScriptDeck.app"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
bash "$ROOT/Scripts/make-icon.sh"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

BUILD_ARGS=(--build-system native --package-path "$ROOT" \
    --triple "$ARCH-apple-macosx13.0" \
    --cache-path "$ROOT/.build/package-cache" \
    --config-path "$ROOT/.build/package-config" \
    --security-path "$ROOT/.build/package-security" \
    --experimental-prune-unused-dependencies --disable-prefetching --disable-sandbox -c release --product ScriptDeck \
    -Xswiftc -module-cache-path -Xswiftc "$ROOT/.build/module-cache")
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
ACTUAL_ARCH="$(lipo -archs "$BIN_DIR/ScriptDeck")"
if [[ "$ACTUAL_ARCH" != "$ARCH" ]]; then
    printf 'Expected %s executable, found %s\n' "$ARCH" "$ACTUAL_ARCH" >&2
    exit 1
fi
cp "$BIN_DIR/ScriptDeck" "$APP/Contents/MacOS/ScriptDeck"

rm -rf "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle"
ditto "$BIN_DIR/ScriptDeck_ScriptDeck.bundle" "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle"
# Ensure every workspace-facing guide and the schema actually ship in the app.
diff -rq "$ROOT/Docs/Workspace" "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle/Workspace"
cmp "$ROOT/Resources/library.schema.json" "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle/library.schema.json"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

cp "$ROOT/Resources/ThirdPartyNotices.txt" "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp "$ROOT/Resources/library.schema.json" "$APP/Contents/Resources/library.schema.json"
rm -f "$APP/Contents/Resources/default-script-path.txt"
codesign --force --sign - "$APP"
printf 'Build complete: %s\n' "$APP"
