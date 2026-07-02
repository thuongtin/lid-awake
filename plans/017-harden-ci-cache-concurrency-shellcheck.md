# Plan 017: Harden CI with dependency caching, concurrency cancellation, and shellcheck

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first): `git diff --stat 5d89d38..HEAD -- .github/workflows/ci.yml scripts/check.sh Package.swift Package.resolved`
> This plan was written at commit `5d89d38` while the Sparkle integration was
> still uncommitted in the working tree. The excerpts below reflect that
> working tree. If `.github/workflows/ci.yml` changed beyond what this plan
> describes, compare the "Current state" excerpts against the live file before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- Priority: P1
- Effort: S
- Risk: LOW
- Depends on: none
- Category: dx
- Planned at: commit `5d89d38`, 2026-07-02
- Execution status: TODO

## Why this matters

The repo just gained its first third-party dependency (Sparkle, in
`Package.swift`). CI runs `swift test` and `swift build` on `macos-latest`
with zero caching, so every push and PR now re-downloads and re-compiles
Sparkle from scratch. CI also has no concurrency cancellation (stacked pushes
run to completion) and no shell linting, even though five bash scripts in
`script/` perform release signing and Sparkle plist injection where a quoting
bug has real consequences. Each fix here is a few lines of YAML and pays back
on every CI run.

## Current state

- `.github/workflows/ci.yml` - the entire CI configuration (21 lines):

```yaml
name: CI

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  swift:
    runs-on: macos-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Print Swift version
        run: swift --version

      - name: Run CI-safe checks
        run: ./scripts/check.sh
```

- `scripts/check.sh` - the verification gate CI calls:

```bash
#!/usr/bin/env bash
set -euo pipefail

swift test
swift build
./script/build_and_run.sh --stage
plutil -lint dist/LidAwake.app/Contents/Info.plist
```

- Shell scripts in the repo: `script/stage_app.sh`, `script/build_and_run.sh`,
  `script/package_release.sh`, `script/package_dmg.sh`,
  `script/package_appcast.sh`, `scripts/check.sh`, `scripts/verify.sh`.
  All use `set -euo pipefail`. None are linted anywhere.
- `Package.resolved` exists in the repo root and pins Sparkle. It is part of
  the Sparkle integration change set. The cache key below depends on it being
  tracked by git.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Confirm lockfile is tracked | `git ls-files --error-unmatch Package.resolved` | prints `Package.resolved`, exit 0 |
| YAML sanity check | `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"` | prints `ok` |
| Install shellcheck locally | `brew install shellcheck` | exit 0 |
| Lint scripts locally | `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` | exit 0, no output |
| Full local gate | `./scripts/check.sh` | exit 0 |

If `python3` has no `yaml` module, use `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'ok'"` instead.

## Scope

In scope (the only files you should modify):

- `.github/workflows/ci.yml`
- `script/*.sh` and `scripts/*.sh` - ONLY quoting/robustness edits required to
  make shellcheck pass, nothing behavioral.

Out of scope (do NOT touch, even though they look related):

- `scripts/check.sh` build-step contents - do not "optimize" the duplicate
  `swift build`; SwiftPM incremental builds make it nearly free, and changing
  the gate is not this plan.
- Any release automation (notarization, appcast publishing) - deliberate
  manual process, documented in `docs/releasing.md`.
- `Package.swift` / `Package.resolved` contents.

## Git workflow

- Branch: `advisor/017-harden-ci` (repo history shows plain imperative commit
  subjects, e.g. "Add DMG release packaging" - match that style).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Confirm Package.resolved is tracked

Run: `git ls-files --error-unmatch Package.resolved`

If it exits non-zero, the Sparkle integration has not been committed yet.
STOP and report: the cache key in step 3 hashes `Package.resolved`, and the
maintainer needs to land the Sparkle change set first.

### Step 2: Add concurrency cancellation

In `.github/workflows/ci.yml`, after the `on:` block, add:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Verify: the YAML sanity command prints `ok`.

### Step 3: Add SwiftPM build caching

In the `swift` job, between the checkout step and "Print Swift version", add:

```yaml
      - name: Cache SwiftPM build
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-swiftpm-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-swiftpm-
```

Verify: the YAML sanity command prints `ok`.

### Step 4: Add a shellcheck job

Add a second job to `.github/workflows/ci.yml` (ubuntu runner - cheaper, and
shellcheck ships preinstalled on ubuntu images):

```yaml
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Lint shell scripts
        run: shellcheck script/*.sh scripts/check.sh scripts/verify.sh
```

Verify: the YAML sanity command prints `ok`.

### Step 5: Make the scripts shellcheck-clean locally

Install shellcheck (`brew install shellcheck`) and run:

`shellcheck script/*.sh scripts/check.sh scripts/verify.sh`

Fix only what it reports, and only with non-behavioral edits (quoting
variables, `read -r`, replacing legacy backticks, adding `|| exit` where
shellcheck demands it). If a reported issue cannot be fixed without changing
behavior (for example a deliberately unquoted word-split), suppress that
single line with a `# shellcheck disable=SCnnnn` comment and a one-line reason
instead of restructuring the script.

Verify: `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` -> exit 0.

### Step 6: Run the full local gate

Verify: `./scripts/check.sh` -> exit 0 (tests pass, build succeeds, app
stages, plist lints). This proves the shellcheck edits did not change script
behavior.

## Test plan

No Swift tests change. The verification is:

- YAML parses (step 2-4 checks).
- `shellcheck` exits 0 across all seven scripts.
- `./scripts/check.sh` exits 0 end to end.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `git ls-files --error-unmatch Package.resolved` exits 0
- [ ] `.github/workflows/ci.yml` contains `concurrency:`, `actions/cache@v4`, and a `shellcheck` job (`grep -c "concurrency:\|actions/cache@v4\|shellcheck" .github/workflows/ci.yml` >= 3 lines matched)
- [ ] `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` exits 0
- [ ] `./scripts/check.sh` exits 0
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `Package.resolved` is not tracked by git (step 1).
- Shellcheck reports more than ~15 distinct findings, or any finding whose fix
  would change script behavior (control flow, command arguments, defaults).
  List the findings in your report instead of fixing them.
- `./scripts/check.sh` fails after your edits and one reasonable fix attempt.
- `.github/workflows/ci.yml` no longer matches the "Current state" excerpt.

## Maintenance notes

- The cache key hashes `Package.resolved`; when dependencies change, the first
  CI run repopulates the cache. If CI ever pins a Swift toolchain version, add
  it to the key.
- `macos-latest` was deliberately left as-is; if a GitHub runner image bump
  breaks CI, pin to an explicit image (for example `macos-15`) in a follow-up.
- Future scripts must be added to the shellcheck job's file list; consider a
  glob via `find` if the script count grows.
