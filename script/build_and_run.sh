#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LidAwake"
APP_DISPLAY_NAME="Lid Awake"
# Previous pre-release process name kept temporarily for local cleanup.
LEGACY_APP_NAME="AgentAwake"
HELPER_NAME="LidAwakeHelper"
BUNDLE_ID="com.thuongtin.LidAwake"
ASSERTION_REASON="Lid Awake keeping Mac awake"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/$LEGACY_APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
STAGE_SCRIPT="$ROOT_DIR/script/stage_app.sh"

kill_existing_app() {
  /usr/bin/osascript -e "tell application \"$APP_DISPLAY_NAME\" to quit" >/dev/null 2>&1 || true
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  /usr/bin/osascript -e "tell application \"$LEGACY_APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
  pkill -u "$(id -u)" -x "$HELPER_NAME" >/dev/null 2>&1 || true

  for _ in 1 2 3 4 5; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 \
      && ! pgrep -x "$LEGACY_APP_NAME" >/dev/null 2>&1 \
      && ! pgrep -u "$(id -u)" -x "$HELPER_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -9 -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
  pkill -9 -u "$(id -u)" -x "$HELPER_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --stage|stage)
    "$STAGE_SCRIPT"
    ;;
  run)
    kill_existing_app
    rm -rf "$LEGACY_APP_BUNDLE"
    "$STAGE_SCRIPT"
    open_app
    ;;
  --debug|debug)
    kill_existing_app
    rm -rf "$LEGACY_APP_BUNDLE"
    "$STAGE_SCRIPT"
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    kill_existing_app
    rm -rf "$LEGACY_APP_BUNDLE"
    "$STAGE_SCRIPT"
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    kill_existing_app
    rm -rf "$LEGACY_APP_BUNDLE"
    "$STAGE_SCRIPT"
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    kill_existing_app
    rm -rf "$LEGACY_APP_BUNDLE"
    "$STAGE_SCRIPT"
    defaults delete "$BUNDLE_ID" LidAwake.settings >/dev/null 2>&1 || true
    open_app
    for _ in 1 2 3 4 5; do
      sleep 1
      pgrep -x "$APP_NAME" >/dev/null
      if pmset -g assertions | rg "$ASSERTION_REASON" >/dev/null; then
        kill_existing_app
        sleep 1
        if pmset -g assertions | rg "$ASSERTION_REASON" >/dev/null; then
          echo "Lid Awake assertion remained after process exit" >&2
          exit 1
        fi
        "$STAGE_SCRIPT" >/dev/null
        exit 0
      fi
    done
    kill_existing_app
    echo "Lid Awake launched but no wake assertion was observed" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--stage|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
