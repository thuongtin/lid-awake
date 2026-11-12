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

# Prints the CDHash that identifies a bundle's signed code. A copy made with
# ditto, inside a zip, or on a DMG reports the same value as its source.
bundle_cdhash() {
  local signing_info
  signing_info="$(codesign -dv --verbose=4 "$1" 2>&1 || true)"
  sed -n 's/^CDHash=//p' <<<"$signing_info"
}

archive_check_dir=""
archive_mount_dir=""

# Succeeds when the directory is the root of a mounted volume: it then sits
# on another device than its parent.
is_mount_point() {
  local dir_device parent_device
  dir_device="$(/usr/bin/stat -f %d "$1" 2>/dev/null)" || return 1
  parent_device="$(/usr/bin/stat -f %d "$1/.." 2>/dev/null)" || return 1
  [[ "$dir_device" != "$parent_device" ]]
}

# Detaches the archive's volume if one is mounted at the mount point. Fails
# only when a volume is still mounted there afterwards.
detach_archive_mount() {
  if [[ -n "$archive_mount_dir" ]] && is_mount_point "$archive_mount_dir"; then
    hdiutil detach "$archive_mount_dir" >/dev/null 2>&1 \
      || hdiutil detach -force "$archive_mount_dir" >/dev/null 2>&1 \
      || true
    if is_mount_point "$archive_mount_dir"; then
      return 1
    fi
  fi
  archive_mount_dir=""
}

# Detaches the archive's volume before removing the directory it is mounted
# in. If the volume cannot be detached, the directory is left alone.
cleanup_archive_check() {
  if ! detach_archive_mount; then
    echo "warning: could not detach $archive_mount_dir; detach it, then remove $archive_check_dir" >&2
    return
  fi
  if [[ -n "$archive_check_dir" ]]; then
    rm -rf "$archive_check_dir"
    archive_check_dir=""
  fi
}
trap cleanup_archive_check EXIT

