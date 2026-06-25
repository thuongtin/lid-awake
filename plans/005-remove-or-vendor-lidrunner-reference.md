# Plan 005: Remove or vendor the LidRunner reference cleanly

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && find work -maxdepth 3 -type d -name .git -print`
> Because this repo has no commits, compare the "Current state" facts against
> the live tree before proceeding.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/004-add-open-source-project-docs.md`
- **Category**: dx
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

`work/lidrunner` is a full reference repository nested inside this repo,
including its own `.git` directory, license, docs, and scripts. That is useful
for local study, but it is dangerous for a public repo because it can be
committed accidentally, confuse project ownership, and mix two products in one
source tree. Before Open Source release, the reference must either be removed
or vendored with explicit attribution and no nested git metadata.

## Current State

Relevant facts from audit:

```text
work/lidrunner/.git
```

Reference files include:

```text
work/lidrunner/README.md
work/lidrunner/LICENSE
work/lidrunner/CONTRIBUTING.md
work/lidrunner/SECURITY.md
work/lidrunner/script/stage_app.sh
```

Reference license excerpt:

```text
// work/lidrunner/LICENSE:1
MIT License
```

This app's real source lives at:

```text
Sources/AgentAwake/
Sources/AgentAwakeCore/
Sources/AgentAwakeHelper/
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Find nested git dirs | `find . -path '*/.git' -type d -maxdepth 4 | sort` | only `./.git` remains |
| Check references | `rg 'work/lidrunner|LidRunner' . --glob '!work/**' --glob '!.git/**'` | no unexpected references, except intentional attribution if added |
| Build | `swift build` | exit 0 |
| Tests | `swift test` | exit 0 |

## Scope

In scope:

- `work/lidrunner/**` removal, or conversion to a documented vendor/reference
  path without `.git`
- `.gitignore`
- `README.md`
- `NOTICE.md` if attribution is needed
- `docs/power-model.md` only if it mentions the reference

Out of scope:

- Copying LidRunner source into the app.
- Rewriting app architecture to match LidRunner.
- Changing license terms without maintainer approval.
- Removing the root `.git` directory.

## Git Workflow

- Branch: `codex/005-clean-lidrunner-reference`
- Commit message example: `chore: remove nested lidrunner reference`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Decide remove vs vendor

Recommended path: remove `work/lidrunner/` from this repo before public release.
If the maintainer wants to preserve the reference, convert it to one of:

- a Git submodule with clear README instructions
- a separate external link in `README.md`
- a `vendor/` snapshot with license attribution and no nested `.git`

Do not keep `work/lidrunner/.git` in the public tree.

**Verify**: decision is recorded in the PR description or in `README.md`.

### Step 2: Remove the nested reference from the tracked tree

If choosing removal, delete `work/lidrunner/`. Keep no build, docs, or source
dependency on it.

Update `.gitignore` to ignore local scratch/reference folders such as:

```gitignore
work/
outputs/
.codex/
```

Only add `.codex/` if the maintainer confirms it should remain local to Codex.

**Verify**:

```bash
find . -path '*/.git' -type d -maxdepth 4 | sort
```

Expected: only `./.git`.

### Step 3: Preserve attribution if needed

If any code or text from LidRunner was copied into this app, add a short
attribution in `NOTICE.md` or `README.md` and keep license obligations. Do not
copy full unrelated docs into this project.

If the team only used LidRunner as a reference, mention it in development notes
only if the maintainer wants that public.

**Verify**: `rg 'LidRunner|ph56jk|MIT' README.md NOTICE.md 2>/dev/null || true`
prints only intentional attribution.

### Step 4: Run baseline verification

Run:

```bash
swift test
swift build
```

Expected: both exit 0.

## Test Plan

No new app tests are required. This is repo hygiene. The verification is that
the project builds and tests without `work/lidrunner`, and only the root `.git`
directory remains.

## Done Criteria

- [ ] `work/lidrunner/.git` is gone from the tree.
- [ ] `find . -path '*/.git' -type d -maxdepth 4 | sort` prints only `./.git`.
- [ ] `.gitignore` prevents local reference folders from being committed again.
- [ ] Any required attribution is present and intentional.
- [ ] `swift test` exits 0.
- [ ] `swift build` exits 0.
- [ ] `plans/README.md` status row for Plan 005 is updated.

## STOP Conditions

Stop and report if:

- The app source imports or executes files from `work/lidrunner`.
- The maintainer wants to vendor LidRunner but has not approved attribution.
- Removing `work/lidrunner` causes build or tests to fail.

## Maintenance Notes

Keep third-party reference repos outside the app repository unless they are
intentional dependencies. If a reference must be retained, prefer a submodule or
external docs link over a nested source copy.
