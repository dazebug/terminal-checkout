#!/bin/bash
set -e

# 사용법: ./install.sh [--id EXTENSION_ID]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_SCRIPT="$SCRIPT_DIR/native-host/terminal_checkout.py"
NATIVE_HOST_WRAPPER="$SCRIPT_DIR/native-host/run.sh"
CHROME_MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.dazebug.terminal_checkout.json"
EXTENSION_DIR="$SCRIPT_DIR/extension"
# iTerm Checkout 시절 설치분
LEGACY_MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.iterm.checkout.json"
LEGACY_SCRIPT_PATH="/usr/local/bin/iterm_checkout.py"

# --id 옵션 파싱
EXTENSION_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --id)
            EXTENSION_ID="$2"
            shift 2
            ;;
        *)
            echo "사용법: $0 [--id EXTENSION_ID]"
            exit 1
            ;;
    esac
done

echo "=== Terminal Checkout 설치 ==="
echo ""

# [1/6] 의존성 프리플라이트 체크
MISSING=()
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")
command -v zoxide >/dev/null 2>&1 || command -v z >/dev/null 2>&1 || MISSING+=("zoxide (brew install zoxide)")
[ -d "/Applications/Google Chrome.app" ] || MISSING+=("Google Chrome (/Applications/Google Chrome.app)")

# 터미널: iTerm2 또는 WezTerm 중 하나 이상 필요
DETECTED_TERMINALS=()
[ -d "/Applications/iTerm.app" ] && DETECTED_TERMINALS+=("iTerm2")
[ -d "/Applications/WezTerm.app" ] && DETECTED_TERMINALS+=("WezTerm")
if [ ${#DETECTED_TERMINALS[@]} -eq 0 ]; then
    MISSING+=("iTerm2 또는 WezTerm (하나 이상 필요)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[1/6] 의존성 프리플라이트 체크 — 누락 발견 ✗"
    for dep in "${MISSING[@]}"; do
        echo "      - $dep"
    done
    exit 1
else
    echo "[1/6] 의존성 프리플라이트 체크 ✓"
    echo "      감지된 터미널: ${DETECTED_TERMINALS[*]}"
fi

# [2/6] python3 절대경로 래퍼 생성
# Chrome은 GUI 앱이라 PATH가 제한적 (/usr/bin:/bin 등만 포함)
# pyenv, Homebrew 등의 python3를 찾으려면 절대경로가 필요
PYTHON3_PATH=$(python3 -c "import sys; print(sys.executable)")
chmod +x "$NATIVE_HOST_SCRIPT"
cat > "$NATIVE_HOST_WRAPPER" << WRAPPER_EOF
#!/bin/bash
exec "$PYTHON3_PATH" "$NATIVE_HOST_SCRIPT"
WRAPPER_EOF
chmod +x "$NATIVE_HOST_WRAPPER"
echo "[2/6] Native Host 래퍼 생성 — python3: $PYTHON3_PATH"

# [3/6] Extension ID 결정
if [ -n "$EXTENSION_ID" ]; then
    echo "[3/6] Extension ID — --id 옵션 사용: $EXTENSION_ID"
else
    # SHA-256(절대경로) 앞 32 hex → a-p 매핑으로 자동 계산
    EXTENSION_ID=$(python3 -c "
import hashlib
path = '$EXTENSION_DIR'
sha = hashlib.sha256(path.encode('utf-8')).hexdigest()[:32]
mapping = {c: chr(ord('a') + i) for i, c in enumerate('0123456789abcdef')}
print(''.join(mapping[c] for c in sha))
")
    echo "[3/6] Extension ID — 경로에서 자동 계산: $EXTENSION_ID"
fi

# [4/6] Native Host manifest 생성
FIRST_INSTALL=false
if [ ! -f "$MANIFEST_PATH" ]; then
    FIRST_INSTALL=true
fi

mkdir -p "$CHROME_MANIFEST_DIR"

NEED_MANIFEST=true
if [ -f "$MANIFEST_PATH" ]; then
    CURRENT_OK=$(python3 -c "
import json
with open('$MANIFEST_PATH') as f:
    data = json.load(f)
path_ok = data.get('path') == '$NATIVE_HOST_WRAPPER'
origin_ok = data.get('allowed_origins') == ['chrome-extension://$EXTENSION_ID/']
print('yes' if path_ok and origin_ok else 'no')
" 2>/dev/null || echo "no")
    if [ "$CURRENT_OK" = "yes" ]; then
        NEED_MANIFEST=false
    fi
fi

if [ "$NEED_MANIFEST" = true ]; then
    cat > "$MANIFEST_PATH" << EOF
{
  "name": "com.dazebug.terminal_checkout",
  "description": "Terminal Checkout Native Host",
  "path": "$NATIVE_HOST_WRAPPER",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
EOF
    echo "[4/6] Native Host manifest 생성 완료"
else
    echo "[4/6] Native Host manifest — 이미 최신 상태 ✓"
fi

# [5/6] 셀프 테스트
SELF_TEST_OK=$(printf '\x02\x00\x00\x00{}' | "$NATIVE_HOST_WRAPPER" | python3 -c "
import sys, struct, json
raw = sys.stdin.buffer.read(4)
length = struct.unpack('=I', raw)[0]
data = json.loads(sys.stdin.buffer.read(length))
if data.get('success') == False and 'Missing repo' in data.get('error', ''):
    print('yes')
else:
    print('no')
" 2>/dev/null || true)

if [ "$SELF_TEST_OK" = "yes" ]; then
    echo "[5/6] 셀프 테스트 — Native Host 프로토콜 정상 ✓"
else
    echo "[5/6] 셀프 테스트 — 실패 (Native Host 응답 이상)"
    echo "      수동 확인: printf '\\x02\\x00\\x00\\x00{}' | $NATIVE_HOST_WRAPPER"
fi

# [6/6] 레거시 정리 + 첫 설치 시 chrome://extensions 오픈
LEGACY_FOUND=false
if [ -f "$LEGACY_MANIFEST_PATH" ]; then
    LEGACY_FOUND=true
    rm "$LEGACY_MANIFEST_PATH"
    echo "[6/6] iTerm Checkout 시절 manifest 삭제됨: $LEGACY_MANIFEST_PATH"
fi
if [ -f "$LEGACY_SCRIPT_PATH" ]; then
    LEGACY_FOUND=true
    echo "      이전 설치 감지: $LEGACY_SCRIPT_PATH"
    echo "      더 이상 필요하지 않습니다. 삭제하려면:"
    echo "      sudo rm $LEGACY_SCRIPT_PATH"
fi
if [ "$LEGACY_FOUND" = false ]; then
    echo "[6/6] 레거시 정리 — 해당 없음 ✓"
fi

echo ""
echo "=== 설치 완료! ==="
echo ""

if [ "$FIRST_INSTALL" = true ]; then
    echo "Chrome에서 확장 프로그램을 로드하세요:"
    echo "  1. '개발자 모드' 켜기"
    echo "  2. '압축해제된 확장 프로그램을 로드합니다' 클릭"
    echo "  3. 경로 선택: $EXTENSION_DIR"
    echo ""
    open "google-chrome://extensions" 2>/dev/null || true
fi

echo "GitHub PR 페이지에서 checkout 아이콘을 클릭하면 터미널에서 checkout!"
echo ""
