#!/bin/bash
# build-app.sh — Builds CCRMenuBar.app bundle
set -e

APP_NAME="CCR Menu Bar"
BUNDLE_ID="com.ccr.menubar"
BUILD_DIR=".build/release"

# Build release
swift build -c release

# Create .app bundle
APP_DIR="${APP_NAME}.app/Contents"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

# Copy binary
cp "${BUILD_DIR}/CCRMenuBar" "${APP_DIR}/MacOS/CCRMenuBar"

# Copy resources bundle if it exists
RESOURCE_BUNDLE="${BUILD_DIR}/CCRMenuBar_CCRMenuBar.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Resources/"
fi

# Create Info.plist
cat > "${APP_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CCRMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.ccr.menubar</string>
    <key>CFBundleName</key>
    <string>CCR Menu Bar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

echo "Built: ${APP_NAME}.app"
echo "To install: cp -r '${APP_NAME}.app' /Applications/"
