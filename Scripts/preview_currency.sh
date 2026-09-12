#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${1:-cad}"
case "$FIXTURE" in cad|mixed|mixed-assets|foreign-holding|zero-foreign-cash|foreign-cash|missing-cash|missing-total|unknown-currency|partial-total|zero-total) ;; *) echo "Usage: Scripts/preview_currency.sh [cad|mixed|mixed-assets|foreign-holding|zero-foreign-cash|foreign-cash|missing-cash|missing-total|unknown-currency|partial-total|zero-total]" >&2; exit 2 ;; esac
cd "$ROOT_DIR"
mkdir -p .build/currency-previews
SNAPTRADE_FIXTURE_OUTPUT_DIR="$ROOT_DIR/.build/currency-previews" swift test --filter PortfolioAggregatorTests
"$ROOT_DIR/Scripts/package_app.sh" debug
PREVIEW_APP="$ROOT_DIR/.build/SnapTrade Currency Preview.app"
ditto "$ROOT_DIR/.build/SnapTrade Menu Bar Test.app" "$PREVIEW_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.snaptrade.menubar.currency-preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName SnapTrade Currency Preview' "$PREVIEW_APP/Contents/Info.plist"
open --env "SNAPTRADE_PREVIEW_SNAPSHOT=$ROOT_DIR/.build/currency-previews/$FIXTURE.json" "$PREVIEW_APP"
