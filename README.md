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
open ".build/SnapTrade Menu Bar Test.app"
```

Debug packages are named **SnapTrade Menu Bar Test** and use a separate app
identifier, settings, sign-in storage, and portfolio cache. They can run alongside
the production app and show **TEST** in the menu bar. Sign in separately using your
normal SnapTrade account; both builds use production data. Complete one sign-in at
a time because both use the same local callback port. Rebuild with the command
above after code changes, then quit and reopen the test app.

## Release

### Offline currency previews

Run `bash Scripts/preview_currency.sh cad` or `bash Scripts/preview_currency.sh mixed`
to open a separate **SAMPLE** menu bar app with simulated API data. Quit the sample
before switching scenarios. The previews use the real aggregation and UI code,
do not connect to brokerages, and do not load or modify your saved sign-in.

CAD-only portfolios show CAD totals. Mixed portfolios display totals and positions
separately by currency, with no exchange-rate conversion or combined daily return.
Calculated totals sum holdings and cash in each native currency across all accounts.
Missing amounts prevent a complete calculated total for the affected currency.

Production OAuth is configured with the verified public-native MenuBar client.
See [PRODUCTION_ROLLOUT.md](PRODUCTION_ROLLOUT.md) for the verified prerequisites,
migration behavior, and exact challenge enrollment procedure. Signed release packaging
fails closed while `AppConfig.productionClientID` is unset.

To create a beta with Sparkle-signed updates, without Apple Developer ID:

```sh
RELEASE_NOTES="$PWD/ReleaseNotes/0.1.1.md" Scripts/release_app.sh --beta
```

This retains the initial macOS security-exception install flow. Updates are
verified using the Sparkle signing key stored in the release machine's Keychain.

To create a local unsigned `.dmg` with updates disabled for testing the installer layout:

```sh
Scripts/release_app.sh --unsigned
```

To create a distributable release for users, install a Developer ID Application
certificate and run:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: SnapTrade Inc. (TEAMID)"
export NOTARYTOOL_PROFILE="snaptrade-notary"
export RELEASE_NOTES="$PWD/ReleaseNotes/<new-version>.md"
export MENU_BAR_SITE_CHECKOUT="/path/to/current/MenuBar/Sites/checkout"
export MENU_BAR_TAP_CHECKOUT="/path/to/SnapTradeHQ/homebrew-tap"
Scripts/release_app.sh --stage-distribution
```

Create the notary profile once with:

```sh
xcrun notarytool store-credentials snaptrade-notary
```

The release script builds the app, signs it with hardened runtime, creates a
`.dmg`, submits it for notarization, staples the notarization ticket, and writes
the final artifact to `.build/release-artifacts/`. With `--stage-distribution`,
it also stages the signed downloads and feed in the current Sites checkout,
updates both website download links and the checksum label, and updates the
Homebrew cask version and checksum. Publish the Site and verify the live DMG
before pushing the cask. See [UPDATES.md](UPDATES.md) for the release order.

Production builds include Sparkle with **Check for Updates…** in the actions menu.
See [UPDATES.md](UPDATES.md) for update signing, feed publication, and the initial
manual upgrade. Debug/Test builds do not check for production updates.

The app uses an AppKit status item and popover, authorization code + PKCE, a loopback callback server, Keychain token storage, and `URLSession` for API calls.

Debug builds store OAuth tokens in app preferences to avoid repeated macOS Keychain prompts after every unsigned rebuild. Release builds use macOS Keychain.

## Configuration

The app offers display preferences for the menu bar and portfolio totals. Developers can override service defaults with environment variables:

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

The OAuth redirect URI is fixed at `http://127.0.0.1:18787/oauth/callback`.

The app defaults to the production client ID:

```text
JSuxSu887CLm80FO3lgqmN-32FsGtD1X
```

It also defaults to the fixed redirect URI mode so the registered callback is:

```text
http://127.0.0.1:18787/oauth/callback
```

Currency edge-case previews are also available: `foreign-holding` (a CAD account
with USD investments), `zero-foreign-cash`, `foreign-cash`, `missing-cash`,
`missing-total`, `unknown-currency`, `partial-total`, and `zero-total`.
For example, run `bash Scripts/preview_currency.sh foreign-holding`.
Broker-reported and calculated totals appear side by side in each currency group.
A group is shown only when either value is nonzero (including negative values).
Missing values remain unavailable; zero values remain zero. Missing broker totals
are flagged. No difference is shown because the columns group values differently.

Use `bash Scripts/preview_currency.sh mixed-assets` for two accounts reporting CAD
and USD respectively, each holding both CAD and USD investments and cash.
Broker totals are synthetic (CA$2,550 and US$1,800). Native calculated totals
are CA$1,800 and US$2,300, with no currency conversion.

On first sync, account results appear progressively as a partial portfolio.
Percentages and daily returns wait until the full sync completes. Later refreshes
keep the last complete portfolio visible. Partial results are never cached; a
failed first sync keeps them on screen with a retry action.
