#!/bin/bash
# The e2e regression test: Chrome framing → relay → unix socket → app server → response round trip.
# It uses failure paths only, so no terminal is actually opened. Precondition: ./build.sh has run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/build/Terminal Checkout.app"
RELAY="$APP_DIR/Contents/MacOS/terminal-checkout-relay"

# The unix socket path has a 104-byte limit, so a short path is mandatory
export TERMINAL_CHECKOUT_SOCKET="/tmp/tc-e2e-$$.sock"

rm -f "$TERMINAL_CHECKOUT_SOCKET"
"$APP_DIR/Contents/MacOS/TerminalCheckout" --headless-server &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true; rm -f "$TERMINAL_CHECKOUT_SOCKET"' EXIT

for _ in $(seq 1 50); do
  [ -S "$TERMINAL_CHECKOUT_SOCKET" ] && break
  sleep 0.1
done
[ -S "$TERMINAL_CHECKOUT_SOCKET" ] || { echo "FAIL: the server socket was never created"; exit 1; }

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

# Checks that claude_inputs reach the app's resolver through the relay (a variable inside an input gets the same validation as one in the command)
run_case "claude_inputs unprovided variable" \
  '{"command_template":"z {repo} && claude","variables":{"repo":"r"},"claude_inputs":["fix {nope}"]}' \
  'Variable {nope} not provided'

run_case "claude_inputs must be array" \
  '{"command_template":"z {repo}","variables":{"repo":"r"},"claude_inputs":"x"}' \
  'claude_inputs must be an array'

# The issue/PR number and the owner also go into the shell as they are, so they get the same whitelist validation
run_case "issue number injection" \
  '{"command_template":"gh issue view {number}","variables":{"number":"1; rm -rf /"}}' \
  'Invalid characters'

run_case "owner injection" \
  '{"command_template":"gh api repos/{owner}/{repo}","variables":{"owner":"a`whoami`","repo":"r"}}' \
  'Invalid characters'

# {cd} (the repository entry clause) is a shell fragment the app assembles from its base directory
# setting. A value the extension sends under that same name is rejected, not merged — allowing the
# merge would let the extension run an arbitrary shell fragment. The verdict is the same whatever
# the app's base directory holds, so this case does not depend on machine state.
run_case "app-provided variable cannot come from the extension" \
  '{"command_template":"{cd}","variables":{"cd":"rm -rf /"}}' \
  'Unknown variable: {cd}'

echo "e2e: all cases passed"
