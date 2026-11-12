# Plan 024: Answer the app before the helper watchdog reads pmset

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first):
> `git diff --stat a81523c..HEAD -- Sources/LidAwakeHelper/LidAwakeHelperMain.swift Sources/LidAwakeCore/ClosedLidRestoreWatchdog.swift Sources/LidAwakeCore/PMSetService.swift Sources/LidAwake/ClosedLidHelperService.swift`
> If any of these files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- Priority: P2
- Effort: S
- Risk: MED (four moved lines, but inside the privileged helper)
- Depends on: none
- Category: bug
- Planned at: commit `a81523c`, 2026-11-12
- Execution status: TODO

## Why this matters

The privileged helper runs `pmset -a disablesleep` as root for the app and
answers over XPC. The app waits four seconds for that answer. What the app
does next depends on which failure it sees:

- "the helper answered that `pmset` failed" (`.commandFailed`): the app shows
  the `pmset` message and retries by itself after 60 seconds.
- "the helper did not answer in time" (`.timedOut`): the app concludes the
  helper itself is broken, stops retrying, and offers the Repair button.

When `pmset` is slow, the helper currently does its own bookkeeping, which can
include a second `pmset` call, before it answers. The two calls together can
take longer than the app's four seconds. The app then reports a broken helper
and asks the user to repair a helper that is working, and the real `pmset`
error is never shown. Answering first removes that: the bookkeeping does not
need to happen before the reply.

This case is rare (it needs `pmset` to hang or crawl), so the impact is
low to medium. It is worth fixing because the wrong diagnosis sends the user
to System Settings for nothing, at exactly the moment the machine-wide
`disablesleep` setting may be stuck on.

## Current state

The request handler, `Sources/LidAwakeHelper/LidAwakeHelperMain.swift` lines
68-89:

```swift
func setClosedLidMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
    // Only valid while this call is being delivered, so read it before
    // hopping queues. It names the client the accept-time checks approved.
    let clientProcessID = NSXPCConnection.current()?.processIdentifier
    commandQueue.async { [self] in
        var changeError: Error?
        do {
            try pmsetService.setClosedLidMode(enabled: enabled)
        } catch {
            changeError = error
        }

        if let clientProcessID {
            restoreWatchdog.closedLidModeChangeAttempted(
                enabled: enabled,
                outcome: ClosedLidModeChangeOutcome(error: changeError),
                clientProcessID: clientProcessID
            )
        }
        reply(changeError == nil, changeError?.localizedDescription)
    }
}
```

`commandQueue` is a serial queue and the only place the watchdog is touched
(same file, lines 17-20):

```swift
/// Every connection gets its own queue, so without this two requests could
/// run `pmset` at once and finish in either order. The watchdog relies on it
/// too: it is only touched from here.
private let commandQueue = DispatchQueue(label: "\(LidAwakeHelperConstants.machServiceName).commands")
```

The watchdog bookkeeping reads `pmset` on the two failure paths
(`Sources/LidAwakeCore/ClosedLidRestoreWatchdog.swift` lines 97-123):

```swift
public func closedLidModeChangeAttempted(
    enabled: Bool,
    outcome: ClosedLidModeChangeOutcome,
    clientProcessID: Int32
) {
    guard enabled else {
        if outcome == .succeeded {
            disarm()
            pendingRestore = nil
        } else if armed == nil, pendingRestore == nil, readClosedLidStatus() != .disabled {
            arm(clientProcessID: clientProcessID)
        }
        return
    }

    guard outcome != .failed || readClosedLidStatus() != .disabled else {
        return
    }
    ...
```

The time budget, from `Sources/LidAwakeCore/PMSetService.swift` lines 22-26,
`Sources/LidAwakeCore/ProcessRunner.swift` line 23, and
`Sources/LidAwake/ClosedLidHelperService.swift` line 100:

```swift
public static let statusReadTimeout: TimeInterval = 2
/// Short enough for the helper to answer inside the app's XPC deadline.
public static let closedLidChangeTimeout: TimeInterval = 3
```

```swift
static let terminationGracePeriod: TimeInterval = 0.5
```

