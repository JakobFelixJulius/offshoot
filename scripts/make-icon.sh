#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/IconRenderer.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=build/icon
rm -rf "$WORK"
mkdir -p "$WORK/AppIcon.iconset"
swift scripts/IconRenderer.swift "$WORK/icon-1024.png"

for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/icon-1024.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns"
