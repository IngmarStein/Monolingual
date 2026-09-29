#!/bin/bash
#
# Build, notarize and package a Monolingual release.
#
# Usage: scripts/release.sh
#
# Bumps nothing: the version is whatever Info.plist says, which is the version
# the release workflow checks the tag against. Writes into release-<version>/:
#
#   Monolingual-<version>.dmg     disk image, notarized and stapled
#   Monolingual-<version>.zip     app bundle, notarized and stapled
#   Monolingual.app.dSYM.zip      debug symbols
#   appcast.xml                   Sparkle feed for the zip
#
# Credentials: see scripts/notarize.sh. The Sparkle signing key is read from
# the login keychain unless SPARKLE_ED_KEY holds it, which is how CI passes it.

set -euo pipefail
cd "$(dirname "$0")/.."
TOP="$PWD"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Ingmar Stein (ADVP2P7SJK)}"
BUILD_DIR="$TOP/build"
APP="$BUILD_DIR/Monolingual.app"
DMG="$BUILD_DIR/Monolingual.dmg"

echo "==> Building..."
./scripts/build.sh Release

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
RELEASE_DIR="$TOP/release-$VERSION"
RELEASE_NAME="Monolingual-$VERSION"
RELEASE_ZIP="$RELEASE_DIR/$RELEASE_NAME.zip"

echo "==> Checking the build..."
codesign --verify --deep --strict --verbose=2 "$APP"
# The launch daemon registers the privileged helper. A release without it
# installs an app that can't remove anything.
test -f "$APP/Contents/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.PrivilegedHelper.plist"
test -x "$APP/Contents/MacOS/com.github.IngmarStein.Monolingual.Helper"

echo "==> Staging the disk image contents..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/build/.dmg-resources"
# The symbols are for the release directory, not for the disk image: whoever
# has the app has the debug symbols for it, and nothing else needs them.
cp -R "$BUILD_DIR/Monolingual.app.dSYM.zip" "$RELEASE_DIR"
cp -R "$APP" "$APP/Contents/Resources"/*.rtfd "$APP/Contents/Resources/LICENSE.txt" \
    "$RELEASE_DIR/build"
tiffutil -cathidpicheck "$TOP/dmg-bg.png" "$TOP/dmg-bg@2x.png" \
    -out "$RELEASE_DIR/build/.dmg-resources/dmg-bg.tiff"
ln -s /Applications "$RELEASE_DIR/build"

echo "==> Creating the disk image..."
./make-diskimage.sh "$DMG" "$RELEASE_DIR/build" Monolingual "$CODESIGN_IDENTITY" dmg.js

echo "==> Notarizing..."
# notarytool takes an archive, not a bundle, so the app is zipped for the
# submission and the zip thrown away again; the app itself is what gets
# stapled below and packaged for Sparkle.
NOTARY_ZIP="$BUILD_DIR/Monolingual-notarize.zip"
rm -f "$NOTARY_ZIP"
/usr/bin/ditto -c -k --rsrc --keepParent "$APP" "$NOTARY_ZIP"
./scripts/notarize.sh "$NOTARY_ZIP" "$DMG"
rm -f "$NOTARY_ZIP"

echo "==> Stapling..."
xcrun stapler staple "$APP"
xcrun stapler validate --verbose "$APP"
xcrun stapler staple "$DMG"
xcrun stapler validate --verbose "$DMG"

echo "==> Verifying with Gatekeeper..."
# Gatekeeper only accepts the app once the ticket has been stapled to it.
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
codesign -vvvv -R="notarized" --check-notarization "$DMG"

echo "==> Packaging..."
mv "$DMG" "$RELEASE_DIR/$RELEASE_NAME.dmg"
/usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"

echo "==> Signing the update feed..."
# Sparkle's sign_update is taken from the framework's own package artifacts
# rather than checked in, so the tool that writes the signature is always the
# version that ships in the app: an older copy signs a format the framework may
# no longer read.
SIGN_UPDATE=""
for CANDIDATE in "$BUILD_DIR"/DerivedData/SourcePackages/artifacts/sparkle/*/bin/sign_update; do
    if [ -x "$CANDIDATE" ]; then
        SIGN_UPDATE="$CANDIDATE"
        break
    fi
done
if [ -z "$SIGN_UPDATE" ]; then
    echo "Error: Sparkle's sign_update is not in the package artifacts;" >&2
    echo "the build did not fetch Sparkle into $BUILD_DIR/DerivedData." >&2
    exit 1
fi
if [ -n "${SPARKLE_ED_KEY:-}" ]; then
    SIGNATURE=$(printf '%s' "$SPARKLE_ED_KEY" | "$SIGN_UPDATE" --ed-key-file - "$RELEASE_ZIP")
else
    SIGNATURE=$("$SIGN_UPDATE" "$RELEASE_ZIP")
fi
sed -e "s/%VERSION%/$VERSION/g" \
    -e "s/%PUBDATE%/$(LC_ALL=C date +"%a, %d %b %G %T %z")/g" \
    -e "s/%FILENAME%/$RELEASE_NAME.zip/g" \
    -e "s@%SIGNATURE%@$SIGNATURE@g" \
    appcast.xml.tmpl > "$RELEASE_DIR/appcast.xml"

rm -rf "$RELEASE_DIR/build"

echo
echo "===== Monolingual $VERSION ====="
ls -l "$RELEASE_DIR"
