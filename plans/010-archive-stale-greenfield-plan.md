# Plan 010: Archive stale greenfield planning material

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && nl -ba plans/001-build-native-macos-agent-awake-app.md | sed -n '1,80p' && nl -ba plans/README.md`
> Because this repo has no commits, compare the current plan index against the
> excerpts below before proceeding.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/004-add-open-source-project-docs.md`
- **Category**: docs
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

The old Plan 001 was correct when the workspace was greenfield, but it is now
stale. It says there is no source, no git repo, no build commands, and no
privileged helper, while the repo now contains a SwiftPM app and helper. Keeping
that plan as if it were current creates confusion for future executor agents and
Open Source contributors.

## Current State

Old plan still says it is for an empty workspace:

```markdown
<!-- plans/001-build-native-macos-agent-awake-app.md:7 -->
This plan was written for an empty greenfield workspace.
```

Old plan current state is stale:

```markdown
<!-- plans/001-build-native-macos-agent-awake-app.md:24 -->
The current workspace contains only `plans/`, `work/`, and `outputs/`.
```

Current plan index marks it historical:

```markdown
<!-- plans/README.md -->
001 | Build a native macOS menu bar app that keeps coding agents awake safely | P1 | L | - | DONE, historical greenfield plan
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Plan audit | `rg 'greenfield|no existing application source|not a git repository|must not install a privileged helper' plans` | stale claims appear only in archived historical context |
| Index check | `rg 'historical|archive|002|010' plans/README.md plans/001-build-native-macos-agent-awake-app.md` | expected historical markers are present |

## Scope

In scope:

- `plans/001-build-native-macos-agent-awake-app.md`
- `plans/README.md`
- Optional `plans/archive/` if moving historical plans is preferred

Out of scope:

- Source code.
- Current implementation docs outside `plans/`.
- Rewriting new plans 002 through 009.

## Git Workflow

- Branch: `codex/010-archive-stale-plan`
- Commit message example: `docs: archive stale greenfield plan`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Choose archive strategy

Recommended strategy: keep the file path but add a strong top warning so any
executor opening Plan 001 sees it is historical and should not execute it.

Alternative: move it to `plans/archive/001-build-native-macos-agent-awake-app.md`
and leave a short stub at the original path that points to the archive.

Do not delete the old plan unless the maintainer asks. It is useful context for
how the app started.

**Verify**: chosen strategy is reflected in `plans/README.md`.

### Step 2: Mark Plan 001 as historical

At the top of `plans/001-build-native-macos-agent-awake-app.md`, add a warning:

```markdown
> Historical note: this plan was executed against an empty workspace and is no
> longer a current implementation plan. Do not execute it against the existing
> SwiftPM app. Use plans 002 and later for Open Source readiness work.
```

If moving to archive, create a stub at the old path with the same warning and a
relative link to the archived file.

**Verify**:

```bash
sed -n '1,20p' plans/001-build-native-macos-agent-awake-app.md | rg 'Historical note|Do not execute'
```

Expected: warning appears.

### Step 3: Keep the index current

Ensure `plans/README.md`:

- marks Plan 001 as historical
- lists plans 002 through 010
- states that all new plans were generated for Open Source readiness
- states that the repo has no commits yet if that is still true

**Verify**:

```bash
rg 'Open Source readiness|historical|002|010|no commits' plans/README.md
```

Expected: all terms appear.

## Test Plan

No app tests are required. This is planning hygiene. Run the plan audit commands
above and confirm stale claims are clearly marked historical.

## Done Criteria

- [ ] Plan 001 has a top warning or is moved under `plans/archive/` with a stub.
- [ ] `plans/README.md` points executors at plans 002 and later for current work.
- [ ] Stale greenfield claims are not presented as current instructions.
- [ ] `plans/README.md` status row for Plan 010 is updated.

## STOP Conditions

Stop and report if:

- The maintainer wants to keep Plan 001 exactly as-is.
- Another active workflow is still using Plan 001 as current implementation
  guidance.
- Updating the plan index would conflict with executor status changes made by
  another agent.

## Maintenance Notes

When future improve runs generate new plans, keep historical plans clearly
marked. Executors with limited context should never have to infer whether a
plan is current.
