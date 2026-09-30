#!/bin/bash
#
# Build and sign Monolingual.
#
# Usage: scripts/build.sh [Debug|Release]      (default: Release)
#
# Produces, in build/:
#   Monolingual.app             the app, signed with a Developer ID identity
#   Monolingual.app.dSYM.zip    debug symbols
#   Monolingual.xcarchive       the archive the app was exported from
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
cp -R "$ARCHIVE/dSYMs/Monolingual.app.dSYM" "$BUILD_DIR/"

ARCHIVED="$ARCHIVE/Products/Applications/Monolingual.app"
APP="$BUILD_DIR/Monolingual.app"
EXPORT_DIR="$BUILD_DIR/export"
ARCHIVED_PLIST="$ARCHIVED/Contents/Info.plist"

IDENTITY=$(codesign -dv --verbose=4 "$ARCHIVED" 2>&1 | sed -n 's/^Authority=//p' | head -1)
TEAM=$(codesign -dv --verbose=4 "$ARCHIVED" 2>&1 | sed -n 's/^TeamIdentifier=//p')

if [ -n "$IDENTITY" ]; then
    # The export is what signs the code inside Sparkle. Xcode signs the
    # framework as it embeds it but not what the framework carries: Autoupdate,
    # Updater.app and the two XPC services ship ad-hoc signed and stay that way
    # through archiving, and notarization rejects them twice over for it ("not
    # signed with a valid Developer ID certificate", "does not include a secure
    # timestamp"). Signing them by hand works, and Sparkle documents doing so,
    # but the export already knows how: it signs every nested item inside-out
    # with the identity the app was built with, and keeps the entitlements each
    # one was built with -- Autoupdate loses com.apple.application-identifier
    # otherwise.
    #
    # The export can't run on the archive as `xcodebuild archive` leaves it: it
    # reads an ApplicationProperties dictionary out of the archive's Info.plist
    # that the Xcode IDE writes and no command line component does. Without it
    # it refuses with "expected one {} but found developer-id" whichever method
    # the options plist names. Writing the dictionary is all it takes, and what
    # goes in it is read off the app that is being exported.
    echo "==> Exporting with $IDENTITY..."
    /usr/libexec/PlistBuddy \
        -c "Add :ApplicationProperties dict" \
        -c "Add :ApplicationProperties:ApplicationPath string Applications/Monolingual.app" \
        -c "Add :ApplicationProperties:CFBundleIdentifier string $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ARCHIVED_PLIST")" \
        -c "Add :ApplicationProperties:CFBundleShortVersionString string $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_PLIST")" \
        -c "Add :ApplicationProperties:CFBundleVersion string $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVED_PLIST")" \
        -c "Add :ApplicationProperties:SigningIdentity string $IDENTITY" \
        -c "Add :ApplicationProperties:Team string $TEAM" \
        "$ARCHIVE/Info.plist"

    EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM</string>
</dict>
</plist>
PLIST

    rm -rf "$EXPORT_DIR"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
    cp -R "$EXPORT_DIR/Monolingual.app" "$BUILD_DIR/"
else
    echo "Warning: $ARCHIVED is not signed by an authority; leaving it as archived." >&2
    cp -R "$ARCHIVED" "$BUILD_DIR/"
fi
/usr/bin/ditto -c -k --keepParent "$BUILD_DIR/Monolingual.app.dSYM" "$BUILD_DIR/Monolingual.app.dSYM.zip"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "==> Done: build/Monolingual.app $VERSION"
