#!/bin/bash
#
# Build and sign Monolingual.
#
# Usage: scripts/build.sh [Debug|Release]      (default: Release)
#
# Produces, in build/:
#   Monolingual.app             the app, signed with a Developer ID identity
#   Monolingual.app.dSYM.zip    debug symbols
#   Monolingual.xcarchive       the archive both were taken from
#
# The signing identity and the team are build settings in the project, so a
# Developer ID Application certificate for team ADVP2P7SJK has to be in the
# keychain. scripts/release.sh and the release workflow both build through
# here, so they package the same app.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-Release}"

# Xcode 27 is the floor: the app deploys to macOS 27.
DEVELOPER_DIR="$(scripts/select-xcode.sh)"
export DEVELOPER_DIR

BUILD_DIR="$PWD/build"
ARCHIVE="$BUILD_DIR/Monolingual.xcarchive"

echo "==> Building Monolingual ($CONFIGURATION) with $(xcodebuild -version | head -1)..."

rm -rf "$ARCHIVE"
xcodebuild archive \
    -project Monolingual.xcodeproj \
    -scheme Monolingual \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$ARCHIVE"

echo "==> Collecting the app and its symbols..."
rm -rf "$BUILD_DIR/Monolingual.app" "$BUILD_DIR/Monolingual.app.dSYM" "$BUILD_DIR/Monolingual.app.dSYM.zip"
cp -R "$ARCHIVE/Products/Applications/Monolingual.app" "$BUILD_DIR/"
cp -R "$ARCHIVE/dSYMs/Monolingual.app.dSYM" "$BUILD_DIR/"
/usr/bin/ditto -c -k --keepParent "$BUILD_DIR/Monolingual.app.dSYM" "$BUILD_DIR/Monolingual.app.dSYM.zip"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILD_DIR/Monolingual.app/Contents/Info.plist")
echo "==> Done: build/Monolingual.app $VERSION"
