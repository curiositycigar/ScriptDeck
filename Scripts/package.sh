#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1-$(uname -m)}"
if [[ $# -gt 1 || ( "$ARCH" != arm64 && "$ARCH" != x86_64 ) ]]; then
    printf 'Usage: %s [arm64|x86_64]\n' "$0" >&2
    exit 2
fi
bash "$ROOT/build.sh" "$ARCH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
NAME="ScriptDeck-$VERSION-$ARCH"
STAGING="$(mktemp -d "$ROOT/.build/release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
RELEASE="$STAGING/$NAME"
mkdir -p "$RELEASE"
ditto "$ROOT/dist/$ARCH/ScriptDeck.app" "$RELEASE/ScriptDeck.app"
mkdir -p "$RELEASE/ExampleLibrary/scripts"
cp "$ROOT/ExampleLibrary/library.json" "$RELEASE/ExampleLibrary/"
for SCRIPT in show-options.sh interactive-demo.sh; do
    cp "$ROOT/ExampleLibrary/scripts/$SCRIPT" "$RELEASE/ExampleLibrary/scripts/"
done
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
ditto -c -k --sequesterRsrc --keepParent "$RELEASE" "$STAGING/$NAME.zip"
unzip -tq "$STAGING/$NAME.zip"
bash "$ROOT/Scripts/make-dmg.sh" "$DMG_ROOT" "$STAGING/$NAME.dmg" "$VERSION"
(
    cd "$STAGING"
    for EXTENSION in zip dmg; do
        shasum -a 256 "$NAME.$EXTENSION" > "$NAME.$EXTENSION.sha256"
        shasum -a 256 -c "$NAME.$EXTENSION.sha256"
    done
)
mv "$STAGING/$NAME.zip" "$STAGING/$NAME.zip.sha256" \
    "$STAGING/$NAME.dmg" "$STAGING/$NAME.dmg.sha256" "$ROOT/dist/"
printf 'Packages complete: %s\n%s\n' "$ROOT/dist/$NAME.zip" "$ROOT/dist/$NAME.dmg"
