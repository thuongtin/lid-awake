#!/usr/bin/env bash
set -euo pipefail

APP_PRODUCT="LidAwake"
HELPER_PRODUCT="LidAwakeHelper"
APP_NAME="LidAwake"
APP_DISPLAY_NAME="Lid Awake"
HELPER_NAME="LidAwakeHelper"
BUNDLE_ID="com.thuongtin.LidAwake"
HELPER_LABEL="com.thuongtin.LidAwake.Helper"
HELPER_PLIST_NAME="$HELPER_LABEL.plist"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.1.1}"
APP_BUILD="${APP_BUILD:-$(git rev-list --count HEAD 2>/dev/null || printf '1')}"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SPARKLE_ENABLED="${SPARKLE_ENABLED:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PUBLIC_ED_KEY_FILE="${SPARKLE_PUBLIC_ED_KEY_FILE:-}"

case "$CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

if [[ -z "$SPARKLE_ENABLED" ]]; then
  if [[ "$CONFIGURATION" == "release" || -n "$SPARKLE_FEED_URL" ]]; then
    SPARKLE_ENABLED=1
  else
    SPARKLE_ENABLED=0
  fi
fi

case "$SPARKLE_ENABLED" in
  0|1)
    ;;
  *)
    echo "SPARKLE_ENABLED must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ "$CONFIGURATION" == "release" && "$SPARKLE_ENABLED" != "1" ]]; then
  echo "error: release staging requires Sparkle update metadata" >&2
  exit 2
fi

if [[ "$SPARKLE_ENABLED" == "1" && -z "$SPARKLE_FEED_URL" ]]; then
  SPARKLE_FEED_URL="https://github.com/thuongtin/lid-awake/releases/latest/download/appcast.xml"
fi

SPARKLE_ALLOW_INSECURE_FEED="${SPARKLE_ALLOW_INSECURE_FEED:-}"

if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  if [[ "$SPARKLE_FEED_URL" =~ [[:space:]\"\'] ]]; then
    echo "error: SPARKLE_FEED_URL must not contain spaces or quotes" >&2
    exit 2
  fi
  if [[ "$SPARKLE_FEED_URL" != https://* && -z "$SPARKLE_ALLOW_INSECURE_FEED" ]]; then
    echo "error: SPARKLE_FEED_URL must use https (set SPARKLE_ALLOW_INSECURE_FEED=1 for local testing only)" >&2
    exit 2
  fi
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_LAUNCH_SERVICES="$APP_CONTENTS/Library/LaunchServices"
APP_LAUNCH_DAEMONS="$APP_CONTENTS/Library/LaunchDaemons"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
HELPER_BINARY="$APP_LAUNCH_SERVICES/$HELPER_NAME"
HELPER_PLIST="$APP_LAUNCH_DAEMONS/$HELPER_PLIST_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_FILE="$DIST_DIR/LidAwake.icns"
APP_ICON="$APP_RESOURCES/LidAwake.icns"

if [[ -z "$SPARKLE_PUBLIC_ED_KEY_FILE" && -f "$ROOT_DIR/scripts/sparkle_public_key.txt" ]]; then
  SPARKLE_PUBLIC_ED_KEY_FILE="$ROOT_DIR/scripts/sparkle_public_key.txt"
fi

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" && -n "$SPARKLE_PUBLIC_ED_KEY_FILE" && -f "$SPARKLE_PUBLIC_ED_KEY_FILE" ]]; then
  SPARKLE_PUBLIC_ED_KEY="$(tr -d '[:space:]' <"$SPARKLE_PUBLIC_ED_KEY_FILE")"
fi

if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: Sparkle staging requires SPARKLE_PUBLIC_ED_KEY or scripts/sparkle_public_key.txt" >&2
    echo "hint: run Sparkle generate_keys and commit only the public key" >&2
    exit 2
  fi
  if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: SPARKLE_PUBLIC_ED_KEY is not a valid base64 Ed25519 public key" >&2
    exit 2
  fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/"Developer ID Application:|"Apple Development:/ { print $2; exit }'
  )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "warning: no Developer ID Application or Apple Development signing identity found; using ad-hoc signing" >&2
  echo "warning: Accessibility and LaunchDaemon approvals can become stale after each rebuild" >&2
fi

swift build -c "$CONFIGURATION" --product "$APP_PRODUCT"
swift build -c "$CONFIGURATION" --product "$HELPER_PRODUCT"
BUILD_BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_PRODUCT"
BUILD_HELPER_BINARY="$BUILD_BIN_DIR/$HELPER_PRODUCT"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_LAUNCH_SERVICES" "$APP_LAUNCH_DAEMONS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER_BINARY" "$HELPER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$HELPER_BINARY"

SPARKLE_FRAMEWORK_SOURCE="$BUILD_BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  SPARKLE_FRAMEWORK_SOURCE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "error: Sparkle.framework was not found after swift build" >&2
  exit 2
fi
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/Sparkle.framework"

swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$APP_ICON"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>LidAwake.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright (c) 2026 Lid Awake contributors</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool true" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST" >/dev/null
fi

cat >"$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_LABEL</string>
  <key>BundleProgram</key>
  <string>Contents/Library/LaunchServices/$HELPER_NAME</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_LABEL</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign_args=(--force --sign "$SIGNING_IDENTITY")
  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign_args+=(--options runtime)
    if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
      codesign_args+=(--timestamp)
    fi
  fi
  codesign "${codesign_args[@]}" --deep "$APP_FRAMEWORKS/Sparkle.framework" >/dev/null
  codesign "${codesign_args[@]}" --identifier "$HELPER_LABEL" "$HELPER_BINARY" >/dev/null
  codesign "${codesign_args[@]}" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
fi

printf '%s\n' "$APP_BUNDLE"
