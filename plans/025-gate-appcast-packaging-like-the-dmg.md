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
