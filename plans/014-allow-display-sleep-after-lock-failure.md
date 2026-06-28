# Plan 014: Allow display sleep after lock failure

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- Sources/LidAwakeCore/ClosedLidDisplayCoordinator.swift Sources/LidAwakeCore/ClosedLidLockCoordinator.swift Sources/LidAwake/AppModel.swift Tests/LidAwakeCoreTests/ClosedLidDisplayCoordinatorTests.swift Tests/LidAwakeTests/AppModelLifecycleTests.swift docs/troubleshooting.md`

## Status

- Priority: P2
- Effort: M
- Risk: MED
- Depends on: plans/012-restore-closed-lid-before-helper-removal.md
- Category: bug
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

When `Lock Mac when lid closes` and `Turn display off` are both enabled, display sleep waits for macOS to report a locked session. If the lock request fails because Accessibility is missing, or if lock state cannot be read, display sleep can be blocked forever. Users selecting Turn display off should still get display sleep after the lock path has clearly failed.

## Current state

Display sleep blocks whenever lock is enabled and state is not locked:

```swift
// Sources/LidAwakeCore/ClosedLidDisplayCoordinator.swift:79
if settings.lockScreenWhenLidCloses,
   screenLockStateReader?.screenLockState() != .locked {
    return .none
}
```

Lock coordinator only requests once by default:

```swift
// Sources/LidAwakeCore/ClosedLidLockCoordinator.swift:22
maximumLockRequests: Int = 1
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Display tests | `swift test --filter ClosedLidDisplayCoordinatorTests` | exit 0 |
| App tests | `swift test --filter AppModelLifecycleTests` | exit 0 |
| Full tests | `swift test` | exit 0 |
| Build | `swift build` | exit 0 |

## Scope

In scope:

- `Sources/LidAwakeCore/ClosedLidDisplayCoordinator.swift`
- `Sources/LidAwake/AppModel.swift`
- `Tests/LidAwakeCoreTests/ClosedLidDisplayCoordinatorTests.swift`
- `Tests/LidAwakeTests/AppModelLifecycleTests.swift`
- `docs/troubleshooting.md`

Out of scope:

- Replacing the macOS lock mechanism.
- Adding new UI controls.
- Changing the default lock-on-close setting.

## Steps

### Step 1: Make the lock gate explicit

Add an explicit parameter to `ClosedLidDisplayCoordinator.update`, for example `waitForScreenLockBeforeDisplaySleep`, defaulting to `true`.

Verify: `swift build` exits 0.

### Step 2: Do not wait forever on unavailable lock state

If lock state is `.unavailable`, allow display sleep instead of returning `.none`.

Verify: `swift test --filter ClosedLidDisplayCoordinatorTests` exits 0.

### Step 3: Let AppModel bypass the lock gate after lock failure

In `AppModel.reconcileClosedLidDisplay()`, pass `waitForScreenLockBeforeDisplaySleep: closedLidLockError == nil`. That keeps the preferred behavior after successful lock requests, but lets display sleep proceed after a visible lock failure.

Verify: `swift test --filter AppModelLifecycleTests` exits 0.

### Step 4: Document the fallback

Update troubleshooting so users know Turn display off still proceeds after lock failure, with an error shown.

Verify: `rg 'lock failure|display sleep|Turn display off' docs/troubleshooting.md` prints the new text.

## Done criteria

- `swift test` exits 0.
- Display sleep no longer waits forever after lock failure.
- Tests cover lock-state unavailable and explicit bypass.

## STOP conditions

- The fix hides lock errors from the UI.
- The fix sends display sleep before a successful lock when no failure has occurred.
