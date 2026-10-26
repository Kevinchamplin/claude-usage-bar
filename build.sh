#!/usr/bin/env bash
# Builds build/ClaudeUsageBar.app with swiftc (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/ClaudeUsageBar.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -framework AppKit -framework SwiftUI \
  Sources/*.swift -o "$APP/Contents/MacOS/ClaudeUsageBar"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
