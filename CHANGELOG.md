# Changelog

All notable changes to Lid Awake will be documented in this file.

The format follows dated release sections after the first tagged release.

## Unreleased

- Improved closed-lid display-off reliability on multi-monitor setups by retrying display sleep during the first closed-lid transition ticks, removing the `ScreenSaverEngine.app` lock fallback, and waiting for session lock before display sleep when lock-on-close is enabled.
- Added a timeout and repair action for stale Advanced Helper updates so the app no longer stays on `Updating helper` when the helper registration is approved but XPC cannot start it.
- Added local helper maintenance commands for development builds, including `--helper-status`, `--helper-repair`, and `--helper-remove`.
- Added Accessibility refresh handling for lock-on-close so stale screen lock errors clear after the current app is approved in System Settings.
- Added separate Accessibility warning banners and quick actions for lock-on-close in both the menu bar UI and Settings.
- Added `--screen-lock-status` for local diagnosis of the active lock method, Accessibility trust state, bundle identifier, bundle path, and signing mode.
- Added a developer permissions guide covering helper approval, Accessibility, signing, and diagnostic commands.
- Added an ad-hoc signing warning during staging because Accessibility and LaunchDaemon approvals can become stale after rebuilds.
- Changed local staging to prefer an available Apple code signing identity because macOS blocks the privileged LaunchDaemon helper when it is ad-hoc signed.

## 0.1.0 - 2026-06-26

- Current development version: `0.1.0` build `1`.
- Added Open Source project docs, including README, MIT license, contribution guide, security policy, editor config, and GitHub issue and pull request templates.
- Added release packaging scripts, checksums under `dist/releases`, and signing plus notarization guidance in `docs/releasing.md`.
- Added code of conduct, support guide, feature request template, and troubleshooting documentation.
- Added an optional lock-screen action when the lid closes, with a `ScreenSaverEngine.app` fallback for macOS builds without `CGSession`.
