#!/bin/bash
set -euo pipefail

# Terminal Checkout.app을 빌드해 ~/Applications에 설치하고 실행한다.
# Native Host 등록·확장 프로그램 설치·터미널 권한은 실행된 앱 안에서 진행한다.
# sudo 불필요, 멱등, 완전 비대화식.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Terminal Checkout.app"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "=== Terminal Checkout 설치 ==="
echo ""

# [1/3] 의존성 프리플라이트 체크
MISSING=()
command -v swift >/dev/null 2>&1 || MISSING+=("Swift 툴체인 (Xcode 또는 Command Line Tools)")
[ -d "/Applications/Google Chrome.app" ] || MISSING+=("Google Chrome (/Applications/Google Chrome.app)")

DETECTED_TERMINALS=()
[ -d "/Applications/iTerm.app" ] && DETECTED_TERMINALS+=("iTerm2")
[ -d "/Applications/WezTerm.app" ] && DETECTED_TERMINALS+=("WezTerm")
if [ ${#DETECTED_TERMINALS[@]} -eq 0 ]; then
    MISSING+=("iTerm2 또는 WezTerm (하나 이상 필요)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[1/3] 의존성 프리플라이트 체크 — 누락 발견 ✗"
    for dep in "${MISSING[@]}"; do
        echo "      - $dep"
    done
    exit 1
fi
echo "[1/3] 의존성 프리플라이트 체크 ✓"
echo "      감지된 터미널: ${DETECTED_TERMINALS[*]}"
if ! command -v zoxide >/dev/null 2>&1 && ! command -v z >/dev/null 2>&1; then
    echo "      경고: zoxide/z가 없습니다. 기본 명령의 'z {repo}'가 동작하지 않습니다 (brew install zoxide)"
fi

# [2/3] 앱 빌드
echo "[2/3] 앱 빌드 중..."
"$SCRIPT_DIR/app/build.sh"

# [3/3] 설치 & 실행
mkdir -p "$INSTALL_DIR"
if pgrep -x TerminalCheckout >/dev/null 2>&1; then
    pkill -x TerminalCheckout || true
    sleep 1
fi
rm -rf "$INSTALL_DIR/$APP_NAME"
ditto "$SCRIPT_DIR/app/build/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true
echo "[3/3] 설치 완료: $INSTALL_DIR/$APP_NAME"

echo ""
echo "=== 설치 완료! 앱을 실행합니다 ==="
echo ""
echo "앱 설정 창이 남은 단계를 안내합니다 (Native Host 등록·확장 폴더 준비는 자동):"
echo "  ① [Chrome에 설치하기] → chrome://extensions에서 폴더 로드"
echo "  ② 터미널 선택 (iTerm2 선택 시 권한 허용 — 권한은 이 앱에만 부여됩니다)"
echo "  ③ [터미널에서 실행]으로 동작 테스트"
echo ""

open "$INSTALL_DIR/$APP_NAME"
