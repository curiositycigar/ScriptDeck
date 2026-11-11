#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/build.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
STAGING="$(mktemp -d "$ROOT/.build/release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
RELEASE="$STAGING/ScriptDeck-$VERSION"
mkdir -p "$RELEASE"
ditto "$ROOT/dist/ScriptDeck.app" "$RELEASE/ScriptDeck.app"
# Exclude local history before copying; never read or bundle its contents.
mkdir -p "$RELEASE/ExampleLibrary"
/usr/bin/rsync -a --exclude='logs/' --exclude='.DS_Store' --exclude='.env' --exclude='.env.*' --exclude='.private/' "$ROOT/ExampleLibrary/" "$RELEASE/ExampleLibrary/"
ditto "$ROOT/Docs/Workspace" "$RELEASE/ExampleLibrary"
cp "$ROOT/Resources/library.schema.json" "$RELEASE/ExampleLibrary/library.schema.json"
cp "$ROOT/README.md" "$RELEASE/README.md"
cp "$ROOT/README.zh-CN.md" "$RELEASE/README.zh-CN.md"
ditto "$ROOT/Docs" "$RELEASE/Docs"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE" "$ROOT/dist/ScriptDeck-$VERSION.zip"
printf 'Package complete: %s\n' "$ROOT/dist/ScriptDeck-$VERSION.zip"
