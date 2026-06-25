# Plan 009: Add app and helper lifecycle tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && wc -l Sources/AgentAwake/AppModel.swift Sources/AgentAwake/ClosedLidHelperService.swift Package.swift`
> Because this repo has no commits, compare the "Current state" excerpts
> against live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-harden-privileged-helper-xpc.md`, `plans/003-make-closed-lid-restore-crash-safe.md`, `plans/006-align-lid-awake-package-naming.md`
- **Category**: tests
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

The existing 45 tests cover the core policy layer well, but the regressions the
user has been hitting live in app/helper lifecycle: permission approval refresh,
helper status transitions, settings window activation, closed-lid ownership, and
restore behavior. Those paths currently sit behind concrete services inside
`AppModel`, which makes them hard to test without real `SMAppService`, `pmset`,
or `NSApplication` calls.

## Current State

`AppModel` constructs concrete dependencies internally:

```swift
// Sources/AgentAwake/AppModel.swift:19
private let settingsStore = SettingsStore()
private let batteryMonitor = SystemBatteryMonitor()
private let loginItemService = LoginItemService()
private let pmsetService = PMSetService()
private let closedLidHelperService = ClosedLidHelperService()
```

Approval refresh exists but is not directly covered by tests:

```swift
// Sources/AgentAwake/AppModel.swift:148
func refreshAfterExternalPermissionChange() {
    refreshClosedLidPermissionState()
    evaluate()
}
```

Package currently has only core tests:

```swift
// Package.swift:25
.testTarget(
    name: "AgentAwakeCoreTests",
    dependencies: ["AgentAwakeCore"]
)
```

Existing core tests use fake dependencies, for example
`ClosedLidDisplayCoordinatorTests` with `FakeClamshellStateReader` and
`FakeDisplaySleeper`.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `swift test` | exit 0 and includes new lifecycle tests |
| Build | `swift build` | exit 0 |
| List tests | `swift test list 2>/dev/null || true` | if supported, includes new test names |

## Scope

In scope:

- `Package.swift`
- `Sources/LidAwake/AppModel.swift` after Plan 006, or `Sources/AgentAwake/AppModel.swift` if Plan 006 has not landed
- `Sources/LidAwake/ClosedLidHelperService.swift` or current equivalent
- `Sources/LidAwake/SettingsWindowPresenter.swift` only if needed for activation seam
- New `Tests/LidAwakeTests/**` after Plan 006, or `Tests/AgentAwakeTests/**`
  if naming has not changed
- Shared protocols or reducers under `Sources/LidAwakeCore/**`

Out of scope:

- Calling real `pmset` in tests.
- Registering a real `SMAppService` in tests.
- Launching the app in tests.
- Snapshot tests for SwiftUI layout.

## Git Workflow

- Branch: `codex/009-app-helper-lifecycle-tests`
- Commit message example: `test: cover app helper lifecycle`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Introduce dependency injection without changing behavior

Add protocols for app-level services:

- settings store
- battery monitor
- login item service
- closed-lid helper service
- closed-lid status reader
- notification service
- display coordinator if needed

Keep the default `AppModel()` initializer for production. Add an internal
initializer that accepts fake services for tests.

Move only enough logic to make lifecycle transitions testable. Do not rewrite
the UI.

**Verify**: `swift build` exits 0.

### Step 2: Add an app test target

Add a test target in `Package.swift`:

```swift
.testTarget(
    name: "LidAwakeTests",
    dependencies: ["LidAwake", "LidAwakeCore"]
)
```

If SwiftPM cannot test the executable target directly, move the testable app
logic into a small library target such as `LidAwakeAppCore`, then make the
executable depend on it. Keep UI entrypoint minimal.

**Verify**: `swift test` exits 0 with the empty new target.

### Step 3: Test helper approval refresh

Add tests covering:

- status changes from `requiresApproval` to `enabled`
- `refreshAfterExternalPermissionChange()` clears readiness errors when helper
  becomes ready
- suppressed closed-lid target is cleared when helper becomes ready
- `evaluate()` is called or its effects are visible after refresh

Use fake helper service status transitions. Do not open System Settings.

**Verify**: `swift test --filter Approval` exits 0 if filtering works, otherwise
run `swift test`.

### Step 4: Test closed-lid ownership lifecycle from Plan 003

Add tests covering:

- app does not claim ownership when system was already enabled
- app records ownership after successful enable
- app restores and clears ownership on disable
- startup restore attempts cleanup when persisted ownership exists
- helper unavailable keeps warning and ownership state

Prefer pure reducer tests in `LidAwakeCore` if Plan 003 extracted a reducer.

**Verify**: `swift test --filter ClosedLid` exits 0 if filtering works,
otherwise run `swift test`.

### Step 5: Test settings activation seam only if practical

If `SettingsWindowPresenter` can be tested without launching a real app, cover:

- `show()` calls activation policy transition through an injected app activator
- closing settings returns to accessory policy

If testing AppKit window activation would be brittle, document the manual QA in
`docs/power-model.md` or `CONTRIBUTING.md` and stop at service-level tests.

**Verify**: `swift test` exits 0.

## Test Plan

New tests should be deterministic and use fakes. Required cases:

- helper approval refresh
- readiness error clearing
- ownership record creation and clearing
- startup recovery when ownership is stale
- no real `SMAppService`, `pmset`, or `NSApplication` calls

Existing tests that should remain passing:

- `WakePolicyCoordinatorTests`
- `ClosedLidDisplayCoordinatorTests`
- `PMSetServiceTests`
- `PowerAssertionManagerTests`

## Done Criteria

- [ ] `swift test` exits 0 and includes new lifecycle tests.
- [ ] `swift build` exits 0.
- [ ] `AppModel` production initializer still works.
- [ ] Tests can simulate helper status changes without real System Settings.
- [ ] Tests can simulate closed-lid ownership restore without real `pmset`.
- [ ] No test launches the app or registers a real helper.
- [ ] `plans/README.md` status row for Plan 009 is updated.

## STOP Conditions

Stop and report if:

- SwiftPM cannot expose the app logic for tests without a target split.
- The target split becomes a large architecture refactor beyond lifecycle seams.
- Tests require real OS helper approval or real power settings.
- Plan 002 or Plan 003 has not landed and the tested behavior is still changing.

## Maintenance Notes

Keep the app target thin. When future UI bugs involve helper state, add tests at
the service or reducer seam instead of relying only on manual menu bar QA.
