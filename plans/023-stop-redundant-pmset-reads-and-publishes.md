# Plan 023: Stop redundant pmset reads and SwiftUI publishes on the 5 second tick

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first):
> `git diff --stat a81523c..HEAD -- Sources/LidAwake/AppModel.swift Tests/LidAwakeTests/AppModelLifecycleTests.swift`
> This plan was written at commit `a81523c` PLUS working-tree edits that were
> not committed yet, and it assumes plan 022 has landed. Precondition checks:
> `grep -c 'clock.now.timeIntervalSince(lastVerified)' Sources/LidAwake/AppModel.swift`
> must print `1`, and
> `grep -c 'guard !closedLidHelperRemovalRequested, !closedLidHelperNeedsRepair else' Sources/LidAwake/AppModel.swift`
> must print `1`. If either prints `0`, STOP and report.

## Status

- Priority: P2
- Effort: S
- Risk: LOW-MED
- Depends on: 022
- Category: perf
- Planned at: commit `a81523c`, 2026-11-12
- Execution status: TODO

## Why this matters

Lid Awake is a menu bar app that runs all day, so anything it does on its
five-second evaluate timer is paid about 17,000 times a day. Plan 019 removed
most of that work. Two leftovers remain:

1. Keep Awake is on but the Advanced Helper is not set up (the default for a
   new user, and for anyone who never approves the helper). Every tick
   fork/execs `/usr/bin/pmset` to read the closed-lid setting, and then throws
   the answer away because the app is blocked from acting on it anyway. That
   is a process spawn every five seconds for as long as Keep Awake is on.
2. Keep Awake is on and closed-lid mode is healthy (the normal working
   state). Every tick assigns `nil` to two `@Published` properties that are
   already `nil`. `@Published` announces a change on every assignment, equal
   or not, so every tick invalidates the menu bar popover and Settings views
   for nothing: six `objectWillChange` events per three evaluates, measured.

Both were reproduced with failing tests on a scratch copy before this plan
was written, and the changes below made the whole suite pass there.

## Current state

All source excerpts are from `Sources/LidAwake/AppModel.swift`, as they look
after plan 022.

The error property (lines 81-88). The inner assignment publishes even when the
flag is already `false`:

```swift
@Published private(set) var closedLidError: String? {
    didSet {
        closedLidHelperProbeID = nil
        if closedLidError == nil {
            closedLidHelperNeedsRepair = false
        }
    }
}
```

The steady-state helper, after plan 022. It assigns `nil` even when the error
is already `nil`:

```swift
private func clearClosedLidErrorUnlessRemovalPending() {
    guard !closedLidHelperRemovalRequested, !closedLidHelperNeedsRepair else {
        return
    }

    closedLidError = nil
}
```

`reconcileClosedLidMode` (lines 1237-1275). The steady-state shortcut calls the
helper above on every tick, and when the shortcut does not apply the function
always goes on to read `pmset`:

```swift
private func reconcileClosedLidMode(forceStatusRead: Bool = false) {
    guard !isChangingClosedLidMode, !isTerminating else {
        return
    }

    syncClosedLidHelperStatus()

    let desired = shouldEnableClosedLidMode
    guard desired || appEnabledClosedLidMode || forceStatusRead else {
        return
    }

    // Steady state: when closed-lid mode is already enabled and still desired,
    // re-verify with `pmset` only occasionally instead of spawning a subprocess
    // on every 5s evaluate. Each read fork/execs /usr/bin/pmset, so an
    // unthrottled read here is ~17k process spawns/day while holding.
    // A wall clock that was set back makes the last read look like it is
    // still ahead, which must not hold the next one off.
    if desired, !forceStatusRead, closedLidStatus == .enabled,
       let lastVerified = lastClosedLidVerifiedAt,
       0..<closedLidVerifyInterval ~= clock.now.timeIntervalSince(lastVerified) {
        clearClosedLidErrorUnlessRemovalPending()
        return
    }

    guard !isReadingClosedLidStatus else {
        return
    }

    isReadingClosedLidStatus = true
    readClosedLidStatus { [weak self] status in
        guard let self else {
            return
        }

        isReadingClosedLidStatus = false
        finishReconcilingClosedLidMode(status: status)
    }
}
```

What happens to that read when the app is blocked
(`finishReconcilingClosedLidMode`, lines 1284-1299): unless the mode reads as
on, the result is dropped at the second guard.

```swift
if shouldEnableClosedLidMode {
    guard status != .enabled else {
        clearClosedLidErrorUnlessRemovalPending()
        rearmClosedLidRestoreWatchdogIfNeeded()
        return
    }

    guard suppressedClosedLidTarget != true, !closedLidHelperRemovalRequested else {
        return
    }

    guard closedLidHelperStatus.canControlClosedLidMode else {
        suppressedClosedLidTarget = true
        closedLidError = "Set up Advanced Helper before enabling closed-lid mode."
        return
    }
```

How a block is lifted, so you can see the skipped read is not needed for
recovery:

