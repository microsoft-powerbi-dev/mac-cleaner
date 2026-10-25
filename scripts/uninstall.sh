#!/usr/bin/env bash
# Removes MacCleaner from /Applications along with its preferences and saved state.
set -euo pipefail

APP_NAME="MacCleaner"
BUNDLE_ID="com.maccleaner.app"
APP_PATH="/Applications/$APP_NAME.app"

osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true

if [[ -d "$APP_PATH" ]]; then
    SUDO=""
    [[ -w "/Applications" ]] || SUDO="sudo"
    $SUDO rm -rf "$APP_PATH"
    echo "Removed $APP_PATH"
else
    echo "$APP_PATH is not installed."
fi

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -rf \
    "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
    "$HOME/Library/Caches/$BUNDLE_ID" \
    "$HOME/Library/HTTPStorages/$BUNDLE_ID"
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Removed $APP_NAME preferences and saved state."
