#!/usr/bin/env bash
set -euo pipefail

# Local runtime QA only. This script is not used by CI.
# It may launch Lid Awake, delete LidAwake.settings defaults for verification,
# and check live pmset assertions on the developer Mac.
swift test
swift build
./script/build_and_run.sh --verify
