# Plan 018: Enforce an OS-verified code-signing requirement on helper XPC connections

> Executor instructions: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If a
> STOP condition occurs, stop and report - do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> Drift check (run first): `git diff --stat 5d89d38..HEAD -- Sources/LidAwakeHelper/LidAwakeHelperMain.swift Sources/LidAwakeCore/HelperClientAuthorizer.swift Sources/LidAwakeCore/LidAwakeHelperXPCProtocol.swift Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift`
> This plan was written at commit `5d89d38`. If any in-scope file changed since,
> compare the "Current state" excerpts against the live code before proceeding;
> on a mismatch, treat it as a STOP condition.

## Status

- Priority: P1
- Effort: M
- Risk: MED
- Depends on: none
- Category: security
- Planned at: commit `5d89d38`, 2026-07-02
- Execution status: TODO

## Why this matters

The privileged helper runs `pmset -a disablesleep` as root and authorizes XPC
clients by reading code-signing info for `connection.processIdentifier`
(a PID). PID-based checks are the known-weak pattern for XPC authorization:
a PID can be reused between the moment the helper validates it and the moment
messages are processed, and the check runs once at accept time rather than
being enforced by the OS per message. macOS 13+ provides
`NSXPCConnection.setCodeSigningRequirement(_:)`, which makes the kernel verify
the peer against a code-signing requirement for the lifetime of the
connection. This repo targets macOS 14, so the API is always available. The
existing PID check stays as defense in depth; this plan adds the OS-enforced
layer on top. Impact is bounded (the helper only exposes two fixed pmset
operations) but this is the correct hardening for a root helper.

## Current state

- `Sources/LidAwakeHelper/LidAwakeHelperMain.swift` - the whole helper (39
  lines). The accept gate today:

```swift
// Sources/LidAwakeHelper/LidAwakeHelperMain.swift:8-19
func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    let processID = connection.processIdentifier
    guard clientAuthorizer.isAuthorized(processID: processID) else {
        NSLog("Rejected helper XPC connection from PID \(processID)")
        return false
    }

    connection.exportedInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
}
```

- `Sources/LidAwakeCore/HelperClientAuthorizer.swift` - PID-based authorizer.
  Key behavior to preserve: it requires BOTH an identifier match and a
  non-empty Team ID match. When the helper build has no Team ID (ad-hoc
  signing), `expectedTeamIdentifier()` returns nil and `isAuthorized` returns
  false for every client:

```swift
// Sources/LidAwakeCore/HelperClientAuthorizer.swift:44-64
public func isAuthorized(processID: pid_t) -> Bool {
    guard let info = try? provider.codeSigningInfo(forProcessID: processID) else {
        return false
    }

    guard info.signingIdentifier == allowedIdentifier
        || info.bundleIdentifier == allowedIdentifier else {
        return false
    }

    guard
        let expectedTeamIdentifier = expectedTeamIdentifier(),
        !expectedTeamIdentifier.isEmpty,
        let clientTeamIdentifier = info.teamIdentifier,
        !clientTeamIdentifier.isEmpty
    else {
        return false
    }

    return clientTeamIdentifier == expectedTeamIdentifier
}
```

- `Sources/LidAwakeCore/LidAwakeHelperXPCProtocol.swift` - constants:
  `clientBundleIdentifier = "com.thuongtin.LidAwake"`,
  `machServiceName = "com.thuongtin.LidAwake.Helper"`.
- `SecurityCodeSigningInfoProvider.currentProcessCodeSigningInfo()` (same
  file as the authorizer) already gives the helper its own
  `teamIdentifier` - reuse it, do not write new SecCode plumbing.
