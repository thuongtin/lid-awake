# Plan 013: Require Developer ID for public release packaging

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- script/package_release.sh script/stage_app.sh docs/releasing.md README.md CONTRIBUTING.md`

## Status

- Priority: P1
- Effort: S-M
- Risk: LOW
- Depends on: none
- Category: dx
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

Public macOS downloads need Developer ID signing and notarization. The current package script can create a release-shaped zip even when the staged app is signed with Apple Development or ad-hoc identity. That is useful for local archive testing, but unsafe as the default public release path.

## Current state

`package_release.sh` runs staging without enforcing Developer ID:

```bash
// script/package_release.sh:11
./scripts/check.sh
CONFIGURATION=release ./script/stage_app.sh
```

`stage_app.sh` selects either Developer ID or Apple Development:

```bash
// script/stage_app.sh:45
security find-identity -v -p codesigning 2>/dev/null \
  | awk -F '"' '/"Developer ID Application:|"Apple Development:/ { print $2; exit }'
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Default package gate | `./script/package_release.sh` | fails before packaging if no Developer ID identity exists |
| Docs check | `rg 'ALLOW_NON_DEVELOPER_ID_RELEASE|Developer ID|package_release' docs/releasing.md README.md CONTRIBUTING.md` | prints matches |
| Full tests | `swift test` | exit 0 |

## Scope

In scope:

- `script/package_release.sh`
- `docs/releasing.md`
- `README.md`
- `CONTRIBUTING.md`

Out of scope:

- Notarization automation.
- Storing Apple credentials.
- Changing app code signing identifiers.

## Steps

### Step 1: Gate the default release path

Make `package_release.sh` require a `Developer ID Application:` identity by default. If `SIGNING_IDENTITY` is unset, auto-detect only Developer ID. If none is present, fail with a clear message before running `scripts/check.sh`.

Verify: on a machine without Developer ID, `./script/package_release.sh` exits nonzero with a clear Developer ID message.

### Step 2: Keep an explicit local archive escape hatch

Add an opt-in environment flag such as `ALLOW_NON_DEVELOPER_ID_RELEASE=1` for local archive testing. This path may use Apple Development or ad-hoc signing, but it must print a warning.

Verify: `rg 'ALLOW_NON_DEVELOPER_ID_RELEASE' script/package_release.sh` prints the flag.

### Step 3: Update docs

Update release docs and README wording so public release and local archive testing are distinct.

Verify: `rg 'ALLOW_NON_DEVELOPER_ID_RELEASE|Developer ID|public release' docs/releasing.md README.md CONTRIBUTING.md` prints matches.

## Done criteria

- Default `package_release.sh` cannot silently package a non-Developer ID public release.
- Local archive testing remains possible through an explicit flag.
- Docs explain both paths.

## STOP conditions

- The change would require committing Apple credentials or certificate material.
- The script cannot detect signing identity without mutating keychain state.
