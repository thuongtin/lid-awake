#!/usr/bin/env bash
set -euo pipefail

swift test
swift build
./script/build_and_run.sh --stage
plutil -lint dist/LidAwake.app/Contents/Info.plist
# A menu bar app must launch without a Dock icon; the app only switches to a
# regular process while one of its windows is on screen.
if [[ "$(plutil -extract LSUIElement raw dist/LidAwake.app/Contents/Info.plist)" != "true" ]]; then
  echo "error: staged Info.plist does not set LSUIElement" >&2
  exit 1
fi
# package_dmg.sh reads this to refuse a debug bundle.
if [[ "$(plutil -extract LidAwakeBuildConfiguration raw dist/LidAwake.app/Contents/Info.plist)" != "debug" ]]; then
  echo "error: staged Info.plist does not record the debug build configuration" >&2
  exit 1
fi
