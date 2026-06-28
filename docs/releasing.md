# Releasing Lid Awake

This project can create local test archives without Apple Developer secrets, but the default public release command requires Developer ID signing. Public releases also require notarization outside the repository.

## Local Archive

Create a release configuration app bundle, zip archive, and checksum for a public release:

```bash
./script/package_release.sh
```

The archive is written to `dist/releases/LidAwake-<version>-macos.zip` with a matching `.sha256` file. The version comes from `CFBundleShortVersionString` in the staged app `Info.plist`.

By default, `package_release.sh` requires a `Developer ID Application` signing identity and fails before packaging if it cannot find one. This prevents accidentally uploading Apple Development or ad-hoc signed archives as public downloads.

For local archive mechanics only, use the explicit escape hatch:

```bash
ALLOW_NON_DEVELOPER_ID_RELEASE=1 ./script/package_release.sh
```

That mode may use Apple Development or ad-hoc signing and should not be uploaded as a final public download. The advanced LaunchDaemon helper will not reliably run from an ad-hoc signed bundle on modern macOS.

## Signing Identity

For a public release, export a Developer ID signing identity before packaging if auto-detection does not select the right one:

```bash
export SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION"
CONFIGURATION=release ./script/stage_app.sh
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
2. Create the archive with `SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION" ./script/package_release.sh`.
3. Confirm `codesign --verify --deep --strict dist/LidAwake.app` exits 0.
4. Submit the zip with `xcrun notarytool submit` using `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`.
5. Wait for notarization to succeed.
6. Staple the ticket to `dist/LidAwake.app` with `xcrun stapler staple`.
7. Recreate the public zip and `.sha256` checksum after stapling.
8. Verify Gatekeeper behavior on a clean macOS machine before publishing.

Never commit Apple ID credentials, app-specific passwords, private keys, or certificate exports.

## Public Release Checklist

- `CHANGELOG.md` has the release version and date.
- `README.md` and `CONTRIBUTING.md` point to current packaging commands.
- `./scripts/check.sh` exits 0.
- `CONFIGURATION=release ./script/stage_app.sh` exits 0.
- `codesign --verify --deep --strict dist/LidAwake.app` exits 0.
- The notarized archive and `.sha256` checksum are uploaded together.
