#!/bin/bash
set -euo pipefail

APP_PATH="$HOME/Applications/Terminal Checkout.app"
APP_SUPPORT="$HOME/Library/Application Support/TerminalCheckout"
CHROME_MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.dazebug.terminal_checkout.json"
# iTerm Checkout 시절 설치분
LEGACY_MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.iterm.checkout.json"
LEGACY_SCRIPT_PATH="/usr/local/bin/iterm_checkout.py"

echo "=== Terminal Checkout 삭제 ==="
echo ""

# 1. 실행 중인 앱 종료 + 앱 삭제
if pgrep -x TerminalCheckout >/dev/null 2>&1; then
    pkill -x TerminalCheckout || true
    sleep 1
fi
# Warp pane 안에서 도는 주입 헬퍼는 앱의 자식이 아니라 pane 셸 쪽에 붙어 있어 위 pkill로는
# 잡히지 않는다. SIGTERM을 받으면 스스로 소켓을 지우고 나가지만, 이미 죽어 남은 파일도 있다
if pgrep -f 'terminal-checkout-warp-helper --serve' >/dev/null 2>&1; then
    pkill -f 'terminal-checkout-warp-helper --serve' || true
    sleep 1
fi
# 앱과 같은 판정으로만 지운다: 소켓은 실제로 소켓인 것만(같은 이름의 일반 파일·심볼릭 링크를
# 누구나 놓을 수 있다), Tab Config는 우리가 만든 헤더가 있는 것만
# (조건은 if로 쓴다 — set -e에서 AND 리스트가 거짓이면 스크립트가 통째로 끝난다)
for sock in "${TMPDIR:-/tmp}"tcw-*.sock /tmp/tcw-*.sock; do
    if [ -S "$sock" ] && [ ! -L "$sock" ]; then
        rm -f "$sock"
    fi
done
for toml in "$HOME"/.warp/tab_configs/terminal-checkout.toml "$HOME"/.warp/tab_configs/terminal-checkout-*.toml; do
    if [ -f "$toml" ] && [ ! -L "$toml" ] && head -1 "$toml" | grep -q '^# Terminal Checkout이 자동 생성합니다'; then
        rm -f "$toml"
    fi
done
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
    echo "[1/4] 앱 삭제됨: $APP_PATH"
else
    echo "[1/4] 앱 — 설치되어 있지 않음 ✓"
fi

# 2. Native Host manifest 삭제
if [ -f "$MANIFEST_PATH" ]; then
    rm "$MANIFEST_PATH"
    echo "[2/4] Native Host manifest 삭제됨"
else
    echo "[2/4] Native Host manifest — 해당 없음 ✓"
fi

# 3. App Support 데이터 삭제 (설치된 확장 폴더·소켓 포함)
if [ -d "$APP_SUPPORT" ]; then
    rm -rf "$APP_SUPPORT"
    echo "[3/4] 앱 데이터 삭제됨: $APP_SUPPORT"
else
    echo "[3/4] 앱 데이터 — 해당 없음 ✓"
fi

# 4. 레거시 정리
LEGACY_FOUND=false
if [ -f "$LEGACY_MANIFEST_PATH" ]; then
    LEGACY_FOUND=true
    rm "$LEGACY_MANIFEST_PATH"
    echo "[4/4] 레거시 manifest 삭제됨: $LEGACY_MANIFEST_PATH"
fi
if [ -f "$LEGACY_SCRIPT_PATH" ]; then
    LEGACY_FOUND=true
    echo "[4/4] 이전 방식 스크립트 감지: $LEGACY_SCRIPT_PATH"
    echo "      삭제하려면: sudo rm $LEGACY_SCRIPT_PATH"
fi
if [ "$LEGACY_FOUND" = false ]; then
    echo "[4/4] 레거시 정리 — 해당 없음 ✓"
fi

echo ""
echo "=== 삭제 완료! ==="
echo ""
echo "Chrome 확장 프로그램은 chrome://extensions에서 직접 삭제해주세요."
echo "부여했던 자동화 권한은 시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 정리할 수 있습니다."
echo ""
