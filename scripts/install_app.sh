#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Quitting any running Luna instance..."
pkill -f "Luna" 2>/dev/null || true
sleep 1

echo "==> Building latest Luna..."
"$DIR/scripts/build_app.sh"

APP_NAME="Luna - Screen Recorder"
SOURCE_APP="$DIR/$APP_NAME.app"
TARGET_APP="/Applications/$APP_NAME.app"

echo "==> Installing $APP_NAME to /Applications..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "/Applications/"

echo "==> Launching updated Luna..."
open "$TARGET_APP"

echo "==> Done! Luna with System Audio support is now running."
