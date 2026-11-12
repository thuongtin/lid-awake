# Plan 026: Notify whenever a hold is released

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first):
> `git diff --stat a81523c..HEAD -- Sources/LidAwakeCore/NotificationDeduplicator.swift Tests/LidAwakeCoreTests/NotificationEventTests.swift Sources/LidAwakeCore/WakePolicy.swift`
> If any of these files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- Priority: P2
- Effort: S
- Risk: LOW
- Depends on: none
- Category: bug
- Planned at: commit `a81523c`, 2026-11-12
- Execution status: TODO

## Why this matters

Lid Awake tells the user when it starts keeping the Mac awake ("Keeping your
Mac awake.") and when it stops ("Wake assertions were released."). People rely
on the second message: after it, the Mac may sleep, and a long job running
with the lid closed may be suspended.

Two ways of losing the hold produce no notification at all today:

- The "only when plugged in" setting is on and the power adapter is
  unplugged. This is the common one: the cable gets pulled, the hold is
  dropped, and the Mac goes to sleep without a word.
- macOS refuses the power assertion while the app is holding.

In both cases the user was told the Mac is being kept awake and is never told
that it stopped.

## Current state

The mapping from a status change to a notification,
`Sources/LidAwakeCore/NotificationDeduplicator.swift` lines 10-36:

```swift
public extension NotificationEvent {
    /// The notification a status change deserves, if any.
    ///
    /// The caller passes every evaluate through here, changed or not, and a
    /// battery cutoff carries the current percent, so a block notifies only
    /// when the app moves into that kind of block, not on every reading.
    static func forTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus) -> NotificationEvent? {
        switch (oldStatus, newStatus) {
        case (.holding, .holding):
            return nil
        case (_, .holding):
            return .holdEngaged
        case (.holding, .watching), (.holding, .inactive):
            return .holdReleased
        case (.blocked(.batteryCutoff), .blocked(.batteryCutoff)):
            return nil
        case (_, .blocked(.batteryCutoff)):
            return .batteryCutoff
        case (.blocked(.lowPowerMode), .blocked(.lowPowerMode)):
            return nil
        case (_, .blocked(.lowPowerMode)):
            return .lowPowerBlocked
        default:
            return nil
        }
    }
}
```

A hold that ends in `.blocked(.notPluggedIn)` or `.blocked(.assertionFailed)`
falls through to `default` and returns `nil`.

Where those two statuses come from, `Sources/LidAwakeCore/WakePolicy.swift`
(inside the policy's evaluate function, around lines 105-109 and 148-158):

```swift
if settings.onlyWhenPluggedIn, !battery.isOnACPower {
    releaseAndClear()
    status = .blocked(.notPluggedIn)
    return status
}
```

```swift
do {
    try powerController.acquire(
        reason: reason,
        preventDisplaySleep: settings.shouldPreventDisplaySleep
    )
    currentHoldReason = reason
    status = .holding(reason)
} catch {
    releaseAndClear()
    status = .blocked(.assertionFailed(error.localizedDescription))
}
```

The text the user sees, `Sources/LidAwake/SystemNotificationService.swift`
lines 39-50 (not changed by this plan):

```swift
private func body(for event: NotificationEvent) -> String {
    switch event {
    case .holdEngaged:
        "Keeping your Mac awake."
    case .holdReleased:
        "Wake assertions were released."
    case .batteryCutoff:
        "Battery cutoff reached. Wake assertions were released."
    case .lowPowerBlocked:
        "Low Power Mode is active. Wake assertions are blocked."
    }
}
```

A hold released by the battery cutoff or by Low Power Mode already notifies
with its own, more specific message, and that must stay as it is.

The existing tests, `Tests/LidAwakeCoreTests/NotificationEventTests.swift`
(44 lines). The class has a `hold` fixture and this test at the end:

```swift
    func testHoldTransitions() {
        XCTAssertEqual(NotificationEvent.forTransition(from: .watching, to: hold), .holdEngaged)
        XCTAssertNil(NotificationEvent.forTransition(from: hold, to: hold))
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .watching), .holdReleased)
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .inactive), .holdReleased)
        XCTAssertNil(NotificationEvent.forTransition(from: .watching, to: .watching))
    }
```

The fix was tried on a scratch copy before this plan was written: the three
new tests below failed where expected before the change and the full suite
passed after it.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Run the notification tests | `swift test --filter NotificationEventTests` | 0 failures |
| Full local gate | `./scripts/check.sh` | exit 0 |

## Scope

In scope (the only files you should modify):

- `Sources/LidAwakeCore/NotificationDeduplicator.swift` (the `switch` in
  `forTransition` only)
- `Tests/LidAwakeCoreTests/NotificationEventTests.swift` (three new tests)
- `plans/README.md` (status row only)

Out of scope:

- `SystemNotificationService.swift`: no new notification text, no new
  `NotificationEvent` case. A dedicated "power adapter unplugged" message is a
  product decision for the maintainer, not part of this fix.
- `NotificationDeduplicator` (the class below the extension) and its 600
  second window.
- `WakePolicy.swift`.

## Git workflow

- Branch: `advisor/026-notify-every-hold-release`. Plain imperative commit
  subject, for example `Notify whenever a hold is released`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the tests

Append these three methods to the `NotificationEventTests` class, after
`testHoldTransitions`:

```swift

    func testEveryReleaseOfAHoldNotifies() {
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .blocked(.notPluggedIn)), .holdReleased)
        XCTAssertEqual(
            NotificationEvent.forTransition(from: hold, to: .blocked(.assertionFailed("denied"))),
            .holdReleased
        )
    }

    func testAHoldReleasedByABatteryGuardrailNamesTheGuardrail() {
        XCTAssertEqual(
            NotificationEvent.forTransition(from: hold, to: .blocked(.batteryCutoff(percent: 19, cutoff: 20))),
            .batteryCutoff
        )
        XCTAssertEqual(NotificationEvent.forTransition(from: hold, to: .blocked(.lowPowerMode)), .lowPowerBlocked)
    }

    func testABlockThatNeverHeldDoesNotReportARelease() {
        XCTAssertNil(NotificationEvent.forTransition(from: .watching, to: .blocked(.notPluggedIn)))
        XCTAssertNil(NotificationEvent.forTransition(from: .blocked(.notPluggedIn), to: .blocked(.notPluggedIn)))
        XCTAssertNil(NotificationEvent.forTransition(from: .blocked(.notPluggedIn), to: .watching))
    }
```

Verify: `swift test --filter NotificationEventTests`. Expected at this point:
`testEveryReleaseOfAHoldNotifies` FAILS (both assertions get `nil`); the
other two new tests pass, because they pin behaviour that must not change. If
`testEveryReleaseOfAHoldNotifies` passes before the source change, STOP.

### Step 2: Treat every other exit from a hold as a release

In `forTransition`, delete the case
`case (.holding, .watching), (.holding, .inactive):` with its `return`, and
add a catch-all for holds after the two block-specific groups, so the switch
reads:

```swift
        switch (oldStatus, newStatus) {
        case (.holding, .holding):
            return nil
        case (_, .holding):
            return .holdEngaged
        case (.blocked(.batteryCutoff), .blocked(.batteryCutoff)):
            return nil
        case (_, .blocked(.batteryCutoff)):
            return .batteryCutoff
        case (.blocked(.lowPowerMode), .blocked(.lowPowerMode)):
            return nil
        case (_, .blocked(.lowPowerMode)):
            return .lowPowerBlocked
        case (.holding, _):
            // Every other way out of a hold, so that a release with no
            // notification of its own, such as unplugging the power adapter,
            // is not silent after the hold itself was announced.
            return .holdReleased
        default:
            return nil
        }
```

The order matters: the battery cutoff and Low Power cases must stay above
`(.holding, _)` so those releases keep their specific message.

Verify: `swift test --filter NotificationEventTests` -> 7 tests, 0 failures.

### Step 3: Full gate

Verify: `./scripts/check.sh` -> exit 0.

## Test plan

- New: `testEveryReleaseOfAHoldNotifies` (the regression).
- New: `testAHoldReleasedByABatteryGuardrailNamesTheGuardrail` (pins the case
  ordering, so a later reorder cannot downgrade the specific messages).
- New: `testABlockThatNeverHeldDoesNotReportARelease` (pins that a block which
  never held, or which stays blocked on every five-second evaluate, does not
  start sending notifications).
- Existing `testHoldTransitions` must pass unchanged.

## Done criteria

- [ ] `swift test --filter NotificationEventTests` reports 7 tests, 0
      failures.
- [ ] `swift test` reports 0 failures.
- [ ] `./scripts/check.sh` exits 0.
- [ ] `git diff --stat` lists only the three in-scope files.
- [ ] No em dash character in the diff:
      `git diff | grep -c "$(printf '\xe2\x80\x94')"` prints `0`.
- [ ] Status row for 026 in `plans/README.md` updated.

## STOP conditions

Stop and report back (do not improvise) if:

- `forTransition` no longer matches the excerpt in "Current state" (for
  example a new `WakeStatus` or `WakeBlockReason` case exists).
- `testEveryReleaseOfAHoldNotifies` passes before the source change.
- Any test outside `NotificationEventTests` fails after step 2.

## Maintenance notes

- `(.holding, _)` is a catch-all on purpose: a new `WakeBlockReason` added
  later will notify as a plain release by default instead of being silent.
  Give it its own case above the catch-all only if it deserves its own text.
- The deduplicator still suppresses a repeat of the same event inside 600
  seconds, so plugging and unplugging the adapter repeatedly produces at most
  one "released" and one "engaged" notification per ten minutes. That window
  is unchanged.
- Possible follow-up for the maintainer (not planned): a dedicated message for
  the unplugged case, for example "Power adapter unplugged. Wake assertions
  were released.", which needs a new `NotificationEvent` case and a line in
  `SystemNotificationService.body(for:)`.
