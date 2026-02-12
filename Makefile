PROJECT := ThingLight.xcodeproj
SCHEME := ThingLight
CONFIGURATION := Debug
DERIVED_DATA := build
DESTINATION := platform=macOS

XCODEBUILD := xcodebuild \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED_DATA) \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY=""

APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(SCHEME).app

.PHONY: help build test clean run check-metal download-metal

help:
	@echo "Targets:"
	@echo "  make build          Build app"
	@echo "  make test           Run tests"
	@echo "  make run            Build and launch app"
	@echo "  make clean          Remove derived data"
	@echo "  make check-metal    Verify Metal compiler availability"
	@echo "  make download-metal Download Metal toolchain component"

build:
	$(XCODEBUILD) -destination '$(DESTINATION)' build

test:
	$(XCODEBUILD) -destination '$(DESTINATION)' test

run: build
	open "$(APP_PATH)"

clean:
	rm -rf "$(DERIVED_DATA)"

check-metal:
	@xcrun -k >/dev/null 2>&1 || true
	@xcrun metal -v

download-metal:
	xcodebuild -downloadComponent MetalToolchain
