# Plan 019: Cut idle pmset polling, per-tick status churn, and 5-second log spam

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first): `git diff --stat 5d89d38..HEAD -- Sources/LidAwake/AppModel.swift Sources/LidAwakeCore/WakePolicy.swift Tests/LidAwakeCoreTests/WakePolicyCoordinatorTests.swift Tests/LidAwakeTests/AppModelLifecycleTests.swift`
> This plan was written at commit `5d89d38` while the Sparkle integration was
> still uncommitted in the working tree; the excerpts reflect that working
> tree. On any mismatch with "Current state", treat it as a STOP condition.

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: none
- Category: perf
- Planned at: commit `5d89d38`, 2026-07-02
- Execution status: TODO

## Why this matters

Lid Awake is an always-resident menu bar app whose whole point is power
hygiene, but its own steady-state behavior is wasteful:

1. Every 5 seconds, `AppModel.evaluate()` synchronously spawns `/usr/bin/pmset`
   on the main thread (twice on Macs where `pmset -g` does not report
   `SleepDisabled`), even when the closed-lid feature is disabled, paused, or
   blocked and the read cannot influence anything.
2. While holding, `WakePolicyCoordinator` builds a new `WakeHoldReason` with
   `startedAt: now` on every tick, so `status` compares as "changed" every 5
   seconds. That fires the "status changed" log line every 5 seconds, invokes
   the notification transition handler with a phantom change, and churns
   `@Published` subscribers.
3. `battery`, `closedLidStatus`, and `sessions` are reassigned every tick even
   when unchanged, so `objectWillChange` fires and SwiftUI re-evaluates for
   no reason.

The fix is deterministic and test-covered: stabilize the hold reason, skip the
pmset read when the closed-lid path is provably irrelevant, and publish only
on change.

## Current state

- `Sources/LidAwake/AppModel.swift:179-189` - two repeating timers: 5s ->
  `evaluate()`, 1s -> `reconcileClosedLidSideEffects()`.
- `Sources/LidAwake/AppModel.swift:554-573` - `evaluate()`:

```swift
func evaluate() {
    logger.debug("evaluate begin")
    battery = batteryMonitor.currentState()
    logger.debug("evaluate battery complete")
    sessions = manualHoldSessions(now: Date())
    previousStatus = status
    status = coordinator.update(
        settings: settings,
        sessions: sessions,
        battery: battery
    )
    if status != previousStatus {
        logger.info(
            "status changed enabled=..." // full interpolation elided
        )
    }
    notificationService.handleTransition(from: previousStatus, to: status)
    reconcileClosedLidMode(desired: shouldEnableClosedLidMode, forceDisable: false)
    reconcileClosedLidSideEffects()
}
```

- `Sources/LidAwake/AppModel.swift:672-700` - `reconcileClosedLidMode` begins:

```swift
private func reconcileClosedLidMode(desired: Bool, forceDisable: Bool) {
    if isChangingClosedLidMode {
        return
    }

    syncClosedLidHelperStatus()
    syncClosedLidStatus()          // <- spawns pmset every 5s

    if desired {
        // ... enable path
    }

    guard appEnabledClosedLidMode || forceDisable else {
        return                     // <- common idle exit, AFTER the pmset spawn
    }
    // ... restore path
}
```

- `Sources/LidAwake/AppModel.swift:620-622` - `syncClosedLidStatus()` assigns
  `closedLidStatus` unconditionally from
  `closedLidStatusReader.readClosedLidStatus()`.
- `Sources/LidAwakeCore/PMSetService.swift:20-35` - `readClosedLidStatus()`
  runs `pmset -g` and, when that output lacks a verdict, also `pmset -g custom`.
  `runProcess` (lines 71-90) blocks with `process.waitUntilExit()`.
- `Sources/LidAwakeCore/WakePolicy.swift:140-163` - on every update with an
  active session, a fresh reason is built:

```swift
let reason = WakeHoldReason(
    activeSessionIDs: activeSessions.map(\.id).sorted(),
    activeAgentNames: activeSessions.map(\.displayName).sorted(),
    startedAt: now,                // <- new value every tick
    note: "Manual hold is active"
)
```

  `WakeHoldReason` is `Equatable` including `startedAt`, and
  `WakeStatus.holding(WakeHoldReason)` is `Equatable`, so `status` differs
  every tick while holding. The coordinator already stores
  `currentHoldReason` (line 88).
- `desired` comes from `shouldEnableClosedLidMode`
  (`AppModel.swift:608-618`); note `UserSettings.shouldPreventClosedLidSleep`
  is currently hardcoded `true` (`Sources/LidAwakeCore/UserSettings.swift:68-70`),
  so `desired` is true exactly when `status` is `.holding`.
- `appEnabledClosedLidMode` (`AppModel.swift:89-91`) reads the persisted
  ownership record, no process spawn.
