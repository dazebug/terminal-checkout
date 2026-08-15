#!/bin/bash
set -euo pipefail

# Terminal Checkout.app 빌드: swift build → 번들 조립 → ad-hoc 서명
cd "$(dirname "$0")"

swift build -c release

APP="build/Terminal Checkout.app"
BIN=".build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/TerminalCheckout" "$APP/Contents/MacOS/"
cp "$BIN/terminal-checkout-relay" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"

# 확장 프로그램을 번들에 내장 (앱이 App Support로 복사·설치한다)
cp -R ../extension "$APP/Contents/Resources/extension"
find "$APP/Contents/Resources/extension" -name '.DS_Store' -delete 2>/dev/null || true

# ad-hoc 서명: 번들 안의 개별 실행 파일(relay) 먼저, 그다음 번들 전체
codesign --force --sign - "$APP/Contents/MacOS/terminal-checkout-relay"
codesign --force --sign - "$APP"

echo "빌드 완료: $(pwd)/$APP"
