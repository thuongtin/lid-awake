# Releasing Lid Awake

This project can create local test archives without Apple Developer secrets, but the default public release command requires Developer ID signing. Public releases also require notarization outside the repository.

## Local Archive

Create a release configuration app bundle, zip archive, and checksum for a public release:

```bash
APP_VERSION=0.1.2 APP_BUILD=11 ./script/package_release.sh
```

The archive is written to `dist/releases/LidAwake-<version>-macos.zip` with a matching `.sha256` file. The version comes from `CFBundleShortVersionString` in the staged app `Info.plist`, and Sparkle orders updates by `CFBundleVersion`. Always increase `APP_BUILD` for every public archive.

After the app bundle is notarized and stapled, create the user-facing DMG:

```bash
./script/package_dmg.sh
```

The DMG is written to `dist/releases/LidAwake-<version>-macos.dmg` with a matching `.sha256` file. Public DMG packaging also requires a `Developer ID Application` signing identity by default.

By default, `package_release.sh` requires a `Developer ID Application` signing identity and fails before packaging if it cannot find one. This prevents accidentally uploading Apple Development or ad-hoc signed archives as public downloads.

For local archive mechanics only, use the explicit escape hatch:

```bash
ALLOW_NON_DEVELOPER_ID_RELEASE=1 ./script/package_release.sh
```

That mode may use Apple Development or ad-hoc signing and should not be uploaded as a final public download. The advanced LaunchDaemon helper will not reliably run from an ad-hoc signed bundle on modern macOS.

## Sparkle Update Signing

Sparkle update signing uses a public EdDSA key in the app bundle and a private key outside the repository.

The committed public key lives at `scripts/sparkle_public_key.txt` and is injected into `SUPublicEDKey` during staging. The matching private key was created under the Keychain account `com.thuongtin.LidAwake`.

To check the public key from Keychain:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.thuongtin.LidAwake \
  -p
```

To create a new key only when rotating update signing keys:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.thuongtin.LidAwake
```

Commit only the public key. Never commit a private EdDSA key, exported Keychain item, Apple ID credential, app-specific password, certificate export, or notarization profile.

The default appcast URL is:

```text
https://github.com/thuongtin/lid-awake/releases/latest/download/appcast.xml
```

Release staging enables Sparkle automatically and injects this feed URL plus `SUPublicEDKey`. Debug staging leaves Sparkle unconfigured by default so unreleased local builds do not show update retrieval errors. Override the feed for test channels with `SPARKLE_FEED_URL`; set `SPARKLE_ENABLED=1` when testing Sparkle from a debug bundle.

`script/stage_app.sh` validates these inputs before staging: it rejects a `SPARKLE_FEED_URL` that is not `https://` (or contains spaces or quotes), and it rejects a `SPARKLE_PUBLIC_ED_KEY` that is not a well-formed base64 Ed25519 public key. `SPARKLE_ALLOW_INSECURE_FEED=1` bypasses the HTTPS requirement for local testing only (for example against `http://localhost`) and must never be set when staging a public release.

## Signing Identity

For a public release, export a Developer ID signing identity before packaging if auto-detection does not select the right one:

```bash
export SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION"
APP_VERSION=0.1.2 APP_BUILD=11 CONFIGURATION=release ./script/stage_app.sh
```

Use a Developer ID Application certificate for `DEVELOPER_ID_APPLICATION`. Keep the bundle identifiers unchanged:

- `com.thuongtin.LidAwake`
- `com.thuongtin.LidAwake.Helper`

The helper authorization checks depend on the app retaining the `com.thuongtin.LidAwake` identity.

## Notarization

Use placeholder environment variables for notarization credentials:

```bash
export APPLE_ID="developer@example.com"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_APP_SPECIFIC_PASSWORD="app-specific-password"
```

High-level public release flow:

1. Confirm `./scripts/check.sh` exits 0.
2. Create the archive with `APP_VERSION=<version> APP_BUILD=<increasing-build> SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION" ./script/package_release.sh`.
3. Confirm `codesign --verify --deep --strict dist/LidAwake.app` exits 0.
4. Submit the zip with `xcrun notarytool submit` using `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`.
5. Wait for notarization to succeed.
6. Staple the ticket to `dist/LidAwake.app` with `xcrun stapler staple`.
7. Recreate the public zip and `.sha256` checksum after stapling.
8. Create the DMG with `./script/package_dmg.sh`.
9. Submit the DMG with `xcrun notarytool submit`.
10. Wait for DMG notarization to succeed.
11. Staple the ticket to the DMG with `xcrun stapler staple`.
12. Recreate the DMG `.sha256` checksum after stapling.
13. Generate the Sparkle appcast with `./script/package_appcast.sh`.
14. Verify Gatekeeper behavior on the DMG and on the app inside the mounted DMG before publishing.
15. Upload the DMG, zip, checksum files, `appcast.xml`, and `appcast.xml.sha256` to the GitHub release.

For the default GitHub release channel, `package_appcast.sh` uses:

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/thuongtin/lid-awake/releases/download/v<version>/"
```

Use `SPARKLE_RELEASE_NOTES=/path/to/release-notes.md` if the appcast item should embed release notes. Use `SPARKLE_ED_KEY_FILE` or `SPARKLE_PRIVATE_KEY` only in local automation where the secret is supplied from a secure store.

Never commit Apple ID credentials, app-specific passwords, private keys, or certificate exports.

## Public Release Checklist

- `CHANGELOG.md` has the release version and date.
- `README.md` and `CONTRIBUTING.md` point to current packaging commands.
- `./scripts/check.sh` exits 0.
- `APP_VERSION=<version> APP_BUILD=<increasing-build> CONFIGURATION=release ./script/stage_app.sh` exits 0.
- `dist/LidAwake.app/Contents/Frameworks/Sparkle.framework` exists.
- `dist/LidAwake.app/Contents/Info.plist` contains `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, and `SUScheduledCheckInterval`.
- `codesign --verify --deep --strict dist/LidAwake.app` exits 0.
- `spctl -a -vv --type open --context context:primary-signature dist/releases/LidAwake-<version>-macos.dmg` reports `accepted`.
- `./script/package_appcast.sh` exits 0 and writes `dist/releases/appcast/appcast.xml`.
- The notarized DMG, zip archive, appcast, and `.sha256` checksums are uploaded together.

## Homebrew Tap

The current Homebrew tap is `thuongtin/homebrew-tap`, installed by users as `thuongtin/tap`.

Update `Casks/lid-awake.rb` in that tap after publishing a GitHub release:

- Set `version` to the release version.
- Set `sha256` to the DMG checksum.
- Keep `auto_updates true` after the Sparkle appcast asset is uploaded and verified.
- Keep `depends_on arch: :arm64` while release binaries are Apple Silicon only.
- Run `brew audit --cask --strict --online thuongtin/tap/lid-awake`.
- Run `brew fetch --cask --force thuongtin/tap/lid-awake`.
- Run `brew install --cask --dry-run thuongtin/tap/lid-awake`.
