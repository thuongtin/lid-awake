# Plan 025: Gate appcast packaging the same way as the DMG

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first):
> `git diff --stat a81523c..HEAD -- script/package_appcast.sh script/package_dmg.sh script/stage_app.sh AGENTS.md README.md docs/releasing.md`
> `README.md` and `docs/releasing.md` had unrelated uncommitted edits when
> this plan was written, so a diff in those two is expected; the lines this
> plan touches in them were identical in the commit and the working tree. If
> one of the three scripts changed, compare the "Current state" excerpts
> against the live code before proceeding; on a mismatch, STOP.

## Status

- Priority: P1
- Effort: S
- Risk: LOW-MED (release tooling; no app code)
- Depends on: none
- Category: security
- Planned at: commit `a81523c`, 2026-11-12
- Execution status: TODO

## Why this matters

`appcast.xml` is the file every installed copy of Lid Awake downloads to learn
about its next update. Whatever archive it points at, signed with the Sparkle
EdDSA key, is what users install automatically. It is the highest-trust
artifact the release process produces.

`script/package_dmg.sh` refuses to package anything except the signed,
notarized, stapled release build. `script/package_appcast.sh` has no such
check. It only verifies that `dist/LidAwake.app` exists, then signs an appcast
for whatever archive is in `dist/releases/`. Three concrete ways this goes
wrong:

1. `./scripts/check.sh` restages a DEBUG bundle into `dist/`. Running the
   appcast step after it reads the version and build number from the debug
   bundle and signs an appcast with them.
2. With no DMG present the script falls back to the zip. `package_release.sh`
   writes that zip BEFORE notarization, so unless the maintainer remembered to
   recreate it after stapling, the appcast ships an app with no stapled
   ticket.
3. `SPARKLE_DOWNLOAD_URL_PREFIX` is used as given. An `http://` prefix yields
   an appcast whose download links can be rewritten in transit.

One more gap sits behind the same gate: `script/stage_app.sh` lets
`SPARKLE_ALLOW_INSECURE_FEED=1` (meant for local testing) through for a
release build too, and nothing later checks the feed URL baked into the app.
A release staged that way would fetch its update feed over plain http
forever.

The fix is one shared check used by both packaging scripts, plus an archive
check and an https check in the appcast script.

## Current state

`script/package_appcast.sh` (91 lines). The only precondition, lines 18-22:

```bash
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: staged app not found at $APP_BUNDLE" >&2
  echo "hint: run ./script/package_release.sh, notarize, staple, then run ./script/package_dmg.sh" >&2
  exit 2
fi
```

Archive selection and the prefix, lines 34-53:

```bash
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
dmg="$RELEASE_DIR/LidAwake-$version-macos.dmg"
zip="$RELEASE_DIR/LidAwake-$version-macos.zip"

if [[ -f "$dmg" ]]; then
  update_archive="$dmg"
elif [[ -f "$zip" ]]; then
  update_archive="$zip"
else
  echo "error: no release archive found for version $version" >&2
  echo "hint: expected $dmg or $zip" >&2
  exit 2
fi

if [[ -z "$SPARKLE_DOWNLOAD_URL_PREFIX" ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/thuongtin/lid-awake/releases/download/v$version/"
elif [[ "$SPARKLE_DOWNLOAD_URL_PREFIX" != */ ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="$SPARKLE_DOWNLOAD_URL_PREFIX/"
fi

rm -rf "$APPCAST_DIR"
```

The signing tool is invoked at lines 80-84. Without `SPARKLE_ED_KEY_FILE` or
`SPARKLE_PRIVATE_KEY` it reads the private key from the login Keychain:

```bash
if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_GENERATE_APPCAST" --ed-key-file - "${appcast_args[@]}"
else
  "$SPARKLE_GENERATE_APPCAST" "${appcast_args[@]}"
fi
```

The gate to share, `script/package_dmg.sh` lines 19-55:

```bash
# A public DMG wraps whatever sits in dist/ at the time, and
# ./scripts/check.sh restages a debug bundle there, so check that the app is
# still the signed, notarized release build before packaging it.
if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "error: $APP_BUNDLE does not pass codesign --verify --deep --strict" >&2
    exit 2
  fi

  # Captured first: grep -q exits on the first match, and with pipefail the
  # SIGPIPE codesign then gets would fail a correctly signed app.
  signing_info="$(codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 || true)"
  if ! grep -q '^Authority=Developer ID Application:' <<<"$signing_info"; then
    echo "error: $APP_BUNDLE is not signed with a Developer ID Application identity" >&2
    exit 2
  fi

  if ! xcrun stapler validate "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "error: $APP_BUNDLE has no stapled notarization ticket" >&2
    echo "hint: notarize the release zip, then run xcrun stapler staple dist/LidAwake.app" >&2
    exit 2
  fi

  # Staging records its configuration, since Sparkle keys alone do not tell
  # a release build from a debug one staged with SPARKLE_ENABLED=1.
  build_configuration="$(/usr/libexec/PlistBuddy -c 'Print :LidAwakeBuildConfiguration' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$build_configuration" != "release" ]]; then
    echo "error: $APP_BUNDLE is not a release build (configuration: ${build_configuration:-unknown})" >&2
    echo "hint: restage with CONFIGURATION=release, then sign, notarize, and staple it again" >&2
    exit 2
  fi

  if ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" >/dev/null 2>&1; then
    echo "error: $APP_BUNDLE has no SUPublicEDKey, so it cannot verify updates" >&2
    exit 2
  fi
fi
```

