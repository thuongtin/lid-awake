#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/LidAwake.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RELEASE_DIR="$ROOT_DIR/dist/releases"

cd "$ROOT_DIR"

./scripts/check.sh
CONFIGURATION=release ./script/stage_app.sh

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
archive="$RELEASE_DIR/LidAwake-$version-macos.zip"
checksum="$archive.sha256"

mkdir -p "$RELEASE_DIR"
rm -f "$archive" "$checksum"

(
  cd "$ROOT_DIR/dist"
  ditto -c -k --keepParent "LidAwake.app" "$archive"
)

shasum -a 256 "$archive" >"$checksum"
printf '%s\n' "$archive"