- The documented trust boundary (`docs/power-model.md`, "Helper Trust
  Boundary") says: "The privileged helper accepts XPC clients only when macOS
  code signing information identifies the client as the bundled Lid Awake app
  with identifier com.thuongtin.LidAwake and a Team ID matching the helper
  build." This plan strengthens the mechanism without changing that contract.
- Repo conventions: pure logic lives in `LidAwakeCore` with unit tests in
  `Tests/LidAwakeCoreTests`; the helper main stays minimal. Error/edge tests
  follow the style of `Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Full tests | `swift test` | exit 0, all tests pass |
| Build all targets | `swift build` | exit 0 |
| Full local gate | `./scripts/check.sh` | exit 0 |
| Filter new tests | `swift test --filter HelperCodeSigningRequirementTests` | new tests pass |

## Scope

In scope (the only files you should modify):

- `Sources/LidAwakeCore/HelperCodeSigningRequirement.swift` (create)
- `Sources/LidAwakeHelper/LidAwakeHelperMain.swift`
- `Tests/LidAwakeCoreTests/HelperCodeSigningRequirementTests.swift` (create)
- `docs/power-model.md` (one paragraph in "Helper Trust Boundary")

Out of scope (do NOT touch, even though they look related):

- `Sources/LidAwakeCore/HelperClientAuthorizer.swift` - the PID check stays
  exactly as is (defense in depth and ad-hoc-build parity).
- `Sources/LidAwake/ClosedLidHelperService.swift` - the app-side client does
  not change.
- The XPC protocol surface (`LidAwakeHelperXPCProtocol`) - no new operations.

## Git workflow

- Branch: `advisor/018-xpc-code-signing-requirement`. Plain imperative commit
  subjects (match `git log`, e.g. "Harden helper and release readiness").
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the requirement-string builder to LidAwakeCore

Create `Sources/LidAwakeCore/HelperCodeSigningRequirement.swift` with a pure,
testable builder. Target shape:

```swift
import Foundation

public enum HelperCodeSigningRequirement {
    /// Builds a code signing requirement string that pins the XPC peer to the
    /// Lid Awake app identifier, an Apple-anchored certificate chain, and the
    /// helper's own Team ID. Returns nil when the helper build has no Team ID
    /// (ad-hoc signing), which matches HelperClientAuthorizer rejecting all
    /// clients in that configuration.
    public static func requirement(
        bundleIdentifier: String = LidAwakeHelperConstants.clientBundleIdentifier,
        teamIdentifier: String?
    ) -> String? {
        guard let teamIdentifier, !teamIdentifier.isEmpty else {
            return nil
        }
        guard isSafeRequirementAtom(bundleIdentifier), isSafeRequirementAtom(teamIdentifier) else {
            return nil
        }
        return "identifier \"\(bundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func isSafeRequirementAtom(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }
}
```

The `isSafeRequirementAtom` guard exists so a malformed identifier can never
inject requirement-language syntax through the quoted string.

Verify: `swift build` -> exit 0.

### Step 2: Unit-test the builder

Create `Tests/LidAwakeCoreTests/HelperCodeSigningRequirementTests.swift`
covering at least:

- Team ID present: returns the exact expected string for
  (`com.thuongtin.LidAwake`, `ABCDE12345`).
- Nil Team ID: returns nil.
- Empty Team ID: returns nil.
- Team ID containing a quote or space (for example `AB\"CD`): returns nil.
- Bundle identifier containing a quote: returns nil.

Model the file structure after
`Tests/LidAwakeCoreTests/HelperClientAuthorizerTests.swift` (plain XCTest,
no harness needed).

Verify: `swift test --filter HelperCodeSigningRequirementTests` -> all pass.

### Step 3: Apply the requirement in the helper accept gate

In `Sources/LidAwakeHelper/LidAwakeHelperMain.swift`:

1. Give `HelperService` a stored requirement, computed once at init from the
   helper's own signing info:

```swift
private let codeSigningRequirement: String? = {
    let info = try? SecurityCodeSigningInfoProvider().currentProcessCodeSigningInfo()
    return HelperCodeSigningRequirement.requirement(teamIdentifier: info?.teamIdentifier)
}()
```

2. In `listener(_:shouldAcceptNewConnection:)`, keep the existing
   `clientAuthorizer.isAuthorized(processID:)` guard unchanged, then require
   the OS-enforced pin before configuring the connection:

```swift
guard let codeSigningRequirement else {
    NSLog("Rejected helper XPC connection: helper build has no Team ID")
    return false
}

do {
    try connection.setCodeSigningRequirement(codeSigningRequirement)
} catch {
    NSLog("Rejected helper XPC connection: could not apply code signing requirement")
    return false
}
```

Notes for this step:

- `setCodeSigningRequirement(_:)` is available on macOS 13.0+; the package
  targets macOS 14, so no availability guard is needed. If the compiler
  disagrees, see STOP conditions.
- The call must happen BEFORE `connection.resume()`.
- Behavior parity: an ad-hoc helper build already rejects every client via
  `HelperClientAuthorizer` (nil team). The new nil-requirement guard makes the
  same outcome explicit, so no configuration that worked before stops working.

Verify: `swift build` -> exit 0.

### Step 4: Update the trust boundary doc

In `docs/power-model.md`, section "Helper Trust Boundary", add one sentence
after the existing first paragraph, in the document's plain style, stating
that in addition to the accept-time code-signing check, the helper pins each
connection with an OS-enforced code signing requirement
(identifier + Apple anchor + Team ID) so the peer is re-verified by macOS for
the lifetime of the connection.

Verify: `grep -n "setCodeSigningRequirement\|code signing requirement" docs/power-model.md` -> at least one match.

### Step 5: Full gate

Verify: `./scripts/check.sh` -> exit 0 (all tests, build, staging, plist lint).

## Test plan

- New file `Tests/LidAwakeCoreTests/HelperCodeSigningRequirementTests.swift`
  with the five cases in step 2.
- Existing `HelperClientAuthorizerTests` must pass unchanged (the PID path is
  untouched).
- Runtime QA (cannot run in CI; note for the maintainer, do not attempt in a
  sandbox): on a Developer ID or Apple Development signed build, set up the
  helper, enable closed-lid mode, and confirm `pmset -g` reports
  `SleepDisabled 1` - this proves the legitimate app still passes the
  requirement. This is the manual QA checklist in `docs/power-model.md`,
  items 3-4.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift test` exits 0; `HelperCodeSigningRequirementTests` exists with >= 5 test methods
- [ ] `grep -n "setCodeSigningRequirement" Sources/LidAwakeHelper/LidAwakeHelperMain.swift` -> exactly one match, located before `connection.resume()`
- [ ] `grep -n "isAuthorized(processID:" Sources/LidAwakeHelper/LidAwakeHelperMain.swift` -> still present (PID check retained)
- [ ] `./scripts/check.sh` exits 0
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The compiler reports `setCodeSigningRequirement` unavailable or requires an
  availability guard on the macOS 14 target: report the exact diagnostic
  instead of switching to a different API.
- The accept-gate code in `LidAwakeHelperMain.swift` does not match the
  "Current state" excerpt.
- You find yourself wanting to modify `HelperClientAuthorizer.swift` or the
  app-side `ClosedLidHelperService.swift`: that is out of scope.
- Any existing test fails after your change and one reasonable fix attempt.

## Maintenance notes

- If the app's bundle identifier or Team ID ever changes, the requirement
  string derives both at helper startup, so no code change is needed; but the
  helper and app must be signed with the same Team ID (already true today).
- A reviewer should scrutinize the exact requirement string: `identifier`,
  `anchor apple generic`, and `certificate leaf[subject.OU]` are the three
  clauses; a typo silently rejects the legitimate app, which shows up as the
  in-app "Lid Awake Helper did not respond" timeout error.
- Deferred (out of scope here): migrating the accept-time check from PID to
  audit-token-based SecCode lookup. `setCodeSigningRequirement` already
  closes the PID-reuse race; the audit-token migration would be polish.
