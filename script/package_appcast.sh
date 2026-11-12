#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/LidAwake.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RELEASE_DIR="$ROOT_DIR/dist/releases"
APPCAST_DIR="${SPARKLE_APPCAST_DIR:-$RELEASE_DIR/appcast}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-}"
SPARKLE_RELEASE_NOTES="${SPARKLE_RELEASE_NOTES:-}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.thuongtin.LidAwake}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
ALLOW_NON_DEVELOPER_ID_RELEASE="${ALLOW_NON_DEVELOPER_ID_RELEASE:-0}"

cd "$ROOT_DIR"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: staged app not found at $APP_BUNDLE" >&2
  echo "hint: run ./script/package_release.sh, notarize, staple, then run ./script/package_dmg.sh" >&2
  exit 2
fi

# shellcheck source=script/release_gate.sh
source "$ROOT_DIR/script/release_gate.sh"

# The appcast is what every installed copy trusts for its next update, so it
# must describe the same signed, notarized release build the DMG step checks.
if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  require_public_release_bundle "$APP_BUNDLE" || exit 2
fi

if [[ -z "$SPARKLE_GENERATE_APPCAST" ]]; then
  if [[ -x "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" ]]; then
    SPARKLE_GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
  else
    echo "error: Sparkle generate_appcast was not found" >&2
    echo "hint: run swift build --product LidAwake to fetch Sparkle tools" >&2
    exit 2
  fi
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
dmg="$RELEASE_DIR/LidAwake-$version-macos.dmg"
zip="$RELEASE_DIR/LidAwake-$version-macos.zip"

if [[ -f "$dmg" ]]; then
  update_archive="$dmg"
elif [[ -f "$zip" ]]; then
  update_archive="$zip"
else
  echo "error: no release archive found for version $version" >&2
  echo "hint: expected $dmg or $zip" >&2
  exit 2
fi

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  if [[ "$update_archive" == "$dmg" ]]; then
    if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
      echo "error: $dmg has no stapled notarization ticket" >&2
      echo "hint: notarize the DMG, then run xcrun stapler staple on it" >&2
      exit 2
    fi
  else
    # package_release.sh writes the zip before notarization, so a zip that was
    # not recreated after stapling still holds the unstapled app.
    archive_check_dir="$(mktemp -d)"
    trap 'rm -rf "$archive_check_dir"' EXIT
    ditto -x -k "$zip" "$archive_check_dir"
    if ! require_public_release_bundle "$archive_check_dir/LidAwake.app"; then
      echo "error: $zip does not hold the notarized release build" >&2
      echo "hint: recreate the zip after stapling dist/LidAwake.app, or package the DMG" >&2
      exit 2
    fi
  fi
fi

if [[ -z "$SPARKLE_DOWNLOAD_URL_PREFIX" ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/thuongtin/lid-awake/releases/download/v$version/"
elif [[ "$SPARKLE_DOWNLOAD_URL_PREFIX" != */ ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="$SPARKLE_DOWNLOAD_URL_PREFIX/"
fi

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" && "$SPARKLE_DOWNLOAD_URL_PREFIX" != https://* ]]; then
  echo "error: SPARKLE_DOWNLOAD_URL_PREFIX must use https for a public appcast" >&2
  exit 2
fi

rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$update_archive" "$APPCAST_DIR/"

if [[ -n "$SPARKLE_RELEASE_NOTES" ]]; then
  if [[ ! -f "$SPARKLE_RELEASE_NOTES" ]]; then
    echo "error: SPARKLE_RELEASE_NOTES does not exist: $SPARKLE_RELEASE_NOTES" >&2
    exit 2
  fi
  extension="${SPARKLE_RELEASE_NOTES##*.}"
  cp "$SPARKLE_RELEASE_NOTES" "$APPCAST_DIR/$(basename "$update_archive" ."${update_archive##*.}").$extension"
fi

appcast_args=(
  "--account" "$SPARKLE_KEY_ACCOUNT"
  "--download-url-prefix" "$SPARKLE_DOWNLOAD_URL_PREFIX"
  "--link" "https://github.com/thuongtin/lid-awake"
  "--versions" "$build"
  "$APPCAST_DIR"
)

if [[ -n "$SPARKLE_ED_KEY_FILE" && -z "$SPARKLE_PRIVATE_KEY" ]]; then
  appcast_args=("--ed-key-file" "$SPARKLE_ED_KEY_FILE" "${appcast_args[@]}")
fi

if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_GENERATE_APPCAST" --ed-key-file - "${appcast_args[@]}"
else
  "$SPARKLE_GENERATE_APPCAST" "${appcast_args[@]}"
fi

(
  cd "$APPCAST_DIR"
  shasum -a 256 appcast.xml >appcast.xml.sha256
)

printf '%s\n' "$APPCAST_DIR/appcast.xml"
