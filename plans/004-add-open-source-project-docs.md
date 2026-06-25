# Plan 004: Add the root Open Source project docs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && find . -maxdepth 2 -type f | sort`
> Because this repo has no commits, compare the listed files against the
> "Current state" section before proceeding.

## Status

- **Priority**: P1
- **Effort**: S-M
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

The app is moving toward Open Source, but root-level project docs are missing.
Without a README, license, contribution guide, security policy, and changelog,
users cannot evaluate safety, contributors cannot build consistently, and
security reports have no private path. This is high-leverage because the app
touches local power settings and an admin-approved helper.

## Current State

Root scan during audit showed no root `README.md`, `LICENSE`, `CONTRIBUTING.md`,
`SECURITY.md`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, or `.editorconfig`.
The only root README-like file is the planning index:

```text
plans/README.md
```

Existing product docs:

```markdown
<!-- docs/power-model.md:1 -->
# Lid Awake Power Model
```

Reference material exists under the nested `work/lidrunner` repo:

```markdown
<!-- work/lidrunner/README.md:42 -->
## Build And Run
```

```markdown
<!-- work/lidrunner/SECURITY.md:1 -->
# Security Policy
```

Use `work/lidrunner` as inspiration only. Do not copy it blindly because this
app has a different bundle ID, helper model, product name, and macOS target.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Find docs | `find . -maxdepth 2 -type f \\( -iname 'README*' -o -iname 'LICENSE*' -o -iname 'CONTRIBUTING*' -o -iname 'SECURITY*' -o -iname 'CHANGELOG*' -o -iname '.editorconfig' \\) -print | sort` | prints the new root docs |
| Build | `swift build` | exit 0 |
| Tests | `swift test` | exit 0 |
| Link sanity | `rg 'Lid Awake|com.thuongtin.LidAwake|swift test|build_and_run|SECURITY' README.md CONTRIBUTING.md SECURITY.md CHANGELOG.md docs/power-model.md` | finds expected project terms |

## Scope

In scope:

- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `CHANGELOG.md`
- `CODE_OF_CONDUCT.md` if the maintainer wants a public conduct policy
- `.editorconfig`
- `.github/pull_request_template.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `docs/power-model.md` only to link back to root docs if useful

Out of scope:

- Any source code.
- Release automation. That belongs to Plan 008.
- Removing `work/lidrunner`. That belongs to Plan 005.
- Choosing a license without maintainer approval.

## Git Workflow

- Branch: `codex/004-open-source-docs`
- Commit message example: `docs: add open source project docs`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Confirm license choice

Ask the maintainer to confirm the license before creating `LICENSE`. If no
answer is available, use a placeholder section in `README.md` saying the license
is pending and stop before adding a license file.

Recommended default if approved: MIT, matching the `work/lidrunner` reference.

**Verify**: maintainer approval exists in the task thread, or the plan is marked
`BLOCKED` with "license choice pending".

### Step 2: Write `README.md`

Create a root README that covers:

- what `Lid Awake` is
- macOS requirements
- safety note for closed-lid behavior and heat
- helper permission model
- build and run commands
- local verification commands
- project layout
- link to `docs/power-model.md`
- current limitations

Use these verified commands:

```bash
swift test
swift build
./script/build_and_run.sh
./script/build_and_run.sh --stage
```

Mention that `scripts/verify.sh` is local runtime verification because it opens
the app and checks `pmset`.

**Verify**: `rg 'Lid Awake|Power Model|swift test|--stage|closed-lid|helper' README.md`
finds all terms.

### Step 3: Add contribution and security docs

Create `CONTRIBUTING.md` with:

- prerequisites
- build/test commands
- how to run app locally
- how to report UI screenshots for menu bar/settings changes
- rule that power-management changes must be explicit and reversible
- reminder to add tests for parsing, policy, helper, and state handling

Create `SECURITY.md` with:

- private reporting path
- scope of security-sensitive areas
- warning not to publish exploit details in public issues
- note that the helper and `pmset` path are sensitive

**Verify**: `rg 'helper|pmset|security|swift test|pull request|power' CONTRIBUTING.md SECURITY.md`
prints expected lines.

### Step 4: Add changelog, editor config, and templates

Create:

- `CHANGELOG.md` with an `Unreleased` section
- `.editorconfig` matching Swift style and shell scripts
- `.github/pull_request_template.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`

Issue template should ask for macOS version, hardware model, power source,
helper approval status, logs if relevant, and clear reproduction steps.

**Verify**:

```bash
test -f CHANGELOG.md
test -f .editorconfig
test -f .github/pull_request_template.md
test -f .github/ISSUE_TEMPLATE/bug_report.yml
```

All commands exit 0.

### Step 5: Run baseline verification

Run:

```bash
swift test
swift build
```

Expected: both exit 0. Do not run `scripts/verify.sh` as part of docs-only work
unless the maintainer explicitly asks for runtime QA.

## Test Plan

This is a docs plan, so no new unit tests are required. Verification is file
existence, command accuracy, and baseline `swift test` plus `swift build`.

## Done Criteria

- [ ] Root `README.md` exists and explains product, safety, setup, and commands.
- [ ] License file exists only after maintainer approval.
- [ ] `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md` exist.
- [ ] `.editorconfig` and GitHub issue/PR templates exist.
- [ ] `swift test` exits 0.
- [ ] `swift build` exits 0.
- [ ] `plans/README.md` status row for Plan 004 is updated.

## STOP Conditions

Stop and report if:

- License choice is not approved.
- Documentation would need to claim signing, notarization, or auto-update support
  that does not exist yet.
- You find copied code from `work/lidrunner` that requires legal attribution and
  the maintainer has not approved the wording.

## Maintenance Notes

Keep README commands aligned with Plan 007 once CI-safe checks are added. Any
future helper or release workflow should update `SECURITY.md` and
`docs/power-model.md` in the same change.