# Sparkle installs whatever app the archive holds, so the archive must hold
# exactly the stapled build checked above, not merely some release build: a
# stale archive of another build or of another app must not ship.
if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]]; then
  archive_check_dir="$(mktemp -d)"

  if [[ "$update_archive" == "$dmg" ]]; then
    if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
      echo "error: $dmg has no stapled notarization ticket" >&2
      echo "hint: notarize the DMG, then run xcrun stapler staple on it" >&2
      exit 2
    fi

    # Set before attaching, so an interrupt during or right after the attach
    # still detaches the volume instead of removing files under it.
    archive_mount_dir="$archive_check_dir/mount"
    mkdir "$archive_mount_dir"
    if ! attach_output="$(hdiutil attach -readonly -nobrowse -noautoopen \
      -mountpoint "$archive_mount_dir" "$dmg" 2>&1 </dev/null)"; then
      echo "error: $dmg could not be mounted read-only" >&2
      printf '%s\n' "$attach_output" >&2
      exit 2
    fi

    # package_dmg.sh puts the app next to an Applications symlink. Another app
    # or an installer package on the volume could be what Sparkle installs.
    other_installables="$(find "$archive_mount_dir" -mindepth 1 -maxdepth 1 \
      \( -iname '*.app' -o -iname '*.pkg' -o -iname '*.mpkg' \) ! -name 'LidAwake.app')"
    if [[ -n "$other_installables" ]]; then
      echo "error: $dmg must hold no app or installer package other than LidAwake.app" >&2
      exit 2
    fi

    # Sparkle may search the whole volume, so nothing may sit next to the app
    # except that symlink. A volume made the package_dmg.sh way holds no
    # metadata entries (.fseventsd, .Trashes, .DS_Store), and a compressed
    # read-only image cannot gain any after it is created.
    while IFS= read -r -d '' volume_entry; do
      case "${volume_entry##*/}" in
        LidAwake.app) continue ;;
        Applications)
          if [[ -L "$volume_entry" && "$(readlink "$volume_entry")" == /Applications ]]; then
            continue
          fi
          ;;
      esac
      echo "error: $dmg must hold only LidAwake.app and an Applications symlink to /Applications at its top level" >&2
      exit 2
    done < <(find "$archive_mount_dir" -mindepth 1 -maxdepth 1 -print0)
    archive_app="$archive_mount_dir/LidAwake.app"
  else
    if ! ditto -x -k "$zip" "$archive_check_dir/zip"; then
      echo "error: $zip could not be extracted" >&2
      exit 2
    fi

    zip_entries="$(find "$archive_check_dir/zip" -mindepth 1 -maxdepth 1)"
    if [[ "$zip_entries" != "$archive_check_dir/zip/LidAwake.app" ]]; then
      echo "error: $zip must hold LidAwake.app and nothing else at its top level" >&2
      exit 2
    fi
    archive_app="$archive_check_dir/zip/LidAwake.app"
  fi

  if [[ ! -d "$archive_app" || -L "$archive_app" ]]; then
    echo "error: $update_archive does not hold a LidAwake.app bundle at its top level" >&2
    exit 2
  fi

  # package_release.sh writes the zip before notarization, so a zip that was
  # not recreated after stapling still holds the unstapled app.
  if ! require_public_release_bundle "$archive_app"; then
    echo "error: $update_archive does not hold the notarized release build" >&2
    echo "hint: rebuild the archive from the stapled dist/LidAwake.app (for a DMG: ./script/package_dmg.sh, then notarize and staple it)" >&2
    exit 2
  fi

  dist_cdhash="$(bundle_cdhash "$APP_BUNDLE")"
  archive_cdhash="$(bundle_cdhash "$archive_app")"
  if [[ -z "$dist_cdhash" || "$archive_cdhash" != "$dist_cdhash" ]]; then
    archive_info_plist="$archive_app/Contents/Info.plist"
    archive_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$archive_info_plist" 2>/dev/null || true)"
    archive_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$archive_info_plist" 2>/dev/null || true)"
    echo "error: $update_archive holds a different build than dist/LidAwake.app (archive: ${archive_version:-unknown} build ${archive_build:-unknown}, dist: $version build $build)" >&2
    echo "hint: rebuild the archive from the stapled dist/LidAwake.app (for a DMG: ./script/package_dmg.sh, then notarize and staple it)" >&2
    exit 2
  fi

  # Detach now: the signing tool reads the DMG itself, and must not run while
  # the volume is still attached.
  if ! detach_archive_mount; then
    echo "error: could not detach $archive_mount_dir; detach it, then remove $archive_check_dir" >&2
    # Leave both in place without a second warning from the EXIT trap.
    archive_mount_dir=""
    archive_check_dir=""
    exit 2
  fi
  cleanup_archive_check
fi

if [[ -z "$SPARKLE_DOWNLOAD_URL_PREFIX" ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/thuongtin/lid-awake/releases/download/v$version/"
elif [[ "$SPARKLE_DOWNLOAD_URL_PREFIX" != */ ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="$SPARKLE_DOWNLOAD_URL_PREFIX/"
fi

if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" ]] && ! is_https_url_with_host "$SPARKLE_DOWNLOAD_URL_PREFIX"; then
  echo "error: SPARKLE_DOWNLOAD_URL_PREFIX must be an https URL with a host for a public appcast" >&2
  exit 2
fi

if [[ -n "$SPARKLE_RELEASE_NOTES" && ! -f "$SPARKLE_RELEASE_NOTES" ]]; then
  echo "error: SPARKLE_RELEASE_NOTES does not exist: $SPARKLE_RELEASE_NOTES" >&2
  exit 2
fi

# The notes are copied next to the archive under its name with their own
# extension, and the signing tool reads every archive in that directory: a
# notes file with an archive extension would publish a second, unchecked one.
if [[ "$ALLOW_NON_DEVELOPER_ID_RELEASE" != "1" && -n "$SPARKLE_RELEASE_NOTES" ]]; then
  notes_extension="$(tr '[:upper:]' '[:lower:]' <<<"${SPARKLE_RELEASE_NOTES##*.}")"
  case "$notes_extension" in
    html | md | txt) ;;
    *)
      echo "error: SPARKLE_RELEASE_NOTES must be an .html, .md, or .txt file for a public appcast: $SPARKLE_RELEASE_NOTES" >&2
      exit 2
      ;;
  esac
fi

rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$update_archive" "$APPCAST_DIR/"

if [[ -n "$SPARKLE_RELEASE_NOTES" ]]; then
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
