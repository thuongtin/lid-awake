# Plan 003: Make closed-lid restore crash-safe

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && git diff --stat -- Sources/AgentAwake Sources/AgentAwakeCore Tests docs script`
> Because this repo currently has no commits, compare the "Current state"
> excerpts against live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: `plans/002-harden-privileged-helper-xpc.md`
- **Category**: correctness
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

Closed-lid mode changes a global macOS power setting. The app currently keeps
ownership state only in memory, so a crash or forced kill can leave
`disablesleep` enabled until the user notices. A public macOS power utility must
be able to recover on next launch, avoid disabling settings it did not enable,
and explain when cleanup is blocked by helper approval.

## Current State

Relevant files:

- `Sources/AgentAwake/AppModel.swift` - current closed-lid mode state machine.
- `Sources/AgentAwake/SettingsStore.swift` - persisted app settings.
- `Sources/AgentAwakeCore/ClosedLidStatus.swift` - status model.
- `Sources/AgentAwakeCore/PMSetService.swift` - reads and writes `pmset`.
- `Tests/AgentAwakeCoreTests/ClosedLidDisplayCoordinatorTests.swift` - pattern
  for deterministic closed-lid tests.

Current ownership is RAM-only:

```swift
// Sources/AgentAwake/AppModel.swift:32
private var appEnabledClosedLidMode = false
```

Current code marks ownership even if system mode was already enabled:

```swift
// Sources/AgentAwake/AppModel.swift:362
guard closedLidStatus != .enabled else {
    appEnabledClosedLidMode = true
    closedLidError = nil
    return
}
```

Current cleanup runs only on normal app stop:

```swift
// Sources/AgentAwake/AppModel.swift:491
private func restoreClosedLidModeForTerminationIfNeeded() {
    guard appEnabledClosedLidMode else {
        return
    }
```

Current settings persistence is available:

```swift
// Sources/AgentAwake/SettingsStore.swift:23
func save(_ settings: UserSettings) {
    guard let data = try? JSONEncoder().encode(settings) else {
        return
    }
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `swift test` | exit 0, all tests pass |
| Build | `swift build` | exit 0 |
| Stage | `./script/build_and_run.sh --stage` | exit 0 |
| Local runtime QA | `./script/build_and_run.sh --verify` | exit 0 on a developer Mac where app launch and assertions are allowed |

## Scope

In scope:

- `Sources/AgentAwake/AppModel.swift`
- `Sources/AgentAwake/SettingsStore.swift`
- New ownership store type under `Sources/AgentAwake/` or deterministic core
  reducer under `Sources/AgentAwakeCore/`
- `Tests/AgentAwakeCoreTests/*` and, if needed, a new app test target
- `docs/power-model.md`

Out of scope:

- Changing helper registration UX.
- Adding new display modes.
- Renaming package or targets.
- Any direct source edit outside the closed-lid ownership and test seams.

## Git Workflow

- Branch: `codex/003-crash-safe-closed-lid-restore`
- Commit message example: `fix: make closed-lid restore crash-safe`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Define durable ownership state

Add a small persisted ownership model, for example `ClosedLidOwnershipRecord`,
with at least:

- `ownedByThisApp: Bool`
- `enabledAt: Date?`
- `previousStatus: ClosedLidStatus`
- `lastAttemptedRestoreAt: Date?`

Store it separately from user settings so cleanup metadata survives settings
changes. Use `UserDefaults` or an app support file, but keep it behind a small
store protocol so tests can use an in-memory fake.

**Verify**: `swift test` exits 0 after adding compile-only scaffolding and
basic encode/decode tests.

### Step 2: Record ownership only when the app actually changes the setting

Update `finishClosedLidModeChange(enabled:result:status:)` and the code around
`reconcileClosedLidMode(desired:forceDisable:)` so the app records ownership
only after it successfully changes the status from disabled or not reported to
enabled.

Do not set ownership when `closedLidStatus == .enabled` before the app asks for
enable. In that case, show the current system state but do not promise to
restore it.

**Verify**: add tests for:

- status already enabled before app action does not create app ownership
- successful enable from disabled creates ownership record
- successful disable clears ownership record

Run `swift test`.

### Step 3: Restore on normal stop and next startup

Update startup flow in `AppModel.start()`:

- load ownership record
- sync helper status and system closed-lid status
- if ownership says the app enabled closed-lid mode and settings/status no
  longer require it, request restore through the helper
- if helper is not ready, keep a visible `closedLidError` and do not clear the
  ownership record

Keep `restoreClosedLidModeForTerminationIfNeeded()` for normal quit, but make it
use the same persisted ownership store.

**Verify**: add deterministic tests around the extracted reducer/store logic.
Run `swift test`.

### Step 4: Document recovery behavior

Update `docs/power-model.md` with a "Crash recovery" section:

- what state is persisted
- when the app restores on next launch
- what the user should do if helper approval is missing
- that the app does not disable a mode it did not enable

**Verify**: `rg 'Crash recovery|ownership|restore|did not enable' docs/power-model.md`
prints the new documentation.

## Test Plan

Create tests that do not call real `pmset`:

- ownership encode/decode
- enable creates ownership only when previous status was not enabled
- pre-existing enabled system state is not claimed by the app
- normal disable clears ownership
- startup cleanup tries restore when persisted ownership exists
- startup cleanup leaves warning when helper is not ready

Use existing tests such as
`Tests/AgentAwakeCoreTests/ClosedLidDisplayCoordinatorTests.swift` as the style
pattern: fake dependencies, assert actions and state transitions.

## Done Criteria

- [ ] `swift test` exits 0 with new ownership and recovery tests.
- [ ] `swift build` exits 0.
- [ ] App no longer treats pre-existing enabled closed-lid mode as app-owned.
- [ ] App persists ownership after successful enable and clears it after
  successful restore.
- [ ] App attempts cleanup on next launch when ownership is stale.
- [ ] User-visible error remains if cleanup is blocked by helper status.
- [ ] `docs/power-model.md` documents crash recovery.
- [ ] `plans/README.md` status row for Plan 003 is updated.

## STOP Conditions

Stop and report if:

- The restore flow requires broad app-state rewrites outside `AppModel` and the
  new ownership store.
- Helper authorization from Plan 002 is not present.
- You cannot write deterministic tests without calling real `pmset`.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance Notes

Every future change to closed-lid behavior must preserve the distinction between
system state and app-owned state. Reviewers should look for accidental writes to
ownership state before helper success is confirmed.
