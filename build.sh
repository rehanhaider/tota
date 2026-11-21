#!/bin/bash
# Builds Tota and installs it to ~/Applications/Tota.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Tota"
APP="$HOME/Applications/Tota.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tota"
cp Info.plist "$APP/Contents/Info.plist"
cp backend/worker.py "$APP/Contents/Resources/worker.py"
codesign --force --sign - "$APP"
echo "Installed: $APP"