- `syncClosedLidHelperStatus()` runs at the top of every reconcile and calls
  `clearClosedLidReadinessBlockIfPossible()` (lines 1177-1209), which resets
  `suppressedClosedLidTarget = nil` as soon as the helper becomes controllable
  and any retry delay has passed. The next tick then reads again.
- `probeClosedLidHelperIfBlocked()` lifts a "helper unreachable" block.
- Opening the popover, opening Settings, and app activation call
  `refreshAfterExternalPermissionChange()` or
  `refreshClosedLidPermissionState()`, which pass `forceStatusRead: true`.

The existing idle-state test carries a comment that is no longer true
(`Tests/LidAwakeTests/AppModelLifecycleTests.swift`, inside
`testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish`):

```swift
        // Note: the objectWillChange churn assertion was dropped here because it is
        // flaky due to unrelated published writes outside this plan's scope
        // (e.g. syncClosedLidHelperStatus() and refreshScreenLockAccessibilityState()
        // reassign their @Published properties unconditionally on every tick). See
        // plan 019 step 5 for the documented fallback.
        harness.model.evaluate()
        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.closedLidStatusReader.readCount, countAfterStart)
```

Both functions it names now publish only on a real change, and the dropped
assertion passes today (checked on the scratch copy).

Convention to match, from `syncClosedLidHelperStatus()` in the same file:

```swift
// Only publish on a real transition. @Published fires objectWillChange on
// every assignment regardless of equality, so an unconditional write here
// would re-render observing views on every 5s evaluate for no change.
if closedLidHelperStatus != next {
    closedLidHelperStatus = next
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Run the new tests | `swift test --filter 'AppModelLifecycleTests/testHolding'` | 0 failures |
| Run the app test target | `swift test --filter LidAwakeTests` | 0 failures |
| Full local gate | `./scripts/check.sh` | exit 0 |

Never run `./scripts/verify.sh` or `./script/build_and_run.sh` without
`--stage`: they launch the app and touch live power-management state.

## Scope

In scope (the only files you should modify):

- `Sources/LidAwake/AppModel.swift`
- `Tests/LidAwakeTests/AppModelLifecycleTests.swift`
- `plans/README.md` (status row only)

Out of scope:

- The two timers in `start()` and the one-second side-effects tick. Pausing
  timers while Keep Awake is off is a separate, riskier change that is
  deliberately not planned here.
- `finishReconcilingClosedLidMode`, `finishClosedLidModeChange`,
  `clearClosedLidReadinessBlockIfPossible`, and the helper probe.
- `closedLidVerifyInterval` and every other interval constant.

## Git workflow

- Branch: `advisor/023-stop-redundant-pmset-reads`. Plain imperative commit
  subject, for example `Skip pmset reads and publishes that change nothing`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the failing tests

In `Tests/LidAwakeTests/AppModelLifecycleTests.swift`:

1. Add `import Combine` to the imports at the top, keeping them in the
   existing order (after `import AppKit`).
2. Insert these two methods immediately before
   `func testEnabledModeTheAppDoesNotOwnIsNotRearmed`:

```swift
    func testHoldingWithoutAHelperDoesNotReadPMSetOnEveryEvaluate() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .notRegistered,
            closedLidStatus: .disabled
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        let readsAfterStart = harness.closedLidStatusReader.readCount
        let errorAfterStart = harness.model.closedLidError

        harness.model.evaluate()
        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.closedLidStatusReader.readCount, readsAfterStart)
        XCTAssertEqual(harness.model.closedLidError, errorAfterStart)
        XCTAssertNotNil(errorAfterStart)
    }

    func testHoldingSteadyStateDoesNotPublishOnEveryEvaluate() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        var publishCount = 0
        let subscription = harness.model.objectWillChange.sink { publishCount += 1 }
        harness.model.evaluate()
        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()
        subscription.cancel()

        XCTAssertEqual(publishCount, 0)
    }
```

Verify: `swift test --filter 'AppModelLifecycleTests/testHolding'`. Expected
at this point: both new tests FAIL (read count one higher than after start;
publish count 6 instead of 0). Other tests matched by the filter pass. If
either new test passes before any source change, STOP.

### Step 2: Publish only on a real change

In `Sources/LidAwake/AppModel.swift`:

1. In the `didSet` of `closedLidError`, change the inner condition so the flag
   is written only when it is set:

```swift
        didSet {
            closedLidHelperProbeID = nil
            if closedLidError == nil, closedLidHelperNeedsRepair {
                closedLidHelperNeedsRepair = false
            }
        }
