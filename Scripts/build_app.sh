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

# Ad-hoc signing is the default on purpose: a Developer ID signature *without*
# notarization is rejected by Gatekeeper (source=Unnotarized Developer ID), and that
# rejection silently breaks TCC prompts (Calendar access, etc.) with no visible dialog
# and no error — a real bug hunted down the hard way. So local dev builds stay ad-hoc
# unless CODESIGN_IDENTITY is explicitly set (CI sets it after importing a cert and
# pairs it with real notarization — see release.sh). Don't reintroduce auto-detecting a
# keychain identity here.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

if [ -z "$SIGN_IDENTITY" ]; then
    # Local ad-hoc dev builds get a separate bundle identifier from the shipped app, so
    # local testing never shares (or resets) the real app's Calendar TCC grant, and so
    # LaunchServices never has two different builds fighting over the same identity.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.rufushonour.headsup" "$APP_BUNDLE/Contents/Info.plist"
fi

SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Code signing with $SIGN_IDENTITY..."
    SIGN_EXTRA_ARGS="--options runtime --timestamp"
    # Hardened runtime enforces entitlement-gated TCC prompts: without this entitlement,
    # tccd silently denies Calendar access instead of showing the system prompt at all
    # (no dialog, no error — "Policy disallows prompt" in the unified log). Ad-hoc builds
    # never hit this because they don't have hardened runtime enabled. Only the top-level
    # app needs it, not Sparkle's nested XPC helpers.
    APP_ENTITLEMENTS_ARGS="--entitlements $ROOT_DIR/Resources/HeadsUp.entitlements"
else
    echo "Ad-hoc code signing (set CODESIGN_IDENTITY to sign with a Developer ID — only useful if you'll also notarize, e.g. via release.sh)..."
    SIGN_IDENTITY="-"
    SIGN_EXTRA_ARGS=""
    APP_ENTITLEMENTS_ARGS=""
fi

# $SIGN_EXTRA_ARGS/$APP_ENTITLEMENTS_ARGS are deliberately unquoted below to word-split
# (or vanish when empty) — macOS's default /bin/bash is 3.2, where "${empty_array[@]}"
# throws "unbound variable" under `set -u`, so a plain string is used instead of an array.
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR/Versions/B/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS "$SPARKLE_DIR"
codesign --force --deep --sign "$SIGN_IDENTITY" $SIGN_EXTRA_ARGS $APP_ENTITLEMENTS_ARGS "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
