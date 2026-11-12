#!/usr/bin/env bash
# Release build → build/Sip.app (universal, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftUI's macros need full Xcode; use it even if xcode-select points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/Sip.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Sip" "$APP/Contents/MacOS/Sip"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ "${SKIP_ADHOC_SIGN:-0}" != "1" ]]; then
    codesign --force --sign - "$APP"
fi

echo "Built $APP (version $VERSION)"
