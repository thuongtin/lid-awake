#!/usr/bin/env bash
set -euo pipefail

swift test
swift build
./script/build_and_run.sh --stage
plutil -lint dist/LidAwake.app/Contents/Info.plist
