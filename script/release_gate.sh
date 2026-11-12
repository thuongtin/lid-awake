#!/usr/bin/env bash
set -euo pipefail

# Sourced by the packaging scripts; it does nothing when run on its own.

# Succeeds only for the signed, notarized release build of the app.
#
# A public artifact wraps whatever sits in dist/ at the time, and
# ./scripts/check.sh restages a debug bundle there, so every packaging step
# checks the bundle again before it ships it.
require_public_release_bundle() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"
  local signing_info build_configuration feed_url

  if ! codesign --verify --deep --strict "$app_bundle" 2>/dev/null; then
    echo "error: $app_bundle does not pass codesign --verify --deep --strict" >&2
    return 2
  fi

  # Captured first: grep -q exits on the first match, and with pipefail the
  # SIGPIPE codesign then gets would fail a correctly signed app.
  signing_info="$(codesign -dv --verbose=2 "$app_bundle" 2>&1 || true)"
  if ! grep -q '^Authority=Developer ID Application:' <<<"$signing_info"; then
    echo "error: $app_bundle is not signed with a Developer ID Application identity" >&2
    return 2
  fi

  if ! xcrun stapler validate "$app_bundle" >/dev/null 2>&1; then
    echo "error: $app_bundle has no stapled notarization ticket" >&2
    echo "hint: notarize the release zip, then run xcrun stapler staple dist/LidAwake.app" >&2
    return 2
  fi

  # Staging records its configuration, since Sparkle keys alone do not tell
  # a release build from a debug one staged with SPARKLE_ENABLED=1.
  build_configuration="$(/usr/libexec/PlistBuddy -c 'Print :LidAwakeBuildConfiguration' "$info_plist" 2>/dev/null || true)"
  if [[ "$build_configuration" != "release" ]]; then
    echo "error: $app_bundle is not a release build (configuration: ${build_configuration:-unknown})" >&2
    echo "hint: restage with CONFIGURATION=release, then sign, notarize, and staple it again" >&2
    return 2
  fi

  if ! /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" >/dev/null 2>&1; then
    echo "error: $app_bundle has no SUPublicEDKey, so it cannot verify updates" >&2
    return 2
  fi

  # Staging accepts a plain http feed for local testing, and a release staged
  # that way would fetch its update feed over a connection anyone can rewrite.
  feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist" 2>/dev/null || true)"
  if [[ "$feed_url" != https://* ]]; then
    echo "error: $app_bundle does not read its update feed over https (SUFeedURL: ${feed_url:-missing})" >&2
    echo "hint: restage without SPARKLE_ALLOW_INSECURE_FEED, then sign, notarize, and staple it again" >&2
    return 2
  fi
}
