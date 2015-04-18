TOP=$(shell pwd)
RELEASE_VERSION=1.6.8
RELEASE_DIR=release-$(RELEASE_VERSION)
RELEASE_NAME=Monolingual-$(RELEASE_VERSION)
RELEASE_FILE=$(RELEASE_DIR)/$(RELEASE_NAME).dmg
BUILD_DIR=$(TOP)/build
ARCHIVE_NAME=$(RELEASE_NAME).xcarchive
ARCHIVE=$(BUILD_DIR)/$(ARCHIVE_NAME)
XCODEBUILD=$(shell which xctool || echo "xcodebuild")

.PHONY: all release development deployment archive clean

all: deployment

development:
	$(XCODEBUILD) -workspace Monolingual.xcworkspace -scheme Monolingual -configuration Debug build CONFIGURATION_BUILD_DIR=$(BUILD_DIR)

deployment:
	$(XCODEBUILD) -workspace Monolingual.xcworkspace -scheme Monolingual -configuration Release build CONFIGURATION_BUILD_DIR=$(BUILD_DIR)

archive:
	$(XCODEBUILD) -workspace Monolingual.xcworkspace -scheme Monolingual -configuration Release archive -archivePath $(ARCHIVE)
	xcodebuild -exportArchive -exportFormat APP -archivePath $(ARCHIVE) -exportPath $(BUILD_DIR)/Monolingual.app -exportWithOriginalSigningIdentity

clean:
	-rm -rf $(BUILD_DIR) $(RELEASE_DIR)

release: clean archive
	# Check code signature
	codesign -vvv --deep $(BUILD_DIR)/Monolingual.app
	# Check SMJobBless code signing setup
	./SMJobBlessUtil.py check $(BUILD_DIR)/Monolingual.app/Contents/XPCServices/Monolingual.xpc
	# Check app against Gatekeeper system policies
	spctl -vv --assess --type execute $(BUILD_DIR)/Monolingual.app
	mkdir -p $(RELEASE_DIR)/build
	cp -R $(ARCHIVE) $(RELEASE_DIR)
	cp -R $(BUILD_DIR)/Monolingual.app $(BUILD_DIR)/Monolingual.app/Contents/Resources/*.rtfd $(BUILD_DIR)/Monolingual.app/Contents/Resources/LICENSE.txt $(RELEASE_DIR)/build
	mkdir -p $(RELEASE_DIR)/build/.dmg-resources
	cp dmg-bg.tiff $(RELEASE_DIR)/build/.dmg-resources/dmg-bg.tiff
	ln -s /Applications $(RELEASE_DIR)/build
	./make-diskimage.sh $(RELEASE_FILE) $(RELEASE_DIR)/build Monolingual dmg.js
	sed -e "s/%VERSION%/$(RELEASE_VERSION)/g" \
		-e "s/%PUBDATE%/$$(LC_ALL=C date +"%a, %d %b %G %T %z")/g" \
		-e "s/%SIZE%/$$(stat -f %z "$(RELEASE_FILE)")/g" \
		-e "s/%FILENAME%/$(RELEASE_NAME).dmg/g" \
		-e "s/%MD5%/$$(md5 -q $(RELEASE_FILE))/g" \
		-e "s@%SIGNATURE%@$$(openssl dgst -sha1 -binary < $(RELEASE_FILE) | openssl dgst -dss1 -sign ~/.ssh/monolingual_priv.pem | openssl enc -base64)@g" \
		appcast.xml.tmpl > $(RELEASE_DIR)/appcast.xml
	rm -rf $(RELEASE_DIR)/build
