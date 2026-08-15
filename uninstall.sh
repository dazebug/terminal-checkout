#!/bin/bash
set -e

CHROME_MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.dazebug.terminal_checkout.json"
# iTerm Checkout 시절 설치분
LEGACY_MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.iterm.checkout.json"
LEGACY_SCRIPT_PATH="/usr/local/bin/iterm_checkout.py"

echo "=== Terminal Checkout 삭제 ==="
echo ""

# 1. Native Host manifest 삭제
if [ -f "$MANIFEST_PATH" ]; then
    echo "[1/3] Native Host manifest 삭제 중..."
    rm "$MANIFEST_PATH"
    echo "      → $MANIFEST_PATH 삭제됨"
else
    echo "[1/3] Native Host manifest가 없습니다."
fi

# 2. 레거시 manifest 삭제 (com.iterm.checkout)
if [ -f "$LEGACY_MANIFEST_PATH" ]; then
    echo "[2/3] 레거시 manifest 삭제 중..."
    rm "$LEGACY_MANIFEST_PATH"
    echo "      → $LEGACY_MANIFEST_PATH 삭제됨"
else
    echo "[2/3] 레거시 manifest — 해당 없음 ✓"
fi

# 3. 레거시 Native Host 스크립트 삭제
if [ -f "$LEGACY_SCRIPT_PATH" ]; then
    echo "[3/3] 이전 방식 Native Host 스크립트 감지: $LEGACY_SCRIPT_PATH"
    echo "      삭제하려면: sudo rm $LEGACY_SCRIPT_PATH"
else
    echo "[3/3] 레거시 스크립트 — 해당 없음 ✓"
fi

echo ""
echo "=== 삭제 완료! ==="
echo ""
echo "Chrome 확장 프로그램은 chrome://extensions에서 직접 삭제해주세요."
echo ""
