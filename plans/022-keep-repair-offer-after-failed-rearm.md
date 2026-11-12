# Plan 022: Keep the Repair offer after a failed watchdog re-arm

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first):
> `git diff --stat a81523c..HEAD -- Sources/LidAwake/AppModel.swift Tests/LidAwakeTests/AppModelLifecycleTests.swift`
> This plan was written at commit `a81523c` PLUS working-tree edits that were
> not committed yet (they replaced `Date()` with `clock.now` in `AppModel`).
> The excerpts below quote that working tree. Precondition check:
> `grep -c 'clock.now.timeIntervalSince(lastVerified)' Sources/LidAwake/AppModel.swift`
> must print `1`. If it prints `0`, the edits have not landed in your checkout:
> STOP and report. If the files changed in other ways, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- Priority: P1
- Effort: S
- Risk: LOW
- Depends on: the uncommitted `clock.now` working-tree edits being committed
- Category: bug
- Planned at: commit `a81523c`, 2026-11-12
- Execution status: TODO

## Why this matters

Lid Awake turns on the machine-wide `pmset -a disablesleep 1` setting through
a privileged helper. The helper watches the app process and restores the
setting if the app dies. When the app starts and finds a mode it already owns
(for example after a helper update), it re-sends the enable so the new helper
watches it ("re-arm").

If that re-arm fails because the helper cannot be reached, the app must keep
showing the warning with the Repair button until the helper answers again.
Today the warning disappears by itself within five seconds, while the fault is
still there. The result:

- The user loses the Repair button for a broken helper. The global
  `disablesleep 1` setting stays on with no helper watching the app, which is
  the exact situation the watchdog exists to prevent, and nothing on screen
  says so.
- The app then reconnects blindly and fails again, so the warning flickers on
  and off for as long as the app runs.

## Current state

All excerpts are from `Sources/LidAwake/AppModel.swift`.

The error and its repair flag are a pair. Clearing the error also clears the
flag (lines 81-88):

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

The Repair button is offered only while both are set (lines 439-443):

```swift
var shouldOfferClosedLidHelperRepair: Bool {
    closedLidHelperStatus == .enabled
        && closedLidHelperNeedsRepair
        && closedLidError != nil
}
```

A failed change records the failure (`finishClosedLidModeChange`, lines
1442-1450):

```swift
case let .failure(error):
    suppressedClosedLidTarget = enabled
    closedLidError = closedLidUserFacingError(from: error)
    closedLidHelperNeedsRepair = isRepairableClosedLidFailure(error)
    // A helper that cannot be reached waits for repair or a probe
    // instead; this delay is for one that answered and failed.
    closedLidRetryNotBefore = closedLidHelperNeedsRepair
        ? nil
        : clock.now.addingTimeInterval(Self.closedLidFailureRetryDelay)
```

The defect is in this helper (lines 1211-1221). It treats "closed-lid mode is
on and wanted" as proof that everything is healthy and drops the error:

```swift
/// Closed-lid mode being on and wanted is the healthy steady state, except
/// after a removal that could not finish: there it is the very thing the
/// warning is about, and clearing it would hide that the helper is still
/// installed.
private func clearClosedLidErrorUnlessRemovalPending() {
    guard !closedLidHelperRemovalRequested else {
        return
    }

    closedLidError = nil
}
```

It has two callers, both reached on the regular five-second evaluate while
the mode reads as on:

- `reconcileClosedLidMode`, the steady-state shortcut (lines 1255-1260):

  ```swift
  if desired, !forceStatusRead, closedLidStatus == .enabled,
     let lastVerified = lastClosedLidVerifiedAt,
     0..<closedLidVerifyInterval ~= clock.now.timeIntervalSince(lastVerified) {
      clearClosedLidErrorUnlessRemovalPending()
      return
  }
  ```

- `finishReconcilingClosedLidMode` (lines 1284-1289):

  ```swift
  if shouldEnableClosedLidMode {
      guard status != .enabled else {
          clearClosedLidErrorUnlessRemovalPending()
          rearmClosedLidRestoreWatchdogIfNeeded()
          return
      }
  ```

