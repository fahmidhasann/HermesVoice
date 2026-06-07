#!/bin/bash
set -e

echo "🔨 Building HermesVoice..."
cd "$(dirname "$0")"
swift build -c release 2>&1

echo "📦 Creating app bundle..."
APP_DIR="./build/HermesVoice.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary
cp .build/release/HermesVoice "$APP_DIR/MacOS/HermesVoice"

# Copy Info.plist
cp Resources/Info.plist "$APP_DIR/Info.plist"

# Sign with ad-hoc signature (needed for hardened runtime features)
codesign --force --sign - --entitlements entitlements.plist "$APP_DIR/MacOS/HermesVoice"

echo "✅ Built: $(pwd)/build/HermesVoice.app"
echo ""
echo "To install:"
echo "  cp -r build/HermesVoice.app /Applications/"
echo ""
echo "To run now:"
echo "  open build/HermesVoice.app"
echo ""
echo "Hotkey: ⌃⇧H (Control+Shift+H) to toggle the voice panel"
