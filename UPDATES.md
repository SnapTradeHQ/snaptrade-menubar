# App updates

Production uses Sparkle 2.9.6. It checks automatically and asks before installing.
The actions menu offers **Check for Updates…** in every connection state.
The first release containing Sparkle is 0.1.1 (build 2). Existing 0.1.0 users
must install it manually once; subsequent releases can be installed in the app.
Keep the production bundle ID and signing identity stable to preserve sessions.

Debug/Test builds never start Sparkle. `--unsigned` local-test packages have
their feed URL removed. `--beta` packages keep updates enabled: the app is
ad hoc signed and the update archive is signed with Sparkle EdDSA. Apple
Developer ID and notarization are optional for this beta workflow; initial
manual installation still requires the macOS security exception.

## Release prerequisites

- For notarized releases only: a valid Developer ID Application certificate
  and notarization credentials. These are not required for `--beta`.
- The Sparkle signing key in the release machine's login Keychain, account
  `com.snaptrade.menubar`. Its public key is committed in `Bundle/Info.plist`.
  The private key must stay out of source control and website hosting. Preserve
  it in a secure backup before moving or wiping the release machine.
- A working public feed at `https://menubar.snaptra.de/updates/appcast.xml`.

The release script checks that the local signing key matches the bundled public
key and generates an EdDSA-signed update entry for both beta and notarized
releases. For notarized releases it also signs Sparkle's helpers and framework
before the app and waits for notarization to succeed.

## Prepare an update

1. Increase `CFBundleVersion` in `Bundle/Info.plist` for every published build;
   also set the user-visible `CFBundleShortVersionString`. Never replace a
   published build with different bytes. Check the live feed when preparing
   releases from a new checkout; local duplicate detection is not a registry.
2. Write HTML or Markdown notes in `ReleaseNotes/`.
3. Run from the repository root:

   ```sh
   export DEVELOPER_ID_APPLICATION="Developer ID Application: SnapTrade Inc. (TEAMID)"
   export NOTARYTOOL_PROFILE="snaptrade-notary"
   export RELEASE_NOTES="$PWD/ReleaseNotes/<new-version>.md"
   export MENU_BAR_SITE_CHECKOUT="/path/to/current/MenuBar/Sites/checkout"
   export MENU_BAR_TAP_CHECKOUT="/path/to/SnapTradeHQ/homebrew-tap"
   Scripts/release_app.sh --stage-distribution
   ```

   For the current beta, use this instead (no Apple credentials):

   ```sh
   RELEASE_NOTES="$PWD/ReleaseNotes/0.1.1.md" Scripts/release_app.sh --beta
   ```

4. The script writes the DMG, notes, `appcast.xml`, and any generated deltas into
   `.build/release-artifacts/updates/`. Keep that directory between releases, or
   restore the previously published files first, to retain update history.
5. `--stage-distribution` requires clean, current checkouts of the MenuBar Sites
   source and `SnapTradeHQ/homebrew-tap`. It copies appcast-referenced assets
   into the Site, writes the DMG checksum file, changes both website download
   buttons and their version label, and updates the cask. It refuses to replace
   a published release filename with different bytes. It never publishes or
   pushes either checkout, and ignores `old_updates/` and unreferenced files.
6. Review and publish the Site through its normal Sites hosting workflow. The
   appcast and DMG must become live together. Fetch the live feed and new DMG
   to confirm HTTPS availability and that the DMG SHA-256 matches the staged
   cask. Check `ruby -c Casks/menubar.rb` in the tap checkout, then commit and
   push the cask. Run `brew update`, `brew audit --cask --strict
   snaptradehq/tap/menubar`, and `brew fetch --cask snaptradehq/tap/menubar`
   against the published tap. Keep the prior DMGs hosted for older Sparkle clients.
7. Test an older signed app updating to the new signed app, including relaunch
   and retention of sign-in. Local compilation alone does not validate
   installation, notarization, or live hosting.

`--beta` generates a Sparkle-signed update feed without Apple notarization.
`--unsigned` and `--skip-notarize` never generate a publishable update feed.
Nothing is uploaded automatically by the release script.

## Validation and rollout status

A beta installer and signed feed have been generated locally. The updater was
exercised using two isolated, ad hoc signed test apps served over localhost,
The test passed: build 1 downloaded and installed build 2, relaunched from the
same path, and retained the saved preference.
The test apps have a different bundle ID and do not access portfolio credentials.
This checks Sparkle's installation path; it does not establish Gatekeeper behavior
on a fresh Mac or confirm a live website deployment.

Before publishing, confirm the local update test passes, then deploy the beta
installer and feed together. Existing users still need the first updater-enabled
version installed manually. No Apple Developer ID is needed for that beta release.
