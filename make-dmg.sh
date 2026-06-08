#!/bin/bash
set -e

# Package HermesVoice as a distributable .dmg.
#
# The app is ad-hoc-signed (valid signature, no Developer ID), so a downloaded
# copy shows macOS's "unidentified developer" prompt — NOT "damaged" — and a
# right-click ▸ Open clears it. See README.md for the install/bypass steps.
#
# No notarization and no paid Apple Developer account are required.

cd "$(dirname "$0")"

# 1. Build + ad-hoc-sign the app (embeds the icon, stamps the version).
./build-app.sh

APP="build/HermesVoice.app"
[ -d "$APP" ] || { echo "❌ $APP not found (build-app.sh did not produce a bundle)"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/HermesVoice-$VERSION.dmg"
VOLNAME="HermesVoice"

echo ""
echo "📦 Packaging $DMG …"
rm -f "$DMG"

packaged=0

# 2. Preferred path: create-dmg (Homebrew) for a drag-to-Applications layout
#    with a background. Optional — fall back to hdiutil if it's absent or fails.
if command -v create-dmg >/dev/null 2>&1; then
    echo "   create-dmg found — building a drag-to-install window…"
    if create-dmg \
        --volname "$VOLNAME" \
        --window-size 600 380 \
        --icon-size 110 \
        --icon "HermesVoice.app" 150 190 \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "$DMG" "$APP" 2>/dev/null; then
        packaged=1
    else
        echo "   ⚠️  create-dmg failed; falling back to hdiutil."
        rm -f "$DMG"
    fi
fi

# 3. Fallback (always available, no dependencies): stage the app plus an
#    /Applications symlink and let hdiutil build a compressed image.
if [ "$packaged" != "1" ]; then
    echo "   using hdiutil…"
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create \
        -volname "$VOLNAME" \
        -srcfolder "$STAGE" \
        -ov -format ULFO \
        "$DMG" >/dev/null
fi

SIZE=$(du -h "$DMG" | cut -f1 | tr -d ' ')
echo ""
echo "✅ Built $(pwd)/$DMG  ($SIZE)"
echo ""
echo "Distribute this file. On first launch the recipient must right-click ▸ Open"
echo "▸ Open once (unsigned app). Full instructions are in README.md."
