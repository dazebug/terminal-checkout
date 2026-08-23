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
# only files carrying the header we write.
# The `/` before the glob is explicit: `$TMPDIR` carries a trailing slash on macOS but nothing
# guarantees it, and without one the pattern would silently match nothing
# (write the conditions as if statements — under set -e, a false AND list would end the whole script)
# Two suffixes, because a helper has two names: the staging one it binds and the advertised one it
# takes with `link` once it is listening. A helper killed in between leaves the first, and a sweep
# that only knew the second would leave it here for good
for sock in "${TMPDIR:-/tmp}"/tcw-* /tmp/tcw-*; do
    if [ -S "$sock" ] && [ ! -L "$sock" ] && [[ "${sock##*/}" =~ ^tcw-[0-9a-f]{8}\.(sock|pre)$ ]]; then
        rm -f "$sock"
    fi
done
# The prompt working directories hold the assembled opening message — PR and issue bodies, and
# whatever a `!` input printed. The running app reclaims them by age; an uninstall takes them,
# but still only directories (never links) whose name is our prefix plus an 8 character hex token.
# One exception: a `handed-to-claude` marker means a claude session was told to read that context
# file, and those sessions belong to the user, not to the app being removed — deleting the file
# out from under a session that is still running would break it in a way nothing explains. Those
# are reported instead, with the command to remove them
KEPT_CONTEXTS=()
for dir in "${TMPDIR:-/tmp}"/tc-prompt-* /tmp/tc-prompt-*; do
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [[ "${dir##*/}" =~ ^tc-prompt-[0-9a-f]{8}$ ]]; then
        # The marker is dropped by a running pane, so it can appear between the test and the
        # removal. The window cannot be closed from a script; what we can do is look again
        # **after** the attempt, so a directory that survived is reported rather than silently
        # skipped
        if [ ! -e "$dir/handed-to-claude" ]; then
            rm -rf "$dir"
        fi
        if [ -e "$dir" ]; then
            KEPT_CONTEXTS+=("$dir")
        fi
    fi
done
# The two headers below must equal `warpTabConfigHeader` and `warpTabConfigLegacyHeader` in
# app/Sources/Core/WarpControl.swift — UninstallScriptSyncTests enforces both matches.
# The first is a permanent machine protocol and will not change again; the second is what earlier
# builds wrote and is kept so their files are still collected here.
# The first alternative is anchored at **both** ends: unanchored, a file whose first line merely
# starts with the token — `…/v10`, or a user's own line — reads as ours and gets deleted. The
# second cannot be: earlier builds put the explanation on that same line, so only its start is
# fixed. `warpTabConfigIsOurs` splits the two the same way, and UninstallScriptSweepTests runs this
# block against real files to check the boundary rather than the spelling.
for toml in "$HOME"/.warp/tab_configs/terminal-checkout.toml "$HOME"/.warp/tab_configs/terminal-checkout-*.toml; do
    if [ -f "$toml" ] && [ ! -L "$toml" ] && head -1 "$toml" | grep -qE '^#!terminal-checkout/tab-config/v1$|^# Terminal Checkout이 자동 생성합니다'; then
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
if [ ${#KEPT_CONTEXTS[@]} -gt 0 ]; then
    echo "Kept ${#KEPT_CONTEXTS[@]} context file(s) a claude session was told to read:"
    for dir in "${KEPT_CONTEXTS[@]}"; do
        echo "      $dir"
    done
    echo "      Remove them once those sessions are done: rm -rf <path>"
    echo ""
fi
echo "=== Uninstall complete! ==="
echo ""
echo "Please remove the Chrome extension yourself from chrome://extensions."
echo "The Automation permissions you granted can be cleaned up in System Settings → Privacy & Security → Automation."
echo ""