The staging loophole, `script/stage_app.sh` lines 59-68 (not changed by this
plan; the gate catches its result instead):

```bash
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  if [[ "$SPARKLE_FEED_URL" =~ [[:space:]\"\'] ]]; then
    echo "error: SPARKLE_FEED_URL must not contain spaces or quotes" >&2
    exit 2
  fi
  if [[ "$SPARKLE_FEED_URL" != https://* && -z "$SPARKLE_ALLOW_INSECURE_FEED" ]]; then
    echo "error: SPARKLE_FEED_URL must use https (set SPARKLE_ALLOW_INSECURE_FEED=1 for local testing only)" >&2
    exit 2
  fi
fi
```

Where the zip comes from, `script/package_release.sh` line 55 (runs before
any notarization):

```bash
  ditto -c -k --keepParent "LidAwake.app" "$archive"
```

Repo conventions that apply:

- Every shell script starts with `#!/usr/bin/env bash` and
  `set -euo pipefail`.
- CI lints with `shellcheck script/*.sh scripts/check.sh scripts/verify.sh`
  (`.github/workflows/ci.yml` line 41). A new file under `script/` is covered
  by that glob automatically.
- Scripts committed to the repo use `grep`, not `rg`.
- Error lines start with `error:` and optional `hint:` lines follow, all on
  stderr; a refused precondition exits 2.
- `ALLOW_NON_DEVELOPER_ID_RELEASE=1` is the existing, documented escape hatch
  for local packaging tests and must keep working in both scripts.

The complete change below was applied and exercised on a scratch copy before
this plan was written (see "Test plan" for what was and was not covered).

## SAFETY RULES FOR THIS PLAN (read before running anything)

- NEVER run `./script/package_appcast.sh` without
  `SPARKLE_GENERATE_APPCAST` pointing at the stub from step 4. The real tool
  reads the Sparkle EdDSA private key from the Keychain.
- NEVER set `SPARKLE_PRIVATE_KEY` or `SPARKLE_ED_KEY_FILE`, and never print,
  copy, or search for the private key.
- NEVER run `./script/package_release.sh` or `xcrun notarytool`: releases are
  deliberately manual and belong to the maintainer.
- Always pass `SPARKLE_APPCAST_DIR` pointing into a temporary directory when
  testing, so the script's `rm -rf "$APPCAST_DIR"` cannot touch a real
  appcast.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint the scripts | `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` | exit 0, no output |
| Stage a debug bundle | `./script/build_and_run.sh --stage` | exit 0, `dist/LidAwake.app` exists |
| Full local gate | `./scripts/check.sh` | exit 0 |

If `shellcheck` is not installed, STOP and report (CI runs it, so the change
must be linted before it lands).

## Scope

In scope (the only files you should create or modify):

- `script/release_gate.sh` (new)
- `script/package_dmg.sh`
- `script/package_appcast.sh`
- `AGENTS.md` (one list entry)
- `README.md` (one list entry)
- `docs/releasing.md` (one added paragraph)
- `plans/README.md` (status row only)

Out of scope:

- `script/stage_app.sh` and `script/package_release.sh`. Tightening staging
  itself is a separate decision; the gate makes the result unshippable, which
  is enough.
- `docs/build-notarize-release.vi.md`: the maintainer's own runbook. It runs
  the appcast step after the DMG is stapled, which the new gate accepts.
- `.github/workflows/`: no CI change is needed.
- Any Swift source.

## Git workflow

- Branch: `advisor/025-gate-appcast-packaging`. Plain imperative commit
  subject, for example `Gate appcast packaging like the DMG`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the shared gate

