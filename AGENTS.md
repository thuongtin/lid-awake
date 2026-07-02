# Lid Awake - Agent Guide

Lid Awake is a native macOS menu bar app that keeps a Mac awake during
deliberate local work, optionally managing closed-lid sleep through an
admin-approved privileged helper.

## Verification commands

| Command | Purpose | Safe in CI/sandbox? |
|---------|---------|----------------------|
| `./scripts/check.sh` | Full CI-safe gate: `swift test`, `swift build`, stage via `./script/build_and_run.sh --stage`, then `plutil -lint` the staged `Info.plist`. Run this before finishing any change. | Yes |
| `swift test` | Run the test suite only. | Yes |
| `swift build` | Build all SwiftPM targets. | Yes |
| `./script/build_and_run.sh --stage` | Stage the app bundle without launching it. | Yes |

WARNING: `./scripts/verify.sh` is local-only runtime verification. It may
launch the app, delete `LidAwake.settings` defaults, and read live `pmset`
power assertions. It is never used by CI. Run it only on a developer Mac
where mutating live power-management state is acceptable, never in CI or a
sandbox.

## Repo layout

- `Sources/LidAwake`: menu bar app, settings UI, and app-side services.
- `Sources/LidAwakeCore`: shared policy, parsing, settings, power
  abstractions, and helper XPC contract (fully unit-tested).
- `Sources/LidAwakeHelper`: privileged helper entrypoint for closed-lid mode.
- `script/`: staging and packaging (`stage_app.sh`, `build_and_run.sh`,
  `package_release.sh`, `package_dmg.sh`, `package_appcast.sh`).
- `scripts/`: checks and assets (`check.sh`, `verify.sh`,
  `sparkle_public_key.txt`).
- `plans/`: numbered agent plans plus the status index in
  `plans/README.md`.

## Danger zones

- Privileged helper: `Sources/LidAwakeHelper/` runs `pmset -a disablesleep`
  as root. The trust boundary is documented in `docs/power-model.md`
  ("Helper Trust Boundary"). Changes to `HelperClientAuthorizer`,
  `LidAwakeHelperMain`, or the XPC protocol are security-sensitive and
  require the manual QA checklist in `docs/power-model.md`.
- Power side effects: `pmset -a disablesleep` is a GLOBAL machine setting,
  not scoped to this app. Code that enables it must always restore it; do
  not add a code path that can leave the setting on after the app exits.
- Sparkle keys: only the public key (`scripts/sparkle_public_key.txt`) lives
  in the repo. The Sparkle EdDSA private key must never be committed and
  must never be printed to logs, commit messages, or chat output.
- Release packaging: deliberately manual. `script/package_release.sh` is a
  public release gate that requires a `Developer ID Application` signing
  identity by default; see `docs/releasing.md` before changing it.

## Conventions

- Every system service has a protocol seam plus a fake for tests; see the
  harness in `Tests/LidAwakeTests/AppModelLifecycleTests.swift` for the
  pattern.
- `Sources/LidAwakeCore` behavior is covered by deterministic unit tests with
  no live system dependencies.
- Commit subjects are plain and imperative (e.g. "Add release packaging").
- All shell scripts start with `set -euo pipefail`.
- Code, comments, and log messages are English.

## Plans workflow

Implementation plans live in `plans/`, numbered in execution order. An
executor reads the whole plan before starting, honors any `STOP conditions`
instead of improvising around them, and updates the status row for that plan
in `plans/README.md` when finished.
