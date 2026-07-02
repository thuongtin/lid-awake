# Lid Awake

Lid Awake is a native macOS menu bar app for keeping a Mac awake during deliberate local work. It can hold standard idle sleep assertions and, when the user opts in, use an admin-approved helper to manage closed-lid sleep behavior.

Bundle identifier: `com.thuongtin.LidAwake`.

## Project Status

Lid Awake is early release software. Public downloads are Developer ID signed, notarized by Apple, and distributed as DMG and zip archives with SHA-256 checksums.
Release builds include Sparkle update metadata so users can check for signed updates from the app.

## Features

- Menu bar control for keeping the Mac awake.
- Battery and Low Power Mode guardrails.
- Optional launch at login.
- Optional closed-lid mode through a macOS-approved privileged helper.
- Display-on or display-off behavior for supported closed-lid workflows.
- Optional lock screen request when the lid closes.
- Sparkle-powered update checks from the menu bar and Settings.
- CI-safe checks separated from local runtime verification.
- Local release archive creation with SHA-256 checksum.

## Runtime Requirements

- macOS 14 or newer.
- Apple Silicon Mac. Current public builds are `arm64` only and do not run on Intel Macs.

## Development Requirements

- Xcode command line tools.
- Swift toolchain compatible with SwiftPM `swift-tools-version: 5.10`.

## Install

Install with Homebrew:

```bash
brew tap thuongtin/tap
brew install --cask lid-awake
```

The Homebrew cask declares `depends_on arch: :arm64`, so Intel Macs are blocked at install time.

