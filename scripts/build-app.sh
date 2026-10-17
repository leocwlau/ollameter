#!/bin/sh
set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/SanDisk500G/Applications/Xcode.app/Contents/Developer}"
BUNDLE_ID="dev.ollameter.app"
APP_NAME="Ollameter"
BUILD_DIR=".build/release/Ollameter.app"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$REPO_ROOT/.build/clang-module-cache"

mkdir -p "$MODULE_CACHE"
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/swift build --configuration release --manifest-cache local --cache-path "$REPO_ROOT/.swiftpm-cache"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources"

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
    <key>CFBundleName</key>
    <string>Ollameter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
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
