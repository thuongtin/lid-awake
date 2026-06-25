# Plan 008: Add release packaging and notarization guidance

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report.
>
> **Drift check, run first**: `git status --short && nl -ba script/build_and_run.sh | sed -n '1,180p' && find docs -maxdepth 2 -type f | sort`
> Because this repo has no commits, compare the current packaging behavior
> against the excerpts below before proceeding.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-harden-privileged-helper-xpc.md`, `plans/006-align-lid-awake-package-naming.md`, `plans/007-split-ci-safe-verification.md`
- **Category**: dx
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why This Matters

Open Source users can build from source, but many macOS users will expect a
downloadable app archive. The current staging script creates a local bundle and
ad-hoc signs it, but it does not provide version metadata, release archive
creation, checksums, or notarization guidance. A public power-management utility
needs a clear release process so users understand what is signed, what is local
only, and what trust guarantees exist.

## Current State

Current app Info.plist generation omits release version fields:

```bash
# script/build_and_run.sh:75
<key>CFBundleExecutable</key>
<string>$APP_NAME</string>
```

Current signing is ad-hoc:

```bash
# script/build_and_run.sh:113
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --identifier "$HELPER_LABEL" "$HELPER_BINARY" >/dev/null
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi
```

Reference release docs exist only in `work/lidrunner`:

```markdown
<!-- work/lidrunner/docs/releasing.md:3 -->
This repository can produce an unsigned, ad-hoc-signed zip locally.
```

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| CI-safe check | `./scripts/check.sh` | exit 0 |
| Package release | `./script/package_release.sh` | prints zip path under `dist/releases/` |
| Plist lint | `plutil -lint dist/LidAwake.app/Contents/Info.plist` | prints `OK` |
| Codesign local verify | `codesign --verify --deep --strict dist/LidAwake.app` | exit 0 for local staged app |
| Checksum | `shasum -a 256 dist/releases/*.zip` | prints checksum |

## Scope

In scope:

- `script/stage_app.sh` if created by Plan 007, otherwise refactor staging out
  of `script/build_and_run.sh`
- `script/build_and_run.sh`
- `script/package_release.sh`
- `docs/releasing.md`
- `CHANGELOG.md`
- `README.md`
- `CONTRIBUTING.md`

Out of scope:

- Storing Apple Developer credentials.
- Creating secrets in CI.
- Implementing auto-update.
- Changing helper behavior.

## Git Workflow

- Branch: `codex/008-release-packaging`
- Commit message example: `build: add release packaging`
- Do not push unless explicitly instructed.

## Steps

### Step 1: Split reusable staging from run behavior

If Plan 007 has not already created a pure staging path, create
`script/stage_app.sh` and have `script/build_and_run.sh` call it.

`stage_app.sh` should:

- build release or debug based on `CONFIGURATION`
- create `dist/LidAwake.app`
- copy app and helper binaries
- generate or copy the app icon
- write `Info.plist`
- write the helper LaunchDaemon plist
- sign locally with ad-hoc identity when no signing identity is provided
- print the app bundle path

Do not open the app from `stage_app.sh`.

**Verify**:

```bash
CONFIGURATION=release ./script/stage_app.sh
plutil -lint dist/LidAwake.app/Contents/Info.plist
```

Expected: script exits 0 and `plutil` prints `OK`.

### Step 2: Add release metadata

Add app metadata to `Info.plist` generation:

- `CFBundleShortVersionString`
- `CFBundleVersion`
- `LSApplicationCategoryType` with utility category
- `NSHumanReadableCopyright`

Put version/build values in one place, for example:

- `APP_VERSION`
- `APP_BUILD`

Keep the bundle identifier `com.thuongtin.LidAwake`.

**Verify**:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/LidAwake.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/LidAwake.app/Contents/Info.plist
```

Expected: both print non-empty values.

### Step 3: Add release archive script

Create `script/package_release.sh`:

- runs `./scripts/check.sh`
- stages release app with `CONFIGURATION=release`
- creates `dist/releases/LidAwake-<version>-macos.zip`
- writes `dist/releases/LidAwake-<version>-macos.zip.sha256`
- prints archive path

Use `ditto -c -k --keepParent` for the app bundle archive.

**Verify**:

```bash
./script/package_release.sh
test -f dist/releases/*.sha256
```

Expected: zip and checksum exist.

### Step 4: Document signing and notarization

Create `docs/releasing.md` with:

- local archive command
- public release checklist
- signing identity requirements
- notarization steps at a high level
- no secret values
- warning that ad-hoc local archives are not notarized public releases
- GitHub release checklist with changelog and checksum

Use placeholder environment variable names only, such as:

```text
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
DEVELOPER_ID_APPLICATION
```

Do not include real credentials.

**Verify**:

```bash
rg 'notar|Developer ID|checksum|APPLE_ID|ad-hoc|LidAwake' docs/releasing.md
```

Expected: all terms appear.

### Step 5: Update public docs

Update `README.md`, `CONTRIBUTING.md`, and `CHANGELOG.md` with release command
references and current version placeholder.

**Verify**:

```bash
rg 'package_release|releasing|CHANGELOG|dist/releases' README.md CONTRIBUTING.md CHANGELOG.md docs/releasing.md
```

Expected: references are present.

## Test Plan

No app behavior tests are required. Packaging verification is command based:

```bash
./scripts/check.sh
./script/package_release.sh
codesign --verify --deep --strict dist/LidAwake.app
shasum -a 256 dist/releases/*.zip
```

If `codesign --verify` fails because a real Developer ID identity is not
available, keep ad-hoc signing for local packages and document the limitation.

## Done Criteria

- [ ] Pure staging script exists and does not launch the app.
- [ ] `Info.plist` includes version, build, category, and copyright metadata.
- [ ] `script/package_release.sh` creates a zip and checksum.
- [ ] `docs/releasing.md` documents signing and notarization without secrets.
- [ ] README and contributing docs point to release workflow.
- [ ] `./scripts/check.sh` exits 0.
- [ ] `./script/package_release.sh` exits 0.
- [ ] `plans/README.md` status row for Plan 008 is updated.

## STOP Conditions

Stop and report if:

- Packaging requires Apple Developer secrets not available locally.
- Helper signing identity changes break Plan 002 authorization.
- Release archive cannot be built without launching the app.
- The maintainer has not approved versioning convention.

## Maintenance Notes

Any future auto-update system must reuse the same release metadata and should
not weaken helper signing assumptions. Reviewers should inspect the generated
bundle layout before publishing every release.
