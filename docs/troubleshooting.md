# Troubleshooting

This guide focuses on common local development and runtime issues for Lid Awake.

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
- `Turn display off`: the app keeps system wake behavior through the helper but does not hold display sleep, and it may request display sleep when the lid closes.

macOS and hardware policy can still affect final display behavior.

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
