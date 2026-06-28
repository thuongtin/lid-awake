# Plan 011: Bind helper authorization to Team ID

> Executor instructions: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If a STOP condition occurs, stop and report.
>
> Drift check: `git diff --stat 3465524..HEAD -- Sources/LidAwakeCore/HelperClientAuthorizer.swift Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift docs/power-model.md docs/developer-permissions.md`

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: none
- Category: security
- Planned at: commit `3465524`, 2026-06-28
- Execution status: DONE

## Why this matters

The privileged LaunchDaemon helper can run `pmset -a disablesleep 1` and `pmset -a disablesleep 0`. The current authorization accepts a client when its signing identifier or bundle identifier equals `com.thuongtin.LidAwake`, but it does not bind that identity to a Team ID or designated requirement. A different local app could reuse the same identifier unless the helper also validates the signing team.

## Current state

- `Sources/LidAwakeCore/HelperClientAuthorizer.swift` contains `CodeSigningInfo` and the pure authorization decision.
- `Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift` covers identifier allow and deny cases.
- `docs/power-model.md` and `docs/developer-permissions.md` describe the helper trust boundary.

Current authorization:

```swift
// Sources/LidAwakeCore/HelperClientAuthorizer.swift:43
return info.signingIdentifier == allowedIdentifier
    || info.bundleIdentifier == allowedIdentifier
```

Current tests do not include team identity:

```swift
// Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift:5
func testAcceptsExpectedAppIdentifier() {
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Targeted tests | `swift test --filter HelperClientAuthorizerTests` | exit 0 |
| Full tests | `swift test` | exit 0, 82 or more tests pass |
| Build | `swift build` | exit 0 |

## Scope

In scope:

- `Sources/LidAwakeCore/HelperClientAuthorizer.swift`
- `Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift`
- `docs/power-model.md`
- `docs/developer-permissions.md`

Out of scope:

- Changing helper XPC method names.
- Changing bundle identifiers.
- Adding a permissive fallback for ad-hoc release builds.

## Steps

### Step 1: Add Team ID to signing info

Extend `CodeSigningInfo` with `teamIdentifier: String?`. Update `SecurityCodeSigningInfoProvider` to read `kSecCodeInfoTeamIdentifier`.

Verify: `swift build` exits 0.

### Step 2: Require matching Team ID

Update `HelperClientAuthorizer` so it accepts a client only when:

- the client identifier matches `com.thuongtin.LidAwake`
- the client Team ID matches an explicit allowed Team ID or the helper process Team ID
- the Team ID is present

Verify: `swift test --filter HelperClientAuthorizerTests` exits 0.

### Step 3: Add regression tests

Add tests for same Team ID accepted, wrong Team ID rejected, missing client Team ID rejected, and missing helper Team ID rejected.

Verify: `swift test --filter HelperClientAuthorizerTests` exits 0.

### Step 4: Document the trust boundary

Update docs to say the helper validates both bundle identifier and Team ID.

Verify: `rg 'Team ID|team identifier|com.thuongtin.LidAwake' docs/power-model.md docs/developer-permissions.md` prints the new text.

## Done criteria

- `swift build` exits 0.
- `swift test` exits 0.
- Helper authorization tests cover Team ID mismatch and missing Team ID.
- Docs mention Team ID binding.

## STOP conditions

- Security framework APIs cannot provide a Team ID for identified builds.
- The fix requires accepting arbitrary ad-hoc clients in release mode.
