# Lid Awake Power Model

Lid Awake is a native macOS menu bar app that keeps the Mac awake when manual hold is enabled. The default path uses documented idle sleep assertions. Closed-lid mode is an explicit opt-in because it changes a global macOS power setting.

Bundle identifier: `com.thuongtin.LidAwake`.
Advanced helper label: `com.thuongtin.LidAwake.Helper`.

## What The MVP Does

- Acquires `kIOPMAssertionTypePreventUserIdleSystemSleep` while manual hold is enabled and safety rules allow it.
- Optionally acquires `kIOPMAssertionTypePreventUserIdleDisplaySleep` when the lid-close display mode is set to keep display on.
- Closed-lid mode uses an advanced LaunchDaemon helper registered with `SMAppService`.
- After the helper is approved once in System Settings, the app can ask it through XPC to run `pmset -a disablesleep 1` or `pmset -a disablesleep 0`.
- Restores closed-lid mode when the user turns the mode off, a scheduled stop is reached, disables the app, or quits after this app enabled it.
- Releases assertions when manual hold is disabled, stopped by its schedule, or blocked by safety rules.
- Releases assertions immediately when the app is disabled, stopped by its schedule, quits, is blocked by battery cutoff, or is blocked by Low Power Mode.
- Optionally requests the macOS lock screen when the user enables lock-on-close. It uses `CGSession` when available and falls back to the system Lock Screen keyboard shortcut on macOS builds without that command.
- Does not detect coding agents or inspect process activity.
- Can register as a macOS login item from Settings.

## What The MVP Does Not Do

- It does not run `sudo`.
- It does not call `pmset sleep 0`.
- It does not silently change closed-lid behavior. The advanced helper must be set up and approved first.
- It does not install a driver extension or kernel extension.
- It does not guarantee closed-lid operation on every Mac. macOS lid behavior depends on hardware state, power source, and system policy.

## Helper Trust Boundary

The privileged helper accepts XPC clients only when macOS code signing information identifies the client as the bundled `Lid Awake` app with identifier `com.thuongtin.LidAwake` and a Team ID matching the helper build. The helper rejects unauthorized local clients before exporting its XPC object or resuming the connection. In addition to that accept-time check, the helper pins each accepted connection with an OS-enforced code signing requirement (identifier plus Apple anchor plus Team ID) via `setCodeSigningRequirement`, so macOS re-verifies the peer for the lifetime of the connection rather than only at accept time.

The helper exposes only two operations: read the closed-lid power status and set closed-lid mode through the approved `pmset -a disablesleep` command path. It runs those `pmset` changes one at a time on a single serial queue, and every `pmset` call it makes has a hard timeout so a hung `pmset` cannot wedge the helper.

The helper also restores closed-lid mode on its own in one case: when the authorized client process that last asked to enable it exits without a successful disable afterwards. It learns that process from the accepted connection, watches it with a dispatch process source, and only ever runs `pmset -a disablesleep 0` in response. No client input reaches this path beyond the process identifier macOS reports for an already-authorized connection.

## Crash recovery

Lid Awake persists closed-lid ownership separately from user settings. The record stores whether this app owns the current closed-lid mode change, when it enabled the mode, the previous reported status, and the last attempted restore time.

The app writes the record before it sends the enable request, not after the reply. The helper can apply `disablesleep 1` and still miss the app's XPC deadline, and the app can quit or crash while the request is in flight, so a record written only on a successful reply could leave the setting on with nothing that knows to restore it. A record for an enable that never landed is harmless: cleanup retires it once `pmset` reports the mode as disabled. A status that cannot be read is not treated as disabled, so it never retires a record by itself.

On a normal quit the app asks AppKit to wait (`terminateLater`), sends the restore to the helper without reading `pmset` first, and lets the app exit once the helper answers or after 5 seconds, whichever comes first. The deadline outlasts the helper's 4 second XPC deadline, so a reply that is on its way is not cut off. A restore that is still unconfirmed at exit keeps its ownership record for the next launch.