Sequence of the bug: the app owns the mode, the mode is on, the re-arm fails
with a lost connection. `closedLidError` and `closedLidHelperNeedsRepair` are
set. On the next evaluate the mode is still on (the failure was about the
watchdog, not about the setting), so one of the two callers clears the error,
the `didSet` clears the repair flag, and the re-arm is sent again a little
later because nothing blocks it any more.

The right way to retire a "helper unreachable" failure already exists:
`probeClosedLidHelperIfBlocked()` (lines 472-500) asks the helper directly
every 30 seconds while the repair flag is set, and
`finishClosedLidHelperProbe` (lines 502-522) clears the error once the helper
answers. The fix is to stop the steady-state path from clearing an error that
is waiting for that probe.

This was reproduced before writing the plan: on a scratch copy of the repo,
the first test in the Test plan failed with the Repair offer gone after one
`evaluate()` and a second enable request sent. With the one-line fix below the
whole suite passed.

Conventions to match:

- Tests for `AppModel` live in
  `Tests/LidAwakeTests/AppModelLifecycleTests.swift` and use the file-private
  `AppModelHarness`, `ownedRecord()`, and `drainMainQueue()` helpers defined
  at the bottom of that file. New tests go in the same file, in the same
  `XCTestCase` class, as `async` methods.
- Code comments are English, explain the reason rather than the mechanics,
  and never use the em dash character.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Run the new tests | `swift test --filter 'AppModelLifecycleTests/testFailedRearm'` | 2 tests, 0 failures |
| Run the app test target | `swift test --filter LidAwakeTests` | 0 failures |
| Full local gate | `./scripts/check.sh` | exit 0 |

Never run `./scripts/verify.sh` or `./script/build_and_run.sh` without
`--stage`: they launch the app and touch live power-management state.

## Scope

In scope (the only files you should modify):

- `Sources/LidAwake/AppModel.swift` (one guard, one doc comment)
- `Tests/LidAwakeTests/AppModelLifecycleTests.swift` (two new tests)
- `plans/README.md` (status row only)

Out of scope:

- `Sources/LidAwakeHelper/` and anything in `Sources/LidAwakeCore/`.
- The `didSet` of `closedLidError` and the status read in
  `reconcileClosedLidMode`: plan 023 changes those. Do not combine the plans.
- `probeClosedLidHelperIfBlocked` and `finishClosedLidHelperProbe`: they are
  correct as they are.

## Git workflow

- Branch: `advisor/022-keep-repair-offer-after-failed-rearm`. Plain imperative
  commit subject, for example `Keep the Repair offer after a failed re-arm`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the failing tests

In `Tests/LidAwakeTests/AppModelLifecycleTests.swift`, insert these two
methods immediately before `func testEnabledModeTheAppDoesNotOwnIsNotRearmed`:

```swift
    func testFailedRearmKeepsOfferingRepairAcrossEvaluates() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord()
        )
        harness.helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.connectionLost)
        harness.helper.probeConnectionResult = .failure(.connectionLost)

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair, "after start")
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        harness.model.evaluate()
        await drainMainQueue()
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair, "after next evaluate")
        XCTAssertEqual(harness.model.closedLidError, ClosedLidHelperFailure.connectionLostMessage)

        harness.clock.advance(seconds: 31)
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.evaluate()
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true], "no blind resend")
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair, "after verify interval")
    }

    func testFailedRearmRecoversOnceTheHelperAnswers() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord()
        )
        harness.helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.connectionLost)
        harness.helper.probeConnectionResult = .failure(.connectionLost)

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.model.evaluate()
        await drainMainQueue()

        harness.helper.setClosedLidModeResult = .success(())
        harness.helper.probeConnectionResult = .success(())
        harness.clock.advance(seconds: 31)
        harness.model.evaluate()
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertNil(harness.model.closedLidError)
        XCTAssertFalse(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
    }
```

