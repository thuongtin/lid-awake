# Plan 006: Align package and target names with Lid Awake

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && rg 'AgentAwake|LidAwake|Lid Awake' Package.swift Sources Tests script scripts docs`
> Because this repo has no commits, compare the "Current state" excerpts
> against live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-harden-privileged-helper-xpc.md`, `plans/003-make-closed-lid-restore-crash-safe.md`
- **Category**: tech-debt
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

The public app is now `Lid Awake`, but SwiftPM package names, target names,
directories, imports, tests, and build script product names still say
`AgentAwake`. For Open Source contributors this creates constant ambiguity:
the app users see, the package they build, and the helper binary do not share
one identity. Renaming before public release is cheaper than carrying legacy
names into docs, CI, release archives, and issue reports.

## Current State

Current SwiftPM manifest:

```swift
// Package.swift:6
name: "AgentAwake",
```

```swift
// Package.swift:11
.library(name: "AgentAwakeCore", targets: ["AgentAwakeCore"]),
.executable(name: "AgentAwake", targets: ["AgentAwake"]),
.executable(name: "AgentAwakeHelper", targets: ["AgentAwakeHelper"])
```

Current staging maps old product names to new app names:

```bash
# script/build_and_run.sh:5
APP_PRODUCT="AgentAwake"
HELPER_PRODUCT="AgentAwakeHelper"
APP_NAME="LidAwake"
```

Shared helper constants are already public-name aligned:

```swift
// Sources/AgentAwakeCore/AgentAwakeHelperXPCProtocol.swift:4
public static let machServiceName = "com.thuongtin.LidAwake.Helper"
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Rename audit | `rg 'AgentAwake' Package.swift Sources Tests script scripts docs` | only intentional legacy migration mentions remain |
| Build | `swift build` | exit 0 |
| Tests | `swift test` | exit 0 |
| Stage | `./script/build_and_run.sh --stage` | exit 0, creates `dist/LidAwake.app` |
| Bundle binary check | `test -x dist/LidAwake.app/Contents/MacOS/LidAwake` | exit 0 |
| Helper binary check | `test -x dist/LidAwake.app/Contents/Library/LaunchServices/LidAwakeHelper` | exit 0 |

## Scope

In scope:

- `Package.swift`
- `Sources/AgentAwake/**` to rename to `Sources/LidAwake/**`
- `Sources/AgentAwakeCore/**` to rename to `Sources/LidAwakeCore/**`
- `Sources/AgentAwakeHelper/**` to rename to `Sources/LidAwakeHelper/**`
- `Tests/AgentAwakeCoreTests/**` to rename to `Tests/LidAwakeCoreTests/**`
- Imports, symbols, test names, and helper protocol names that include
  `AgentAwake`
- `script/build_and_run.sh`
- `scripts/verify.sh`
- `docs/power-model.md`
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md` if created by Plan 004

Out of scope:

- Bundle identifier changes. Keep `com.thuongtin.LidAwake`.
- Removing explicit legacy cleanup for old process names in the staging script.
- UI redesign.
- Behavior changes to power assertions or helper restore.

## Git Workflow

- Branch: `codex/006-align-lid-awake-naming`
- Commit message example: `refactor: align package names with lid awake`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Rename SwiftPM package products and targets

Update `Package.swift`:

- package `name` becomes `LidAwake`
- library product becomes `LidAwakeCore`
- app executable product becomes `LidAwake`
- helper executable product becomes `LidAwakeHelper`
- test target becomes `LidAwakeCoreTests`

Move directories to match target names. Prefer `git mv` if the executor is
working in a git repo with commits, otherwise use normal filesystem moves.

**Verify**:

```bash
swift package dump-package | rg '"name" : "LidAwake"|"name" : "LidAwakeCore"|"name" : "LidAwakeHelper"'
```

Expected: all three names appear.

### Step 2: Rename imports and shared helper symbols

Replace imports from `AgentAwakeCore` to `LidAwakeCore`.

Rename helper protocol symbols:

- `AgentAwakeHelperConstants` to `LidAwakeHelperConstants`
- `AgentAwakeHelperXPCProtocol` to `LidAwakeHelperXPCProtocol`

Keep string constants for Mach service and plist name unchanged:

```swift
"com.thuongtin.LidAwake.Helper"
"com.thuongtin.LidAwake.Helper.plist"
```

**Verify**:

```bash
rg 'AgentAwakeCore|AgentAwakeHelperConstants|AgentAwakeHelperXPCProtocol' Sources Tests
```

Expected: no matches unless intentionally left in a migration comment.

### Step 3: Update build and verification scripts

In `script/build_and_run.sh`, set:

```bash
APP_PRODUCT="LidAwake"
HELPER_PRODUCT="LidAwakeHelper"
APP_NAME="LidAwake"
HELPER_NAME="LidAwakeHelper"
```

Keep `LEGACY_APP_NAME="AgentAwake"` only if it is used for migration cleanup,
and add a short comment explaining that it is a previous pre-release process
name.

Update `scripts/verify.sh` if target names are referenced.

**Verify**:

```bash
swift build
swift test
./script/build_and_run.sh --stage
```

Expected: all exit 0.

### Step 4: Update docs and tests

Update docs to use `LidAwake`, `LidAwakeCore`, and `LidAwakeHelper` as internal
target names. Remove stale `AgentAwake` references from current docs except a
single migration note if needed.

**Verify**:

```bash
rg 'AgentAwake' Package.swift Sources Tests scripts docs README.md CONTRIBUTING.md SECURITY.md 2>/dev/null
```

Expected: no matches except explicit legacy cleanup note in
`script/build_and_run.sh`.

## Test Plan

No new behavior tests are required, but all existing tests must compile after
the target rename. The key regression risk is broken SwiftPM target membership
or stale imports.

Run:

```bash
swift test
swift build
./script/build_and_run.sh --stage
```

## Done Criteria

- [ ] SwiftPM package and target names use `LidAwake`.
- [ ] Source and test directories use `LidAwake` names.
- [ ] Imports use `LidAwakeCore`.
- [ ] Staged app binary is `Contents/MacOS/LidAwake`.
- [ ] Staged helper binary is `Contents/Library/LaunchServices/LidAwakeHelper`.
- [ ] `swift test`, `swift build`, and `./script/build_and_run.sh --stage`
  exit 0.
- [ ] Only intentional legacy migration references to `AgentAwake` remain.
- [ ] `plans/README.md` status row for Plan 006 is updated.

## STOP Conditions

Stop and report if:

- Renaming breaks helper approval in a way that requires a new bundle ID.
- There are public package consumers that depend on the `AgentAwakeCore` module.
- The rename starts mixing behavior changes with naming changes.

## Maintenance Notes

After this plan lands, future docs, CI, and release artifacts should use
`LidAwake` names only. Keep legacy process cleanup for one or two pre-release
cycles if users have already tested old builds locally.
