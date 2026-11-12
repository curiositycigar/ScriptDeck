#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$1"
OUTPUT="$2"
VERSION="$3"
TOOLS="$ROOT/.build/dmg-python"
export PYTHONPATH="$TOOLS"
if ! python3 -c 'import importlib.metadata as m; assert m.version("dmgbuild") == "1.6.7" and m.version("ds_store") == "1.3.3" and m.version("mac_alias") == "2.2.3"' 2>/dev/null; then
    python3 -m pip install --upgrade --target "$TOOLS" -r "$ROOT/Scripts/dmg-requirements.txt"
fi
mkdir -p "$SOURCE/.background"
swift -module-cache-path "$ROOT/.build/module-cache" "$ROOT/Scripts/make-dmg-background.swift" \
    "$SOURCE/.background/installer.png"
python3 -m dmgbuild -s "$ROOT/Scripts/dmg-settings.py" \
    -D "source=$SOURCE" -D "root=$ROOT" "ScriptDeck $VERSION" "$OUTPUT"
hdiutil verify "$OUTPUT"
