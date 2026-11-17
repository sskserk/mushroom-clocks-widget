#!/bin/zsh
# Build Mushroom Clocks (with build.sh) and install it into /Applications.
# The build happens in a temporary folder that is removed afterwards, so macOS
# only ever sees one registered copy of the app and its widget.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUILD="$(mktemp -d)"
APP=/Applications/MushroomClocks.app

BUILD_DIR="$BUILD" ./build.sh Release

osascript -e 'tell application "MushroomClocks" to quit' 2>/dev/null || true
killall MushroomClocksWidget 2>/dev/null || true
rm -rf "$APP"
ditto "$BUILD/Release/MushroomClocks.app" "$APP"
rm -rf "$BUILD"
"$LSREGISTER" -f -R "$APP"
codesign --verify --deep --strict "$APP"
# Restart the widget daemon. Replacing the app while it is loading the widget
# makes that load fail, and it then waits up to an hour before trying again,
# leaving a blank widget on the desktop. Other widgets reload for a moment.
killall chronod 2>/dev/null || true
open "$APP"
echo "Installed $APP"
