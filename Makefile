TOP=$(shell pwd)
RELEASE_VERSION=1.9.0
RELEASE_DIR=$(TOP)/release-$(RELEASE_VERSION)
RELEASE_NAME=Monolingual-$(RELEASE_VERSION)
RELEASE_FILE=$(RELEASE_DIR)/$(RELEASE_NAME).dmg
RELEASE_ZIPFILE=$(RELEASE_NAME).zip
RELEASE_ZIP=$(RELEASE_DIR)/$(RELEASE_ZIPFILE)
SOURCE_DIR=$(TOP)
BUILD_DIR=$(TOP)/build
CODESIGN_IDENTITY='Developer ID Application: Ingmar Stein (ADVP2P7SJK)'

.PHONY: all release development deployment archive clean

all: deployment

development: clean
	bundle exec fastlane debug

deployment: clean
	bundle exec fastlane release

clean:
	-rm -rf $(BUILD_DIR) $(RELEASE_DIR)

release: clean deployment
	# Check code signature
	codesign -vvv --deep --strict $(BUILD_DIR)/Monolingual.app
	# Check SMJobBless code signing setup
	./SMJobBlessUtil.py check $(BUILD_DIR)/Monolingual.app/Contents/XPCServices/Monolingual.xpc
	# Check app against Gatekeeper system policies
	spctl --assess --type execute -vv $(BUILD_DIR)/Monolingual.app
	mkdir -p $(RELEASE_DIR)/build
	cp -R $(BUILD_DIR)/Monolingual.app.dSYM.zip $(RELEASE_DIR)
	cp -R $(BUILD_DIR)/Monolingual.app $(BUILD_DIR)/Monolingual.app/Contents/Resources/*.rtfd $(BUILD_DIR)/Monolingual.app/Contents/Resources/LICENSE.txt $(RELEASE_DIR)/build
	mkdir -p $(RELEASE_DIR)/build/.dmg-resources
	tiffutil -cathidpicheck $(SOURCE_DIR)/dmg-bg.png $(SOURCE_DIR)/dmg-bg@2x.png -out $(RELEASE_DIR)/build/.dmg-resources/dmg-bg.tiff
	ln -s /Applications $(RELEASE_DIR)/build
	./make-diskimage.sh $(BUILD_DIR)/Monolingual.dmg $(RELEASE_DIR)/build Monolingual $(CODESIGN_IDENTITY) dmg.js
	# Verify DMG code signature
	spctl --assess --type open --context context:primary-signature -vv $(BUILD_DIR)/Monolingual.dmg
	# Notarize app and disk image
	bundle exec fastlane notarize
	xcrun stapler validate --verbose $(BUILD_DIR)/Monolingual.app
	xcrun stapler validate --verbose $(BUILD_DIR)/Monolingual.dmg
	# Verify notarization
	codesign -vvvv -R="notarized" --check-notarization $(BUILD_DIR)/Monolingual.dmg
	/usr/bin/ditto -c -k --keepParent $(BUILD_DIR)/Monolingual.app $(RELEASE_ZIP)
	mv $(BUILD_DIR)/Monolingual.dmg $(RELEASE_FILE)
	sed -e "s/%VERSION%/$(RELEASE_VERSION)/g" \
		-e "s/%PUBDATE%/$$(LC_ALL=C date +"%a, %d %b %G %T %z")/g" \
		-e "s/%SIZE%/$$(stat -f %z "$(RELEASE_ZIP)")/g" \
		-e "s/%FILENAME%/$(RELEASE_ZIPFILE)/g" \
		-e "s/%MD5%/$$(md5 -q $(RELEASE_ZIP))/g" \
		-e "s@%SIGNATURE%@$$(openssl dgst -sha1 -binary < $(RELEASE_ZIP) | openssl dgst -dss1 -sign ~/.ssh/monolingual_priv.pem | openssl enc -base64)@g" \
		appcast.xml.tmpl > $(RELEASE_DIR)/appcast.xml
	rm -rf $(RELEASE_DIR)/build
