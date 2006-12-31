RELEASE_DIR=release
RELEASE_NAME=Monolingual-1.3.6
BUILD_DIR=build/Deployment

.PHONY: all release development deployment clean

all: deployment

development:
	xcodebuild -target Monolingual -configuration Development build

deployment:
	xcodebuild -target Monolingual -configuration Deployment build

clean:
	xcodebuild -alltargets clean
	-rm -rf $(RELEASE_DIR)

release: deployment
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)/build
	cp -R $(BUILD_DIR)/Monolingual.app $(BUILD_DIR)/Monolingual.app/Contents/Resources/*.rtfd $(BUILD_DIR)/Monolingual.app/Contents/Resources/COPYING.txt $(RELEASE_DIR)/build
	mkdir -p $(RELEASE_DIR)/build/.dmg-resources
	cp -R dmg-bg.jpg $(RELEASE_DIR)/build/.dmg-resources/dmg-bg.jpg
	./make-diskimage.sh $(RELEASE_DIR)/$(RELEASE_NAME).dmg $(RELEASE_DIR)/build Monolingual dmg.scpt

