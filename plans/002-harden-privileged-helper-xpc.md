# Plan 002: Harden the privileged helper XPC boundary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. Do not improvise around privileged macOS behavior.
>
> **Drift check, run first**: `git status --short && git diff --stat -- Sources/AgentAwakeHelper Sources/AgentAwakeCore Sources/AgentAwake script tests Tests Package.swift`
> Because this repo currently has no commits, compare the "Current state"
> excerpts against the live code before proceeding. On mismatch, stop and ask
> whether this plan should be refreshed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: no commit available, git repo has no commits on 2026-06-24

## Why this matters

The app installs an admin-approved LaunchDaemon helper that can run
`pmset -a disablesleep 1` and `pmset -a disablesleep 0`. Today the helper
accepts any incoming XPC connection and exposes that command directly. Before
publishing this as Open Source, the helper must verify that the caller is the
expected `Lid Awake` app and reject every other local process.

## Current State

Relevant files:

- `Sources/AgentAwakeHelper/AgentAwakeHelperMain.swift` - privileged helper
  listener and exported XPC object.
- `Sources/AgentAwake/ClosedLidHelperService.swift` - app-side privileged XPC
  client.
- `Sources/AgentAwakeCore/AgentAwakeHelperXPCProtocol.swift` - shared Mach
  service name and XPC protocol.
- `script/build_and_run.sh` - stages and signs the app/helper bundle.

Current helper accepts every connection:

```swift
// Sources/AgentAwakeHelper/AgentAwakeHelperMain.swift:7
func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: AgentAwakeHelperXPCProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
}
```

Current helper command surface:

```swift
// Sources/AgentAwakeHelper/AgentAwakeHelperMain.swift:18
func setClosedLidMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
    do {
        try pmsetService.setClosedLidMode(enabled: enabled)
```

Current app-side connection uses the same Mach service:

```swift
// Sources/AgentAwake/ClosedLidHelperService.swift:117
let connection = NSXPCConnection(
    machServiceName: AgentAwakeHelperConstants.machServiceName,
    options: .privileged
)
```

Repo conventions to follow:

- Keep system side effects behind small services.
- Test deterministic logic in `Tests/AgentAwakeCoreTests` with fake adapters.
- User-facing text is English in the app today.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| Tests | `swift test` | exit 0, all tests pass |
| Stage bundle | `./script/build_and_run.sh --stage` | exit 0 and creates `dist/LidAwake.app` |
| Inspect helper plist | `plutil -lint dist/LidAwake.app/Contents/Library/LaunchDaemons/com.thuongtin.LidAwake.Helper.plist` | prints `OK` |

## Scope

In scope:

- `Sources/AgentAwakeHelper/AgentAwakeHelperMain.swift`
- `Sources/AgentAwakeCore/AgentAwakeHelperXPCProtocol.swift`
- New testable helper authorization type, preferably under `Sources/AgentAwakeCore/`
- `Tests/AgentAwakeCoreTests/*`
- `script/build_and_run.sh`
- `docs/power-model.md`

Out of scope:

- Changing the user-facing permission flow.
- Replacing `SMAppService`.
- Adding auto-update, notarization, or distribution changes. Those belong to
  Plan 008.
- Renaming `AgentAwake` targets. That belongs to Plan 006.

## Git Workflow

- Branch: `codex/002-harden-privileged-helper-xpc`
- Commit style: use a concise conventional commit if committing is requested,
  for example `fix: validate helper xpc clients`.
- Do not push or open a PR unless explicitly instructed.

## Steps

### Step 1: Add a testable client authorization layer

Create a small type that decides whether an XPC client process is allowed to
control closed-lid mode. The production path should use Security framework code
to inspect the connecting process by PID and verify its signing identifier or
bundle identifier matches `com.thuongtin.LidAwake`.

Implementation guidance:

- Keep the low-level Security calls behind a protocol such as
  `CodeSigningInfoProviding`.
