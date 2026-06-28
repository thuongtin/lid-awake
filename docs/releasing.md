# Releasing Lid Awake

This project can create local archives without Apple Developer secrets. Public releases require Developer ID signing and notarization outside the repository.

## Local Archive

Create a release configuration app bundle, zip archive, and checksum:

```bash
./script/package_release.sh
```

The archive is written to `dist/releases/LidAwake-<version>-macos.zip` with a matching `.sha256` file. The version comes from `CFBundleShortVersionString` in the staged app `Info.plist`.

By default, staging uses the first available `Developer ID Application` or `Apple Development` code signing identity. If none is available, it falls back to ad-hoc signing. An ad-hoc archive is useful for packaging checks, but the advanced LaunchDaemon helper will not run from an ad-hoc signed bundle and the archive should not be uploaded as a final public download.

## Signing Identity

For a public release, export a Developer ID signing identity before packaging:

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
2. Build and sign with `SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION" CONFIGURATION=release ./script/stage_app.sh`.
3. Create the archive with `./script/package_release.sh` or zip the signed staged app with `ditto -c -k --keepParent`.
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
