# Contributing

Thanks for helping improve Lid Awake. This project touches local power behavior and a privileged helper, so changes should be narrow, explicit, and easy to verify.

Please read `CODE_OF_CONDUCT.md`, `SECURITY.md`, and `SUPPORT.md` before opening issues or pull requests.

## Prerequisites

- macOS 14 or newer.
- Xcode command line tools.
- Swift toolchain compatible with SwiftPM `swift-tools-version: 5.10`.

## Build And Test

Run the default CI-safe contributor check:

```bash
./scripts/check.sh
```

This command runs tests, builds targets, stages the app bundle, and lints the staged `Info.plist` without launching the app.

Run only the test suite:

```bash
swift test
```

Build all targets:

```bash
swift build
```

Run the app locally:

```bash
./script/build_and_run.sh
```

Stage the app bundle without launching:

```bash
./script/build_and_run.sh --stage
```

`scripts/verify.sh` is optional local runtime verification. It is not used by CI because it may launch the app, delete `LidAwake.settings` defaults for verification, and check live `pmset` power assertions.

Create a local release archive and checksum:

```bash
./script/package_release.sh
```

Release archives are written to `dist/releases`. See `docs/releasing.md` before publishing because public releases require Developer ID signing and notarization.

The release package script requires `Developer ID Application` signing by default. Use `ALLOW_NON_DEVELOPER_ID_RELEASE=1 ./script/package_release.sh` only when checking local archive mechanics without publishing the result.

Settings window activation uses AppKit and should be checked manually after UI changes: open the menu bar settings, confirm the app becomes active, close the window, and confirm the app returns to accessory behavior.

## Pull Requests

- Keep power-management behavior explicit and reversible.
- Do not add hidden changes to global macOS power settings.
- Add tests for parsing, policy, helper authorization, and state handling when those surfaces change.
- Include screenshots or short recordings for menu bar, settings, permission, and error-state UI changes.
- Describe any manual helper approval or `pmset` observations used during testing.
- Keep release packaging, notarization, and auto-update changes out of unrelated pull requests.
- Update `CHANGELOG.md` when user-visible behavior, packaging, or release process changes.

## Security-Sensitive Changes

The helper and `pmset` path require extra review. Any change to XPC authorization, `SMAppService`, LaunchDaemon plists, command execution, signing identifiers, or closed-lid restore behavior must explain the trust boundary and rollback behavior.

## Documentation Changes

Update the public docs when behavior changes:

- `README.md` for user-facing setup, build, and project overview changes.
- `docs/power-model.md` for power-management semantics and manual QA.
- `docs/troubleshooting.md` for recurring local setup or runtime issues.
- `docs/releasing.md` for packaging, signing, notarization, or checksum changes.
- `CHANGELOG.md` for notable user-visible or release-process changes.
