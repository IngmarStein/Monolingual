#!/bin/bash
set -ev
SWIFT_SNAPSHOT="swift-3.0-PREVIEW-4"

echo "Installing ${SWIFT_SNAPSHOT}..."
if [ ! -f "${SWIFT_SNAPSHOT}-osx.pkg" ]; then
  curl -s -L -O "https://swift.org/builds/$(echo $SWIFT_SNAPSHOT | tr A-Z a-z)/xcode/${SWIFT_SNAPSHOT}/${SWIFT_SNAPSHOT}-osx.pkg"
fi

sudo installer -package "${SWIFT_SNAPSHOT}-osx.pkg" -target /
rm -f "${SWIFT_SNAPSHOT}-osx.pkg"
