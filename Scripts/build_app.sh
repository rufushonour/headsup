#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-debug}"
APP_NAME="HeadsUp"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$ROOT_DIR/.build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "Build did not produce expected binary at $BIN_PATH" >&2
    exit 1
fi

SPARKLE_FRAMEWORK="$ROOT_DIR/.build/$CONFIG/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

echo "Packaging $APP_BUNDLE ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Ad-hoc code signing..."
SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$SPARKLE_DIR/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign - "$SPARKLE_DIR/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign - "$SPARKLE_DIR/Versions/B/Autoupdate"
codesign --force --sign - "$SPARKLE_DIR/Versions/B/Updater.app"
codesign --force --sign - "$SPARKLE_DIR"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
