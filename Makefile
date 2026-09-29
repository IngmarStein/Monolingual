TOP=$(shell pwd)

.PHONY: all release development deployment clean

all: deployment

# Debug build
development: clean
	./scripts/build.sh Debug

# Release build
deployment: clean
	./scripts/build.sh Release

# Build, notarize and package a release. scripts/release.sh takes the version
# from Info.plist, so bump that before tagging; it writes release-<version>.
release: clean
	./scripts/release.sh

clean:
	-rm -rf $(TOP)/build
