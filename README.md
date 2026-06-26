# Lid Awake

Lid Awake is a native macOS menu bar app for keeping a Mac awake during deliberate local work. It can hold standard idle sleep assertions and, when the user opts in, use an admin-approved helper to manage closed-lid sleep behavior.

Bundle identifier: `com.thuongtin.LidAwake`.

## Project Status

Lid Awake is pre-release software. The source tree can build, test, stage, and package a local macOS app bundle, but public notarized releases still require Developer ID signing and notarization by a maintainer.

## Features

- Menu bar control for keeping the Mac awake.
- Battery and Low Power Mode guardrails.
- Optional launch at login.
- Optional closed-lid mode through a macOS-approved privileged helper.
- Display-on or display-off behavior for supported closed-lid workflows.
- Optional lock screen request when the lid closes.
- CI-safe checks separated from local runtime verification.
- Local release archive creation with SHA-256 checksum.

## Requirements

- macOS 14 or newer.
- Xcode command line tools.
- Swift toolchain compatible with SwiftPM `swift-tools-version: 5.10`.

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

Optional local runtime verification lives in `scripts/verify.sh`. It may launch the app, delete `LidAwake.settings` defaults for verification, and check live `pmset` power assertions, so it is not used by CI and should run only on a developer Mac where runtime power-management QA is acceptable.

## Release Packaging

Create a local release archive:

```bash
./script/package_release.sh
```

Archives are written to `dist/releases` with a `.sha256` checksum. Local archives use ad-hoc signing unless `SIGNING_IDENTITY` is set, so read [Releasing](docs/releasing.md) before publishing a public build.

## Documentation

- [Power Model](docs/power-model.md): power-management behavior, helper trust boundary, and manual QA.
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
- `scripts/check.sh`: CI-safe build, test, stage, and plist lint.
- `scripts/verify.sh`: optional local runtime smoke verification that may launch the app.
- `plans/`: implementation plans and reviewer status.

## Development Hygiene

Keep local scratch output and reference repositories outside the public source tree. The repository ignores `work/`, `outputs/`, `.codex/`, `dist/`, and Swift build output so local study material and generated artifacts do not become project artifacts.

## Current Limitations

- Public notarized releases require Developer ID signing and the checklist in `docs/releasing.md`.
- No auto-update channel is included.
- Closed-lid mode requires explicit helper approval in System Settings.
- The local staged app uses development signing suitable for local testing.
- Closed-lid behavior may vary by Mac model, power source, lid state, and macOS policy.

## License

Lid Awake is available under the MIT License. See [LICENSE](LICENSE).
