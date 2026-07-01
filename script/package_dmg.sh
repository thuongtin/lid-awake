#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/LidAwake.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RELEASE_DIR="$ROOT_DIR/dist/releases"
ALLOW_NON_DEVELOPER_ID_RELEASE="${ALLOW_NON_DEVELOPER_ID_RELEASE:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

cd "$ROOT_DIR"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: staged app not found at $APP_BUNDLE" >&2
  echo "hint: run ./script/package_release.sh first, then notarize and staple dist/LidAwake.app" >&2
  exit 2
fi

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
    echo "error: public DMG packaging requires a Developer ID Application signing identity" >&2
    echo "hint: use ALLOW_NON_DEVELOPER_ID_RELEASE=1 only for local DMG testing" >&2
    exit 2
  fi
elif [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY=""
  echo "warning: creating an unsigned local test DMG" >&2
elif [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "warning: creating a local test DMG without Developer ID signing: $SIGNING_IDENTITY" >&2
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
dmg_name="LidAwake-$version-macos.dmg"
dmg="$RELEASE_DIR/$dmg_name"
checksum="$dmg.sha256"
staging_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$RELEASE_DIR" "$staging_dir/Lid Awake"
ditto "$APP_BUNDLE" "$staging_dir/Lid Awake/LidAwake.app"
ln -s /Applications "$staging_dir/Lid Awake/Applications"

rm -f "$dmg" "$checksum"
hdiutil create -volname "Lid Awake" -srcfolder "$staging_dir/Lid Awake" -ov -format UDZO "$dmg" >/dev/null

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg" >/dev/null
fi

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$dmg_name" >"$(basename "$checksum")"
)

printf '%s\n' "$dmg"
