#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
APP_NAME="HeadsUp"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")
DMG_NAME="HeadsUp-${VERSION}.dmg"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
DMG_PATH="$ROOT_DIR/build/$DMG_NAME"

echo "Building app ($CONFIG)..."
"$ROOT_DIR/Scripts/build_app.sh" "$CONFIG"

echo "Preparing DMG staging directory..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$ROOT_DIR/build/$APP_NAME.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_NAME ..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING_DIR"
echo "Done: $DMG_PATH"
