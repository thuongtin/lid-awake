# Changelog

All notable changes to Lid Awake will be documented in this file.

The format follows dated release sections after the first tagged release.

## 0.1.7 - 2026-07-29

- Fixed a blank Settings window when Settings was opened from anywhere other than the menu bar popover.
- Fixed the software update window opening behind the frontmost app with no way to reach it, since the app has no Dock icon or app switcher entry while running as a menu bar accessory.
- Fixed the menu bar popover detaching from its status item icon and floating below the menu bar.
- Fixed a permanent "Closed-lid playback is blocked" warning that offered a Set Up button which did nothing. When the approved helper belongs to an older copy of the app, after an update, a move, or a reinstall, it refuses the connection while macOS still reports the registration as enabled. The warning now explains what happened, offers Repair, which is the action that actually reconnects, stops retrying a connection that cannot succeed, and clears itself once the helper answers again.
- Fixed removing Lid Awake Helper while it is unreachable leaving no way forward. Closed-lid mode cannot be restored over a refused connection, so the removal is held back and Repair is offered instead.
- Changed Lid Awake Helper to log connection rejections as readable text in the unified log instead of `<private>`, so these failures can be diagnosed from a user's machine.

## 0.1.6 - 2026-07-28

- Removed scheduled-stop controls from the menu bar popover while keeping the feature available in Settings.

## 0.1.5 - 2026-07-28

- Replaced temporary pause controls with a scheduled stop that turns off Keep Awake after 30 minutes, one hour, or a custom duration.
- Restored app-owned closed-lid mode and released power assertions when the scheduled stop is reached.
- Migrated existing saved pause deadlines to the new scheduled-stop setting.

## 0.1.4 - 2026-07-03

- Changed the public website link from `lidawake.thuongtin.com` to `lidawake.pages.dev` across the app, landing page, and documentation.

## 0.1.3 - 2026-07-03

- Added an About section in Settings showing the app icon, version, bundle identifier, requirements, website and GitHub links, and MIT license, and renamed the previous transparency pane to Safety.
- Reduced idle CPU and battery usage by giving the periodic timers scheduling tolerance so macOS can coalesce their wakeups.
- Reduced idle work by skipping the per-second closed-lid clamshell reads while keep-awake is disabled.
- Reduced steady-state process spawns by re-verifying closed-lid status with `pmset` on an interval instead of on every evaluation while holding.
- Stopped redundant SwiftUI updates by publishing closed-lid helper status, screen lock trust, and lock error only when they actually change.
- Added Sparkle 2 update checks from the menu bar and Settings, including automatic update check controls.
- Added Sparkle framework staging, public update key injection, and signed appcast generation for public releases.
- Disabled Sparkle metadata in local debug staging by default so unreleased builds do not show appcast retrieval errors.
- Documented current Apple Silicon only release support.
- Added Homebrew tap installation guidance for `thuongtin/tap/lid-awake`.

## 0.1.1 - 2026-07-01

- Improved closed-lid display-off reliability on multi-monitor setups by retrying display sleep during the first closed-lid transition ticks, removing the `ScreenSaverEngine.app` lock fallback, and waiting for session lock before display sleep when lock-on-close is enabled.
- Fixed launch and permission-refresh behavior so opening the app while the lid is already closed does not trigger lock-on-close or display-off side effects.
- Replaced the SwiftUI `MenuBarExtra` window with an `NSStatusItem` and transient popover to reduce idle CPU usage.
- Published the first Developer ID signed, notarized, and stapled public release archive with a SHA-256 checksum.
- Added a signed, notarized, and stapled DMG release artifact for a more familiar macOS install flow.
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
