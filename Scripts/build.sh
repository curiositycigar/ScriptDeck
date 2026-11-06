#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
APP="$ROOT/dist/ScriptDeck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
bash "$ROOT/Scripts/make-icon.sh"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

swift build --package-path "$ROOT" \
    --cache-path "$ROOT/.build/package-cache" \
    --config-path "$ROOT/.build/package-config" \
    --security-path "$ROOT/.build/package-security" \
    --experimental-prune-unused-dependencies --disable-prefetching --disable-sandbox -c release --product ScriptDeck \
    -Xswiftc -module-cache-path -Xswiftc "$ROOT/.build/module-cache"
cp "$ROOT/.build/release/ScriptDeck" "$APP/Contents/MacOS/ScriptDeck"

rm -rf "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle"
ditto "$ROOT/.build/release/ScriptDeck_ScriptDeck.bundle" "$APP/Contents/Resources/ScriptDeck_ScriptDeck.bundle"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

cp "$ROOT/Resources/ThirdPartyNotices.txt" "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp "$ROOT/Resources/library.schema.json" "$APP/Contents/Resources/library.schema.json"
rm -f "$APP/Contents/Resources/default-script-path.txt"
codesign --force --sign - "$APP"
printf 'Build complete: %s\n' "$APP"