Verify: `swift test --filter 'AppModelLifecycleTests/testFailedRearm'`.
Expected at this point: `testFailedRearmKeepsOfferingRepairAcrossEvaluates`
FAILS (the "after next evaluate" assertion), and
`testFailedRearmRecoversOnceTheHelperAnswers` passes. If the first test
passes before any source change, STOP: the bug is already fixed or the
harness changed.

### Step 2: Stop clearing an error that waits for the helper probe

In `Sources/LidAwake/AppModel.swift`, replace the helper shown in "Current
state" with:

```swift
/// Closed-lid mode being on and wanted is the healthy steady state, with
/// two exceptions. After a removal that could not finish it is the very
/// thing the warning is about, and clearing it would hide that the helper
/// is still installed. And a helper the app could not reach says nothing
/// about the setting, which stays on: that warning is retired by
/// `probeClosedLidHelperIfBlocked()` once the helper answers, and clearing
/// it here would take the Repair button away and reconnect blindly.
private func clearClosedLidErrorUnlessRemovalPending() {
    guard !closedLidHelperRemovalRequested, !closedLidHelperNeedsRepair else {
        return
    }

    closedLidError = nil
}
```

Do not rename the function and do not change its two call sites.

Verify: `swift test --filter 'AppModelLifecycleTests/testFailedRearm'` ->
2 tests, 0 failures.

### Step 3: Full gate

Verify: `swift test --filter LidAwakeTests` -> 0 failures, and no existing
test needed an edit. Then `./scripts/check.sh` -> exit 0.

## Test plan

- New: `testFailedRearmKeepsOfferingRepairAcrossEvaluates` (the regression:
  Repair stays offered across evaluates and across the 30 second verify
  interval, and no second enable is sent while the helper is unreachable).
- New: `testFailedRearmRecoversOnceTheHelperAnswers` (the recovery path still
  works: once the probe succeeds, the error clears and the re-arm is sent
  exactly once more).
- Existing tests that guard the neighbouring behaviour and must stay green
  unchanged: every test in `AppModelLifecycleTests` whose name contains
  `Repair`, `Probe`, `Rearm`, or `Removal`.

## Done criteria

- [ ] `swift test --filter 'AppModelLifecycleTests/testFailedRearm'` reports 2
      tests, 0 failures.
- [ ] `swift test` reports 0 failures.
- [ ] `./scripts/check.sh` exits 0.
- [ ] `git diff --stat` lists only the three in-scope files.
- [ ] `git diff -- Sources/LidAwake/AppModel.swift` shows one changed guard
      line and the doc comment above it, nothing else.
- [ ] No em dash character in the diff:
      `git diff | grep -c "$(printf '\xe2\x80\x94')"` prints `0`.
- [ ] Status row for 022 in `plans/README.md` updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The precondition check in the header prints `0`, or
  `clearClosedLidErrorUnlessRemovalPending` no longer matches the excerpt.
- The first new test passes before the source change in step 2.
- Any existing test fails after step 2. Do not edit existing tests to make
  them pass; report which one failed and its message.
- The fix seems to need a change outside `clearClosedLidErrorUnlessRemovalPending`.

## Maintenance notes

- `closedLidError` and `closedLidHelperNeedsRepair` are a pair with one rule:
  only a successful change, a successful probe, or an explicit user action may
  retire a repairable failure. Any new code that assigns
  `closedLidError = nil` on a timer path must respect that rule.
- Plan 023 edits the same function (adds `closedLidError != nil` to the guard)
  and must land after this plan.
- Reviewer focus: the guard must not block the two success paths, which
  assign `closedLidError = nil` directly (`finishClosedLidModeChange` success
  and `finishClosedLidHelperProbe`) and do not go through this helper.
- Manual QA from `docs/power-model.md` is not required for this plan: it does
  not touch the helper, the XPC protocol, or any code that changes `pmset`.
  Item 13 ("Re-arm after Repair") is the closest manual check if the
  maintainer wants one on a signed build.
