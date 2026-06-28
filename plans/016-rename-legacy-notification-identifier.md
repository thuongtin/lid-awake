# Plan 016: Rename legacy notification identifier

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- Sources/LidAwake/SystemNotificationService.swift`

## Status

- Priority: P3
- Effort: S
- Risk: LOW
- Depends on: none
- Category: tech-debt
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

The app has been renamed to Lid Awake, but notification request identifiers still use `agentawake`. This does not break runtime behavior, but it leaves stale branding in system notification metadata and future diagnostics.

## Current state

```swift
// Sources/LidAwake/SystemNotificationService.swift:47
identifier: "agentawake.\(event)",
```

Intentional legacy `AgentAwake` mentions still exist in `script/build_and_run.sh` and troubleshooting docs for pre-release cleanup. Do not remove those in this plan.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Search legacy app source | `rg 'agentawake' Sources Tests` | no matches |
| Full tests | `swift test` | exit 0 |
| Build | `swift build` | exit 0 |

## Scope

In scope:

- `Sources/LidAwake/SystemNotificationService.swift`

Out of scope:

- `script/build_and_run.sh` legacy cleanup.
- Historical plan files.
- User-facing notification copy.

## Steps

### Step 1: Rename notification identifier prefix

Change `agentawake.\(event)` to `lidawake.\(event)`.

Verify: `rg 'agentawake' Sources Tests` returns no matches.

## Done criteria

- App source has no `agentawake` prefix.
- `swift test` exits 0.
- `swift build` exits 0.

## STOP conditions

- Another source file depends on the old notification identifier prefix.
