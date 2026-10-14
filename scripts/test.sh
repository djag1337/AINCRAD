#!/bin/zsh
# Runs the unit tests (config parsing, tolerant decoding, layout geometry).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project AINCRAD.xcodeproj -scheme AINCRAD -configuration Debug \
  -derivedDataPath "$HOME/Library/Caches/AINCRAD-build" test 2>&1 | grep -E "Test (Case|Suite)|error:|failed|passed|\*\* TEST" || true
