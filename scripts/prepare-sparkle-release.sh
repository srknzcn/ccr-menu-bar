#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <tag>"
  echo "Example: $0 v1.4.0"
  exit 1
fi

TAG="$1"
REPO="srknzcn/ccr-menu-bar"
APP_NAME="CCR Menu Bar"
ZIP_NAME="CCR.Menu.Bar.zip"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
SIGN_UPDATE_ARGS=()

if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
  SIGN_UPDATE_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi

cd "$ROOT_DIR"

if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  swift package resolve
fi

./build-app.sh

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME"
RELEASE_NOTES_URL="https://github.com/$REPO/releases/tag/$TAG"
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "${SIGN_UPDATE_ARGS[@]}" "$ZIP_PATH")"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>CCR Menu Bar Updates</title>
    <link>https://srknzcn.github.io/ccr-menu-bar/</link>
    <description>Most recent CCR Menu Bar releases.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$DOWNLOAD_URL" $SIGNATURE_ATTRS type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo "Built update archive: $ZIP_PATH"
echo "Updated appcast: $APPCAST_PATH"
echo "Upload $ZIP_NAME to GitHub release $TAG before pushing the appcast live."
