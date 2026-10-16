#!/usr/bin/env bash
set -euo pipefail
LABEL=com.champlin.claudeusagebar
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "ClaudeUsageBar.app" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf /Applications/ClaudeUsageBar.app
echo "removed"
