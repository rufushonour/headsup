#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>   e.g. $0 0.1.1" >&2
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like X.Y.Z, got: $VERSION" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree isn't clean. Commit or stash changes before cutting a release." >&2
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
    echo "You're on '$BRANCH', not 'main'. Switch to main before cutting a release." >&2
    exit 1
fi

echo "Bumping Info.plist to $VERSION..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist

git add Resources/Info.plist
git commit -m "Bump version to $VERSION"
git push origin main

git tag "v$VERSION"
git push origin "v$VERSION"

echo ""
echo "Pushed v$VERSION — .github/workflows/release.yml will build, sign, and publish it."
echo "Watch it with: gh run watch"
