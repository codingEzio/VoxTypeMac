#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/VoxType.icon/Assets/VoxType-master-v2.png"
ICONSET="$ROOT/runtime/temp/icon/AppIcon.iconset"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 1024 1024 "$SOURCE" --out "$ROOT/Resources/AppIcon-1024.png" >/dev/null
for specification in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  read -r size filename <<< "$specification"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$filename" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "generated: Resources/AppIcon-1024.png"
echo "generated: Resources/AppIcon.icns"