- Use `SecCodeCopyGuestWithAttributes` with `kSecGuestAttributePid` to read the
  client code signing information.
- Reject clients when code signing info cannot be read.
- Avoid a release-mode insecure fallback. If a local debug fallback is needed,
  gate it behind an explicit build-time flag and document that it is not used
  for release staging.

Add unit tests for the pure authorization decision:

- accepts expected app identifier
- rejects wrong identifier
- rejects missing identifier
- rejects provider failure

**Verify**: `swift test --filter Helper` should run the new tests if a filter is
possible. If the filter finds no tests because of naming, run `swift test` and
confirm the new tests are listed and pass.

### Step 2: Enforce authorization in the helper listener

Update `HelperService.listener(_:shouldAcceptNewConnection:)` so it validates
the connection before setting `exportedInterface` and `exportedObject`.

Expected behavior:

- Authorized app connection returns `true`.
- Unauthorized connection returns `false` and does not call `resume()`.
- Log rejection with PID and no sensitive data.

Do not rely on the caller passing an identifier over XPC. The helper must verify
the OS-level connection identity.

**Verify**: `swift build` exits 0.

### Step 3: Make staging produce identities that authorization can verify

Update `script/build_and_run.sh` so staged debug bundles expose stable code
signing identifiers for both app and helper.

Current staging signs helper with:

```bash
# script/build_and_run.sh:113
codesign --force --sign - --identifier "$HELPER_LABEL" "$HELPER_BINARY" >/dev/null
codesign --force --sign - "$APP_BUNDLE" >/dev/null
```

Keep ad-hoc signing for local development if needed, but make sure the app
bundle identity is visible to the helper authorization logic. If that is not
possible with ad-hoc signing on this macOS version, stop and report rather than
shipping a permissive fallback.

**Verify**:

```bash
./script/build_and_run.sh --stage
codesign -dv dist/LidAwake.app 2>&1 | rg 'Identifier=com.thuongtin.LidAwake'
codesign -dv dist/LidAwake.app/Contents/Library/LaunchServices/LidAwakeHelper 2>&1 | rg 'Identifier=com.thuongtin.LidAwake.Helper'
```

Expected: both `rg` commands find the matching identifiers.

### Step 4: Document the helper trust boundary

Update `docs/power-model.md` with a short section explaining:

- the helper only accepts the bundled `Lid Awake` app as a client
- the helper only exposes read status and set closed-lid mode operations
- unauthorized local clients are rejected

**Verify**: `rg 'helper|client|unauthorized|com.thuongtin.LidAwake' docs/power-model.md`
prints the new section.

## Test Plan

- Add unit tests for the authorization decision using fake code-signing info.
- Add at least one helper listener test if the code is factored so it can be
  tested without constructing a real privileged XPC service.
- Keep existing `PMSetServiceTests` unchanged unless their helpers are reused.
- Run `swift test` after all changes.

## Done Criteria

- [ ] `swift build` exits 0.
- [ ] `swift test` exits 0 and includes new helper authorization tests.
- [ ] `./script/build_and_run.sh --stage` exits 0.
- [ ] `codesign -dv` on app and helper shows expected identifiers.
- [ ] The helper rejects clients whose identity is not the expected app.
- [ ] No release-mode insecure fallback accepts arbitrary clients.
- [ ] `docs/power-model.md` documents the helper trust boundary.
- [ ] `plans/README.md` status row for Plan 002 is updated.

## STOP Conditions

Stop and report if:

- macOS APIs available to this SwiftPM target cannot verify client identity.
- The staged app cannot expose a stable identifier without a larger packaging
  change.
- The fix requires changing bundle IDs or target names. That belongs to
  Plan 006.
- Verification fails twice after a reasonable fix attempt.

## Maintenance Notes

Reviewers should scrutinize every acceptance path in
`listener(_:shouldAcceptNewConnection:)`. For future helper methods, do not add
new privileged operations until the client identity check is shared and tested.
