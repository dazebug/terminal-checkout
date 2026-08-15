#!/bin/bash
# e2e 회귀 테스트: Chrome 프레이밍 → relay → unix socket → 앱 서버 → 응답 왕복.
# 터미널이 실제로 열리지 않도록 오류 경로만 사용한다. 사전 조건: ./build.sh 완료.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/build/Terminal Checkout.app"
RELAY="$APP_DIR/Contents/MacOS/terminal-checkout-relay"

# unix socket 경로는 104바이트 제한이 있어 짧은 경로가 필수
export TERMINAL_CHECKOUT_SOCKET="/tmp/tc-e2e-$$.sock"

rm -f "$TERMINAL_CHECKOUT_SOCKET"
"$APP_DIR/Contents/MacOS/TerminalCheckout" --headless-server &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true; rm -f "$TERMINAL_CHECKOUT_SOCKET"' EXIT

for _ in $(seq 1 50); do
  [ -S "$TERMINAL_CHECKOUT_SOCKET" ] && break
  sleep 0.1
done
[ -S "$TERMINAL_CHECKOUT_SOCKET" ] || { echo "FAIL: 서버 소켓이 생성되지 않음"; exit 1; }

frame() {
  python3 -c 'import struct,sys; p=sys.argv[1].encode(); sys.stdout.buffer.write(struct.pack("=I",len(p))+p)' "$1"
}
unframe() {
  python3 -c 'import struct,sys; raw=sys.stdin.buffer.read(4); n=struct.unpack("=I",raw)[0]; sys.stdout.write(sys.stdin.buffer.read(n).decode())'
}

run_case() {
  local name="$1" payload="$2" expect="$3"
  local out
  out=$(frame "$payload" | "$RELAY" | unframe)
  if echo "$out" | grep -qF "$expect"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name — got: $out"
    exit 1
  fi
}

run_case "unknown variable" \
  '{"command_template":"z {repo}","variables":{"evil":"x"},"terminal":"iterm"}' \
  'Unknown variable: {evil}'

run_case "invalid characters" \
  '{"command_template":"z {repo}","variables":{"repo":"a;rm -rf /"}}' \
  'Invalid characters'

run_case "missing command_template" \
  '{"unrelated":1}' \
  'command_template is required'

run_case "unprovided template variable" \
  '{"command_template":"git checkout {main}","variables":{"repo":"r"}}' \
  'Variable {main} not provided'

# claude_inputs가 relay를 거쳐 앱의 해석까지 닿는지 확인 (입력 속 변수도 command와 같은 검증)
run_case "claude_inputs unprovided variable" \
  '{"command_template":"z {repo} && claude","variables":{"repo":"r"},"claude_inputs":["fix {nope}"]}' \
  'Variable {nope} not provided'

run_case "claude_inputs must be array" \
  '{"command_template":"z {repo}","variables":{"repo":"r"},"claude_inputs":"x"}' \
  'claude_inputs must be an array'

# 이슈/PR 번호와 owner도 셸에 그대로 들어가므로 같은 화이트리스트 검증을 받는다
run_case "issue number injection" \
  '{"command_template":"gh issue view {number}","variables":{"number":"1; rm -rf /"}}' \
  'Invalid characters'

run_case "owner injection" \
  '{"command_template":"gh api repos/{owner}/{repo}","variables":{"owner":"a`whoami`","repo":"r"}}' \
  'Invalid characters'

echo "e2e 전체 통과"
