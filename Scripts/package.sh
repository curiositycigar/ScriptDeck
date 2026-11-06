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
mkdir -p "$RELEASE/示例脚本库"
/usr/bin/rsync -a --exclude='logs/' --exclude='.DS_Store' "$ROOT/ExampleLibrary/" "$RELEASE/示例脚本库/"
cp "$ROOT/Resources/library.schema.json" "$RELEASE/示例脚本库/library.schema.json"
cp "$ROOT/README.md" "$RELEASE/使用说明.md"
ditto "$ROOT/Docs" "$RELEASE/Docs"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE" "$ROOT/dist/ScriptDeck-$VERSION.zip"
printf '打包完成：%s\n' "$ROOT/dist/ScriptDeck-$VERSION.zip"
