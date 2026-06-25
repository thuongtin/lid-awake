# Plan 001: Build a native macOS menu bar app that keeps coding agents awake safely

> **Historical note**: this plan was executed against an empty workspace and is
> no longer a current implementation plan. **Do not execute** it against the
> existing SwiftPM app. Use plans 002 and later for Open Source readiness work.
> The stale greenfield claims below are preserved only as project history.

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report. Do not improvise around system power behavior.
>
> **Drift check, run first**: `find . -maxdepth 2 -type f | sort && git rev-parse --is-inside-work-tree 2>/dev/null || true`
>
> This plan was written for an empty greenfield workspace. If you see existing app source such as `*.xcodeproj`, `Package.swift`, `AgentAwake/`, `Sources/`, `Tests/`, or any non-plan product files, stop and ask the operator whether to adapt this plan to that repository before creating files.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: direction
- **Planned at**: no git commit available, workspace was not a git repository on 2026-06-24

## Why This Matters

The product goal is a native macOS app similar in spirit to Hold My Lid: keep a Mac awake only while coding agents are doing real work, then release assertions quickly to save battery. The highest product risk is not the menu bar UI, it is power safety: the app must acquire and release wake locks deterministically, respect battery thresholds, and be honest about closed-lid limits. This plan builds a production-shaped MVP without privileged helper tools, payment, updater, or global `pmset` changes, so the team can validate the core behavior before adding riskier features.

## Current State

- The current workspace contains only `plans/`, `work/`, and `outputs/`. There is no Xcode project, Swift package, source file, test target, CI, or git history.
- The app should be native macOS, not Electron. Use Swift, SwiftUI for settings, AppKit where needed for status item behavior, notifications, login items, and lower-level integration.
- Target macOS 14.0 or later for the MVP. This matches the public Hold My Lid website metadata observed during recon and keeps the implementation aligned with modern SwiftUI menu bar APIs.
- The MVP must use IOKit power assertions directly. Do not shell out to `caffeinate` for app behavior. `caffeinate` is useful only as a reference and manual comparison tool.
- The MVP must not call `sudo`, must not run `pmset disablesleep`, must not install a privileged helper, and must not change global power settings. Deep closed-lid behavior on battery is a deferred feature.
- User-facing product truth for MVP: "Agent-aware idle sleep prevention with battery guardrails. Closed-lid behavior depends on macOS power policy and hardware state; deep closed-lid hold is not enabled in this version."
- Source conventions to establish:
  - Code, symbols, file names, log messages, and inline comments are English.
  - Plan, docs, and operator-facing status can be Vietnamese if the operator requests it, but app UI strings may be English until localization is planned.
  - Service logic should be testable behind protocols. UI should not call IOKit or process enumeration directly.
  - Every system side effect must flow through one of these services: `PowerAssertionManager`, `BatteryMonitor`, `AgentActivityMonitor`, `WakePolicyCoordinator`, `NotificationService`.

## Commands You Will Need

