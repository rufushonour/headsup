#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO="rufushonour/headsup"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")
DMG_NAME="HeadsUp-${VERSION}.dmg"
STAGING_DIR="$ROOT_DIR/build/appcast-staging"

GENERATE_APPCAST=$(find "$ROOT_DIR/.build" -type f -name generate_appcast -perm +111 2>/dev/null | head -1)
if [ -z "$GENERATE_APPCAST" ]; then
    echo "Could not find the generate_appcast tool. Run 'swift package resolve' first." >&2
    exit 1
fi

echo "Building HeadsUp $VERSION..."
"$ROOT_DIR/Scripts/build_dmg.sh" release

echo "Preparing appcast staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp "$ROOT_DIR/build/$DMG_NAME" "$STAGING_DIR/"
cp "$ROOT_DIR/appcast.xml" "$STAGING_DIR/appcast.xml"

DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/v${VERSION}/"

echo "Generating signed appcast entry..."
"$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_PREFIX" "$STAGING_DIR"

cp "$STAGING_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
rm -rf "$STAGING_DIR"

echo ""
echo "Done. appcast.xml updated for version $VERSION."
echo ""
echo "Next steps to publish (not run automatically):"
echo "  1. git add appcast.xml && git commit -m \"Release v$VERSION\" && git push"
echo "  2. gh release create v$VERSION build/$DMG_NAME --title \"v$VERSION\" --notes \"...\""
echo "     (the tag and asset filename must exactly match what's now in appcast.xml)"
