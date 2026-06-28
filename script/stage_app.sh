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
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

case "$CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
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
mkdir -p "$APP_MACOS" "$APP_LAUNCH_SERVICES" "$APP_LAUNCH_DAEMONS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER_BINARY" "$HELPER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$HELPER_BINARY"

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
  codesign "${codesign_args[@]}" --identifier "$HELPER_LABEL" "$HELPER_BINARY" >/dev/null
  codesign "${codesign_args[@]}" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
fi

printf '%s\n' "$APP_BUNDLE"
