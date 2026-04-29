#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Screen Divider"
APP_BUNDLE="$APP_NAME.app"
INSTALL_DIR="$HOME/Desktop"

echo "Building Screen Divider..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

echo "Creating app bundle..."
BUNDLE_PATH="$INSTALL_DIR/$APP_BUNDLE"
rm -rf "$BUNDLE_PATH"

mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

# Copy binary
cp .build/release/ScreenDivider "$BUNDLE_PATH/Contents/MacOS/ScreenDivider"

# Copy example config into bundle resources
cp Resources/config-example.json "$BUNDLE_PATH/Contents/Resources/"

# Create Info.plist
cat > "$BUNDLE_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Screen Divider</string>
    <key>CFBundleDisplayName</key>
    <string>Screen Divider</string>
    <key>CFBundleIdentifier</key>
    <string>com.screendivider.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ScreenDivider</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Screen Divider needs accessibility access to move and resize windows.</string>
</dict>
</plist>
PLIST

# Create a simple app icon (colored grid icon using iconutil)
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

# Generate icon using Python (available on macOS)
python3 - "$ICONSET_DIR" << 'PYEOF'
import sys, os

iconset_dir = sys.argv[1]

# Simple SVG-like approach: create PNG icons using the sips-compatible method
# We'll use a basic approach with AppKit via PyObjC if available, otherwise skip icon
try:
    from AppKit import NSImage, NSBitmapImageRep, NSGraphicsContext, NSColor, NSBezierPath, NSMakeRect
    from Foundation import NSSize

    sizes = [16, 32, 64, 128, 256, 512]
    for size in sizes:
        for scale in [1, 2]:
            px = size * scale
            img = NSImage.alloc().initWithSize_(NSSize(px, px))
            img.lockFocus()

            # Background
            NSColor.colorWithCalibratedRed_green_blue_alpha_(0.2, 0.5, 0.9, 1.0).setFill()
            NSBezierPath.fillRect_(NSMakeRect(0, 0, px, px))

            # Grid lines
            NSColor.whiteColor().setStroke()
            gap = px * 0.08
            inner_x = gap
            inner_y = gap
            inner_w = px - 2 * gap
            inner_h = px - 2 * gap

            path = NSBezierPath.bezierPath()
            path.setLineWidth_(max(1, px * 0.02))

            # Outer rect
            path.appendBezierPathWithRect_(NSMakeRect(inner_x, inner_y, inner_w, inner_h))

            # Vertical line at 50%
            mid_x = inner_x + inner_w * 0.5
            path.moveToPoint_((mid_x, inner_y))
            path.lineToPoint_((mid_x, inner_y + inner_h))

            # Left side: 3 horizontal lines (3 rows)
            for i in range(1, 3):
                y = inner_y + inner_h * i / 3.0
                path.moveToPoint_((inner_x, y))
                path.lineToPoint_((mid_x, y))

            # Right side: 1 horizontal line (2 rows)
            y = inner_y + inner_h * 0.5
            path.moveToPoint_((mid_x, y))
            path.lineToPoint_((inner_x + inner_w, y))

            path.stroke()
            img.unlockFocus()

            rep = NSBitmapImageRep.alloc().initWithData_(img.TIFFRepresentation())
            png_data = rep.representationUsingType_properties_(4, {})  # 4 = PNG

            if scale == 1:
                filename = f"icon_{size}x{size}.png"
            else:
                filename = f"icon_{size}x{size}@2x.png"
            png_data.writeToFile_atomically_(os.path.join(iconset_dir, filename), True)

    print("Icons generated")
except ImportError:
    print("PyObjC not available, skipping icon generation")
PYEOF

# Convert iconset to icns if icons were generated
if ls "$ICONSET_DIR"/*.png 1>/dev/null 2>&1; then
    iconutil -c icns "$ICONSET_DIR" -o "$BUNDLE_PATH/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

echo ""
echo "✅ Installed to: $BUNDLE_PATH"
echo ""
echo "Next steps:"
echo "  1. Double-click 'Screen Divider' on your Desktop to launch"
echo "  2. Grant Accessibility permission when prompted (System Settings > Privacy & Security > Accessibility)"
echo "  3. Edit ~/.config/screendivider/config.json to customize layouts"
echo "  4. Drag the app to your Dock for quick access"