```swift
private let xpcResponseTimeout: TimeInterval = 4
```

Worst case today for a change that hangs: 3.0 s (change timeout) + 0.5 s
(termination grace) = 3.5 s, then the watchdog read: up to 2.0 s + 0.5 s. That
is up to 6.0 s before `reply` runs, against a 4 s deadline. The comment on
`closedLidChangeTimeout` states the intent ("answer inside the app's XPC
deadline"); the bookkeeping order breaks it.

Why the reorder is safe (checked while writing this plan; re-check each point
against the live code before you edit):

1. Everything stays on `commandQueue`. The next request from any client is
   queued behind the current block, so it cannot observe the watchdog before
   the bookkeeping for this request has run.
2. Successful enable, then the app dies between the reply and `arm`:
   `DispatchProcessExitWatch` (`ClosedLidRestoreWatchdog.swift`, near the end
   of the file) checks `kill(processID, 0)` right after it starts watching and
   fires at once for a process that is already gone, so the restore still
   happens.
3. Successful disable, then the app exits between the reply and `disarm`: the
   exit handler is delivered on `commandQueue`, so it runs after this block,
   when `disarm()` has already invalidated the watch.
4. `reply` is called exactly once on every path, as before.

There is no unit test target for `LidAwakeHelper` (it is an executable target
whose `HelperService` talks to real XPC), and this plan deliberately does not
introduce one: extracting the handler into `LidAwakeCore` would turn a
four-line reorder in security-sensitive code into a refactor. The watchdog's
own behaviour is already covered by
`Tests/LidAwakeCoreTests/ClosedLidRestoreWatchdogTests.swift`, which this plan
must leave green and unchanged.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build the helper | `swift build --product LidAwakeHelper` | exit 0 |
| Watchdog tests | `swift test --filter ClosedLidRestoreWatchdogTests` | 0 failures |
| Full local gate | `./scripts/check.sh` | exit 0 |

Never run `./scripts/verify.sh` or `./script/build_and_run.sh` without
`--stage`: they launch the app and touch live power-management state. Do not
install, register, or launch the helper.

## Scope

In scope (the only files you should modify):

- `Sources/LidAwakeHelper/LidAwakeHelperMain.swift` (the body of
  `setClosedLidMode` only)
- `plans/README.md` (status row only)

Out of scope:

- `listener(_:shouldAcceptNewConnection:)`, `HelperClientAuthorizer`, the
  code-signing requirement, and `LidAwakeHelperXPCProtocol`. This plan does
  not change who may call the helper or what the helper accepts.
- `ClosedLidRestoreWatchdog`, `PMSetService`, and every timeout constant.
  Do not "fix" the budget by changing a timeout.
- `Sources/LidAwake/`: the app side needs no change.

## Git workflow

- Branch: `advisor/024-answer-before-watchdog-read`. Plain imperative commit
  subject, for example `Answer the app before the watchdog reads pmset`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Confirm the four safety points

Read `Sources/LidAwakeCore/ClosedLidRestoreWatchdog.swift` in full and confirm
points 1 to 4 in "Current state" against the live code: the exit handler is
dispatched on the queue passed in as `watchProcessExit`'s queue
(`commandQueue` in `LidAwakeHelperMain.swift`), and `DispatchProcessExitWatch`
checks for an already-exited process after it starts watching.

Verify: `grep -n 'ESRCH' Sources/LidAwakeCore/ClosedLidRestoreWatchdog.swift`
prints at least one line, and
`grep -n 'DispatchProcessExitWatch(processID: processID, queue: commandQueue' Sources/LidAwakeHelper/LidAwakeHelperMain.swift`
prints one line. If either prints nothing, STOP.

### Step 2: Reply first

Replace the tail of the `commandQueue.async` block (from `if let
clientProcessID {` through the `reply(...)` line) with:

```swift
            // Answer before recording the attempt: the watchdog may read
            // `pmset` to decide whether to watch the client, and a slow read
            // on top of a slow change would outlast the app's XPC deadline, so
            // the app would report a lost helper instead of what `pmset` said.
            reply(changeError == nil, changeError?.localizedDescription)

            if let clientProcessID {
                restoreWatchdog.closedLidModeChangeAttempted(
                    enabled: enabled,
                    outcome: ClosedLidModeChangeOutcome(error: changeError),
                    clientProcessID: clientProcessID
                )
            }
```

Nothing else in the file changes. The `pmsetService.setClosedLidMode` call
stays before the reply.

Verify: `swift build --product LidAwakeHelper` -> exit 0.
`git diff --stat` -> one file, and `git diff` shows only the moved `reply`
line plus the four comment lines.

### Step 3: Full gate

Verify: `swift test --filter ClosedLidRestoreWatchdogTests` -> 0 failures.
`./scripts/check.sh` -> exit 0.

### Step 4: Hand over the manual QA

This change is in a file that `AGENTS.md` lists as security-sensitive, and the
repo requires the manual QA checklist in `docs/power-model.md` for it. An
executor cannot run that checklist (it needs a Developer ID signed build, an
approved helper, and live `pmset` changes), so do NOT attempt it. Instead:

- Set the status row in `plans/README.md` to
  `DONE, pending manual QA items 9, 10, 11, 13, 14`.
- In your final report, list those five items for the maintainer exactly as
  written under "Test plan" below.

## Test plan

Automated (must stay green, unchanged): `ClosedLidRestoreWatchdogTests` and
the whole `swift test` suite. No new automated test: see "Current state" for
why.

Manual, for the maintainer, on a Developer ID signed build with the helper
approved (items from `docs/power-model.md`, "Manual QA Checklist"):

- Item 9, Quit app: closed-lid mode is restored on quit.
- Item 10, Force quit while closed-lid mode is on: `kill -9` the app; within
  a second `pmset -g` reports `SleepDisabled 0` and the helper log shows the
  restore line. This is the check for safety point 2.
- Item 11, Command-line removal: `--helper-remove` after a `kill -9` ends with
  `SleepDisabled 0`.
- Item 13, Re-arm after Repair: Repair, wait for `Ready`, `kill -9`; within a
  second `SleepDisabled 0`.
- Item 14, Quit during Repair: the app quits with `SleepDisabled 0`.

## Done criteria

- [ ] `swift build` exits 0.
- [ ] `swift test` reports 0 failures, with no test file modified.
- [ ] `./scripts/check.sh` exits 0.
- [ ] `git diff --stat` lists only `Sources/LidAwakeHelper/LidAwakeHelperMain.swift`
      and `plans/README.md`.
- [ ] In `setClosedLidMode`, `reply(` appears before
      `restoreWatchdog.closedLidModeChangeAttempted(` and after
      `pmsetService.setClosedLidMode(`.
- [ ] No em dash character in the diff:
      `git diff | grep -c "$(printf '\xe2\x80\x94')"` prints `0`.
- [ ] Status row for 024 in `plans/README.md` says
      `DONE, pending manual QA items 9, 10, 11, 13, 14`.

## STOP conditions

Stop and report back (do not improvise) if:

- Either grep in step 1 prints nothing, or any of the four safety points does
  not hold in the live code.
- `setClosedLidMode` no longer matches the excerpt in "Current state".
- You find yourself wanting to change a timeout, the watchdog, the XPC
  protocol, or the connection acceptance code.
- A watchdog test fails after step 2.

## Maintenance notes

- The rule this plan establishes: in the helper, the reply to the client goes
  out as soon as the outcome of the `pmset` change is known. Anything that can
  block (reads, logging to a slow sink, future bookkeeping) goes after it.
- The watchdog must stay confined to `commandQueue`. The reorder is only safe
  because of that; code that touches `restoreWatchdog` from another queue
  would reintroduce a race between the reply and the bookkeeping.
- Reviewer focus: confirm the diff does not touch connection acceptance, and
  that the maintainer has ticked the five manual QA items before the next
  public release.
- Related, deliberately not planned here: the helper forgets its watch when
  launchd restarts it while the app keeps running, because the app only
  re-arms at its own launch. That needs a design decision (see the fourth
  audit notes in `plans/README.md`).
