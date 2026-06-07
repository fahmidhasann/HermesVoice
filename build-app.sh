#!/bin/bash
set -e

echo "🔨 Building HermesVoice..."
cd "$(dirname "$0")"
swift build -c release 2>&1

echo "📦 Creating app bundle..."
# Start from a clean bundle so each build is reproducible and stale resources
# (e.g. read-only SwiftPM .bundle files from a prior run) can't block the copy.
rm -rf "./build/HermesVoice.app"
APP_DIR="./build/HermesVoice.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary
cp .build/release/HermesVoice "$APP_DIR/MacOS/HermesVoice"

# Copy Info.plist
cp Resources/Info.plist "$APP_DIR/Info.plist"

# Embed the app icon (warm-amber waveform). Regenerate with
# ./tools/generate-icns.sh when the design changes.
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Resources/AppIcon.icns"
else
    echo "⚠️  Resources/AppIcon.icns missing — run ./tools/generate-icns.sh"
fi

# Stamp CFBundleVersion (build number) from the git commit count so every build
# is monotonically versioned, while CFBundleShortVersionString stays the
# human-facing marketing version carried in Info.plist.
BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUM" "$APP_DIR/Info.plist"
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Info.plist")

# Copy SwiftPM resource bundles (e.g. Highlightr's highlight.js + CSS themes)
# next to the app's Resources so each package's `Bundle.module` resolves at
# runtime — without this, syntax highlighting silently fails.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Resources/"
done

# Sign with ad-hoc signature (needed for hardened runtime features)
codesign --force --sign - --entitlements entitlements.plist "$APP_DIR/MacOS/HermesVoice"

# Validate the produced bundle before declaring success.
echo "🔍 Validating bundle..."
plutil -lint "$APP_DIR/Info.plist" >/dev/null
codesign --verify --strict "$APP_DIR/MacOS/HermesVoice"
[ -f "$APP_DIR/Resources/AppIcon.icns" ] || { echo "❌ icon missing from bundle"; exit 1; }
echo "   ✓ Info.plist valid · signature valid · icon embedded"

echo "✅ Built: $(pwd)/build/HermesVoice.app  (v$SHORT_VERSION build $BUILD_NUM)"
echo ""
echo "To install (or update — replaces any existing copy):"
echo "  rm -rf /Applications/HermesVoice.app && cp -r build/HermesVoice.app /Applications/"
echo ""
echo "To run now:"
echo "  open build/HermesVoice.app"
echo ""
echo "First launch shows a short onboarding (mic + speech permissions, hotkey)."
echo "Hotkey: ⌃⇧H (Control+Shift+H) to toggle the voice panel."
echo "Launch-at-login is managed in Settings ▸ General (SMAppService)."
