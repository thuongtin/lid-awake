# Plan 007: Split CI-safe checks from local runtime verification

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && nl -ba scripts/verify.sh && nl -ba script/build_and_run.sh | sed -n '1,180p'`
> Because this repo has no commits, compare the script behavior against the
> excerpts below before proceeding.

## Status

- **Priority**: P2
- **Effort**: S-M
- **Risk**: LOW
- **Depends on**: `plans/006-align-lid-awake-package-naming.md`
- **Category**: dx
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

The current verification command launches the app, deletes app defaults, and
checks live `pmset` assertions. That is valuable local QA, but it is not safe or
reliable for CI and new contributors. Open Source projects need one command
that is safe in automation and a separate explicit command for runtime
power-management QA.

## Current State

Current verify script:

```bash
# scripts/verify.sh:4
swift test
swift build
./script/build_and_run.sh --verify
```

Current runtime verify path launches app and mutates local defaults:

```bash
# script/build_and_run.sh:139
--verify|verify)
  defaults delete "$BUNDLE_ID" LidAwake.settings >/dev/null 2>&1 || true
  open_app
```

Current action config runs the app directly:

```toml
# .codex/environments/environment.toml:8
[[actions]]
name = "Run"
command = "./script/build_and_run.sh"
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `swift test` | exit 0 |
| Build | `swift build` | exit 0 |
| Stage | `./script/build_and_run.sh --stage` | exit 0 |
| CI check | `./scripts/check.sh` | exit 0 and does not launch app |
| Local runtime verify | `./scripts/verify.sh` | exit 0 on a developer Mac where app launch and assertions are allowed |

## Scope

In scope:

- `scripts/check.sh` new CI-safe command
- `scripts/verify.sh`
- `script/build_and_run.sh`
- `.github/workflows/ci.yml`
- `README.md` and `CONTRIBUTING.md` if created by Plan 004
- `.codex/environments/environment.toml` only if needed to keep Run action clear

Out of scope:

- Release archives and notarization. That belongs to Plan 008.
- Renaming targets. That belongs to Plan 006.
- Changing app behavior.

## Git Workflow

- Branch: `codex/007-ci-safe-verification`
- Commit message example: `ci: add safe swift checks`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Add `scripts/check.sh`

Create a CI-safe script:

```bash
#!/usr/bin/env bash
set -euo pipefail

swift test
swift build
./script/build_and_run.sh --stage
plutil -lint dist/LidAwake.app/Contents/Info.plist
```

If Plan 006 renamed products, ensure the staged bundle path is still
`dist/LidAwake.app`.

Make the script executable.

**Verify**:

```bash
chmod +x scripts/check.sh
./scripts/check.sh
```

Expected: exit 0 and the app is not launched.

### Step 2: Keep runtime verification explicit

Keep `scripts/verify.sh` for local runtime verification, but make its purpose
clear in comments and docs:

- it may launch the app
- it may delete `LidAwake.settings` defaults for verification
- it checks live `pmset` assertions
- it is not used by CI

If useful, rename it to `scripts/runtime_verify.sh` and leave a compatibility
wrapper at `scripts/verify.sh`.

**Verify**: `rg 'runtime|pmset|launch|not used by CI' scripts/verify.sh README.md CONTRIBUTING.md`
prints expected warnings.

### Step 3: Add GitHub Actions CI

Create `.github/workflows/ci.yml`:

- trigger on pull requests and pushes to `main`
- run on `macos-latest`
- checkout repository
- print Swift version
- run `./scripts/check.sh`

Do not run `./scripts/verify.sh` in CI.

**Verify**:

```bash
test -f .github/workflows/ci.yml
rg 'macos-latest|scripts/check.sh|pull_request|push' .github/workflows/ci.yml
```

Expected: all terms are present.

### Step 4: Update docs

Update `README.md` and `CONTRIBUTING.md`:

- `./scripts/check.sh` is the default contributor check
- `./scripts/verify.sh` is optional local runtime QA
- explain that runtime QA may prompt app permission or touch power assertions

**Verify**:

```bash
rg 'scripts/check.sh|scripts/verify.sh|runtime|CI' README.md CONTRIBUTING.md
```

Expected: both scripts are documented.

## Test Plan

No new unit tests are required. Verification is script behavior and CI config.

Run:

```bash
./scripts/check.sh
swift test
swift build
```

Only run `./scripts/verify.sh` on a local machine where launching the app and
checking `pmset` is acceptable.

## Done Criteria

- [ ] `scripts/check.sh` exists, is executable, and exits 0.
- [ ] `scripts/check.sh` does not launch the app.
- [ ] `scripts/verify.sh` is clearly documented as local runtime verification.
- [ ] `.github/workflows/ci.yml` runs `./scripts/check.sh` on macOS.
- [ ] `README.md` and `CONTRIBUTING.md` distinguish CI checks from runtime QA.
- [ ] `plans/README.md` status row for Plan 007 is updated.

## STOP Conditions

Stop and report if:

- Staging the app requires launching it.
- GitHub Actions cannot build the SwiftPM macOS target without code signing
  changes that belong to Plan 008.
- The repo does not have Open Source docs from Plan 004 yet.

## Maintenance Notes

Keep CI deterministic. Hardware-specific, permission-specific, and power-state
checks should stay in local runtime QA, not GitHub Actions.