Create `script/release_gate.sh` with exactly this content, then make it
executable like its siblings (`chmod 755 script/release_gate.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sourced by the packaging scripts; it does nothing when run on its own.

# Succeeds only for the signed, notarized release build of the app.
#
# A public artifact wraps whatever sits in dist/ at the time, and
# ./scripts/check.sh restages a debug bundle there, so every packaging step
# checks the bundle again before it ships it.
require_public_release_bundle() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"
  local signing_info build_configuration feed_url

  if ! codesign --verify --deep --strict "$app_bundle" 2>/dev/null; then
    echo "error: $app_bundle does not pass codesign --verify --deep --strict" >&2
    return 2
  fi

  # Captured first: grep -q exits on the first match, and with pipefail the
  # SIGPIPE codesign then gets would fail a correctly signed app.
  signing_info="$(codesign -dv --verbose=2 "$app_bundle" 2>&1 || true)"
  if ! grep -q '^Authority=Developer ID Application:' <<<"$signing_info"; then
    echo "error: $app_bundle is not signed with a Developer ID Application identity" >&2
    return 2
  fi

  if ! xcrun stapler validate "$app_bundle" >/dev/null 2>&1; then
    echo "error: $app_bundle has no stapled notarization ticket" >&2
    echo "hint: notarize the release zip, then run xcrun stapler staple dist/LidAwake.app" >&2
    return 2
  fi

  # Staging records its configuration, since Sparkle keys alone do not tell
  # a release build from a debug one staged with SPARKLE_ENABLED=1.
  build_configuration="$(/usr/libexec/PlistBuddy -c 'Print :LidAwakeBuildConfiguration' "$info_plist" 2>/dev/null || true)"
  if [[ "$build_configuration" != "release" ]]; then
    echo "error: $app_bundle is not a release build (configuration: ${build_configuration:-unknown})" >&2
    echo "hint: restage with CONFIGURATION=release, then sign, notarize, and staple it again" >&2
    return 2
  fi

  if ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" >/dev/null 2>&1; then
    echo "error: $app_bundle has no SUPublicEDKey, so it cannot verify updates" >&2
    return 2
  fi

  # Staging accepts a plain http feed for local testing, and a release staged
  # that way would fetch its update feed over a connection anyone can rewrite.
  feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist" 2>/dev/null || true)"
  if [[ "$feed_url" != https://* ]]; then
    echo "error: $app_bundle does not read its update feed over https (SUFeedURL: ${feed_url:-missing})" >&2
    echo "hint: restage without SPARKLE_ALLOW_INSECURE_FEED, then sign, notarize, and staple it again" >&2
    return 2
  fi
}
```

The function uses `return`, not `exit`, so a caller can add its own message.
The first five checks are the existing DMG gate moved verbatim; the
`SUFeedURL` check is new.

Verify: `bash -n script/release_gate.sh` -> exit 0.

### Step 2: Use the gate in package_dmg.sh

In `script/package_dmg.sh`, replace the whole block quoted in "Current state"
(the three-line comment through the closing `fi`, lines 19-55) with:

```bash
# shellcheck source=script/release_gate.sh
source "$ROOT_DIR/script/release_gate.sh"

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  require_public_release_bundle "$APP_BUNDLE" || exit 2
fi
```

Leave the rest of the file as it is, including the `INFO_PLIST` variable if
later lines still use it. If nothing else uses `INFO_PLIST` after the edit and
shellcheck reports it as unused (SC2034), remove that one assignment.

Verify: `shellcheck script/package_dmg.sh script/release_gate.sh` -> exit 0.

### Step 3: Gate package_appcast.sh

Four edits in `script/package_appcast.sh`:

1. After the line `SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"` add:

```bash
ALLOW_NON_DEVELOPER_ID_RELEASE="${ALLOW_NON_DEVELOPER_ID_RELEASE:-0}"
```

2. Directly after the existing "staged app not found" block (after its `fi`)
   add:

```bash

# shellcheck source=script/release_gate.sh
source "$ROOT_DIR/script/release_gate.sh"

# The appcast is what every installed copy trusts for its next update, so it
# must describe the same signed, notarized release build the DMG step checks.
if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  require_public_release_bundle "$APP_BUNDLE" || exit 2
fi
```

3. Directly after the archive selection block (after the `fi` that follows
   `hint: expected $dmg or $zip`) add:

```bash

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  if [[ "$update_archive" == "$dmg" ]]; then
    if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
      echo "error: $dmg has no stapled notarization ticket" >&2
      echo "hint: notarize the DMG, then run xcrun stapler staple on it" >&2
      exit 2
    fi
  else
    # package_release.sh writes the zip before notarization, so a zip that was
    # not recreated after stapling still holds the unstapled app.
    archive_check_dir="$(mktemp -d)"
    trap 'rm -rf "$archive_check_dir"' EXIT
    ditto -x -k "$zip" "$archive_check_dir"
    if ! require_public_release_bundle "$archive_check_dir/LidAwake.app"; then
      echo "error: $zip does not hold the notarized release build" >&2
      echo "hint: recreate the zip after stapling dist/LidAwake.app, or package the DMG" >&2
      exit 2
    fi
  fi
fi
```

4. Directly after the prefix block (after the `fi` that closes
   `elif [[ "$SPARKLE_DOWNLOAD_URL_PREFIX" != */ ]]`) and before
   `rm -rf "$APPCAST_DIR"` add:

```bash

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" && "$SPARKLE_DOWNLOAD_URL_PREFIX" != https://* ]]; then
  echo "error: SPARKLE_DOWNLOAD_URL_PREFIX must use https for a public appcast" >&2
  exit 2
fi
```

All four checks must sit ABOVE `rm -rf "$APPCAST_DIR"` and above the call to
`"$SPARKLE_GENERATE_APPCAST"`: a refused run must neither delete a previous
appcast nor reach the signing tool.

Verify: `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` -> exit
0, no output.

### Step 4: Exercise the refusals with a stub signer

Create the stub OUTSIDE the repo and point everything else at a temporary
directory:

```bash
work="$(mktemp -d)"
cat >"$work/fake_generate_appcast.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Stand-in for Sparkle's generate_appcast: never touches a signing key.
echo "REACHED generate_appcast" >&2
for last; do :; done
printf '<rss/>\n' >"$last/appcast.xml"
EOF
chmod 755 "$work/fake_generate_appcast.sh"
./script/build_and_run.sh --stage
```

Run each case and compare. `$?` must be read right after each command.

Case A, debug bundle is refused before the signer:

```bash
SPARKLE_GENERATE_APPCAST="$work/fake_generate_appcast.sh" \
  SPARKLE_APPCAST_DIR="$work/appcast" ./script/package_appcast.sh; echo "rc=$?"
```

Expected: `rc=2`, one `error:` line from the gate (which one depends on the
local signing identity: "does not pass codesign", "is not signed with a
Developer ID Application identity", or "has no stapled notarization ticket"),
and NO `REACHED generate_appcast` line.

Case B, the DMG script still refuses the debug bundle:

```bash
./script/package_dmg.sh; echo "rc=$?"
```

Expected: `rc=2` with one of the same `error:` lines, and no `.dmg` created
under `dist/releases/`.

Case C, the escape hatch still reaches the signer:

```bash
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/LidAwake.app/Contents/Info.plist)"
mkdir -p dist/releases
( cd dist && ditto -c -k --keepParent LidAwake.app "releases/LidAwake-$version-macos.zip" )
ALLOW_NON_DEVELOPER_ID_RELEASE=1 SPARKLE_GENERATE_APPCAST="$work/fake_generate_appcast.sh" \
  SPARKLE_APPCAST_DIR="$work/appcast" ./script/package_appcast.sh; echo "rc=$?"
```

Expected: `REACHED generate_appcast`, `rc=0`, and `$work/appcast/appcast.xml`
plus `$work/appcast/appcast.xml.sha256` exist. If a
`dist/releases/LidAwake-$version-macos.dmg` already exists the script picks it
instead of the zip; that is fine for this case.

Case D, a plain http prefix is refused. This check sits behind the bundle
gate, so on a machine without a notarized build it can only be confirmed by
reading: confirm in the file that the https check is above
`rm -rf "$APPCAST_DIR"`. If (and only if) a notarized Lid Awake release build
is already staged in `dist/` by the maintainer, also run:

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="http://example.com/" \
  SPARKLE_GENERATE_APPCAST="$work/fake_generate_appcast.sh" \
  SPARKLE_APPCAST_DIR="$work/appcast" ./script/package_appcast.sh; echo "rc=$?"
```

Expected: `rc=2`, `error: SPARKLE_DOWNLOAD_URL_PREFIX must use https for a
public appcast`, no `REACHED` line.

Clean up: `rm -rf "$work"` and remove the test zip you created in case C
(`rm -f "dist/releases/LidAwake-$version-macos.zip"`; `dist/` is git-ignored,
and you must not delete any other file in `dist/releases/`).

### Step 5: Document the new file and behaviour

1. `AGENTS.md`, "Repo layout": change the `script/` entry to list the new
   file:

```markdown
- `script/`: staging and packaging (`stage_app.sh`, `build_and_run.sh`,
  `package_release.sh`, `package_dmg.sh`, `package_appcast.sh`, and the
  `release_gate.sh` check the last two share).
```

2. `README.md`, in the list that describes each script, add this line right
   after the `script/package_appcast.sh` entry:

```markdown
- `script/release_gate.sh`: shared check that the DMG and appcast steps only package the signed, notarized release build.
```

3. `docs/releasing.md`: directly after the paragraph that starts with
   "Use `SPARKLE_RELEASE_NOTES=/path/to/release-notes.md`", add a blank line
   and this paragraph:

```markdown
`package_appcast.sh` runs the same release gate as `package_dmg.sh` before it reaches the signing tool: `dist/LidAwake.app` must be the Developer ID signed, notarized, stapled release build with an `https` update feed. It also requires a stapled DMG, or, when no DMG exists, a zip that holds the stapled app (recreate the zip after stapling, step 7), and an `https` download prefix. `ALLOW_NON_DEVELOPER_ID_RELEASE=1` skips these checks for local packaging tests only.
```

Do not touch any other line of these three files. `README.md` and
`docs/releasing.md` may contain the maintainer's own pending edits; leave
them exactly as you find them.

Verify: `git diff --stat -- AGENTS.md README.md docs/releasing.md` shows
small additions only (at most 3 changed lines in `AGENTS.md`, 1 in
`README.md`, 2 in `docs/releasing.md`).

### Step 6: Full gate

Verify: `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` -> exit
0. `./scripts/check.sh` -> exit 0.

## Test plan

There is no test harness for the packaging scripts, and this plan does not
add one. Verification is the scripted cases in step 4 plus shellcheck.

Covered on the scratch copy when this plan was written:

- The gate accepts a real notarized Lid Awake build (read-only check against
  an installed copy).
- Debug bundle: appcast refused with exit 2 before the signer; DMG refused
  with exit 2.
- Zip holding a non-release bundle: refused, "does not hold the notarized
  release build".
- Zip holding the notarized build: reaches the (stub) signer, exit 0.
- `http://` prefix: refused. Unstapled DMG: refused.
- `ALLOW_NON_DEVELOPER_ID_RELEASE=1`: reaches the (stub) signer, exit 0.

NOT covered, for the maintainer to confirm at the next real release: the
positive path with a stapled DMG and the real `generate_appcast` (no stapled
DMG was available, and the real signer was deliberately never run).

## Done criteria

- [ ] `shellcheck script/*.sh scripts/check.sh scripts/verify.sh` exits 0.
- [ ] `./scripts/check.sh` exits 0.
- [ ] Step 4 cases A, B, and C gave the expected results.
- [ ] `grep -c 'require_public_release_bundle' script/package_dmg.sh` prints
      `1`; the same grep on `script/package_appcast.sh` prints `2`.
- [ ] `grep -c 'stapler validate' script/package_dmg.sh` prints `0` (the gate
      moved, it was not duplicated).
- [ ] In `script/package_appcast.sh`, the line number of the first
      `require_public_release_bundle` is lower than the line number of
      `rm -rf "$APPCAST_DIR"`.
- [ ] `git status --short` shows only the in-scope files (plus nothing under
      `dist/`, which is ignored).
- [ ] No em dash character in the diff:
      `git diff | grep -c "$(printf '\xe2\x80\x94')"` prints `0`.
- [ ] Status row for 025 in `plans/README.md` updated.

## STOP conditions

Stop and report back (do not improvise) if:

- `shellcheck` is not installed.
- Any step would require running the real `generate_appcast`, a signing
  identity you do not have, `notarytool`, or `package_release.sh`.
- Case A or B does not exit 2, or case A prints `REACHED generate_appcast`.
- Case C does not reach the stub with `ALLOW_NON_DEVELOPER_ID_RELEASE=1`.
- `package_dmg.sh` lines 19-55 no longer match the excerpt in "Current
  state".
- The paragraph or list entries named in step 5 cannot be found as described.

## Maintenance notes

- `require_public_release_bundle` is now the single definition of "a build
  that may be published". A new release requirement (for example a minimum
  hardened-runtime flag) goes there once and covers both the DMG and the
  appcast.
- `scripts/check.sh` asserts that the staged debug bundle records
  `LidAwakeBuildConfiguration = debug` with the comment "package_dmg.sh reads
  this to refuse a debug bundle". The reader is now `release_gate.sh`; the
  comment is still accurate enough and is out of scope here.
- The zip check extracts the archive to a temporary directory and removes it
  with an `EXIT` trap. If the script ever gains another `trap ... EXIT`, merge
  them: bash keeps only the last one.
- Reviewer focus: every refusal happens before `rm -rf "$APPCAST_DIR"` and
  before the signer runs; `ALLOW_NON_DEVELOPER_ID_RELEASE=1` still bypasses
  all of the new checks; no private key handling changed.
- Deliberately left for the maintainer: making `stage_app.sh` itself refuse
  `SPARKLE_ALLOW_INSECURE_FEED` when `CONFIGURATION=release`, and replacing
  the `hdiutil create` call in `package_dmg.sh`, which prints a deprecation
  warning on the current macOS.

### Review follow-up (2026-11-12)

An independent review of `52a8fc5` found these gaps. Each one was reproduced
against the scripts as of `2f13ba3` (stub signer throughout) before it was
fixed:

1. The DMG branch only ran `xcrun stapler validate` on the DMG and never
   looked inside it: a DMG holding only another app reached the signer, exit
   0, previous appcast deleted.
2. The archive was not tied to `dist/LidAwake.app`: a zip holding the real
   0.1.8 build under the 0.1.7 name reached the signer, exit 0.
3. A missing `SPARKLE_RELEASE_NOTES` file was refused only after
   `rm -rf "$APPCAST_DIR"`, so the refusal deleted the previous appcast.
4. A corrupt zip made `ditto` fail under `set -e`: exit 1 and no `error:`
   line.
5. A zip with extra top-level entries next to `LidAwake.app` was accepted.
6. The https checks only looked at the prefix: `SPARKLE_DOWNLOAD_URL_PREFIX=https://`
   reached the signer, and the gate accepted `SUFeedURL=https://` and an
   empty `SUPublicEDKey`.
7. The archive is checked at one path and copied again from that path later.

What changed:

- A (findings 1, 2): with the gate active, the script now locates the
  `LidAwake.app` inside whichever archive it picked, runs the gate on it, and
  requires its CDHash (from `codesign -dv --verbose=4`) to equal the CDHash
  of `dist/LidAwake.app`; a mismatch names the archive and both versions and
  exits 2. The DMG keeps its `stapler validate` check first, is then mounted
  with `hdiutil attach -readonly -nobrowse -noautoopen` at a mount point
  inside the script's temporary directory, and is detached again right after
  the checks (the signer reads the DMG itself). CDHash equality was confirmed
  on the real notarized 0.1.7 build: a `ditto` copy, a `ditto -c -k
  --keepParent` zip round trip, and a DMG built with `hdiutil create
  -srcfolder` all report the original CDHash.
- B (finding 3): the release notes existence check now runs before
  `rm -rf "$APPCAST_DIR"`, with or without the escape hatch. The copy of the
  notes stays where it was.
- C (finding 4): a zip that `ditto` cannot extract is refused with an
  `error:` line and exit 2.
- D (finding 5): the extracted zip must hold exactly one top-level entry,
  `LidAwake.app`. `package_dmg.sh` puts `LidAwake.app` and an `Applications`
  symlink on the volume, so the DMG check refuses any other top-level `.app`,
  `.pkg`, or `.mpkg` (case-insensitive) and tolerates everything else. In
  both archives `LidAwake.app` must be a real directory, not a symlink.
- E (finding 6): the gate now also refuses an empty or whitespace-only
  `SUPublicEDKey` and an `SUFeedURL` with no valid host after `https://`; the
  download prefix must be an https URL with a host. The shared test is
  `is_https_url_with_host` in `release_gate.sh`. The existing gate messages
  for a missing key and for a non-https or missing feed are unchanged, so
  `package_dmg.sh` behaves the same for every case it already refused.
- The script still has exactly one `trap ... EXIT`; it detaches the mount if
  one is attached (falling back to `hdiutil detach -force`) and removes the
  temporary directory. If the volume cannot be detached it leaves the
  directory in place and prints a warning instead of removing files under a
  mounted volume.

Deliberately left alone:

- Finding 7: not restructured. The only actor who can swap the archive
  between the check and the copy has write access to the repository's
  `dist/` directory and could equally change the script itself.
- The feed URL and public key are not pinned to the repository defaults:
  staging lets the maintainer override both, and changing that contract is
  the maintainer's decision.
- The gate's hint for a missing ticket still says `xcrun stapler staple
  dist/LidAwake.app` even when the app being checked is the one inside an
  archive. The `error:` line above it names the real path and the caller's
  own hint follows, so it was left as is to keep `package_dmg.sh` output
  byte-for-byte.
- The DMG check looks only at the top level of the volume; nested content is
  not inspected.

Cases run on 2026-11-12 (stub signer and a scratch `SPARKLE_APPCAST_DIR` with
a sentinel file for every run). "Stub xcrun" means a stub that only answers
`stapler validate` for a `.dmg` (no stapled Lid Awake DMG was available) and
passes everything else, including the gate's checks on the app inside the
DMG, to the real tool. "Stub codesign" means a stub that reports any bundle
as Developer ID signed, needed for bundles no real build can be:

- Real notarized 0.1.7 in `dist/`, zip rebuilt from it: exit 0, reached.
- Zip holding the real notarized 0.1.8 under the 0.1.7 name: exit 2.
- Zip with an extra `.command`, zip with a second `.app`, truncated zip,
  garbage zip: exit 2 each.
- DMG (stub xcrun) holding the same app as `dist/`: exit 0, reached. DMG
  holding 0.1.8, only another app, no app, a second app, a `.pkg`, or a
  `LidAwake.app` symlink: exit 2 each. Unmountable DMG: exit 2. Same DMG
  with the real xcrun (no ticket on the DMG): exit 2. After every DMG case
  no test volume was attached and no temporary directory was left.
- Missing release notes: exit 2, previous appcast kept (also with the escape
  hatch). Existing notes: exit 0, copied.
- Prefix `https://`, `http://example.com/`, `https:///path`: exit 2 each.
  Default prefix and `https://example.com/dl`: exit 0.
- Gate (stub codesign and xcrun) with an empty key, a whitespace key,
  `SUFeedURL=https://`, `https:///appcast.xml`: exit 2 each, with the new
  messages; missing key, http feed, missing feed: exit 2 with the old
  messages unchanged.
- `ALLOW_NON_DEVELOPER_ID_RELEASE=1` with a staged debug bundle and its zip,
  and with a DMG holding another app: exit 0, reached.
- `./script/package_dmg.sh` with the debug bundle: exit 2, no DMG written.
- The same checks from a copy of the repository whose path contains a space:
  zip and DMG, matching and different build, as expected.

Not run: the positive path with a real stapled Lid Awake DMG (none exists
locally) and the real `generate_appcast`. Both are still for the maintainer
to confirm at the next release.

### Second review follow-up (2026-11-12)

An independent adversarial review of `a8623b3` found no blocking issue but
five gaps. Each was reproduced against `a8623b3` with a stub signer before it
was fixed:

1. F1: the DMG check only refused top-level names ending in `.app`, `.pkg`,
   or `.mpkg`. A DMG holding the right `LidAwake.app` plus a top-level
   directory `Aaa` (another Lid Awake build), `Aaa.app ` (trailing space),
   `Docs/LidAwake.app`, or `Docs/LidAwake.pkg` reached the signer, exit 0.
   Sparkle may search the volume recursively and pick one of them.
2. F2: `SPARKLE_RELEASE_NOTES` was only checked with `-f` and copied next to
   the archive under the archive's base name with its own extension. A zip
   passed as release notes replaced or joined the checked archive in
   `$APPCAST_DIR`, unchecked, and reached the signer, exit 0.
3. F3: `archive_mount_dir` was assigned only after `hdiutil attach`
   returned. A SIGTERM right after a successful attach (exit 143) made the
   EXIT trap run `rm -rf` on the directory holding the mounted volume; the
   volume and the temporary directory were left behind.
4. F4: if the detach before the signer failed, the script warned, called the
   signer with the volume still attached (exit 0, previous appcast deleted),
   and the trap warned a second time.
5. F5: `is_https_url_with_host` accepted whitespace and control characters
   after the host, for example `https://example.com/` followed by a newline
   and an `http://` URL, a space, a carriage return, `\001`, or `\177`.

What changed:

- F1 (`script/package_appcast.sh`): after the existing check for another
  `.app`, `.pkg`, or `.mpkg` (unchanged, same message), every top-level
  entry of the volume must be `LidAwake.app` or `Applications`, and
  `Applications` must be a symlink whose target is exactly `/Applications`.
  Anything else exits 2 with `error: <dmg> must hold only LidAwake.app and
  an Applications symlink to /Applications at its top level`. `LidAwake.app`
  must still be a real directory (existing check), and its contents are
  covered by the gate and the CDHash comparison, so no foreign content can
  sit anywhere on the volume. No metadata entry is allowed, from evidence: a
  DMG built exactly the way `package_dmg.sh` builds it (`hdiutil create
  -volname "Lid Awake" -srcfolder ... -ov -format UDZO`, from a `ditto` copy
  of the notarized 0.1.7 app plus `ln -s /Applications`, unsigned, on macOS
  27.0.1) and mounted read-only holds exactly `Applications` and
  `LidAwake.app`, no `.fseventsd`, `.Trashes`, or `.DS_Store`. A UDZO image
  is compressed and read-only, so nothing can add such entries after it is
  created, and signing and stapling do not change the volume. If a future
  `hdiutil` starts adding one, the script refuses with the message above,
  which fails safe; allow that name then, after checking it holds no app or
  package.
- F2: with the gate active, a release notes file whose extension (compared
  case-insensitively) is not `html`, `md`, or `txt` exits 2 with
  `error: SPARKLE_RELEASE_NOTES must be an .html, .md, or .txt file for a
  public appcast: <path>`, after the existence check and before
  `rm -rf "$APPCAST_DIR"`. A path without an extension is refused too (it
  used to fail later with exit 1 and no `error:` line, after the previous
  appcast was deleted). The escape hatch path is unchanged.
- F3: `archive_mount_dir` is set before `mkdir` and `hdiutil attach`. The
  cleanup now asks a real mount point test (`is_mount_point`: the directory
  sits on another device than its parent, from `/usr/bin/stat -f %d`)
  instead of trusting the variable: it detaches only a mounted volume
  (falling back to `-force`), and it removes the temporary directory only
  when nothing is mounted there afterwards. When the attach never happened
  or failed, the directory is not a mount point, so no detach is attempted
  and the directory is removed. The test was tried on a missing directory,
  a plain directory, the same directory with a scratch DMG attached, and
  after detaching: not, not, mounted, not.
- F4: the detach before the signer goes through the same function; if a
  volume is still mounted afterwards the script exits 2 with
  `error: could not detach <mount>; detach it, then remove <dir>`, before
  `rm -rf "$APPCAST_DIR"`, and clears both variables so the EXIT trap does
  not warn again. The trap keeps its single `warning:` for other exits.
- F5 (`script/release_gate.sh`): `is_https_url_with_host` refuses any value
  containing a `[:space:]` or `[:cntrl:]` character. It is shared, so both
  the download prefix and the gate's `SUFeedURL` check use it; their
  messages are unchanged.
- `docs/releasing.md`: the `package_appcast.sh` paragraph describes the
  allowlist, the detach refusal, the URL rule, and the release notes rule.

Deliberately left alone:

- The `Applications` symlink is allowed even though it points outside the
  volume: `package_dmg.sh` creates it, and requiring its exact target keeps
  it from pointing anywhere else on the volume or the machine.
- The DMG volume name is not checked: Sparkle does not use it to pick what
  it installs.
- The release notes content is not inspected, and the escape hatch still
  copies any notes file: the escape hatch is for local tests only.
- An F3 interrupt still ends with the signal's exit status (143 for
  SIGTERM), not 2: the run was interrupted, not refused. What the fix
  guarantees is that nothing stays mounted or left in the temporary
  directory and the signer is not reached.
