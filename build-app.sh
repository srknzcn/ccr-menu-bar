#!/bin/bash
# build-app.sh — Builds CCR Menu Bar.app via xcodebuild (includes icons & assets)
set -e

APP_NAME="CCR Menu Bar"
BUILD_DIR="$(pwd)/build"

# Regenerate Xcode project
echo "Generating Xcode project..."
xcodegen generate

# Clean & build release
echo "Building release..."
rm -rf "$BUILD_DIR"
xcodebuild \
  -project CCRMenuBar.xcodeproj \
  -scheme CCRMenuBar \
  -configuration Release \
  -derivedDataPath /tmp/ccr-deriveddata \
  clean build \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  -quiet

# Verify
if [ -d "$BUILD_DIR/${APP_NAME}.app" ]; then
  echo ""
  echo "Built: $BUILD_DIR/${APP_NAME}.app"
  echo "To install: cp -r '$BUILD_DIR/${APP_NAME}.app' /Applications/"
else
  echo "ERROR: Build failed — .app not found"
  exit 1
fi
