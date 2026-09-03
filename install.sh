#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Screen Divider"
APP_BUNDLE="$APP_NAME.app"
INSTALL_DIR="/Applications"

echo "Building Screen Divider..."
cd "$SCRIPT_DIR"

# Optional local unlock: a self-hosted build that bypasses the App Store
# paywall. Enabled by creating a `.local-unlock` marker file next to this
# script (it's gitignored, so it never ships). App Store / xcodegen builds
# never define this flag, so distribution stays paywalled.
UNLOCK_FLAG=""
if [ -f "$SCRIPT_DIR/.local-unlock" ]; then
  UNLOCK_FLAG="-D SD_LOCAL_UNLOCK"
  echo "  (.local-unlock present → building with paywall disabled)"
fi

# Build with swiftc (works with Command Line Tools, no Xcode needed)
# Compile every Swift source so new files are picked up automatically.
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AppKit -framework ApplicationServices \
  $UNLOCK_FLAG \
  -O -o ScreenDivider \
  $(find Sources/ScreenDivider -name "*.swift")

echo "Creating app bundle..."
BUNDLE_PATH="$INSTALL_DIR/$APP_BUNDLE"
rm -rf "$BUNDLE_PATH"

mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

# Copy binary
cp ScreenDivider "$BUNDLE_PATH/Contents/MacOS/ScreenDivider"

# Copy Info.plist
cp Info.plist "$BUNDLE_PATH/Contents/Info.plist"

# Copy resources (icons, config example)
cp Resources/AppIcon.icns "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon@2x.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon@3x.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/config-example.json "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true

# Ad-hoc sign so macOS can persistently identify the app for permissions
codesign --force --deep --sign - "$BUNDLE_PATH" 2>&1

echo ""
echo "Installed to: $BUNDLE_PATH"
echo ""
echo "You can now find 'Screen Divider' in Spotlight, Launchpad, or /Applications."
echo ""
echo "First launch:"
echo "  1. Open Screen Divider from Spotlight (Cmd+Space, type 'Screen Divider')"
echo "  2. Grant Accessibility permission when prompted"
echo "  3. Grant Input Monitoring permission when prompted"
echo "  4. The app icon will appear in your menu bar"
