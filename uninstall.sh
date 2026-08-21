#!/bin/bash
set -euo pipefail

APP_PATH="$HOME/Applications/Terminal Checkout.app"
APP_SUPPORT="$HOME/Library/Application Support/TerminalCheckout"
CHROME_MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.dazebug.terminal_checkout.json"
# Left over from the iTerm Checkout days
LEGACY_MANIFEST_PATH="$CHROME_MANIFEST_DIR/com.iterm.checkout.json"
LEGACY_SCRIPT_PATH="/usr/local/bin/iterm_checkout.py"

echo "=== Uninstalling Terminal Checkout ==="
echo ""

# 1. Quit the running app + delete the app
if pgrep -x TerminalCheckout >/dev/null 2>&1; then
    pkill -x TerminalCheckout || true
    sleep 1
fi
# The injection helper that runs inside a Warp pane is not a child of the app — it hangs off the
# pane's shell, so the pkill above does not catch it. On SIGTERM it removes its own socket and
# exits, but sockets left behind by helpers that already died also remain
if pgrep -f 'terminal-checkout-warp-helper --serve' >/dev/null 2>&1; then
    pkill -f 'terminal-checkout-warp-helper --serve' || true
    sleep 1
fi
# Delete only what the app itself would recognize: for sockets, only things that really are
# sockets (anyone can drop a regular file or a symlink under the same name); for Tab Configs,
# only files carrying the header we write
# (write the conditions as if statements — under set -e, a false AND list would end the whole script)
for sock in "${TMPDIR:-/tmp}"tcw-*.sock /tmp/tcw-*.sock; do
    if [ -S "$sock" ] && [ ! -L "$sock" ]; then
        rm -f "$sock"
    fi
done
# The prompt working directories hold the assembled opening message — PR and issue bodies, and
# whatever a `!` input printed. The running app reclaims them by age; an uninstall takes them all,
# but still only directories (never links) whose name is our prefix plus an 8 character hex token
for dir in "${TMPDIR:-/tmp}"tc-prompt-* /tmp/tc-prompt-*; do
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [[ "${dir##*/}" =~ ^tc-prompt-[0-9a-f]{8}$ ]]; then
        rm -rf "$dir"
    fi
done
# The header below must equal `warpTabConfigHeader` in app/Sources/Core/WarpControl.swift —
# UninstallScriptSyncTests enforces the match (the app still writes this header in Korean)
for toml in "$HOME"/.warp/tab_configs/terminal-checkout.toml "$HOME"/.warp/tab_configs/terminal-checkout-*.toml; do
    if [ -f "$toml" ] && [ ! -L "$toml" ] && head -1 "$toml" | grep -q '^# Terminal Checkout이 자동 생성합니다'; then
        rm -f "$toml"
    fi
done
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
    echo "[1/4] App deleted: $APP_PATH"
else
    echo "[1/4] App — not installed ✓"
fi

# 2. Delete the Native Host manifest
if [ -f "$MANIFEST_PATH" ]; then
    rm "$MANIFEST_PATH"
    echo "[2/4] Native Host manifest deleted"
else
    echo "[2/4] Native Host manifest — nothing to do ✓"
fi

# 3. Delete App Support data (including the installed extension folder and sockets)
if [ -d "$APP_SUPPORT" ]; then
    rm -rf "$APP_SUPPORT"
    echo "[3/4] App data deleted: $APP_SUPPORT"
else
    echo "[3/4] App data — nothing to do ✓"
fi

# 4. Legacy cleanup
LEGACY_FOUND=false
if [ -f "$LEGACY_MANIFEST_PATH" ]; then
    LEGACY_FOUND=true
    rm "$LEGACY_MANIFEST_PATH"
    echo "[4/4] Legacy manifest deleted: $LEGACY_MANIFEST_PATH"
fi
if [ -f "$LEGACY_SCRIPT_PATH" ]; then
    LEGACY_FOUND=true
    echo "[4/4] Script from the old setup detected: $LEGACY_SCRIPT_PATH"
    echo "      To remove it: sudo rm $LEGACY_SCRIPT_PATH"
fi
if [ "$LEGACY_FOUND" = false ]; then
    echo "[4/4] Legacy cleanup — nothing to do ✓"
fi

echo ""
echo "=== Uninstall complete! ==="
echo ""
echo "Please remove the Chrome extension yourself from chrome://extensions."
echo "The Automation permissions you granted can be cleaned up in System Settings → Privacy & Security → Automation."
echo ""
