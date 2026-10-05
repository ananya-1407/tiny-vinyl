#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  Sources/TimedLyrics.swift Sources/RhythmAnalysis.swift Tests/CoreTests.swift \
  -o build/CoreTests
build/CoreTests "$@"
