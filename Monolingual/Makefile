RELEASE_DIR=release
RELEASE_VERSION=1.4.4
RELEASE_NAME=Monolingual-$(RELEASE_VERSION)
RELEASE_FILE=$(RELEASE_DIR)/$(RELEASE_NAME).dmg
BUILD_DIR=build/Release
CHECK_DIR=$(PWD)/check

.PHONY: all release development deployment clean check

all: deployment

development:
	xcodebuild -target Monolingual -configuration Debug build

deployment:
	xcodebuild -target Monolingual -configuration Release build

clean:
	xcodebuild -alltargets clean
	-rm -rf $(RELEASE_DIR) $(CHECK_DIR)

check:
	scan-build -o $(CHECK_DIR) -v xcodebuild -target Monolingual -configuration Debug

release: deployment
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)/build
	cp -R $(BUILD_DIR)/Monolingual.app $(BUILD_DIR)/Monolingual.app/Contents/Resources/*.rtfd $(BUILD_DIR)/Monolingual.app/Contents/Resources/COPYING.txt $(RELEASE_DIR)/build
	mkdir -p $(RELEASE_DIR)/build/.dmg-resources
	cp -R dmg-bg.jpg $(RELEASE_DIR)/build/.dmg-resources/dmg-bg.jpg
	ln -s /Applications $(RELEASE_DIR)/build
	./make-diskimage.sh $(RELEASE_FILE) $(RELEASE_DIR)/build Monolingual dmg.scpt
	sed -e "s/%VERSION%/$(RELEASE_VERSION)/g" \
		-e "s/%PUBDATE%/$$(LC_ALL=C date +"%a, %d %b %G %T %z")/g" \
		-e "s/%SIZE%/$$(stat -f %z "$(RELEASE_FILE)")/g" \
		-e "s/%FILENAME%/$(RELEASE_NAME).dmg/g" \
		-e "s/%MD5%/$$(md5 -q $(RELEASE_FILE))/g" \
		-e "s@%SIGNATURE%@$$(openssl dgst -sha1 -binary < $(RELEASE_FILE) | openssl dgst -dss1 -sign ~/.ssh/monolingual_priv.pem | openssl enc -base64)@g" \
		appcast.xml.tmpl > appcast.xml
