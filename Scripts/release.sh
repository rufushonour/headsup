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

if [ -n "${APPLE_NOTARY_KEY_ID:-}" ] && [ -n "${APPLE_NOTARY_ISSUER_ID:-}" ] && [ -n "${APPLE_NOTARY_KEY_PATH:-}" ]; then
    echo "Submitting $DMG_NAME for notarization..."
    # Apple's notary service occasionally leaves submissions stuck "In Progress" for a
    # very long time (a known, recurring issue, not specific to this project — see Apple
    # Developer Forums). --timeout bounds how long this waits so a stuck submission fails
    # the build instead of hanging indefinitely and burning CI minutes. The submission
    # itself isn't cancelled by this timeout; check its status with
    # `xcrun notarytool info <id>` and rerun once it resolves.
    xcrun notarytool submit "$ROOT_DIR/build/$DMG_NAME" \
        --key "$APPLE_NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" \
        --wait \
        --timeout 20m

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$ROOT_DIR/build/$DMG_NAME"
else
    echo "Skipping notarization (APPLE_NOTARY_KEY_ID / APPLE_NOTARY_ISSUER_ID / APPLE_NOTARY_KEY_PATH not set)."
fi

echo "Preparing appcast staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp "$ROOT_DIR/build/$DMG_NAME" "$STAGING_DIR/"
cp "$ROOT_DIR/appcast.xml" "$STAGING_DIR/appcast.xml"

DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/v${VERSION}/"

echo "Generating signed appcast entry..."
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    # CI path: key is supplied via a secret env var, piped straight in, never written to disk.
    echo "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - --download-url-prefix "$DOWNLOAD_PREFIX" "$STAGING_DIR"
else
    # Local path: key lives in this Mac's Keychain.
    "$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_PREFIX" "$STAGING_DIR"
fi

cp "$STAGING_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
rm -rf "$STAGING_DIR"

echo ""
echo "Done. appcast.xml updated for version $VERSION."

if [ -z "${CI:-}" ]; then
    echo ""
    echo "Next steps to publish (not run automatically):"
    echo "  1. git add appcast.xml && git commit -m \"Release v$VERSION\" && git push"
    echo "  2. gh release create v$VERSION build/$DMG_NAME --title \"v$VERSION\" --notes \"...\""
    echo "     (the tag and asset filename must exactly match what's now in appcast.xml)"
    echo ""
    echo "Or just push a tag matching Info.plist's version (e.g. git tag v$VERSION && git push origin v$VERSION)"
    echo "and .github/workflows/release.yml will do all of the above for you."
fi
