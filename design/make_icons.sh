#!/bin/zsh
# Renders the icon and resizes it into App/Assets.xcassets/AppIcon.appiconset.
set -euo pipefail
cd "${0:A:h}/.."
swift design/AppIcon.swift design/icon_1024.png
SET=App/Assets.xcassets/AppIcon.appiconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size design/icon_1024.png --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) design/icon_1024.png --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
echo "Icons written to $SET"
