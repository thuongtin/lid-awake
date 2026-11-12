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
include a status read of one or two more `pmset` calls, before it answers. The
change and the read together can take longer than the app's four seconds. The
app then reports a helper that did not respond
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

The watchdog bookkeeping reads `pmset` on two paths only
(`Sources/LidAwakeCore/ClosedLidRestoreWatchdog.swift` lines 97-123):

- an enable that `pmset` reported as failed (outcome `.failed`, from
  `PMSetError.commandFailed`). An enable that timed out has the outcome
  `.unknown`, arms the watch without a read, and so adds no read time;
- a disable that did not succeed (outcome `.failed` or `.unknown`, so a
  timed-out disable counts too) while no watch is armed and no restore is
  pending. A disable while a watch is armed or a restore is pending does not
  read.

A successful enable or disable never reads.

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

The change itself takes at most about 3.5 s: 3.0 s (change timeout) + 0.5 s
(termination grace when `pmset` hangs, or the bound on draining its pipes
when it exits just before the timeout).

The watchdog's status read, `PMSetService.readClosedLidStatus`, can run two
`pmset` processes in sequence. It first runs `pmset -g`, bounded by 2.0 s
(status read timeout) + 0.5 s (termination grace or pipe drain bound). If
that call times out, the read ends there with `.notReported`, after about
2.5 s. If it exits in time but fails or reports no `SleepDisabled` line, the
read then runs `pmset -g custom`, bounded the same way. So one read can take
up to about 5.0 s (the review measured 3.92 s with hanging stand-in
processes).

Worst case today, on a path that reads (see above): up to about 3.5 s for the
change plus about 5.0 s for the read, so up to about 8.5 s before `reply`
runs, against a 4 s deadline. With the reply first, it goes out after at most
about 3.5 s (the review measured 3.0 s). That leaves roughly 0.5 s of the
app's 4 s for the on-demand launch of the helper, the client code-signing
check, and XPC overhead. That margin has not been verified on a signed build.
The comment on `closedLidChangeTimeout` states the intent ("answer inside the
app's XPC deadline"); the bookkeeping order breaks it.

Why the reorder is safe (checked while writing this plan; re-check each point
against the live code before you edit):

1. Everything stays on `commandQueue`. The next request from any client is
   queued behind the current block, so it cannot observe the watchdog before
   the bookkeeping for this request has run.
2. Successful enable, then the app dies between the reply and `arm`:
   `DispatchProcessExitWatch` (`ClosedLidRestoreWatchdog.swift`, near the end
   of the file) checks `kill(processID, 0)` right after it starts watching
   and, for a process that is already gone, queues the exit handler on
   `commandQueue` with `queue.async`. It runs after the current block, not at
   once, and the restore still happens.
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
            // `pmset`, and a slow read on top of a slow change could pass the
            // app's XPC deadline, so the app would report a helper that did not
            // respond instead of what `pmset` said.
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

### Review notes (2026-11-12)

An independent review of the implementing commit `bcb07fb` found no blocking
problem. Its corrections to the timing budget and to when the watchdog reads
`pmset` are folded into "Current state" above. It also named these trade-offs
of replying first, which this plan accepts:

1. The read's latency is not removed, it moves behind the reply. A request
   sent right after the reply to a failed change (for example the disable
   the app sends when the user quits, or the disable that the command-line
   `--helper-repair`, `ClosedLidHelperRemoval.repairHelper`, sends once the
   app has quit) waits on `commandQueue` behind the watchdog's read, and can
   pass the 4 s deadline, so that next request is reported as a timeout. The
   in-app Repair is not an example: a reply that `pmset` failed sets
   `closedLidHelperNeedsRepair` to false, so Repair is not offered then.
   Accepted because it is safe and not new: the helper still runs the queued
   disable and then disarms, a failed disable leaves the watch on the app's
   PID in place, a command-line repair whose restore timed out goes on to
   restore through the newly registered helper, and the same wait already
   existed under the old order whenever the client had timed out on the first
   request while the helper was still reading.
2. On the paths that read, the window between the reply and arming the watch
   is longer by the duration of the read, so a client that exits right after
   the reply (for example the command-line repair) could in theory have its
   PID reused by another process before the watch is armed. Accepted because
   the helper already identifies its client by PID, the window grows only on
   paths that read, and macOS hands out PIDs sequentially, so reuse within a
   few seconds is very unlikely.
3. Manual QA items 9, 10, 11, 13 and 14 in `docs/power-model.md` do not
   exercise the window between the reply and arming, and none makes `pmset`
   slow or failing. The watchdog unit tests cover the watchdog logic with
   fakes, not the ordering inside `HelperService`. Accepted because these
   items still confirm that normal behaviour did not regress, and the ordering
   itself is a four-line change that can be checked by reading it; they do
   not, however, show that the false timeout is gone.

Suggested extra manual check for the maintainer (a suggestion only, not part
of the checklist in `docs/power-model.md`). Use a local, never-shipped build
of the helper with two temporary changes:

- its enable runs the real `pmset -a disablesleep 1` and then reports it as
  failed with a distinctive message that is not a permission failure (a
  permission message is shown to the user as an approval prompt instead);
- the watchdog's `readClosedLidStatus` closure in `LidAwakeHelperMain.swift`
  sleeps about 5 s in Swift before calling `pmsetService.readClosedLidStatus()`.
  The delay must be added in Swift around the read, not inside a slow `pmset`
  stand-in process, because the 2 s status read timeout would cut a slow
  process short. Delay only the watchdog's closure: the helper's XPC
  `readClosedLidStatus`, which the app uses to probe the connection, calls the
  same service method.

Enable closed-lid mode from the app. With the reply first, the app shows the
distinctive failure message almost at once. With the old order, the reply
would come only after the 5 s read, past the app's 4 s XPC deadline, so the
app would show "Lid Awake Helper did not respond" and offer Repair instead.
Seeing the failure message is what shows the false timeout is gone. Then
`kill -9` the app as soon as that message appears, while the helper is still
in its 5 s read: when the read ends it reports the mode as on, the watchdog
arms a watch for the app's PID that is already gone, and the watch fires
right after. Within about 6 s of the message `pmset -g` should report
`SleepDisabled 0` and the helper log should show the restore line, which
shows that a watch armed after the client exited still restores. Reinstall
the normal signed helper afterwards.