- UI freshness safety net: both surfaces that display `closedLidStatus`
  refresh explicitly when shown (`MenuBarContentView.swift:31` and
  `SettingsView.swift:243` call `model.refreshAfterExternalPermissionChange()`,
  which calls `syncClosedLidStatus()` via `refreshClosedLidPermissionState()`),
  so skipping the idle background poll does not leave visible state stale.
- Conventions: `BatteryState`, `ClosedLidStatus`, `WakeStatus` are all
  `Equatable`. App tests use the harness + fakes pattern in
  `Tests/LidAwakeTests/AppModelLifecycleTests.swift` (see `AppModelHarness`
  and `drainMainQueue()` there). Core tests live in
  `Tests/LidAwakeCoreTests/WakePolicyCoordinatorTests.swift`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Full tests | `swift test` | exit 0, all pass |
| Core policy tests only | `swift test --filter WakePolicyCoordinatorTests` | all pass |
| App lifecycle tests only | `swift test --filter AppModelLifecycleTests` | all pass |
| Full local gate | `./scripts/check.sh` | exit 0 |

## Scope

In scope (the only files you should modify):

- `Sources/LidAwakeCore/WakePolicy.swift`
- `Sources/LidAwake/AppModel.swift`
- `Tests/LidAwakeCoreTests/WakePolicyCoordinatorTests.swift`
- `Tests/LidAwakeTests/AppModelLifecycleTests.swift`

Out of scope (do NOT touch, even though they look related):

- `Sources/LidAwakeCore/PMSetService.swift` - do not make it async; the
  synchronous read is still required by the transactional paths
  (mode-change completion at `AppModel.swift:750`, timeout at line 825,
  termination restore at line 990).
- The 1-second `closedLidSideEffectsTimer` and the coordinators it drives -
  their internal counters gate real side effects; changing that cadence risks
  the lock-on-close and display-sleep behavior.
- `NotificationDeduplicator` / `SystemNotificationService` - keep the
  `handleTransition(from:to:)` call exactly where it is; dedup is its job.
- Any UI file.

## Git workflow

- Branch: `advisor/019-cut-idle-polling`. Plain imperative commit subjects.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Stabilize the hold reason in WakePolicyCoordinator

In `Sources/LidAwakeCore/WakePolicy.swift`, inside `update`, replace the
unconditional reason construction (the excerpt above) with reuse of
`currentHoldReason` when the active set is unchanged:

```swift
let activeIDs = activeSessions.map(\.id).sorted()
let activeNames = activeSessions.map(\.displayName).sorted()
let reason: WakeHoldReason
if let current = currentHoldReason,
   current.activeSessionIDs == activeIDs,
   current.activeAgentNames == activeNames {
    reason = current
} else {
    reason = WakeHoldReason(
        activeSessionIDs: activeIDs,
        activeAgentNames: activeNames,
        startedAt: now,
        note: "Manual hold is active"
    )
}
```

The rest of the branch (acquire, `currentHoldReason = reason`,
`status = .holding(reason)`) stays as is.

Verify: `swift test --filter WakePolicyCoordinatorTests` -> all pass.

### Step 2: Add a regression test for the stable reason

In `Tests/LidAwakeCoreTests/WakePolicyCoordinatorTests.swift`, add a test
(model it on the existing tests in that file, using their fakes and clock):

- `testRepeatedUpdatesWithSameSessionsKeepStableHoldStatus`: call `update`
  twice with the same enabled settings and the same single working session,
  advancing the fake clock between calls; assert the two returned statuses are
  equal (`XCTAssertEqual(first, second)`).

Verify: `swift test --filter WakePolicyCoordinatorTests` -> all pass,
including the new test.

### Step 3: Skip the idle pmset read in reconcileClosedLidMode

In `Sources/LidAwake/AppModel.swift`, change the top of
`reconcileClosedLidMode(desired:forceDisable:)` to return before
`syncClosedLidStatus()` when the read cannot matter. Keep
`syncClosedLidHelperStatus()` where it is (it is cheap and its
`clearClosedLidReadinessBlockIfPossible()` side effect must keep running):

```swift
private func reconcileClosedLidMode(desired: Bool, forceDisable: Bool) {
    if isChangingClosedLidMode {
        return
    }

    syncClosedLidHelperStatus()

    guard desired || forceDisable || appEnabledClosedLidMode else {
        return
    }

    syncClosedLidStatus()
    // ... everything below unchanged
}
```

Correctness argument the executor can rely on: in today's code, when
`desired == false && forceDisable == false && appEnabledClosedLidMode == false`,
execution always reaches `guard appEnabledClosedLidMode || forceDisable else { return }`
and returns without using the freshly read status for any decision or side
effect other than publishing it. The new guard makes that exit happen before
the process spawn. All paths where the status is consumed
(`desired == true`, restore paths, forceDisable) still read it first.

Verify: `swift test --filter AppModelLifecycleTests` -> all pass.

### Step 4: Publish only on change

Still in `AppModel.swift`:

