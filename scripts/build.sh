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

APP="$BUILD_DIR/Monolingual.app"
IDENTITY=$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)

if [ -n "$IDENTITY" ]; then
    # Xcode signs the Sparkle framework as it embeds it, but not the code
    # inside it: Sparkle ships Autoupdate, Updater.app and the two XPC services
    # ad-hoc signed, and archiving leaves them that way, which notarization
    # rejects twice over ("not signed with a valid Developer ID certificate" and
    # "does not include a secure timestamp"). Sparkle documents signing these
    # by hand for builds that don't go through Xcode's export step, which this
    # one doesn't, and warns against --deep: it signs nested code without the
    # order the seals need. Each nested item is signed before the framework and
    # the framework before the app, whose seal covers both.
    #
    # --preserve-metadata keeps the entitlements each item was built with --
    # Autoupdate loses com.apple.application-identifier without it -- and the
    # app keeps the sandbox and the exceptions it talks to the helper through.
    echo "==> Signing the code inside Sparkle with $IDENTITY..."
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
    for NESTED in \
        "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
        "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
        "$SPARKLE/Versions/B/Updater.app" \
        "$SPARKLE/Versions/B/Autoupdate"; do
        codesign --force --options runtime --timestamp \
            --preserve-metadata=entitlements,requirements --sign "$IDENTITY" "$NESTED"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE"
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements,requirements --sign "$IDENTITY" "$APP"
else
    echo "Warning: $APP is not signed by an authority; leaving it as archived." >&2
fi
/usr/bin/ditto -c -k --keepParent "$BUILD_DIR/Monolingual.app.dSYM" "$BUILD_DIR/Monolingual.app.dSYM.zip"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILD_DIR/Monolingual.app/Contents/Info.plist")
echo "==> Done: build/Monolingual.app $VERSION"
