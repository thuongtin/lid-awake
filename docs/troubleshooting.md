# Troubleshooting

This guide focuses on common local development and runtime issues for Lid Awake.

For developer-focused permission setup, signing checks, and local diagnostics, see [Developer Permissions Guide](developer-permissions.md).

## The App Does Not Build

Confirm the Swift toolchain is available:

```bash
swift --version
```

Run the CI-safe check:

```bash
./scripts/check.sh
```

If the check fails during staging, remove local build output and retry:

```bash
rm -rf .build dist
./scripts/check.sh
```

## The App Does Not Launch From The Script

Build and launch the staged app:

```bash
./script/build_and_run.sh
```

The script kills any existing `LidAwake` process before launching the new staged bundle. It also tries to quit the old pre-release process name `AgentAwake` for local cleanup.

## Helper Is Missing

If the UI says the advanced helper is missing, stage the app again:

```bash
./script/build_and_run.sh --stage
```

Then confirm the helper exists in the staged bundle:

```bash
test -x dist/LidAwake.app/Contents/Library/LaunchServices/LidAwakeHelper
```

## Helper Needs Approval

Closed-lid mode requires macOS approval for `Lid Awake Helper`.

Open the app, go to Settings, and use the helper setup or approval action. After approving in System Settings, return to Lid Awake and refresh or reopen Settings if the status does not update immediately.

The app should show a warning with a quick action when helper approval is missing. Use that action before manually searching System Settings.

## Helper Stays On Updating

`Updating helper` means Lid Awake sent a request to the privileged helper and is waiting for XPC to return. If it stays there, the helper registration may be stale even though System Settings still reports it as enabled.

Check launchd:

```bash
launchctl print system/com.thuongtin.LidAwake.Helper
```

If the output shows `spawn failed`, `last exit code = 78`, or `Could not find and/or execute program specified by service`, rebuilds may have left the approved helper registration pointing at an old staged bundle. Use the in-app `Repair Helper` action. If repair asks for approval, approve `Lid Awake Helper` in System Settings and return to the app.

If unified logs mention `OS_REASON_CODESIGNING`, `Launch Constraint Violation`, or `adhoc signed`, rebuild the staged app with a real code signing identity. The advanced helper is a LaunchDaemon, so macOS will not run it from an ad-hoc signed development bundle.

For local development, the staged app can run the same repair path without opening the UI:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --helper-repair
```

## Closed-Lid Mode Does Not Work

Check the staged helper and app identity:

```bash
codesign -dv dist/LidAwake.app 2>&1 | rg 'Identifier'
codesign -dv dist/LidAwake.app/Contents/Library/LaunchServices/LidAwakeHelper 2>&1 | rg 'Identifier'
```

Expected identifiers:

- `com.thuongtin.LidAwake`
- `com.thuongtin.LidAwake.Helper`

Check the power setting reported by macOS:

```bash
pmset -g custom | rg 'SleepDisabled|disablesleep' || true
pmset -g | rg 'SleepDisabled|disablesleep' || true
```

If helper approval is missing, the app should show a warning and avoid pretending that closed-lid mode is ready.

## Display Turns Off Or Stays On Unexpectedly

The lid-close display mode has two separate effects:

- `Keep display on`: the app may hold a display sleep assertion while keeping the Mac awake.
- `Turn display off`: the app keeps system wake behavior through the helper but does not hold display sleep, and it requests display sleep during a short retry window when the lid closes.

macOS and hardware policy can still affect final display behavior. On multi-monitor setups, macOS may briefly reconfigure displays after the lid closes, so Lid Awake retries display sleep for the first closed-lid transition ticks. If lock-on-close is enabled too, Lid Awake waits until macOS reports the session is locked before sending display sleep.

## Lock On Lid Close Does Not Trigger

The lock-on-close option requests a macOS lock path after Lid Awake observes the lid as closed. It sends one lock request per lid closure, then waits for macOS to report the session as locked before sending display sleep. It first uses `CGSession -suspend` when that command exists on the system. On macOS builds where `CGSession` is not available, it falls back to the system Lock Screen keyboard shortcut.

This does not require the advanced helper and it does not use `sudo`. The keyboard shortcut fallback may require allowing Lid Awake in System Settings > Privacy & Security > Accessibility.

The app should show a separate screen lock permission warning with an `Open Accessibility` action when this permission is missing. This permission belongs to the main Lid Awake app, not `LidAwakeHelper`.

If System Settings already shows Lid Awake as allowed but the app still reports a screen lock error, confirm the current running bundle is the one that macOS trusts:

```bash
dist/LidAwake.app/Contents/MacOS/LidAwake --screen-lock-status
```

On systems without `CGSession`, expected output includes:

```text
screenLockMethod=keyboardShortcut
accessibilityTrusted=true
bundleIdentifier=com.thuongtin.LidAwake
```

If `accessibilityTrusted=false`, remove old Lid Awake entries from Accessibility and add the current app again. This can happen after switching between `/Applications/LidAwake.app`, `dist/LidAwake.app`, or a rebuild signed with a different identity.

Check:

- Lid Awake is running.
- Keep awake is enabled.
- Settings has `Lock Mac when lid closes` enabled.
- The app has enough time to observe the closed lid before macOS sleeps the machine.
- If the system uses the keyboard shortcut fallback, System Settings allows Lid Awake in Accessibility.

If the Mac sleeps immediately before the app can observe the lid closure, enable the normal keep-awake flow and test again while on AC power.

## Assertions Remain After Quit

Check assertions:

```bash
pmset -g assertions | rg 'Lid Awake|PreventUserIdle' || true
```

If an assertion remains, quit any running local build:

```bash
pkill -x LidAwake || true
```

Then check again. If the issue repeats, file a bug with the assertion output and the steps that led to it.

## Runtime Verification

Only run runtime verification on a developer Mac where launching the app and checking live power assertions is acceptable:

```bash
./scripts/verify.sh
```

CI and routine contributor checks should use:

```bash
./scripts/check.sh
```
