# Developer Permissions Guide

Lid Awake uses two separate macOS permission paths. Keep them separate when debugging, reviewing issues, or preparing builds.

## Permission Paths

### Advanced Helper

The advanced helper is `LidAwakeHelper` with launchd label `com.thuongtin.LidAwake.Helper`.

It is used only for closed-lid sleep control. When approved, the main app can ask the helper through privileged XPC to run:

```bash
pmset -a disablesleep 1
pmset -a disablesleep 0
```

The helper is approved through macOS ServiceManagement. It is not the Accessibility item.

Useful checks:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --helper-status
launchctl print system/com.thuongtin.LidAwake.Helper
pmset -g | rg 'SleepDisabled|disablesleep' || true
```

Repair a stale local helper registration:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --helper-repair
```

Remove the helper registration:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --helper-remove
```

### Accessibility For Lock Screen

Accessibility belongs to the main `Lid Awake` app, not the helper.

Lid Awake first tries `CGSession -suspend` for lock-on-close. On macOS builds where `CGSession` is missing, it falls back to posting the system Lock Screen keyboard shortcut with `CGEvent`. That fallback requires the current `Lid Awake` app bundle to be allowed in System Settings > Privacy & Security > Accessibility.

Useful check:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --screen-lock-status
```

Expected output when the fallback is active and permission is correct:

```text
screenLockMethod=keyboardShortcut
accessibilityTrusted=true
bundleIdentifier=com.thuongtin.LidAwake
teamIdentifier=ABCDE12345
codeSigningMode=identified
```

If `accessibilityTrusted=false`, remove stale Lid Awake entries from Accessibility and add the current app bundle again. This often happens when switching between `dist/LidAwake.app`, `/Applications/LidAwake.app`, rebuilt bundles with a different signing identity, or ad-hoc builds.

If the command reports `codeSigningMode=adhoc` or `teamIdentifier=not set`, treat the Accessibility result with care. System Settings can show an old `LidAwake` row as enabled while the currently rebuilt app process is not trusted. Use a stable Apple signing identity for local QA when testing permissions repeatedly.

## Signing Requirements

Local staging prefers the first available `Developer ID Application` or `Apple Development` signing identity. If no identity exists, staging falls back to ad-hoc signing.

Ad-hoc signing is enough for build and packaging checks, but the advanced LaunchDaemon helper will not reliably run from an ad-hoc signed bundle on modern macOS.

It also makes Accessibility debugging noisy because TCC may keep stale rows for older rebuilds. If System Settings shows Lid Awake as allowed but the app still displays the Accessibility warning, check `codeSigningMode` first.

Check identities:

```bash
codesign -dv dist/LidAwake.app 2>&1 | rg 'Identifier|TeamIdentifier'
codesign -dv dist/LidAwake.app/Contents/Library/LaunchServices/LidAwakeHelper 2>&1 | rg 'Identifier|TeamIdentifier'
```

The identifiers must stay unchanged:

```text
com.thuongtin.LidAwake
com.thuongtin.LidAwake.Helper
```

For helper XPC authorization, the main app must also be signed with the same Team ID as the helper. A process that only reuses `com.thuongtin.LidAwake` without the matching Team ID is rejected by the helper.

## Local QA Checklist

1. Run `./scripts/check.sh`.
2. Launch with `./script/build_and_run.sh`.
3. In Settings > Behavior, confirm `Advanced Helper` is `Ready`.
4. If lock-on-close is enabled, confirm `Screen lock permission` is `Allowed`.
5. Confirm `pmset -g` reports `SleepDisabled 1` while the app is holding.
6. If a permission looks stale, use the in-app quick action first, then verify with the matching command above.

## UI Expectations

The app should show separate warnings and quick actions for each permission path:

- Advanced Helper warning: opens Login Items or helper approval settings.
- Screen Lock permission warning: opens Privacy & Security > Accessibility for the main app.

Do not ask users to add `LidAwakeHelper` to Accessibility. That is the wrong permission surface.
