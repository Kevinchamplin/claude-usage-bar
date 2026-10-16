#!/usr/bin/env bash
# Builds, installs to /Applications and (re)loads the login LaunchAgent.
# Replaces any earlier ClaudeUsageBar install (same app name and label).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

LABEL=com.champlin.claudeusagebar
DEST=/Applications/ClaudeUsageBar.app
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -f "ClaudeUsageBar.app" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R build/ClaudeUsageBar.app "$DEST"

mkdir -p "$HOME/Library/LaunchAgents"
# The agent execs the binary directly (not `open`), which avoids the
# Gatekeeper silent-kill on ad-hoc signed apps. It restarts only on a crash,
# so Quit from the menu really quits until the next login.
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/ClaudeUsageBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL

launchctl bootstrap "$DOMAIN" "$PLIST"
sleep 2
launchctl print "$DOMAIN/$LABEL" | grep -m1 'state ='
