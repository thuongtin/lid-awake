# Lid Awake Power Model

Lid Awake is a native macOS menu bar app that keeps the Mac awake when manual hold is enabled. The default path uses documented idle sleep assertions. Closed-lid mode is an explicit opt-in because it changes a global macOS power setting.

Bundle identifier: `com.thuongtin.LidAwake`.
Advanced helper label: `com.thuongtin.LidAwake.Helper`.

## What The MVP Does

- Acquires `kIOPMAssertionTypePreventUserIdleSystemSleep` while manual hold is enabled and safety rules allow it.
- Optionally acquires `kIOPMAssertionTypePreventUserIdleDisplaySleep` when the lid-close display mode is set to keep display on.
- Closed-lid mode uses an advanced LaunchDaemon helper registered with `SMAppService`.
- After the helper is approved once in System Settings, the app can ask it through XPC to run `pmset -a disablesleep 1` or `pmset -a disablesleep 0`.
- Restores closed-lid mode when the user turns the mode off, pauses, disables the app, or quits after this app enabled it.
- Releases assertions when manual hold is disabled, paused, or blocked by safety rules.
- Releases assertions immediately when the app is disabled, paused, quit, blocked by battery cutoff, or blocked by Low Power Mode.
- Optionally requests the macOS lock screen once per lid closure when the user enables lock-on-close. It uses `CGSession` when available and falls back to `ScreenSaverEngine.app` on macOS builds without that command.
- Does not detect coding agents or inspect process activity.
- Can register as a macOS login item from Settings.

## What The MVP Does Not Do

- It does not run `sudo`.
- It does not call `pmset sleep 0`.
- It does not silently change closed-lid behavior. The advanced helper must be set up and approved first.
- It does not install a driver extension or kernel extension.
- It does not guarantee closed-lid operation on every Mac. macOS lid behavior depends on hardware state, power source, and system policy.

## Helper Trust Boundary

The privileged helper accepts XPC clients only when macOS code signing information identifies the client as the bundled `Lid Awake` app with identifier `com.thuongtin.LidAwake`. The helper rejects unauthorized local clients before exporting its XPC object or resuming the connection.

The helper exposes only two operations: read the closed-lid power status and set closed-lid mode through the approved `pmset -a disablesleep` command path.

## Crash recovery

Lid Awake persists closed-lid ownership separately from user settings. The record stores whether this app owns the current closed-lid mode change, when it enabled the mode, the previous reported status, and the last attempted restore time.

On launch, the app reloads that ownership record, syncs helper status, reads the current closed-lid status, and restores closed-lid mode when the persisted ownership says this app enabled it but current settings and status no longer require it.

If helper approval is missing or the helper is not ready, the app keeps the ownership record and shows a restore warning instead of pretending cleanup succeeded. The user should approve or set up Lid Awake Helper in System Settings, then refresh the app so it can retry restore.

The app does not disable a closed-lid mode it did not enable. If macOS already reported closed-lid mode as enabled before Lid Awake asked for a change, that system state is shown but not claimed as app ownership.

## Safety Defaults

- Battery cutoff: 20 percent.
- Low Power Mode: respected by default.
- Internal idle debounce remains fixed at 30 seconds for future non-manual modes.
- Display sleep prevention: enabled by default, but user configurable.
- Lid-close display mode: turn display off by default.
- Lock Mac when lid closes: disabled by default.
- Closed-lid mode: disabled by default and enabled only after user selection plus advanced helper approval.

## Manual QA Checklist

1. App disabled: `pmset -g assertions | rg 'Lid Awake'` should show no app-owned assertion.
2. Manual hold enabled: `pmset -g assertions | rg 'Lid Awake|PreventUserIdle'` should show an app-owned prevent idle assertion.
3. Advanced Helper setup: Settings should show `Ready` after System Settings approval.
4. Keep-display-on selected with helper ready: `pmset -g` or `pmset -g custom` should report `SleepDisabled 1` or `disablesleep 1`, and app assertions should include display sleep prevention.
5. Turn-display-off selected with helper ready: the same `pmset` output should report `1`, app assertions should not include display sleep prevention, and lid close should trigger `pmset displaysleepnow`.
6. Lock-on-close enabled: closing the lid while Lid Awake is enabled should switch macOS to the lock screen once for that lid closure. If the system falls back to `ScreenSaverEngine.app`, password-after-screensaver must be enabled in macOS security settings.
7. Manual hold disabled: assertion should release.
8. Battery guardrail: fake or manual low-battery state should release the assertion and restore closed-lid mode if this app enabled it.
9. Quit app: no app-owned assertion should remain, and closed-lid mode should be restored if this app enabled it.
