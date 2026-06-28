# Plan 012: Restore closed-lid mode before removing helper

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- Sources/LidAwake/AppModel.swift Tests/LidAwakeTests/AppModelLifecycleTests.swift docs/troubleshooting.md docs/power-model.md`

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: plans/011-bind-helper-authorization-to-team-identity.md
- Category: bug
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

Closed-lid mode changes a global macOS power setting. If Lid Awake owns that change and the user removes the helper, the app must restore the global setting before unregistering the helper. Otherwise the app can lose the privileged path it needs to undo `disablesleep=1`.

## Current state

`removeClosedLidHelper()` unregisters immediately:

```swift
// Sources/LidAwake/AppModel.swift:443
func removeClosedLidHelper() {
    isChangingClosedLidMode = false
    closedLidModeChangeID = nil

    do {
        try closedLidHelperService.unregister()
```

The app already has a restore path for termination:

```swift
// Sources/LidAwake/AppModel.swift:874
private func restoreClosedLidModeForTerminationIfNeeded() {
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Targeted tests | `swift test --filter AppModelLifecycleTests` | exit 0 |
| Full tests | `swift test` | exit 0 |
| Build | `swift build` | exit 0 |

## Scope

In scope:

- `Sources/LidAwake/AppModel.swift`
- `Tests/LidAwakeTests/AppModelLifecycleTests.swift`
- `docs/troubleshooting.md`
- `docs/power-model.md`

Out of scope:

- Changing `SMAppService` registration APIs.
- Adding new helper UI.
- Changing closed-lid ownership encoding.

## Steps

### Step 1: Restore before unregister

Change `removeClosedLidHelper()` so when Lid Awake owns closed-lid mode and the system reports it enabled, it first requests `setClosedLidMode(enabled: false)`. Only unregister after that request succeeds and the ownership record is cleared.

Verify: `swift build` exits 0.

### Step 2: Preserve helper on restore failure

If restore fails or times out, do not unregister. Leave the ownership record and show a user-facing error.

Verify: `swift test --filter AppModelLifecycleTests` exits 0.

### Step 3: Add lifecycle tests

Add tests for:

- remove helper restores then unregisters when this app owns closed-lid mode
- remove helper does not unregister if restore fails
- remove helper unregisters directly when there is no ownership

Verify: `swift test --filter AppModelLifecycleTests` exits 0.

### Step 4: Update docs

Document that Remove restores app-owned closed-lid mode before unregistering the helper.

Verify: `rg 'Remove|restore|helper' docs/troubleshooting.md docs/power-model.md` prints the new text.

## Done criteria

- `swift test` exits 0.
- Removing helper cannot drop the privileged helper before restoring an app-owned `disablesleep=1`.
- New tests cover success and failure.

## STOP conditions

- The restore flow requires real `pmset` in tests.
- The helper cannot be kept registered on restore failure.
