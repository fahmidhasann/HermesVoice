#!/bin/bash
#
# generate-icns.sh — render every iconset size and pack Resources/AppIcon.icns.
#
# The PNGs are rendered fresh at each pixel size (sharp at every resolution)
# rather than downscaled, then iconutil packs them. The resulting AppIcon.icns
# is committed so a normal `./build-app.sh` needs no rendering step.
#
# Re-run this only when the icon design changes.
set -e
cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { swift tools/make-icon.swift "$ICONSET/$2" "$1"; }

echo "🎨 Rendering icon sizes…"
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$ICONSET"
echo "✅ Wrote Resources/AppIcon.icns"
