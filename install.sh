#!/bin/bash
set -euo pipefail

# Builds Terminal Checkout.app, installs it into ~/Applications, and launches it.
# Native Host registration, extension installation, and terminal permissions are all
# handled from inside the app once it is running.
# No sudo required, idempotent, fully non-interactive.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Terminal Checkout.app"
BUNDLE_ID="com.dazebug.terminal-checkout"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# TCC keys its rows by the code's designated requirement, and for an ad-hoc signed bundle that
# requirement *is* the code hash (`codesign -d --requirements -` prints `cdhash H"..."`). So a
# build whose code changed has a new identity, and an Accessibility grant given to the old one
# becomes a dead row: System Settings still lists the app with its switch on, turning it off and
# on again does not revive it, and only a reset followed by a fresh grant does (observed
# 2026-08-21). Empty output means the hash could not be read — the caller treats that as unknown
# and leaves the permission alone rather than guessing.
cdhash_of() {
    codesign -d --verbose=4 "$1" 2>&1 | awk -F= '/^CDHash=/{print $2}' || true
}

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

# Keep this candidate order in lockstep with Core's findCmuxCLI() — if the two detection rules
# diverge, the install passes but the app reports cmux as "not installed", or vice versa.
find_cmux_cli() {
    local candidate path_entry
    local -a candidates=(
        "/Applications/cmux.app/Contents/Resources/bin/cmux"
        "$HOME/Applications/cmux.app/Contents/Resources/bin/cmux"
        "/opt/homebrew/bin/cmux"
        "/usr/local/bin/cmux"
    )
    local -a path_entries=()
    IFS=: read -r -a path_entries <<< "${PATH:-}"
    for path_entry in "${path_entries[@]}"; do
        [ -n "$path_entry" ] && candidates+=("$path_entry/cmux")
    done
    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

CMUX_CLI="$(find_cmux_cli || true)"
[ -n "$CMUX_CLI" ] && DETECTED_TERMINALS+=("cmux")
# NIGHTLY has its own bundle and channel, so do not fall back to a stable CLI or PATH entry here.
find_cmux_nightly_cli() {
    local candidate
    local -a candidates=(
        "/Applications/cmux NIGHTLY.app/Contents/Resources/bin/cmux"
        "$HOME/Applications/cmux NIGHTLY.app/Contents/Resources/bin/cmux"
    )
    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

CMUX_NIGHTLY_CLI="$(find_cmux_nightly_cli || true)"
[ -n "$CMUX_NIGHTLY_CLI" ] && DETECTED_TERMINALS+=("cmux NIGHTLY")
if [ ${#DETECTED_TERMINALS[@]} -eq 0 ]; then
    MISSING+=("at least one of iTerm2, WezTerm, Warp, cmux, or cmux NIGHTLY")
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
    echo "      Note: zoxide/z not found. Commands try 'z' first to reach your repository — either install it"
    echo "            (brew install zoxide), or set a repository base folder in the setup window, which is"
    echo "            used whenever 'z' fails and clones the repository when it isn't there yet"
fi

# [2/3] Build the app
echo "[2/3] Building the app..."
"$SCRIPT_DIR/app/build.sh"

# [3/3] Install & launch
mkdir -p "$INSTALL_DIR"
PREVIOUS_CDHASH=""
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    PREVIOUS_CDHASH="$(cdhash_of "$INSTALL_DIR/$APP_NAME")"
fi
if pgrep -x TerminalCheckout >/dev/null 2>&1; then
    pkill -x TerminalCheckout || true
    sleep 1
fi
# Build the new bundle beside the old one, then swap — rather than deleting the installed app and
# copying into the hole. The same class as the extension folder's replacement (`Installer.swift`),
# on a different target: what reads this path is LaunchServices and the user, not Chrome.
#
# **This is narrowed, not atomic, and the difference is worth stating.** The shell has no equivalent
# of `replaceItemAt`, and `mv` onto a populated directory fails the same way `rename(2)` does, so
# the window cannot be closed here — only shrunk from "the length of a recursive copy" to "the
# length of two renames". It cannot be delegated to the app either: this script is replacing the
# very binary that would have to perform it.
#
# What it does buy besides the shorter window: a failure between the two renames leaves the previous
# bundle sitting at `.<name>.previous`, and the second rename **puts it back**. If restoration also
# fails, both copies remain on disk under the names the message names, which is the most a shell can
# promise here.
STAGING="$INSTALL_DIR/.$APP_NAME.staging"
PREVIOUS="$INSTALL_DIR/.$APP_NAME.previous"
rm -rf "$STAGING" "$PREVIOUS"
ditto "$SCRIPT_DIR/app/build/$APP_NAME" "$STAGING"
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    mv "$INSTALL_DIR/$APP_NAME" "$PREVIOUS"
fi
if ! mv "$STAGING" "$INSTALL_DIR/$APP_NAME"; then
    if [ -d "$PREVIOUS" ] && mv "$PREVIOUS" "$INSTALL_DIR/$APP_NAME"; then
        rm -rf "$STAGING"
        echo "Install failed while swapping the new app in; the previous one is back in place." >&2
    else
        echo "Install failed while swapping the new app in, and the previous app could not be" >&2
        echo "restored. The new build is at $STAGING and the old one at $PREVIOUS." >&2
    fi
    exit 1
fi
rm -rf "$PREVIOUS"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true
echo "[3/3] Installed: $INSTALL_DIR/$APP_NAME"

# Clear the dead Accessibility row, but only when the identity actually changed: resetting a
# grant that still matches would make the user re-approve for nothing. A first install has no row
# to clear, and an unreadable hash on either side means we do not know, so we do not touch it.
NEW_CDHASH="$(cdhash_of "$INSTALL_DIR/$APP_NAME")"
if [ -n "$PREVIOUS_CDHASH" ] && [ -n "$NEW_CDHASH" ] && [ "$PREVIOUS_CDHASH" != "$NEW_CDHASH" ]; then
    if tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "      The app's code signature changed, so its Accessibility permission was reset."
        echo "      Only Warp claude input uses it — allow it again in the setup window if you need it."
    else
        # Keep the script non-interactive: never prompt or escalate, just say what to run.
        echo "      Note: the app's code signature changed, so a previously granted Accessibility"
        echo "      permission is now a dead entry that toggling in System Settings will not revive."
        echo "      If Warp claude input stops working, run this once and grant it again:"
        echo "        tccutil reset Accessibility $BUNDLE_ID"
    fi
fi

echo ""
echo "=== Installation complete! Launching the app ==="
echo ""
echo "The app's setup window walks you through the remaining steps (Native Host registration and extension folder setup are automatic):"
echo "  ① [Install in Chrome] → load the folder from chrome://extensions"
echo "  ② Pick a language and a terminal (if you pick iTerm2, allow the permission prompt — the permission is granted to this app only)"
echo "  ③ Verify it works with [Run in Terminal]"
echo ""

open "$INSTALL_DIR/$APP_NAME"