- The earlier note "The DMG check looks only at the top level of the
  volume" is superseded by the allowlist above.

Cases run on 2026-11-12, every run with the stub signer (prints `REACHED`
and lists the files it was given), `SPARKLE_APPCAST_DIR` pointing at a
scratch directory holding a sentinel file, and neither `SPARKLE_PRIVATE_KEY`
nor `SPARKLE_ED_KEY_FILE` set. `dist/` held a `ditto` copy of the notarized
0.1.7 app; "0.1.8" is a copy of the notarized 0.1.8 release zip. Stubs: the
same stub xcrun as above (answers `stapler validate <path>.dmg` only, which
every DMG case except the "real xcrun" one depends on); a stub hdiutil whose
`detach` always fails (F4); a stub hdiutil that attaches for real and then
sends SIGTERM to the script (F3); a stub codesign that reports any bundle as
Developer ID signed and refuses `--sign`, with a stub xcrun that answers
every `stapler validate` (gate cases only); a stub hdiutil that refuses
everything (all `package_dmg.sh` runs, so none could write or sign a DMG).

| Case | `a8623b3` | Now |
|------|-----------|-----|
| F1: extra top-level dir `Aaa` holding 0.1.8 | 0, reached | 2, not reached |
| F1: top-level `Aaa.app ` (trailing space) | 0, reached | 2, not reached |
| F1: `Docs/LidAwake.app` | 0, reached | 2, not reached |
| F1: `Docs/LidAwake.pkg` | 0, reached | 2, not reached |
| F1: `Applications` symlink to `/tmp` | 0, reached | 2, not reached |
| F1: `Applications` as a real directory | 0, reached | 2, not reached |
| F1: top-level `.DS_Store` | 0, reached | 2, not reached |
| F1: `.fseventsd/LidAwake.app` | 0, reached | 2, not reached |
| F2: notes = zip of the 0.1.8 build | 0, reached | 2, not reached |
| F2: notes file without extension | 1, no `error:`, appcast deleted | 2, not reached |
| F2: `notes.HTML` | 0, reached, copied | same |
| F2: zip notes with the escape hatch | 0, reached | same |
| F3: SIGTERM right after attach | 143, volume and dir left | 143, nothing left |
| F4: detach fails before signer | 0, reached, two warnings | 2, one `error:`, not reached |
| F5: prefix with newline then `http://` URL | 0, reached | 2, not reached |
| F5: prefix with a space, with a tab | 0, reached | 2, not reached |
| F5: `SUFeedURL` with newline then `http://` URL (stub codesign) | passed the gate | 2, gate message |

