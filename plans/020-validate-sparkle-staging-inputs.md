# Plan 020: Validate Sparkle staging inputs and test the update configuration parsing

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first): `git diff --stat 5d89d38..HEAD -- script/stage_app.sh Sources/LidAwake/SoftwareUpdateService.swift docs/releasing.md README.md`
> This plan was written at commit `5d89d38` while the Sparkle integration was
> still uncommitted in the working tree; the excerpts reflect that working
> tree. On any mismatch with "Current state", treat it as a STOP condition.

## Status

- Priority: P2
- Effort: S-M
- Risk: LOW
- Depends on: none (independent of 017-019)
- Category: security
- Planned at: commit `5d89d38`, 2026-07-02
- Execution status: TODO

## Why this matters

`script/stage_app.sh` writes the Sparkle feed URL and EdDSA public key into
the app's Info.plist via unquoted interpolation into PlistBuddy command
strings. Nothing validates that the feed URL is HTTPS or that the key looks
like an Ed25519 public key, and a value containing spaces or quotes would
corrupt the PlistBuddy command. The update feed is the app's most
security-sensitive input after the privileged helper, so the staging gate
should reject malformed or insecure values instead of baking them into a
release bundle. On the Swift side, `SoftwareUpdateConfiguration` (the code
that reads these plist keys back) is private and untested; its message logic
is what users see when a build is misconfigured.

## Current state

- `script/stage_app.sh:17-20` - Sparkle inputs come from the environment:

```bash
SPARKLE_ENABLED="${SPARKLE_ENABLED:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PUBLIC_ED_KEY_FILE="${SPARKLE_PUBLIC_ED_KEY_FILE:-}"
```

- `script/stage_app.sh:53-55` - default feed URL when enabled:

```bash
if [[ "$SPARKLE_ENABLED" == "1" && -z "$SPARKLE_FEED_URL" ]]; then
  SPARKLE_FEED_URL="https://github.com/thuongtin/lid-awake/releases/latest/download/appcast.xml"
fi
```

- `script/stage_app.sh:74-86` - key file fallback reads
  `scripts/sparkle_public_key.txt` and strips whitespace; the only check is
  non-emptiness.
- `script/stage_app.sh:168-175` - the unvalidated interpolation this plan
  guards:

```bash
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST" >/dev/null
  ...
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST" >/dev/null
fi
```

- `Sources/LidAwake/SoftwareUpdateService.swift:172-208` - the private config
  reader:

```swift
private struct SoftwareUpdateConfiguration {
    let feedURL: String?
    let publicKey: String?

    init(bundle: Bundle) {
        self.feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        self.publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    var isConfigured: Bool { hasText(feedURL) && hasText(publicKey) }
    var message: String { /* three missing-key variants + ready text */ }
    private func hasText(_ value: String?) -> Bool { ... }
}
```

- `README.md:100` documents local appcast testing via
  `SPARKLE_ENABLED=1` and `SPARKLE_FEED_URL=<url>`, so non-HTTPS values (for
  example `file://` or `http://localhost`) must remain possible behind an
  explicit override, not silently.
- A Sparkle Ed25519 public key is 32 bytes, base64-encoded to exactly 44
  characters ending in `=` (the committed `scripts/sparkle_public_key.txt` is
  44 chars + newline). Never print or copy key file contents into any output.
- Conventions: script validation errors in this repo print
  `error: ...` to stderr and `exit 2` (see `stage_app.sh:26-28, 43-45, 48-51`).
  App tests live in `Tests/LidAwakeTests`, plain XCTest.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Full tests | `swift test` | exit 0 |
| New tests only | `swift test --filter SoftwareUpdateConfigurationTests` | all pass |
| Full local gate | `./scripts/check.sh` | exit 0 |
| Negative script check (http) | `SPARKLE_ENABLED=1 SPARKLE_FEED_URL=http://example.com/appcast.xml ./script/stage_app.sh` | prints `error:`, exit 2, fast (before any build) |
| Negative script check (bad key) | `SPARKLE_ENABLED=1 SPARKLE_PUBLIC_ED_KEY=not-a-key ./script/stage_app.sh` | prints `error:`, exit 2 |
| Override accepted | `SPARKLE_ENABLED=1 SPARKLE_ALLOW_INSECURE_FEED=1 SPARKLE_FEED_URL=http://localhost:8000/appcast.xml ./script/stage_app.sh` | proceeds past validation (you may Ctrl-C once `swift build` starts) |

## Scope

In scope (the only files you should modify):

- `script/stage_app.sh`
- `Sources/LidAwake/SoftwareUpdateService.swift` (visibility of
  `SoftwareUpdateConfiguration` + a testable init only; no behavior change)
- `Tests/LidAwakeTests/SoftwareUpdateConfigurationTests.swift` (create)
- `docs/releasing.md` (document the new validation + override variable)
- `README.md` (one sentence for the local-testing override)

Out of scope (do NOT touch, even though they look related):

- `script/package_appcast.sh` - private-key handling there is a separate
  concern; do not modify it.
- `scripts/sparkle_public_key.txt` - never edit, print, or move it.
- Sparkle runtime behavior (`SPUStandardUpdaterController` wiring) and the
  Settings UI.

## Git workflow

- Branch: `advisor/020-validate-sparkle-staging`. Plain imperative commit
  subjects.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Validate the feed URL in stage_app.sh

Immediately after the default-feed-URL block (`stage_app.sh:53-55`), add:

