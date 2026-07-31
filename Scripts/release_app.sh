#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SnapTrade Menu Bar"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
ARTIFACTS_DIR="$ROOT_DIR/.build/release-artifacts"
STAGING_DIR="$ARTIFACTS_DIR/dmg-staging"
PLIST="$ROOT_DIR/Bundle/Info.plist"

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"
SKIP_NOTARIZE=0
UNSIGNED=0

usage() {
  cat <<'USAGE'
Usage: Scripts/release_app.sh [--skip-notarize] [--unsigned]

Creates a release .dmg for SnapTrade Menu Bar.

Environment:
  DEVELOPER_ID_APPLICATION   Required unless --unsigned. Example:
                             Developer ID Application: SnapTrade Inc. (TEAMID)

  NOTARYTOOL_PROFILE         Preferred notarization auth. Created with:
                             xcrun notarytool store-credentials snaptrade-notary

  APPLE_ID                   Alternative notarization auth Apple ID.
  TEAM_ID                    Alternative notarization auth Team ID.
  APP_SPECIFIC_PASSWORD      Alternative notarization auth app-specific password.

Options:
  --skip-notarize            Build, sign, and package the .dmg without notarizing.
  --unsigned                 Build an unsigned local-test .dmg. Not suitable for users.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize)
      SKIP_NOTARIZE=1
      ;;
    --unsigned)
      UNSIGNED=1
      SKIP_NOTARIZE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"
}

require_tool swift
require_tool codesign
require_tool hdiutil
require_tool xcrun

VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
DMG_NAME="SnapTradeMenuBar-$VERSION-$BUILD.dmg"
DMG_PATH="$ARTIFACTS_DIR/$DMG_NAME"

if [[ "$UNSIGNED" -eq 0 ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "DEVELOPER_ID_APPLICATION is required for a distributable release." >&2
    echo "Available code-signing identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    exit 1
  fi

  if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "Signing identity not found: $SIGN_IDENTITY" >&2
    echo "Available code-signing identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    exit 1
  fi

  if [[ "$SKIP_NOTARIZE" -eq 0 && -z "$NOTARYTOOL_PROFILE" ]]; then
    if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_SPECIFIC_PASSWORD" ]]; then
      echo "Notarization credentials are required unless --skip-notarize is used." >&2
      echo "Set NOTARYTOOL_PROFILE, or set APPLE_ID, TEAM_ID, and APP_SPECIFIC_PASSWORD." >&2
      exit 1
    fi
  fi
fi

echo "Building $APP_NAME $VERSION ($BUILD)..."
"$ROOT_DIR/Scripts/package_app.sh" release >/dev/null

mkdir -p "$ARTIFACTS_DIR"

if [[ "$UNSIGNED" -eq 0 ]]; then
  echo "Signing app with $SIGN_IDENTITY..."
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"

  echo "Verifying app signature..."
  codesign --verify --strict --verbose=2 "$APP_DIR"
  spctl --assess --type execute --verbose "$APP_DIR"
else
  echo "Skipping signing. This artifact is only for local testing."
fi

echo "Creating dmg..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

if [[ "$UNSIGNED" -eq 0 ]]; then
  echo "Signing dmg..."
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

  if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo "Submitting dmg for notarization..."
    if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
      xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    else
      xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait
    fi

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  else
    echo "Skipping notarization."
  fi
fi

echo "Release artifact:"
echo "$DMG_PATH"
