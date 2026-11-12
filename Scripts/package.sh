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
codesign --verify --deep --strict "$RELEASE/ScriptDeck.app"
# Keep the installer root focused on the app and its drag-to-install destination.
DMG_ROOT="$STAGING/dmg"
mkdir -p "$DMG_ROOT/Extras"
ditto "$RELEASE/ScriptDeck.app" "$DMG_ROOT/ScriptDeck.app"
ln -s /Applications "$DMG_ROOT/Applications"
for ENTRY in ExampleLibrary Docs README.md README.zh-CN.md; do
    ditto "$RELEASE/$ENTRY" "$DMG_ROOT/Extras/$ENTRY"
done
ditto -c -k --sequesterRsrc --keepParent "$RELEASE" "$ROOT/dist/ScriptDeck-$VERSION.zip"
unzip -tq "$ROOT/dist/ScriptDeck-$VERSION.zip"
hdiutil create -volname "ScriptDeck $VERSION" -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov "$ROOT/dist/ScriptDeck-$VERSION.dmg"
hdiutil verify "$ROOT/dist/ScriptDeck-$VERSION.dmg"
(
    cd "$ROOT/dist"
    for EXTENSION in zip dmg; do
        shasum -a 256 "ScriptDeck-$VERSION.$EXTENSION" > "ScriptDeck-$VERSION.$EXTENSION.sha256"
        shasum -a 256 -c "ScriptDeck-$VERSION.$EXTENSION.sha256"
    done
)
printf 'Packages complete: %s\n%s\n' "$ROOT/dist/ScriptDeck-$VERSION.zip" "$ROOT/dist/ScriptDeck-$VERSION.dmg"