Download the latest `LidAwake-<version>-macos.dmg` and matching `.sha256` file from [GitHub Releases](https://github.com/thuongtin/lid-awake/releases). The zip archive is also published for users who prefer scriptable downloads.

Verify the checksum:

```bash
cd ~/Downloads
shasum -a 256 -c LidAwake-<version>-macos.dmg.sha256
```

Then open the DMG and drag `LidAwake.app` to `Applications`. If you choose the zip archive instead, verify the matching `LidAwake-<version>-macos.zip.sha256` file before unzipping.

Release builds are notarized and stapled, including the DMG, so normal installs do not require `xattr`. If macOS still blocks the app, first confirm you downloaded the official release asset and that the checksum matches. Avoid `xattr -cr` for official releases unless you intentionally changed the archive or received it through a channel that added a quarantine problem outside the release package.

## Safety

Closed-lid behavior is hardware and macOS policy dependent. Running a MacBook while closed can increase heat under CPU, GPU, or charging load. Keep the machine ventilated, watch thermal behavior, and turn closed-lid mode off when it is no longer needed.

Lid Awake does not use `sudo` from the app. Closed-lid mode is an explicit user choice and requires macOS approval for the privileged helper before the app can ask it to run `pmset -a disablesleep 1` or `pmset -a disablesleep 0`.

The helper only accepts XPC clients identified by macOS code signing as `com.thuongtin.LidAwake`. See [Power Model](docs/power-model.md) for the helper trust boundary and power-management details.

## Build And Run

Run the CI-safe contributor check:

```bash
./scripts/check.sh
```

This command runs `swift test`, `swift build`, stages `dist/LidAwake.app`, and lints the staged `Info.plist`. It is safe for CI because it does not launch the app.

Run only the test suite:

```bash
swift test
```

Build all SwiftPM targets:

```bash
swift build
```

Stage the app bundle without launching:

```bash
./script/build_and_run.sh --stage
```

Build and launch the local app bundle:

```bash
./script/build_and_run.sh
```

Local debug staging leaves Sparkle update checks unconfigured by default. This prevents local builds from showing update errors before a public `appcast.xml` exists. To test a custom appcast locally, pass `SPARKLE_ENABLED=1` and `SPARKLE_FEED_URL=<url>` to `script/stage_app.sh` or `script/build_and_run.sh`; add `SPARKLE_ALLOW_INSECURE_FEED=1` if the local feed is not `https://` (for example `http://localhost`).

Optional local runtime verification lives in `scripts/verify.sh`. It may launch the app, delete `LidAwake.settings` defaults for verification, and check live `pmset` power assertions, so it is not used by CI and should run only on a developer Mac where runtime power-management QA is acceptable.

## Release Packaging

Create a local release archive:

```bash
./script/package_release.sh
```

Archives are written to `dist/releases` with a `.sha256` checksum. Public release packaging requires Developer ID signing by default, so read [Releasing](docs/releasing.md) before publishing a public build.

`./script/package_release.sh` is a public release gate by default and requires a `Developer ID Application` signing identity. For local archive testing only, run it with `ALLOW_NON_DEVELOPER_ID_RELEASE=1`.

After the app bundle is notarized and stapled, create a DMG installer:

```bash
./script/package_dmg.sh
```

After the notarized DMG is stapled, generate a Sparkle appcast:

```bash
./script/package_appcast.sh
```

The appcast is written to `dist/releases/appcast/appcast.xml`. Sparkle uses the public key in `scripts/sparkle_public_key.txt`; the matching private key must stay in Keychain or a local secret and must never be committed.

## Documentation

- [Agent Guide](AGENTS.md): verification commands, danger zones, and conventions for AI coding agents.
- [Power Model](docs/power-model.md): power-management behavior, helper trust boundary, and manual QA.
- [Developer Permissions Guide](docs/developer-permissions.md): helper approval, Accessibility, signing, and local permission diagnostics.
- [Releasing](docs/releasing.md): packaging, signing, checksum, and notarization guidance.
- [Troubleshooting](docs/troubleshooting.md): common helper, permission, and power assertion issues.
- [Contributing](CONTRIBUTING.md): development workflow and pull request expectations.
- [Security Policy](SECURITY.md): private reporting path for helper and power-management vulnerabilities.
- [Support](SUPPORT.md): where to ask questions and how to file useful issues.
- [Code of Conduct](CODE_OF_CONDUCT.md): community participation expectations.
- [Changelog](CHANGELOG.md): notable user-facing, packaging, and documentation changes.

## Project Layout

- `Sources/LidAwake`: menu bar app, settings UI, and app-side services.
- `Sources/LidAwakeCore`: shared policy, parsing, settings, power abstractions, and helper XPC contract.
- `Sources/LidAwakeHelper`: privileged helper entrypoint for closed-lid mode.
- `Tests/LidAwakeCoreTests`: deterministic unit tests for core behavior.
- `Tests/LidAwakeTests`: app lifecycle tests with fake services.
- `script/stage_app.sh`: pure app bundle staging without launching the app.
- `script/build_and_run.sh`: local stage, run, debug, logs, telemetry, and runtime verification entrypoint.
- `script/package_release.sh`: local release archive and checksum command.
- `script/package_dmg.sh`: DMG creation command for notarized and stapled app bundles.
- `script/package_appcast.sh`: Sparkle appcast generation command for notarized release archives.
- `scripts/sparkle_public_key.txt`: public Sparkle EdDSA key used by release builds.
- `scripts/check.sh`: CI-safe build, test, stage, and plist lint.
- `scripts/verify.sh`: optional local runtime smoke verification that may launch the app.
- `plans/`: implementation plans and reviewer status.

## Development Hygiene

Keep local scratch output and reference repositories outside the public source tree. The repository ignores `work/`, `outputs/`, `.codex/`, `dist/`, and Swift build output so local study material and generated artifacts do not become project artifacts.

## Current Limitations

- Intel Macs are not supported by current public release artifacts.
- Closed-lid mode requires explicit helper approval in System Settings.
- The local staged app uses development signing suitable for local testing.
- Self-update requires the published `appcast.xml` release asset to match the current notarized DMG.
- Closed-lid behavior may vary by Mac model, power source, lid state, and macOS policy.

## License

Lid Awake is available under the MIT License. See [LICENSE](LICENSE).
