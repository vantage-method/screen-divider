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
  -framework StoreKit -framework ServiceManagement \
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

# Embed the source location + built commit so the app's "Check for Updates"
# can pull this same clone and reinstall. Must run BEFORE codesign, since
# editing Info.plist after signing would invalidate the signature.
PLIST="$BUNDLE_PATH/Contents/Info.plist"
BUILD_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
REPO_REMOTE="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")"
for kv in "SDRepoPath:$SCRIPT_DIR" "SDBuildCommit:$BUILD_COMMIT" "SDRepoRemote:$REPO_REMOTE"; do
  key="${kv%%:*}"; val="${kv#*:}"
  /usr/libexec/PlistBuddy -c "Add :$key string $val" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :$key $val" "$PLIST"
done

# Copy resources (icons, config example)
cp Resources/AppIcon.icns "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon@2x.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/menubar-icon@3x.png "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true
cp Resources/config-example.json "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null || true

# Sign the bundle so macOS can identify the app for permissions.
#
# By default this is an ad-hoc signature, whose identity is the code hash —
# so every rebuild changes it and macOS silently drops any Accessibility
# grant, forcing a re-grant. To avoid that, a self-hosted install can use a
# stable self-signed identity: drop a gitignored `.local-signing` file next
# to this script defining SD_SIGN_KEYCHAIN, SD_SIGN_KEYCHAIN_PW and
# SD_SIGN_IDENTITY. The identity's designated requirement pins to the cert
# (not the code hash), so the permission grant survives every future build.
SIGN_IDENTITY="-"
SIGN_ARGS=()
if [ -f "$SCRIPT_DIR/.local-signing" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.local-signing"
  if [ -n "${SD_SIGN_KEYCHAIN:-}" ] \
     && security find-identity -p codesigning "$SD_SIGN_KEYCHAIN" 2>/dev/null | grep -q "${SD_SIGN_IDENTITY:-__none__}"; then
    security unlock-keychain -p "$SD_SIGN_KEYCHAIN_PW" "$SD_SIGN_KEYCHAIN" 2>/dev/null || true
    SIGN_IDENTITY="$SD_SIGN_IDENTITY"
    SIGN_ARGS=(--keychain "$SD_SIGN_KEYCHAIN")
    echo "  (signing with stable identity: $SD_SIGN_IDENTITY)"
  fi
fi
codesign --force --deep --sign "$SIGN_IDENTITY" "${SIGN_ARGS[@]}" "$BUNDLE_PATH" 2>&1

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
