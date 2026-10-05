#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Tiny Vinyl.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -module-cache-path "$PWD/build/module-cache" \
  -framework Cocoa -framework SwiftUI \
  Sources/*.swift -o "$APP/Contents/MacOS/TinyVinyl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements Resources/Entitlements.plist "$APP"
printf 'Built: %s\n' "$APP"
