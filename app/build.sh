#!/bin/bash
set -euo pipefail

# Building Terminal Checkout.app: swift build → assemble the bundle → ad-hoc signing
cd "$(dirname "$0")"

swift build -c release

APP="build/Terminal Checkout.app"
BIN=".build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/TerminalCheckout" "$APP/Contents/MacOS/"
cp "$BIN/terminal-checkout-relay" "$APP/Contents/MacOS/"
# The injection helper that runs inside a Warp pane — the app writes this path into the Tab Config
cp "$BIN/terminal-checkout-warp-helper" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"

# Embed the extension in the bundle (the app copies and installs it into App Support)
cp -R ../extension "$APP/Contents/Resources/extension"
find "$APP/Contents/Resources/extension" -name '.DS_Store' -delete 2>/dev/null || true

# Ad-hoc signing: the individual executables inside the bundle first, then the bundle as a whole
codesign --force --sign - "$APP/Contents/MacOS/terminal-checkout-relay"
codesign --force --sign - "$APP/Contents/MacOS/terminal-checkout-warp-helper"
codesign --force --sign - "$APP"

echo "Build complete: $(pwd)/$APP"
