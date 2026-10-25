#!/usr/bin/env bash
# Builds MacCleaner from source and installs it into /Applications.
#
#   ./scripts/install.sh            build Release and install
#   ./scripts/install.sh --no-open  install without launching the app
#
# Requires macOS 14+ on Apple Silicon and Xcode 16+. Installs XcodeGen with
# Homebrew if it is missing.
set -euo pipefail

APP_NAME="MacCleaner"
DEST_DIR="/Applications"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/install"
OPEN_AFTER=1

for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

step "Checking requirements"
[[ "$(uname -s)" == "Darwin" ]] || fail "MacCleaner only runs on macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "MacCleaner is built for Apple Silicon (arm64) only."
os_major="$(sw_vers -productVersion | cut -d. -f1)"
(( os_major >= 14 )) || fail "macOS 14 or later is required (found $(sw_vers -productVersion))."
# xcode-select may point at the Command Line Tools; fall back to Xcode.app.
if ! xcodebuild -version >/dev/null 2>&1 && [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
xcodebuild -version >/dev/null 2>&1 \
    || fail "Xcode is required. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"

if ! command -v xcodegen >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || fail "XcodeGen is missing and Homebrew isn't installed. See https://brew.sh"
    step "Installing XcodeGen"
    brew install xcodegen
fi

step "Generating Xcode project"
(cd "$ROOT" && xcodegen --quiet)

step "Building $APP_NAME (Release)"
xcodebuild -project "$ROOT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration Release -derivedDataPath "$BUILD_DIR" \
    -quiet build

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || fail "Build finished but $BUILT_APP was not found."

step "Installing to $DEST_DIR"
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
SUDO=""
[[ -w "$DEST_DIR" ]] || SUDO="sudo"
$SUDO rm -rf "$DEST_DIR/$APP_NAME.app"
$SUDO ditto "$BUILT_APP" "$DEST_DIR/$APP_NAME.app"
$SUDO xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

printf '\n\033[1;32mInstalled %s to %s.\033[0m\n' "$APP_NAME" "$DEST_DIR"
cat <<MSG
Grant Full Disk Access so MacCleaner can see caches, Mail downloads and the Trash:
  System Settings → Privacy & Security → Full Disk Access → turn on $APP_NAME
If you installed over an older build, remove $APP_NAME from that list and add it again.
MSG

if (( OPEN_AFTER )); then
    open "$DEST_DIR/$APP_NAME.app"
fi
