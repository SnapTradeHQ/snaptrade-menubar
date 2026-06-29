#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$ROOT_DIR/.build/SnapTrade Menu Bar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/Bundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PRODUCT_DIR/SnapTradeMenuBar" "$MACOS_DIR/SnapTradeMenuBar"
chmod +x "$MACOS_DIR/SnapTradeMenuBar"

echo "$APP_DIR"
