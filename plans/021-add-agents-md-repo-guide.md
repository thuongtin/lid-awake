# Plan 021: Add AGENTS.md so agent executors know the commands, conventions, and danger zones

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first): `git diff --stat 5d89d38..HEAD -- README.md CONTRIBUTING.md docs/`
> This plan was written at commit `5d89d38`. If the referenced docs changed
> since, keep AGENTS.md consistent with their current content.

## Status

- Priority: P2
- Effort: S
- Risk: LOW
- Depends on: none (write it after 017-020 land if possible, so the guide
  reflects the final CI shape)
- Category: dx
- Planned at: commit `5d89d38`, 2026-07-02
- Execution status: TODO

## Why this matters

This repo is routinely worked on by AI agents (the `plans/` directory is
written for agent executors), but there is no `AGENTS.md` or `CLAUDE.md`. The
critical repo knowledge - which verification command is CI-safe versus which
one launches the app and mutates live `pmset` state, where the privileged
helper trust boundary is, which files must never be committed - lives spread
across README, four docs files, and shell script comments. An agent that
misses it can run `scripts/verify.sh` in the wrong environment (launches the
app, deletes settings defaults, touches live power management) or leak a
private key path into a commit. One small file removes that class of mistake.

## Current state

- No `AGENTS.md`, no `CLAUDE.md` in the repo root (`ls AGENTS.md CLAUDE.md`
  fails for both).
- The facts the guide must consolidate (verify each against the live file
  while writing; do not invent):
  - `./scripts/check.sh` = CI-safe gate: `swift test`, `swift build`, stage
    via `./script/build_and_run.sh --stage`, `plutil -lint` (README "Build And
    Run" section).
  - `./scripts/verify.sh` = local-only runtime verification; it may launch the
    app, delete `LidAwake.settings` defaults, and inspect live `pmset`
    assertions (README line ~102). NEVER run in CI or a sandbox.
  - Privileged helper: `Sources/LidAwakeHelper/` runs `pmset -a disablesleep`
    as root; trust boundary documented in `docs/power-model.md` ("Helper
    Trust Boundary"). Changes to `HelperClientAuthorizer`,
    `LidAwakeHelperMain`, or the XPC protocol are security-sensitive and need
    the manual QA checklist in `docs/power-model.md`.
  - Secrets: the Sparkle EdDSA private key must never be committed; only
    `scripts/sparkle_public_key.txt` (public key) is in the tree (README
    "Release Packaging" section). Never print key material.
  - Release packaging is deliberately manual: `docs/releasing.md`.
  - Layout: `Sources/LidAwake` (app), `Sources/LidAwakeCore` (policy/state,
    fully unit-tested), `Sources/LidAwakeHelper` (root helper),
    `script/` (staging/packaging), `scripts/` (checks + assets),
    `plans/` (agent plans + status index).
  - Conventions: protocol seams + fakes for every system service (see
    `Tests/LidAwakeTests/AppModelLifecycleTests.swift` harness), plain
    imperative commit subjects, `set -euo pipefail` in all scripts,
    English code/comments.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Confirm absence first | `ls AGENTS.md` | "No such file" error |
| Full local gate | `./scripts/check.sh` | exit 0 |

## Scope

In scope (the only files you should modify):

- `AGENTS.md` (create, repo root)
- `README.md` (one line in the Documentation list)

Out of scope:

- Any code or script change.
- `CONTRIBUTING.md` rewrite (link to it instead).
- Creating a symlinked or duplicated `CLAUDE.md` (a single `AGENTS.md` is the
  convention this repo adopts; tools that read CLAUDE.md also read AGENTS.md).

## Git workflow

- Branch: `advisor/021-agents-md`. Plain imperative commit subject, e.g.
  "Add AGENTS.md contributor guide for agent executors".
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Write AGENTS.md

Create `AGENTS.md` (target 80-150 lines, English, plain Markdown, no em
dashes) with exactly these sections:

1. `# Lid Awake - Agent Guide` + two-sentence summary of what the app is.
2. `## Verification commands` - a table: `./scripts/check.sh` (CI-safe, run
   before finishing any change), `swift test`, `swift build`,
   `./script/build_and_run.sh --stage`, and a WARNING block for
   `./scripts/verify.sh` (launches app, deletes `LidAwake.settings`
   defaults, reads live pmset; developer Mac only, never CI/sandbox).
3. `## Repo layout` - the directory list from "Current state".
4. `## Danger zones` - privileged helper (root pmset, trust boundary in
   `docs/power-model.md`, manual QA checklist required for helper changes),
   power side effects (`pmset -a disablesleep` is a GLOBAL machine setting;
   code must always restore it), Sparkle keys (public key file only; never
   print or commit private key material), release packaging (manual by
   design; `package_release.sh` is a Developer ID gate).
5. `## Conventions` - protocol + fake seams for system services (pointer to
   `AppModelLifecycleTests.swift` harness), deterministic Core tests, plain
   imperative commit subjects, `set -euo pipefail` in scripts, English
   code/comments/log messages.
6. `## Plans workflow` - plans live in `plans/`, numbered; executors read the
   whole plan, honor STOP conditions, and update the status row in
   `plans/README.md`.

Every claim must be checked against the live file it came from (the pointers
are in "Current state"). Do not document aspirations; document what exists.

Verify: `test -f AGENTS.md && grep -c "^## " AGENTS.md` -> 5 (five `##`
sections).

### Step 2: Link it from README

In `README.md`, in the `## Documentation` list, add:

```markdown
- [Agent Guide](AGENTS.md): verification commands, danger zones, and conventions for AI coding agents.
```

Verify: `grep -n "AGENTS.md" README.md` -> one match in the Documentation
section.

### Step 3: Full gate

Verify: `./scripts/check.sh` -> exit 0 (nothing should have changed
behaviorally; this confirms the tree still builds).

## Test plan

No code tests. Verification is structural: the greps in steps 1-2 plus the
full gate in step 3.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `AGENTS.md` exists with the six required sections (five `##` headings + title)
- [ ] `grep -n "verify.sh" AGENTS.md` -> present, with the never-in-CI warning
- [ ] `grep -n "AGENTS.md" README.md` -> exactly one match
- [ ] `./scripts/check.sh` exits 0
- [ ] No secret values or key material anywhere in AGENTS.md
- [ ] `git status --porcelain` shows only `AGENTS.md` and `README.md` changed
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- An `AGENTS.md` or `CLAUDE.md` already exists (someone landed one since this
  plan was written) - reconcile instead of overwriting, and report.
- You cannot verify one of the "Current state" claims against the live repo
  (for example `verify.sh` no longer deletes defaults) - write what IS true
  and flag the discrepancy in your report.

## Maintenance notes

- AGENTS.md must be updated when: the verification gate changes (plan 017
  adds shellcheck), the helper trust model changes (plan 018), or release
  packaging is automated.
- Keep it under ~150 lines; a guide nobody loads into context is worse than
  none.
