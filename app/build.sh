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

# The string catalogs. They are copied here rather than declared as SwiftPM `resources:` because
# the generated `Bundle.module` accessor resolves through an absolute .build path on the machine
# that compiled it, which hides a missing copy exactly where it would be caught. `cp -R` of
# the directories keeps `<tag>.lproj/<file>` intact; the bundle gate compares what landed here
# against these sources, file set included, so a catalog added to the sources and not to the
# bundle is a red build rather than a language that silently falls back.
cp -R Sources/App/Resources/*.lproj "$APP/Contents/Resources/"

# Embed the extension in the bundle (the app copies and installs it into App Support)
cp -R ../extension "$APP/Contents/Resources/extension"
find "$APP/Contents/Resources/extension" -name '.DS_Store' -delete 2>/dev/null || true

# Ad-hoc signing: the individual executables inside the bundle first, then the bundle as a whole
codesign --force --sign - "$APP/Contents/MacOS/terminal-checkout-relay"
codesign --force --sign - "$APP/Contents/MacOS/terminal-checkout-warp-helper"
codesign --force --sign - "$APP"

# The last step, so that "the build succeeded" means "the bundle carries exactly the resources the
# sources declare". Copying catalogues by hand is what makes a missed copy possible at all, and the
# failure it produces — one language silently falling back — is invisible on the machine that built
# it. CI names this script as its own step as well, so deleting the call from here does not
# quietly delete the gate.
./verify-bundle.sh "$APP"

echo "Build complete: $(pwd)/$APP"
