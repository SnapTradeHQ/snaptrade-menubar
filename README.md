# SnapTrade Menu Bar

A native macOS menu bar app for SnapTrade Personal OAuth portfolio viewing.

## Build

```sh
swift build
swift run SnapTradeMenuBar
```

To create a menu-bar-only `.app` bundle:

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh debug
open ".build/SnapTrade Menu Bar.app"
```

## Release

To create a local unsigned `.dmg` for testing the installer layout:

```sh
Scripts/release_app.sh --unsigned
```

To create a distributable release for users, install a Developer ID Application
certificate and run:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: SnapTrade Inc. (TEAMID)"
export NOTARYTOOL_PROFILE="snaptrade-notary"
Scripts/release_app.sh
```

Create the notary profile once with:

```sh
xcrun notarytool store-credentials snaptrade-notary
```

The release script builds the app, signs it with hardened runtime, creates a
`.dmg`, submits it for notarization, staples the notarization ticket, and writes
the final artifact to `.build/release-artifacts/`.

The app uses SwiftUI `MenuBarExtra`, authorization code + PKCE, a loopback callback server, Keychain token storage, and `URLSession` for API calls.

Debug builds store OAuth tokens in app preferences to avoid repeated macOS Keychain prompts after every unsigned rebuild. Release builds use macOS Keychain.

## Configuration

The app does not expose editable settings. Developers can override build defaults with environment variables:

- `SNAPTRADE_CLIENT_ID`
- `SNAPTRADE_AUTHORIZE_URL`
- `SNAPTRADE_TOKEN_URL`
- `SNAPTRADE_REVOKE_URL`
- `SNAPTRADE_OAUTH_METADATA_URL`
- `SNAPTRADE_API_BASE_URL`
- `SNAPTRADE_SCOPE`

By default, production OAuth endpoints are discovered from:

```text
https://api.snaptrade.com/.well-known/oauth-authorization-server/mcp
```

The app relies on these values from the current published metadata:

- authorization endpoint: `https://dashboard.snaptrade.com/oauth/authorize`
- token endpoint: `https://api.snaptrade.com/oauth/token/`
- revocation endpoint: `https://api.snaptrade.com/oauth/revoke_token/`
- registration endpoint: `https://api.snaptrade.com/oauth/register/`
- scope: `read`
- grant types: `authorization_code`, `refresh_token`
- PKCE method: `S256`

The OAuth redirect URI is either a dynamic loopback URL or `http://127.0.0.1:18787/oauth/callback`.

The demo app defaults to client ID:

```text
OqgWgrKIfojI7ZhONa0xe8fRuqMuvKKE7Grn3H5r
```

It also defaults to the fixed redirect URI mode so the registered callback is:

```text
http://127.0.0.1:18787/oauth/callback
```
