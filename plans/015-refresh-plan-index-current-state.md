# Plan 015: Refresh plan index current state

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- plans/README.md`

## Status

- Priority: P2
- Effort: S
- Risk: LOW
- Depends on: plans/011-bind-helper-authorization-to-team-identity.md, plans/012-restore-closed-lid-before-helper-removal.md, plans/013-require-developer-id-for-public-release-packaging.md, plans/014-allow-display-sleep-after-lock-failure.md
- Category: docs
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

`plans/README.md` is the handoff index future executor agents will read first. It currently describes a pre-commit state and says the test suite had 68 tests, while the repo now has commits and the current execution batch verifies 92 tests. Stale execution metadata causes wrong drift checks and wasted review.

## Current state

```markdown
// plans/README.md:3
Repo hiện có `.git` nhưng chưa có commit đầu tiên
```

```markdown
// plans/README.md:45
`swift test` passed with 68 tests.
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Current SHA | `git rev-parse --short HEAD` | prints current commit |
| Test list | `swift test list 2>/dev/null \|\| true` | includes current tests |
| Search stale text | `rg 'no commit available|68 tests' plans/README.md` | no matches |
| Legacy naming note | `rg 'intentional legacy AgentAwake' plans/README.md` | prints the intentional historical-context note |

## Scope

In scope:

- `plans/README.md`

Out of scope:

- Rewriting historical plan files 001-010.
- Changing source code.

## Steps

### Step 1: Update current repo metadata

Replace stale no-commit and 68-test text with the current commit and current test count.

Verify: `rg '3465524|92 tests|SwiftPM macOS menu bar app' plans/README.md` prints matches.

### Step 2: Add plans 011-016 to the index

Append plan rows in execution order and mark status based on actual execution.

Verify: `rg '011|012|013|014|015|016' plans/README.md` prints all rows.

## Done criteria

- `plans/README.md` has current repo state.
- New plan rows exist.
- Stale current-state text is gone.

## STOP conditions

- A historical plan needs a source rewrite instead of index reconciliation.
