#!/bin/sh
set -euo pipefail

MODE="${1:-build}"
case "$MODE" in
    build|test)
        ;;
    *)
        echo "Usage: $0 [build|test]" >&2
        exit 1
        ;;
esac

DEVELOPER_DIR="${DEVELOPER_DIR:-}"

if [[ -z "$DEVELOPER_DIR" ]]; then
    if [[ -f "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]; then
        DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    fi
fi

if [[ -z "$DEVELOPER_DIR" || ! -d "$DEVELOPER_DIR" ]]; then
    echo "Full Xcode is required for SwiftUI macros. Install Xcode 15 or newer, or set DEVELOPER_DIR." >&2
    exit 1
fi

if [[ ! -f "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]; then
    echo "The selected developer directory does not contain the SwiftUI macro plugin. Full Xcode is required; Apple Command Line Tools are not sufficient." >&2
    exit 1
fi

BUNDLE_ID="com.leocwlau.ollameter"
APP_NAME="Ollameter"
BUILD_DIR=".build/release/Ollameter.app"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$REPO_ROOT/.build/clang-module-cache"
ASSETS_DIR="$REPO_ROOT/assets"
ICONSET_DIR="$ASSETS_DIR/Ollameter.iconset"

mkdir -p "$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

if [[ "$MODE" == "test" ]]; then
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/swift test --manifest-cache local --cache-path "$REPO_ROOT/.swiftpm-cache"
    exit 0
fi


if [[ -f "$ASSETS_DIR/Ollameter-1024.png" ]]; then
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 128 256 512; do
        /usr/bin/sips -s format png -z "$size" "$size" "$ASSETS_DIR/Ollameter-1024.png" \
            --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        /usr/bin/sips -s format png -z $((size * 2)) $((size * 2)) "$ASSETS_DIR/Ollameter-1024.png" \
            --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ASSETS_DIR/Ollameter.icns"
fi

DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/swift build --configuration release --manifest-cache local --cache-path "$REPO_ROOT/.swiftpm-cache"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources"

cp "$ASSETS_DIR/Ollameter.icns" "$BUILD_DIR/Contents/Resources/Ollameter.icns"
cp "$ASSETS_DIR/menu-bar-icon.png" "$BUILD_DIR/Contents/Resources/menu-bar-icon.png"
cp "$ASSETS_DIR/menu-bar-icon@2x.png" "$BUILD_DIR/Contents/Resources/menu-bar-icon@2x.png"

cat > "$BUILD_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Ollameter</string>
    <key>CFBundleExecutable</key>
    <string>Ollameter</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>Ollameter</string>
    <key>CFBundleName</key>
    <string>Ollameter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cp ".build/release/Ollameter" "$BUILD_DIR/Contents/MacOS/Ollameter"

codesign --force --sign - "$BUILD_DIR"

echo "$BUILD_DIR"