1. `evaluate()`: replace the first two assignments with change-guarded ones:

```swift
let nextBattery = batteryMonitor.currentState()
if battery != nextBattery {
    battery = nextBattery
}
let nextSessions = manualHoldSessions(now: Date())
if sessions.map(\.id) != nextSessions.map(\.id) {
    sessions = nextSessions
}
```

   Then pass `nextSessions` and `nextBattery` into `coordinator.update` so the
   policy always sees fresh values even when the published properties were not
   reassigned. Do NOT change the `previousStatus` / `status` bookkeeping or
   the `notificationService.handleTransition` call; after step 1, `status` is
   naturally stable while holding. Guard only the assignment:

```swift
previousStatus = status
let nextStatus = coordinator.update(settings: settings, sessions: nextSessions, battery: nextBattery)
if status != nextStatus {
    status = nextStatus
}
```

   (The existing `if status != previousStatus` log line and the
   `handleTransition` call remain untouched.)

2. `syncClosedLidStatus()`:

```swift
private func syncClosedLidStatus() {
    let next = closedLidStatusReader.readClosedLidStatus()
    if closedLidStatus != next {
        closedLidStatus = next
    }
}
```

Note: `sessions.lastEventAt` will go stale while the ID set is unchanged.
This is safe: `WakePolicyCoordinator.update` filters only on
`$0.state == .working` and never reads `lastEventAt`
(`Sources/LidAwakeCore/WakePolicy.swift:140-148`), and no view renders
`sessions`. If you find another consumer of `lastEventAt`, STOP.

Verify: `swift test` -> all pass.

### Step 5: Add an app-level churn regression test

In `Tests/LidAwakeTests/AppModelLifecycleTests.swift`, add:

- `testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish`: build a harness
  with `UserSettings(enabled: false)` (so `status` is `.inactive`, `desired`
  is false, no ownership record). Wrap the harness's
  `closedLidStatusReader` read counting by extending
  `FakeClosedLidStatusReader` in that file with a
  `private(set) var readCount = 0` incremented in `readClosedLidStatus()`.
  Then: `model.start(scheduleTimers: false)`, drain, record `readCount`,
  call `model.evaluate()` three more times, drain, and assert `readCount`
  did not increase after start (the guard from step 3 skips the read), e.g.
  `XCTAssertEqual(reader.readCount, countAfterStart)`.
  Also subscribe to `model.objectWillChange` (import Combine) before the three
  extra `evaluate()` calls and assert the received-event count is 0.

If the objectWillChange assertion proves flaky because of unrelated published
writes, keep the `readCount` assertion and drop the churn assertion, noting
that in your report.

Verify: `swift test --filter AppModelLifecycleTests` -> all pass, including
the new test.

### Step 6: Full gate

Verify: `./scripts/check.sh` -> exit 0.

## Test plan

- New: `testRepeatedUpdatesWithSameSessionsKeepStableHoldStatus` in
  `WakePolicyCoordinatorTests` (step 2).
- New: `testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish` in
  `AppModelLifecycleTests` (step 5).
- All ~99 existing tests must pass unchanged. Pay particular attention to
  `AppModelLifecycleTests` restore/ownership tests: they exercise the paths
  that must still read fresh pmset status.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift test` exits 0 with the two new tests present and passing
- [ ] In `AppModel.swift`, `syncClosedLidStatus()` is guarded behind `desired || forceDisable || appEnabledClosedLidMode` inside `reconcileClosedLidMode` (verify by reading the function)
- [ ] `grep -n "startedAt: now" Sources/LidAwakeCore/WakePolicy.swift` shows the fresh-reason construction only inside the changed-set branch (step 1 shape)
- [ ] `./scripts/check.sh` exits 0
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any consumer of `AgentSession.lastEventAt` exists outside tests
  (`grep -rn "lastEventAt" Sources/`should only show the model definition and
  `manualHoldSessions`); if more appear, the step 4 session guard is unsafe.
- Any existing `AppModelLifecycleTests` case fails after step 3 and one
  reasonable fix attempt: the guard condition is then subtly wrong; report
  which test and why rather than weakening the test.
- The code no longer matches the "Current state" excerpts (drift).
- You are tempted to make `PMSetService` async or touch the 1-second
  side-effects timer: out of scope.

## Maintenance notes

- Deferred follow-up (deliberately not in this plan): when closed-lid mode is
  active, the 5-second reconcile still spawns `pmset` synchronously on the
  main actor. Moving that read to a background queue requires reworking the
  reconcile state machine and the deterministic test harness; design it as
  its own plan if the remaining jank matters.
- If a future settings toggle makes `shouldPreventClosedLidSleep` user
  controllable (it is hardcoded `true` today), the step 3 guard automatically
  benefits: `desired` becomes false more often.
- Reviewer focus: the step 3 correctness argument, and that
  `coordinator.update` now receives `nextSessions`/`nextBattery` locals
  instead of the published properties.
