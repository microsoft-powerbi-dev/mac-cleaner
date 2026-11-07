#!/usr/bin/env bash
# Removes MacCleaner from /Applications along with its preferences, saved state, usage history
# and AI API keys, and unregisters any other copies (development builds) from Launch Services
# so they no longer appear in Launchpad, Spotlight or "Open With". Build folders are not deleted.
set -euo pipefail

APP_NAME="MacCleaner"
BUNDLE_ID="com.maccleaner.app"
APP_PATH="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
    "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
    "$HOME/Library/Application Support/$APP_NAME"
# AI provider API keys (one Keychain item per provider).
while security delete-generic-password -s "com.maccleaner.ai" >/dev/null 2>&1; do :; done
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Removed $APP_NAME preferences, saved state, usage history and AI keys."

# Unregister every remaining copy Launch Services knows about (e.g. Xcode build products).
"$LSREGISTER" -dump 2>/dev/null \
    | sed -n "s|^path: *\(.*/$APP_NAME\.app\) (0x[0-9a-f]*)\$|\1|p" | sort -u \
    | while IFS= read -r copy; do
        "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
        echo "Unregistered $copy"
    done
