#!/bin/zsh
# Build Mushroom Clocks without installing it.
#
#   ./build.sh            Release build into ./build
#   ./build.sh Debug      Debug build into ./build
#   ./build.sh clean      delete ./build
#   BUILD_DIR=/some/dir ./build.sh    build somewhere else (install.sh does this)
#
# The app ends up at <build dir>/<configuration>/MushroomClocks.app.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ "${1:-}" == clean ]]; then
  rm -rf build
  echo "Removed build/"
  exit 0
fi

CONFIGURATION="${1:-Release}"
BUILD_DIR="${BUILD_DIR:-$PWD/build}"
APP="$BUILD_DIR/$CONFIGURATION/MushroomClocks.app"

# Only compiler errors and the final verdict; xcodebuild's own chatter is dropped.
xcodebuild -project MushroomClocks.xcodeproj -target MushroomClocks -configuration "$CONFIGURATION" \
  SYMROOT="$BUILD_DIR" OBJROOT="$BUILD_DIR/Intermediates" build 2>&1 \
  | grep -E ": error: |^error: |warning: unre|BUILD (SUCCEEDED|FAILED)"

codesign --verify --deep --strict "$APP"
# Building registers this copy with macOS. Unregister it, or its widget would
# compete with the installed one in /Applications.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true   # complains when it was not registered
echo "Built $APP"
