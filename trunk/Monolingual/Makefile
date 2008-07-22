RELEASE_DIR=release
RELEASE_NAME=Monolingual-1.3.9
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
	./make-diskimage.sh $(RELEASE_DIR)/$(RELEASE_NAME).dmg $(RELEASE_DIR)/build Monolingual dmg.scpt
	md5 $(RELEASE_DIR)/$(RELEASE_NAME).dmg
	ls -l $(RELEASE_DIR)/$(RELEASE_NAME).dmg | awk '{ print($$5) }'

