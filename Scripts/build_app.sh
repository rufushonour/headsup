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

# CODESIGN_IDENTITY can be set explicitly (CI does this after importing a cert into a
# fresh keychain). Locally, auto-detect a "Developer ID Application" identity if one's
# in the login keychain; otherwise fall back to ad-hoc signing (dev-only, no notarization).
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
fi

SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Code signing with $SIGN_IDENTITY..."
    SIGN_EXTRA_ARGS="--options runtime --timestamp"
else
    echo "Ad-hoc code signing (no Developer ID identity found — set CODESIGN_IDENTITY to sign for notarization)..."
    SIGN_IDENTITY="-"
    SIGN_EXTRA_ARGS=""
fi

# $SIGN_EXTRA_ARGS is deliberately unquoted below to word-split (or vanish when empty) —
# macOS's default /bin/bash is 3.2, where "${empty_array[@]}" throws "unbound variable"
# under `set -u`, so a plain string is used instead of an array.
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR"
codesign --force --deep --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