Because the repo is greenfield, these commands become available after Step 1 creates the project.

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Confirm Xcode tools | `xcodebuild -version` | exit 0 and prints Xcode version |
| Build app | `xcodebuild -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` | exit 0 with `BUILD SUCCEEDED` |
| Run tests | `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | exit 0 with all tests passing |
| Inspect assertions manually | `pmset -g assertions | rg 'AgentAwake|PreventUserIdle'` | when app is actively holding wake lock, output includes `AgentAwake` and a prevent-idle assertion |
| Check changed files | `git status --short` | only in-scope files changed, if a git repo exists |

## Suggested Executor Toolkit

- If XcodeBuildMCP tools are available, use them for project discovery, build, test, and run instead of ad hoc shell commands. For the first simulator or macOS build call in that environment, follow its default-session setup requirements.
- Keep Apple documentation open for IOKit power assertions: https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep
- Keep Apple support documentation open for user-facing closed-lid wording: https://support.apple.com/en-us/102501

## Scope

**In scope, the only product files you should create or modify**:

- `AgentAwake.xcodeproj/**`
- `AgentAwake/**`
- `AgentAwakeTests/**`
- `AgentAwakeUITests/**` only if Xcode scaffolds it automatically; otherwise skip UI tests for MVP
- `docs/power-model.md`
- `scripts/verify.sh`
- `plans/README.md` status row only, at the end

**Out of scope, do not touch or add**:

- Privileged helper tools, launch daemons, kernel extensions, driver extensions, or any `SMJobBless` flow.
- Any call to `sudo`, `pmset disablesleep`, `pmset sleep 0`, or global system power setting mutation.
- Payment, license activation, trial logic, marketing site, analytics, telemetry, or auto-update.
- Auto-modifying user agent configs for Claude Code, Codex, OpenCode, Gemini, Cursor, or Cline. The MVP may show copyable hook commands, but the user must install them manually.
- App Store submission work. Direct distribution with Developer ID and notarization can be planned later.

## Git Workflow

- If no git repo exists, initialize one only if the operator asked you to manage git. Otherwise create files in place and leave git alone.
- If a git repo exists, create branch `advisor/001-native-macos-agent-awake-app`.
- Commit style if committing is requested later: conventional commits, for example `feat: add agent-aware wake coordinator`.
- Do not push, open a PR, or publish anything unless the operator explicitly instructs you.

## Steps

### Step 1: Create the native macOS app skeleton

Create a new Xcode macOS App project named `AgentAwake` with Swift and SwiftUI. Set deployment target to macOS 14.0. The app should be an agent-only style menu bar utility:

- `AgentAwake/AgentAwakeApp.swift` - app entry point.
- `AgentAwake/App/AppState.swift` - central observable app state.
- `AgentAwake/App/AppServices.swift` - dependency container for service protocols and concrete services.
- `AgentAwake/UI/MenuBarView.swift` - menu bar dropdown content.
- `AgentAwake/UI/SettingsView.swift` - settings window.
- `AgentAwake/Models/*.swift` - plain data models.
- `AgentAwake/Services/*.swift` - system integration services.
- `AgentAwakeTests/*Tests.swift` - unit tests for models and coordinator.

Use `MenuBarExtra` for the MVP if it provides enough control. If it cannot support required menu actions cleanly, use `NSStatusItem` via AppKit, but keep UI state in Swift types rather than scattering state in AppKit delegates.

Add `scripts/verify.sh`:

```sh
#!/bin/sh
set -eu
xcodebuild -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

**Verify**: `xcodebuild -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` -> exit 0 with `BUILD SUCCEEDED`.

### Step 2: Define the domain model and service protocols

Create testable domain types before touching IOKit:

- `Models/AgentKind.swift`: cases `claudeCode`, `codexCli`, `openCode`, `gemini`, `cursor`, `cline`, `unknown`.
- `Models/AgentSession.swift`: `id`, `kind`, `displayName`, `state`, `source`, `lastEventAt`, `processIdentifier`.
- `Models/AgentState.swift`: `working`, `idle`, `finished`, `unknown`.
- `Models/BatteryState.swift`: `percent`, `isCharging`, `isOnACPower`, `isLowPowerModeEnabled`.
- `Models/WakeHoldReason.swift`: fields for active sessions and guardrail explanation.
- `Models/UserSettings.swift`: `enabled`, `batteryCutoffPercent`, `onlyWhenPluggedIn`, `respectLowPowerMode`, `idleReleaseDelaySeconds`, `preventDisplaySleep`, `pauseUntil`.

Create protocols:

- `PowerAssertionControlling`: acquire and release wake assertions.
- `BatteryMonitoring`: publish `BatteryState`.
- `AgentActivityMonitoring`: publish `[AgentSession]`.
- `NotificationSending`: send local notifications.
- `Clock`: provide current time and timers for deterministic tests.

Add unit tests for default settings:

- default app is enabled
- default battery cutoff is 20 percent
- default idle release delay is 30 seconds
- default `respectLowPowerMode` is true
- default does not enable any deep closed-lid override

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0 and includes the new model/settings tests.

### Step 3: Implement `PowerAssertionManager` with IOKit assertions

Create `Services/PowerAssertionManager.swift`. It must:

- Import IOKit power management APIs.
- Acquire `kIOPMAssertionTypePreventUserIdleSystemSleep` when policy says the Mac should stay awake.
- Optionally acquire `kIOPMAssertionTypePreventUserIdleDisplaySleep` when user setting `preventDisplaySleep` is true.
- Store assertion IDs separately for system and display assertions.
- Release every active assertion when policy changes, the app disables, app terminates, or acquisition fails halfway.
- Be idempotent: repeated acquire calls while already held should not create duplicate assertions.
- Log reason strings as `AgentAwake keeping Mac awake for coding agents`.
- Never use shell commands.

Add unit tests with a fake IOKit adapter rather than calling real IOKit in tests. Cover:

- acquire creates only one system assertion when called twice
- release releases all active assertions once
- partial display assertion failure releases the system assertion
- disabled display sleep setting does not acquire display assertion

Manual test command after running the app with an active fake or real session:

`pmset -g assertions | rg 'AgentAwake|PreventUserIdle'`

Expected: output includes the app reason while active, and no app-owned assertion after the session goes idle and the release delay expires.

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0 with `PowerAssertionManagerTests` passing.

### Step 4: Implement battery and Low Power Mode guardrails

Create `Services/BatteryMonitor.swift`. It should read battery and AC state using IOKit power source APIs and Low Power Mode using `ProcessInfo.processInfo.isLowPowerModeEnabled`. It should publish state changes through Combine or Swift observation. Choose one app-wide observation approach and use it consistently.

Guardrail rules:

- If `onlyWhenPluggedIn` is true and the machine is not on AC power, do not hold wake assertions.
- If `respectLowPowerMode` is true and Low Power Mode is enabled, do not hold wake assertions unless the user explicitly disables that guardrail in settings.
- If battery percent is less than or equal to `batteryCutoffPercent` and not charging, release assertions and notify once per threshold crossing.
- If battery information is unavailable on a desktop Mac, treat it as AC power and do not block wake assertions for missing battery data.

Add tests using fake battery state:

- below threshold releases hold
- charging below threshold can hold if policy allows
- Low Power Mode blocks hold by default
- desktop/no battery does not behave as critical battery

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0 with `BatteryGuardrailTests` passing.

### Step 5: Implement agent activity detection with hook events and process fallback

Create `Services/AgentActivityMonitor.swift` with two inputs:

1. Hook events, for precise lifecycle state.
2. Process detection, for fallback when hooks are not installed.

For MVP hook ingestion, prefer a local file queue over a privileged service:

- Store hook events in `~/Library/Application Support/AgentAwake/events/events.jsonl`.
- Each line is a JSON object with `schemaVersion`, `agentKind`, `sessionId`, `state`, `timestamp`, and optional `cwd`.
- Add strict validation. Unknown fields are ignored. Unknown states are rejected. Do not execute any content from hook events.
- Provide a copyable shell command in Settings that appends a valid event through a bundled helper path or a documented `osascript`/URL handoff. If the helper path cannot be robustly bundled in the first version, use process detection for MVP and create a visible "hooks coming next" disabled section instead of inventing a brittle installer.

For process detection:

- Detect known process names and app bundle identifiers for `Claude Code`, `codex`, `opencode`, `gemini`, `Cursor`, and `Cline`.
- Treat process detection as `working while process alive` only. Mark its source as `processDetection` so UI can explain it is less precise.
- Poll at a conservative interval such as 5 seconds. Do not scan the full filesystem. Use `NSWorkspace.shared.runningApplications` and process metadata where possible.

Add tests for hook parsing and session state transitions:

- working event creates or updates a session
- idle event marks the session idle
- finished event marks session finished
- malformed JSON is rejected without changing state
- process-detected sessions are clearly marked as fallback

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0 with agent monitor tests passing.

### Step 6: Implement the wake policy coordinator

Create `Services/WakePolicyCoordinator.swift`. It is the only place that decides whether to acquire or release power assertions.

Policy:

- Hold wake assertions when:
  - app is enabled
  - current time is not before `pauseUntil`
  - at least one watched session is `working`
  - battery and Low Power Mode guardrails allow it
- Release wake assertions when:
  - no session is working for `idleReleaseDelaySeconds`
  - app disabled
  - pause selected
  - battery cutoff hit
  - Low Power Mode blocks it
  - app is terminating

The coordinator should expose a simple status:

- `inactive`
- `watching`
- `holding(reason)`
- `paused(until)`
- `blocked(reason)`

Add tests with fake clock, fake battery, fake sessions, and fake power controller:

- starts holding when first session becomes working
- does not release immediately on idle until 30 second delay
- releases after delay
- pause releases immediately and suppresses reacquire until expiration
- battery cutoff releases immediately
- multiple working sessions keep hold until all are idle or finished

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0 with `WakePolicyCoordinatorTests` passing.

### Step 7: Build the menu bar UI and settings UI

Create menu bar UI with these controls and states:

- Current status line: inactive, watching, holding, paused, or blocked.
- Battery row: percent, AC/charging state, cutoff.
- Active sessions list: agent name, source `hooks` or `process`, working/idle state, last update.
- Toggle: enable or disable app.
- Pause actions: 30 minutes, 1 hour, until tomorrow morning.
- Settings action.
- Quit action.

Create settings UI:

- General: enable app, launch at login placeholder if not implemented.
- Agents: list supported agents and whether hooks or process detection is active.
- Battery: cutoff slider, only-when-plugged-in toggle, respect-Low-Power-Mode toggle.
- Display: prevent display sleep toggle, display-off guidance text. Do not implement display power-off automation unless it is safe and tested.
- Safety: explicit explanation that MVP does not change global lid sleep settings and cannot guarantee deep closed-lid operation on battery.
- Advanced: show copied hook command if hook ingestion is implemented; otherwise show planned but disabled hook installer.

The UI must not contain marketing copy or a landing page. It is a compact utility surface.

**Verify**: run the app from Xcode or with XcodeBuildMCP, open the menu, and confirm all actions are visible without text overlap. Then run `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0.

### Step 8: Add notifications and chimes

Create `Services/NotificationService.swift` using `UserNotifications`.

Notify for:

- wake hold engaged
- all agents idle or finished and assertions released
- battery cutoff hit
- Low Power Mode blocked hold

Do not spam:

- Deduplicate the same notification reason for a reasonable window such as 10 minutes.
- Request notification permission lazily when the first notification would be useful, or provide an explicit settings button.
- Chimes are optional in MVP. If implemented, use bundled system-safe sounds and a setting to disable them.

Add tests for deduplication logic using a fake notification sender.

**Verify**: `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> exit 0, and manual run can trigger one notification per transition.

### Step 9: Document the power model and deferred deep hold work

Create `docs/power-model.md` with:

- What the MVP does: native IOKit idle sleep and optional display sleep assertions.
- What it does not do: no global `pmset`, no privileged helper, no guaranteed closed-lid-on-battery hold.
- Safety defaults: 20 percent battery cutoff, Low Power Mode respected, release after 30 seconds idle.
- Manual QA checklist:
  - app disabled: no app-owned assertion in `pmset -g assertions`
  - one working session: app-owned prevent idle assertion appears
  - session idle: assertion releases after 30 seconds
  - battery guardrail fake/manual path releases
  - quit app releases all assertions
- Future plan trigger: only consider "Deep Hold" after MVP assertions are reliable. That future plan must include admin permission UX, crash-safe rollback, thermal/battery warnings, and restore commands.

**Verify**: `test -f docs/power-model.md && rg 'pmset|IOKit|battery cutoff|Low Power Mode|closed-lid' docs/power-model.md` -> exit 0 with matches.

### Step 10: Run full verification and update the plan index

Run:

```sh
./scripts/verify.sh
```

Expected: build and tests pass with exit 0.

Run:

```sh
pmset -g assertions | rg 'AgentAwake|PreventUserIdle' || true
```

Expected when the app is not actively holding: no app-owned assertion. Expected when a working session is simulated and the app is running: app-owned prevent idle assertion appears.

If this workspace is a git repo, run:

```sh
git status --short
```

Expected: only files listed in Scope are changed.

Update `plans/README.md` row for Plan 001 to `DONE` only after all done criteria pass. Use `BLOCKED` with a one-line reason if any STOP condition occurred.

## Test Plan

Create unit tests first for the parts that can be deterministic:

- `AgentAwakeTests/UserSettingsTests.swift`: default safety settings.
- `AgentAwakeTests/PowerAssertionManagerTests.swift`: fake IOKit adapter behavior and idempotency.
- `AgentAwakeTests/BatteryGuardrailTests.swift`: threshold, AC, charging, Low Power Mode, no-battery desktop behavior.
- `AgentAwakeTests/AgentActivityMonitorTests.swift`: hook JSON parsing, malformed input, state transitions.
- `AgentAwakeTests/WakePolicyCoordinatorTests.swift`: acquire/release policy, idle delay, pause, battery cutoff, multiple sessions.
- `AgentAwakeTests/NotificationServiceTests.swift`: dedupe and transition reasons.

Manual QA after tests:

- Launch app and verify menu bar status appears.
- Toggle enabled off and confirm assertions release.
- Simulate or create a working session and confirm `pmset -g assertions` shows app-owned prevent-idle assertion.
- Mark session idle or finished and confirm assertion releases after default delay.
- Trigger battery cutoff through fake/debug injection if available. If no debug injection exists, document that battery cutoff is covered by unit tests and manual battery QA is deferred.
- Quit app and confirm no app-owned assertion remains.

## Done Criteria

All must hold:

- [ ] `xcodebuild -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` exits 0.
- [ ] `xcodebuild test -project AgentAwake.xcodeproj -scheme AgentAwake -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` exits 0.
- [ ] `./scripts/verify.sh` exits 0.
- [ ] Unit tests exist for settings, power assertion manager, battery guardrails, agent activity monitor, wake policy coordinator, and notification dedupe.
- [ ] The app uses IOKit APIs directly for wake assertions and does not shell out to `caffeinate`.
- [ ] The codebase contains no call to `sudo`, `pmset disablesleep`, `pmset sleep 0`, or privileged helper installation.
- [ ] Manual active-session QA shows an `AgentAwake` owned assertion in `pmset -g assertions`.
- [ ] Manual idle/quit QA shows the `AgentAwake` assertion is released.
- [ ] `docs/power-model.md` exists and clearly documents closed-lid limitations.
- [ ] No files outside Scope are modified, if a git repo exists.
- [ ] `plans/README.md` status row is updated.

## STOP Conditions

Stop and report back if:

- The drift check finds an existing app repo or source tree. This plan is greenfield and must be adapted before editing existing code.
- `xcodebuild -version` fails or Xcode command line tools are unavailable.
- A requirement appears to need `sudo`, `pmset disablesleep`, `SMJobBless`, a LaunchDaemon, or a privileged helper to satisfy MVP acceptance.
- The app cannot create or release IOKit assertions reliably in manual QA.
- Any step requires changing files outside Scope.
- The operator asks for App Store submission, payment, licensing, auto-update, or deep closed-lid battery behavior during this plan. Those need separate plans.
- A verification command fails twice after a reasonable local fix attempt.

## Maintenance Notes

- Reviewers should scrutinize power assertion lifetime. Every acquisition path must have a release path on idle, pause, disable, guardrail block, and app termination.
- Reviewers should check that UI never overpromises closed-lid behavior. The MVP can prevent idle sleep, but deep closed-lid behavior depends on macOS power policy and hardware state.
- Future agent integrations should add precise hooks first and process detection second. Process detection is a fallback and should remain clearly labeled.
- Future "Deep Hold" should be designed as a separate opt-in capability with explicit admin permission, crash recovery, rollback, and thermal/battery warnings.
- If payments or licensing are added later, keep them outside the wake policy path. A license failure must not leave assertions held.
