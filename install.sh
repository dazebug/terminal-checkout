#!/bin/bash
set -euo pipefail

# Builds Terminal Checkout.app, installs it into ~/Applications, and launches it.
# Native Host registration, extension installation, and terminal permissions are all
# handled from inside the app once it is running.
# No sudo required, idempotent, fully non-interactive.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Terminal Checkout.app"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "=== Installing Terminal Checkout ==="
echo ""

# [1/3] Dependency preflight check
MISSING=()
command -v swift >/dev/null 2>&1 || MISSING+=("Swift toolchain (Xcode or Command Line Tools)")
[ -d "/Applications/Google Chrome.app" ] || MISSING+=("Google Chrome (/Applications/Google Chrome.app)")

DETECTED_TERMINALS=()
[ -d "/Applications/iTerm.app" ] && DETECTED_TERMINALS+=("iTerm2")
[ -d "/Applications/WezTerm.app" ] && DETECTED_TERMINALS+=("WezTerm")
# For Warp, look in the same two locations as the app's findWarpAppBundle() — if the two
# detection rules diverge, the install passes but the app reports it as "not installed", or vice versa
{ [ -d "/Applications/Warp.app" ] || [ -d "$HOME/Applications/Warp.app" ]; } && DETECTED_TERMINALS+=("Warp")
if [ ${#DETECTED_TERMINALS[@]} -eq 0 ]; then
    MISSING+=("at least one of iTerm2, WezTerm, or Warp")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[1/3] Dependency preflight check — missing dependencies ✗"
    for dep in "${MISSING[@]}"; do
        echo "      - $dep"
    done
    exit 1
fi
echo "[1/3] Dependency preflight check ✓"
echo "      Detected terminals: ${DETECTED_TERMINALS[*]}"
if ! command -v zoxide >/dev/null 2>&1 && ! command -v z >/dev/null 2>&1; then
    echo "      Warning: zoxide/z not found. 'z {repo}' in the default command will not work (brew install zoxide)"
fi

# [2/3] Build the app
echo "[2/3] Building the app..."
"$SCRIPT_DIR/app/build.sh"

# [3/3] Install & launch
mkdir -p "$INSTALL_DIR"
if pgrep -x TerminalCheckout >/dev/null 2>&1; then
    pkill -x TerminalCheckout || true
    sleep 1
fi
rm -rf "$INSTALL_DIR/$APP_NAME"
ditto "$SCRIPT_DIR/app/build/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true
echo "[3/3] Installed: $INSTALL_DIR/$APP_NAME"

echo ""
echo "=== Installation complete! Launching the app ==="
echo ""
echo "The app's setup window walks you through the remaining steps (Native Host registration and extension folder setup are automatic):"
echo "  ① [Install in Chrome] (shown today as [Chrome에 설치하기]) → load the folder from chrome://extensions"
echo "  ② Pick a terminal (if you pick iTerm2, allow the permission prompt — the permission is granted to this app only)"
echo "  ③ Verify it works with [Run in Terminal] (shown today as [터미널에서 실행])"
echo ""

open "$INSTALL_DIR/$APP_NAME"
