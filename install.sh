#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Screen Divider"
APP_BUNDLE="$APP_NAME.app"
INSTALL_DIR="/Applications"

echo "Building Screen Divider..."
cd "$SCRIPT_DIR"

# Build with swiftc (works with Command Line Tools, no Xcode needed)
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AppKit -framework ApplicationServices \
  -O -o ScreenDivider \
  Sources/ScreenDivider/main.swift \
  Sources/ScreenDivider/AppDelegate.swift \
  Sources/ScreenDivider/Helpers/CoordinateHelper.swift \
  Sources/ScreenDivider/Managers/ConfigManager.swift \
  Sources/ScreenDivider/Managers/DragDetector.swift \
  Sources/ScreenDivider/Managers/LoginItemManager.swift \
  Sources/ScreenDivider/Managers/WindowManager.swift \
  Sources/ScreenDivider/Models/Config.swift \
  Sources/ScreenDivider/Views/PreferencesWindowController.swift \
  Sources/ScreenDivider/Views/ZoneOverlayController.swift \
  Sources/ScreenDivider/Views/ZoneOverlayView.swift

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