```bash
SPARKLE_ALLOW_INSECURE_FEED="${SPARKLE_ALLOW_INSECURE_FEED:-}"

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

Verify: the two negative script checks from the commands table exit 2 with the
matching `error:` line, and the override command proceeds past validation.

### Step 2: Validate the public key format in stage_app.sh

Replace the existing non-empty check at `stage_app.sh:82-86` so the same block
also validates shape (do not echo the key value in any message):

```bash
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: Sparkle staging requires SPARKLE_PUBLIC_ED_KEY or scripts/sparkle_public_key.txt" >&2
    echo "hint: run Sparkle generate_keys and commit only the public key" >&2
    exit 2
  fi
  if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: SPARKLE_PUBLIC_ED_KEY is not a valid base64 Ed25519 public key" >&2
    exit 2
  fi
fi
```

Verify: `SPARKLE_ENABLED=1 SPARKLE_PUBLIC_ED_KEY=not-a-key ./script/stage_app.sh`
-> `error: SPARKLE_PUBLIC_ED_KEY is not a valid base64 Ed25519 public key`,
exit 2. Then confirm the committed key passes:
`SPARKLE_ENABLED=1 ./script/stage_app.sh` must get past validation (it may
then proceed to `swift build`; that is fine, let it finish or interrupt after
the build starts - validation happens first).

### Step 3: Make SoftwareUpdateConfiguration testable

In `Sources/LidAwake/SoftwareUpdateService.swift`:

1. Change `private struct SoftwareUpdateConfiguration` to
   `struct SoftwareUpdateConfiguration` (internal).
2. Add an internal memberwise init alongside the bundle init:

```swift
init(feedURL: String?, publicKey: String?) {
    self.feedURL = feedURL
    self.publicKey = publicKey
}
```

No other change: `isConfigured`, `message`, and `hasText` keep their exact
current bodies.

Verify: `swift build` -> exit 0.

### Step 4: Unit-test the configuration logic

Create `Tests/LidAwakeTests/SoftwareUpdateConfigurationTests.swift`
(`@testable import LidAwake`, plain XCTest) covering:

- both values present -> `isConfigured == true`, message
  `"Ready to check for signed updates."`
- feed URL nil -> not configured, message
  `"This build does not include a Sparkle feed URL."`
- public key nil -> not configured, message
  `"This build does not include a Sparkle update signing key."`
- both nil -> message
  `"This build does not include a Sparkle feed URL or update signing key."`
- whitespace-only values (`"  \n"`) treated as missing for both fields.

Verify: `swift test --filter SoftwareUpdateConfigurationTests` -> 5+ tests
pass.

### Step 5: Document the validation

- `docs/releasing.md`: in the Sparkle/appcast section, add 2-3 sentences: the
  staging script rejects non-HTTPS feed URLs and malformed public keys, and
  `SPARKLE_ALLOW_INSECURE_FEED=1` exists for local testing only and must
  never be used for a public release.
- `README.md`: extend the existing local-testing sentence (line ~100) to
  mention `SPARKLE_ALLOW_INSECURE_FEED=1` for non-HTTPS local feeds.

Verify: `grep -n "SPARKLE_ALLOW_INSECURE_FEED" README.md docs/releasing.md script/stage_app.sh`
-> one match in each file at minimum.

### Step 6: Full gate

Verify: `./scripts/check.sh` -> exit 0.

## Test plan

- New `SoftwareUpdateConfigurationTests` with the five cases in step 4,
  modeled structurally on `Tests/LidAwakeTests/ScreenLockCommandResolverTests.swift`
  (small, no harness).
- Script behavior verified by the negative/positive invocations listed in the
  commands table (manual verification commands, run and record exit codes).
- All existing tests pass unchanged.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `SPARKLE_ENABLED=1 SPARKLE_FEED_URL=http://example.com/a.xml ./script/stage_app.sh` exits 2 before building
- [ ] `SPARKLE_ENABLED=1 SPARKLE_PUBLIC_ED_KEY=not-a-key ./script/stage_app.sh` exits 2 before building
- [ ] `swift test` exits 0; `SoftwareUpdateConfigurationTests` exists with >= 5 tests
- [ ] `grep -c "SPARKLE_ALLOW_INSECURE_FEED" script/stage_app.sh` >= 2 (declaration + check)
- [ ] `./scripts/check.sh` exits 0
- [ ] No secret values appear in any modified file or in your report
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `script/stage_app.sh` no longer matches the "Current state" excerpts
  (the Sparkle block may have been reworked when the integration landed).
- The committed public key in `scripts/sparkle_public_key.txt` does NOT match
  the `^[A-Za-z0-9+/]{43}=$` pattern (report the mismatch WITHOUT quoting the
  file contents; the maintainer must check the key, not you).
- Making `SoftwareUpdateConfiguration` internal breaks compilation somewhere
  unexpected.
- Release staging (`CONFIGURATION=release`) appears to depend on a non-HTTPS
  feed anywhere in scripts or docs.

## Maintenance notes

- The regex approach means PlistBuddy interpolation stays as-is safely:
  validated values cannot contain quotes, spaces, or plist-breaking
  characters. If a future change relaxes validation, the PlistBuddy lines
  must be rewritten to escape values instead.
- If Sparkle ever changes key format (not expected for Ed25519), the
  44-char check in step 2 must be updated.
- Reviewer focus: the override variable must not be settable from anything
  release-facing; `package_release.sh` calls `stage_app.sh` with
  `CONFIGURATION=release` and inherits the caller's environment, so the docs
  warning is the guardrail. A follow-up could hard-fail the override when
  `CONFIGURATION=release`.
