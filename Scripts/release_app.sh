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
RELEASE_NOTES="${RELEASE_NOTES:-}"
SPARKLE_ACCOUNT="com.snaptrade.menubar"
UPDATES_DIR="$ARTIFACTS_DIR/updates"
SKIP_NOTARIZE=0
UNSIGNED=0
BETA=0
GENERATE_FEED=0

usage() {
  cat <<'USAGE'
Usage: Scripts/release_app.sh [--skip-notarize] [--unsigned] [--beta]

Creates a release .dmg for SnapTrade Menu Bar.

Environment:
  DEVELOPER_ID_APPLICATION   Required unless --unsigned or --beta. Example:
                             Developer ID Application: SnapTrade Inc. (TEAMID)

  NOTARYTOOL_PROFILE         Preferred notarization auth. Created with:
                             xcrun notarytool store-credentials snaptrade-notary

  APPLE_ID                   Alternative notarization auth Apple ID.
  TEAM_ID                    Alternative notarization auth Team ID.
  APP_SPECIFIC_PASSWORD      Alternative notarization auth app-specific password.
  RELEASE_NOTES             Required HTML or Markdown release notes for a published update.

Options:
  --skip-notarize            Build, sign, and package the .dmg without notarizing.
  --unsigned                 Build a local-test .dmg with updates disabled.
  --beta                     Build an ad hoc signed beta with Sparkle-signed updates.
                             No Apple Developer ID or notarization required.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize)
      SKIP_NOTARIZE=1
      ;;
    --beta)
      BETA=1
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

if [[ "$BETA" -eq 1 && ( "$UNSIGNED" -eq 1 || "$SKIP_NOTARIZE" -eq 1 ) ]]; then
  echo "--beta cannot be combined with --unsigned or --skip-notarize." >&2
  exit 2
fi
if [[ "$BETA" -eq 1 || ( "$UNSIGNED" -eq 0 && "$SKIP_NOTARIZE" -eq 0 ) ]]; then
  GENERATE_FEED=1
fi
if [[ "$GENERATE_FEED" -eq 1 && ! -f "$RELEASE_NOTES" ]]; then
  echo "Set RELEASE_NOTES to an HTML or Markdown release notes file." >&2
  exit 1
fi

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
if [[ "$GENERATE_FEED" -eq 1 && -e "$UPDATES_DIR/$DMG_NAME" ]]; then
  echo "Update $DMG_NAME already exists. Increment CFBundleVersion before releasing." >&2
  exit 1
fi

# A runtime override does not change the client ID shipped to users.
# Fail closed until the repository contains a verified production registration.
if [[ "$UNSIGNED" -eq 0 ]] && ! grep -Eq 'static let productionClientID: String\? = "[^"]+"' "$ROOT_DIR/Sources/SnapTradeMenuBarApp/Infrastructure/AppConfig.swift"; then
  echo "Production OAuth registration is not configured. No distributable release can be prepared." >&2
  echo "Verify a public native production client and exact loopback callback first." >&2
  exit 1
fi

if [[ "$UNSIGNED" -eq 0 && "$BETA" -eq 0 ]]; then
  if [[ "$SKIP_NOTARIZE" -eq 0 && ! -f "$RELEASE_NOTES" ]]; then
    echo "Set RELEASE_NOTES to an HTML or Markdown release notes file." >&2
    exit 1
  fi
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

if [[ "$GENERATE_FEED" -eq 1 ]]; then
  PUBLIC_KEY="$("$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"
  if [[ "$PUBLIC_KEY" != "$(plist_value SUPublicEDKey)" ]]; then
    echo "The Sparkle signing key does not match Bundle/Info.plist." >&2
    exit 1
  fi
fi

mkdir -p "$ARTIFACTS_DIR"

if [[ "$UNSIGNED" -eq 0 && "$BETA" -eq 0 ]]; then
  echo "Signing app with $SIGN_IDENTITY..."
  SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"

  echo "Verifying app signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
  if [[ "$UNSIGNED" -eq 1 ]]; then
    # Local-only packages do not participate in the beta update feed.
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_DIR/Contents/Info.plist"
  fi
  # Swift's linker signature covers the executable, not the assembled bundle.
  # Seal the complete bundle so quarantined test installs have a valid ad hoc
  # signature rather than failing integrity checks as a damaged application.
  echo "Applying an ad hoc signature for internal testing (no Developer ID)."
  codesign --force --sign - "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
fi

echo "Creating dmg..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

if [[ "$UNSIGNED" -eq 0 && "$BETA" -eq 0 ]]; then
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
    spctl --assess --type execute --verbose "$APP_DIR"
  else
    echo "Skipping notarization."
  fi
fi

if [[ "$GENERATE_FEED" -eq 1 ]]; then
  mkdir -p "$UPDATES_DIR"
  cp "$DMG_PATH" "$UPDATES_DIR/$DMG_NAME"
  cp "$RELEASE_NOTES" "$UPDATES_DIR/${DMG_NAME%.dmg}.${RELEASE_NOTES##*.}"
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://menubar.snaptrade.com/updates/" \
    --release-notes-url-prefix "https://menubar.snaptrade.com/updates/" \
    "$UPDATES_DIR"
  echo "Update feed and signed downloads: $UPDATES_DIR"
fi

echo "Release artifact:"
echo "$DMG_PATH"