Unchanged, with output byte-for-byte identical between `a8623b3` and now
(the outputs were diffed): zip of the real notarized 0.1.7 (0, reached);
zip plus `notes.md` (0, copied); missing release notes, also with the escape
hatch (2, appcast kept); prefixes `http://example.com/`, `https://`,
`https:///path` (2); zip holding 0.1.8, extra `.command`, second app,
truncated zip, garbage zip, `LidAwake.app` symlink (2 each); DMG made the
`package_dmg.sh` way (0, reached); the same DMG with the real xcrun (2, no
ticket); DMG holding 0.1.8, only another app, no app, a second app, a
`.PKG`, a `LidAwake.app` symlink to `/Applications/LidAwake.app`,
unmountable DMG (2 each); escape hatch with a DMG holding another app and
with a staged debug bundle and its zip (0, reached); debug bundle without
the escape hatch (2); gate with an empty key, a whitespace key, a missing
key, `SUFeedURL` `https://`, `https:///appcast.xml`, `http://`, missing
(2 each). A `LidAwake.app` symlink into a top-level directory of the volume
is still refused, now by the allowlist message. `./script/package_dmg.sh`
with the debug bundle and with the gate cases above: 2 each, no DMG written,
output identical except the newline `SUFeedURL`, which `a8623b3` let past
the gate (stopped there only by the refusing hdiutil stub) and which is now
refused by the gate. From a copy of the repository whose path contains a
space: zip and DMG of the same build (0, reached), of another build (2), DMG
with an extra `Aaa` (2), detach failure (2), SIGTERM after attach (143,
nothing left). After every DMG case no scratch volume was attached
(`hdiutil info`) and no temporary directory was left, except the F4 cases,
where the script deliberately leaves the still mounted volume and its
directory; the test harness detached and removed them.

`shellcheck script/*.sh scripts/check.sh scripts/verify.sh`: exit 0.
`SIGNING_IDENTITY=- ./scripts/check.sh`: exit 0.

Not run: the real `generate_appcast`, a real stapled Lid Awake DMG (none
exists locally), and a real Ctrl-C from a terminal (SIGINT to the whole
process group); the SIGTERM stub stands in for it.
