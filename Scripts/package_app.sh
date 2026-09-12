#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_NAME="SnapTrade Menu Bar"
BUNDLE_ID="com.snaptrade.menubar"
if [[ "$CONFIGURATION" == "debug" ]]; then
  APP_NAME="SnapTrade Menu Bar Test"
  BUNDLE_ID="com.snaptrade.menubar.test"
fi
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$CONTENTS_DIR/Frameworks/Sparkle.framework"
cp "$ROOT_DIR/Branding/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/Bundle/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS_DIR/Info.plist"
cp "$PRODUCT_DIR/SnapTradeMenuBar" "$MACOS_DIR/SnapTradeMenuBar"
chmod +x "$MACOS_DIR/SnapTradeMenuBar"

echo "$APP_DIR"