```

2. In `clearClosedLidErrorUnlessRemovalPending`, add the third condition and
   one sentence to the end of its doc comment:

```swift
/// ... (keep the existing text) ... An error that is already clear is left
/// alone, because assigning an equal value still announces a change to
/// every observing view.
private func clearClosedLidErrorUnlessRemovalPending() {
    guard !closedLidHelperRemovalRequested, !closedLidHelperNeedsRepair, closedLidError != nil else {
        return
    }

    closedLidError = nil
}
```

Verify: `swift test --filter 'AppModelLifecycleTests/testHoldingSteadyStateDoesNotPublishOnEveryEvaluate'`
-> 1 test, 0 failures.

### Step 3: Skip the read whose result would be dropped

In `reconcileClosedLidMode`, insert this block between the steady-state
shortcut and `guard !isReadingClosedLidStatus else {`:

```swift
    // Blocked from enabling, with nothing of the app's own to restore: the
    // read below could only be thrown away, and each one spawns `pmset`.
    // Whatever lifts the block resets `suppressedClosedLidTarget` or forces
    // a read, so the next evaluate after that reads again.
    if desired, !forceStatusRead, !appEnabledClosedLidMode,
       suppressedClosedLidTarget == true || closedLidHelperRemovalRequested {
        return
    }
```

The four comma-separated conditions are all required:

- `desired`: only the "wants to enable" branch drops the result.
- `!forceStatusRead`: user-triggered refreshes must still read.
- `!appEnabledClosedLidMode`: when the app owns the mode, the read drives the
  watchdog re-arm and the periodic verification and must keep running.
- the last one mirrors the guard in `finishReconcilingClosedLidMode` that
  drops the result.

Verify: `swift test --filter 'AppModelLifecycleTests/testHoldingWithoutAHelperDoesNotReadPMSetOnEveryEvaluate'`
-> 1 test, 0 failures.

### Step 4: Restore the dropped assertion and remove the outdated comment

In `testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish`, replace the block
quoted in "Current state" (the five-line comment through the final
`XCTAssertEqual`) with:

```swift
        var publishCount = 0
        let subscription = harness.model.objectWillChange.sink { publishCount += 1 }
        harness.model.evaluate()
        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()
        subscription.cancel()

        XCTAssertEqual(harness.closedLidStatusReader.readCount, countAfterStart)
        XCTAssertEqual(publishCount, 0)
```

Verify: `swift test --filter 'AppModelLifecycleTests/testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish'`
-> 1 test, 0 failures. Run it five times in a row
(`for i in 1 2 3 4 5; do swift test --filter 'AppModelLifecycleTests/testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish' 2>&1 | grep -c 'with 0 failures'; done`)
and confirm every run prints a non-zero count. If any run fails, STOP: the
assertion is flaky again and the cause must be reported, not hidden.

### Step 5: Full gate

Verify: `swift test` -> 0 failures, with no other existing test edited.
Then `./scripts/check.sh` -> exit 0.

## Test plan

- New: `testHoldingWithoutAHelperDoesNotReadPMSetOnEveryEvaluate` (no `pmset`
  read per tick while blocked; the setup warning stays on screen).
- New: `testHoldingSteadyStateDoesNotPublishOnEveryEvaluate` (zero
  `objectWillChange` events across three evaluates in the healthy holding
  state).
- Strengthened: `testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish` now
  asserts what its name says.
- Must stay green unchanged, because they prove the skipped read does not
  break recovery: every `AppModelLifecycleTests` test whose name contains
  `Helper`, `Repair`, `Probe`, `Rearm`, `Removal`, or `Reverif`.

## Done criteria

- [ ] `swift test` reports 0 failures.
- [ ] `./scripts/check.sh` exits 0.
- [ ] `git diff --stat` lists only the three in-scope files.
- [ ] `grep -c 'plan 019 step 5' Tests/LidAwakeTests/AppModelLifecycleTests.swift`
      prints `0`.
- [ ] No em dash character in the diff:
      `git diff | grep -c "$(printf '\xe2\x80\x94')"` prints `0`.
- [ ] Status row for 023 in `plans/README.md` updated.

## STOP conditions

Stop and report back (do not improvise) if:

- Either precondition check in the header prints `0`.
- A new test passes before its source change.
- Any existing test fails after a step. Do not edit an existing test other
  than the one named in step 4.
- The restored publish assertion fails or is flaky.
- You find another per-tick `@Published` write and want to fix it: report it
  instead, it is outside this plan.

## Maintenance notes

- Behaviour change to know about: while the helper is not set up, the app no
  longer notices within five seconds that some other tool turned
  `disablesleep` on. The value shown in the popover and in Settings is still
  refreshed whenever either one is opened and whenever the app is activated,
  because those paths force a read.
- Any future code that sets `suppressedClosedLidTarget = true` must have a
  matching path that resets it or forces a read, otherwise the app stops
  polling and never recovers. Today those paths are
  `clearClosedLidReadinessBlockIfPossible`, `finishClosedLidHelperProbe`, a
  successful change, and the forced reads.
- Reviewer focus: the `!appEnabledClosedLidMode` condition in step 3. While
  the app owns closed-lid mode but is blocked or has a helper removal pending,
  it keeps the status read going (every 30 seconds while the mode is on). That
  read refreshes `closedLidStatus` and `lastClosedLidVerifiedAt`, and once
  `pmset` reports the mode on it clears an error that does not need Repair,
  unless a removal is pending. It does not guard the watchdog re-arm:
  `rearmClosedLidRestoreWatchdogIfNeeded` already declines in both states. No
  test pins the condition today, so an edit that drops it keeps the suite
  green.
- Deferred follow-ups, not part of this plan: pausing the evaluate and
  side-effects timers while Keep Awake is off, and replacing the one-second
  lid and display polling with IOKit notifications.
