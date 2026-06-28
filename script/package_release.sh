#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/LidAwake.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RELEASE_DIR="$ROOT_DIR/dist/releases"
ALLOW_NON_DEVELOPER_ID_RELEASE="${ALLOW_NON_DEVELOPER_ID_RELEASE:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

cd "$ROOT_DIR"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/"Developer ID Application:/ { print $2; exit }'
  )"
fi

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" == "1" && -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/"Developer ID Application:|"Apple Development:/ { print $2; exit }'
  )"
fi

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "error: public release packaging requires a Developer ID Application signing identity" >&2
    echo "hint: use ALLOW_NON_DEVELOPER_ID_RELEASE=1 only for local archive testing" >&2
    exit 2
  fi
elif [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "warning: creating a local test archive with ad-hoc signing" >&2
elif [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "warning: creating a local test archive without Developer ID signing: $SIGNING_IDENTITY" >&2
fi

export SIGNING_IDENTITY

./scripts/check.sh
CONFIGURATION=release ./script/stage_app.sh

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
archive_name="LidAwake-$version-macos.zip"
archive="$RELEASE_DIR/$archive_name"
checksum="$archive.sha256"

mkdir -p "$RELEASE_DIR"
rm -f "$archive" "$checksum"

(
  cd "$ROOT_DIR/dist"
  ditto -c -k --keepParent "LidAwake.app" "$archive"
)

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$archive_name" >"$(basename "$checksum")"
)
printf '%s\n' "$archive"