If the app is force quit or crashes while it owns closed-lid mode, Lid Awake Helper notices the app process exit and restores closed-lid mode immediately. If that restore fails, the helper retries after 2, 10, 30 and 120 seconds, then every 10 minutes, until it succeeds or the app enables or restores the mode again. The ownership record is then retired the next time the app launches. The helper only watches the process that last sent it an enable that `pmset` did not reject, or one it rejected while the mode was on anyway, so after a relaunch, a helper repair, or a helper that answers again after being unreachable, the app sends the enable once more while it owns closed-lid mode. The mode is already on, so that request only re-arms the watch. Repair first turns closed-lid mode off through the current helper, because unregistering it stops its watchdog and the new registration takes a few seconds. If the current helper does not answer, which is usually why Repair is offered, the repair goes ahead anyway. If it answers but cannot turn the mode off, its watchdog is still working, so the repair stops and reports the error. Either way the new helper turns the mode back on and watches the app.

The app never waits on `pmset` or a lock command on the main thread. Status reads, `displaysleepnow`, and the CGSession lock command run on background queues and hand their result back to the main thread, which checks its state again before acting on a result, since settings, helper replies, or a quit can arrive while a command runs.

On launch, the app reloads that ownership record, syncs helper status, reads the current closed-lid status, and restores closed-lid mode when the persisted ownership says this app enabled it but current settings and status no longer require it.

If helper approval is missing or the helper is not ready, the app keeps the ownership record and shows a restore warning instead of pretending cleanup succeeded. The user should approve or set up Lid Awake Helper in System Settings, then refresh the app so it can retry restore.

The app does not disable a closed-lid mode it did not enable. If macOS already reported closed-lid mode as enabled before Lid Awake asked for a change, that system state is shown but not claimed as app ownership.

When the user removes Lid Awake Helper while this app owns closed-lid mode, Lid Awake restores closed-lid mode first and unregisters the helper only after restore succeeds. If restore fails, the helper stays registered so the app can retry cleanup. Removal is refused while a closed-lid change is still in flight, and a removal that fails after restore does not turn closed-lid mode back on. `LidAwake --helper-remove` follows the same order from the command line, and it always sends the restore while it owns closed-lid mode rather than trusting a `pmset` read, since an enable can still be queued in the helper. Both `--helper-remove` and `--helper-repair` refuse to run while Lid Awake is open, because the running app can have a change in flight that the command cannot see, and a repair from outside would stop the restore watchdog without the app knowing to arm the new one.

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
5. Turn-display-off selected with helper ready: the same `pmset` output should report `1`, app assertions should not include display sleep prevention, and lid close should trigger repeated `pmset displaysleepnow` requests during the first closed-lid transition ticks. When lock-on-close is also enabled, display sleep waits until macOS reports the session is locked.
6. Lock-on-close enabled: closing the lid while Lid Awake is enabled should switch macOS to the lock screen. If the system falls back to the Lock Screen keyboard shortcut, Lid Awake must be allowed in Accessibility settings.
7. Manual hold disabled: assertion should release.
8. Battery guardrail: fake or manual low-battery state should release the assertion and restore closed-lid mode if this app enabled it.
9. Quit app: no app-owned assertion should remain, and closed-lid mode should be restored if this app enabled it.
10. Force quit while closed-lid mode is on: `kill -9` the `LidAwake` process after this app enabled closed-lid mode. Within a second `pmset -g` should report `SleepDisabled 0`, and `/usr/bin/log show --last 1m --predicate 'subsystem == "com.thuongtin.LidAwake.Helper"'` should show the helper restore line. Relaunching the app should clear the stale ownership record without a warning.
11. Command-line removal: with Lid Awake open, `LidAwake.app/Contents/MacOS/LidAwake --helper-remove` should refuse and leave the helper registered. After a `kill -9` of the app while it owned closed-lid mode, the same command should end with `SleepDisabled 0` before printing `Not set up`. With the helper unapproved, it should fail and leave the helper registered.
12. Remove during a change: pressing Remove in Settings is disabled while `Updating helper` is shown.
13. Re-arm after Repair: with closed-lid mode enabled by the app and Repair offered in Settings, press Repair, wait for `Ready`, then `kill -9` the `LidAwake` process. Within a second `pmset -g` should report `SleepDisabled 0`.
14. Quit during Repair: with closed-lid mode enabled by the app and Repair offered in Settings, press Repair and quit Lid Awake right away. The app should stay open until the helper is registered again (a few seconds), then quit with `pmset -g` reporting `SleepDisabled 0`.
