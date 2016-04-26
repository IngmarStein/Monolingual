#!/bin/bash
set -ev
SWIFT_SNAPSHOT="swift-DEVELOPMENT-SNAPSHOT-2016-04-25-a"

echo "Installing ${SWIFT_SNAPSHOT}..."
if [ ! -f "${SWIFT_SNAPSHOT}-ubuntu14.04.tar.gz" ]; then
  curl -s -L -O "https://swift.org/builds/development/xcode/${SWIFT_SNAPSHOT}/${SWIFT_SNAPSHOT}-osx.pkg"
fi

sudo installer -package "${SWIFT_SNAPSHOT}-osx.pkg" -target /
rm -f "${SWIFT_SNAPSHOT}-osx.pkg"
