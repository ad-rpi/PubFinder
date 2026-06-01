#!/usr/bin/env bash
# Regenerate the app icon: render the 1024 master, then downsize into the
# asset catalog. Run from the project root: ./tools/make_icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift tools/make_icon.swift

SRC="tools/icon_src/icon_1024.png"
SET="BrewBrowser/Resources/Assets.xcassets/AppIcon.appiconset"

for px in 16 32 64 128 256 512; do
  sips -z "$px" "$px" "$SRC" --out "$SET/icon_${px}.png" >/dev/null
done
cp "$SRC" "$SET/icon_1024.png"
echo "Icon sizes written to $SET"
