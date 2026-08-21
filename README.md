# Terminal Checkout

**One click from GitHub to your Mac terminal.**

Terminal Checkout puts configurable buttons on GitHub PR, issue, and repository pages. Press one and your command runs in a new tab of iTerm2, WezTerm, or Warp — check out the branch, create a worktree, or launch a [Claude Code](https://claude.com/claude-code) session that has already read the issue. It ships as a Chrome extension plus a native macOS app.

## Features

- **Buttons where you work** — up to 3 buttons each on PR, issue, and repository pages; labels are free-form (emoji or short text). Clicking the extension icon runs the first button for the page you're on.
- **Any command** — templates with `{repo}`, `{branch}`, `{base}`, `{number}`, … variables, validated against a strict character whitelist before anything runs.
- **Claude Code hand-off** — if your command starts `claude`, up to 5 scheduled inputs are typed and submitted for you once claude is actually ready — slash commands and `!` shell-mode lines included.
- **Opens where you are** — new tabs are created in the terminal window you're currently looking at.
- **Minimal permissions by design** — Chrome itself gets no terminal control. Only the app holds a single "Terminal Checkout → iTerm2" Automation permission; WezTerm and Warp need no TCC permission at all.
- **Settings that follow you** — buttons and commands live in Chrome `storage.sync` and follow your Google account across machines.

## How it works

macOS attributes Automation (Apple Events) permission to the "responsible process". If Chrome spawned a native host that drove the terminal directly, the permission would attach to **Chrome**, and you'd have to grant terminal control to the whole browser. Terminal Checkout splits the path so that never happens:

```mermaid
flowchart LR
    EXT["Chrome extension<br>(JavaScript)"] -->|stdio| RELAY["relay<br>(forwarding only, ships in the app bundle)"]
    RELAY -->|unix socket| APP["Terminal Checkout.app<br>(TCC permission attaches here only)"]
    APP -->|"AppleScript / wezterm cli / Warp Tab Config"| TERM["iTerm2 / WezTerm / Warp"]
```

- The relay Chrome spawns executes nothing — it only forwards bytes to the app's unix socket. If the app isn't running, the relay launches it in the background, so you don't need to keep the app open.
- **Terminal Checkout.app** — launched via LaunchServices, so it is its own responsible process — validates the request, renders the command, and drives the terminal.
- Warp has one extra piece: it has no API for sending text to a pane, so a button with scheduled claude input first launches a small injection helper (`terminal-checkout-warp-helper`, shipped inside the app bundle) in the new tab, and the app hands the input to it. The helper writes only into that tab's tty and exits on its own when delivery finishes or the tab closes. Confirming that claude received the input requires reading the screen — that's why claude input on Warp needs the Accessibility permission.

## Requirements

- macOS 13+
- Google Chrome
- One of iTerm2, WezTerm, or Warp
- Swift toolchain, for building (Command Line Tools via `xcode-select --install` is enough)
- [zoxide](https://github.com/ajeetdsouza/zoxide) or [z.sh](https://github.com/rupa/z) — the default commands jump to your repo with `z`
- Optional: [gh](https://cli.github.com) for the issue presets, `claude` for claude input

On every launch the app checks `z`, `gh`, and `claude` in a login shell and flags only the missing ones in the setup window.

## Installation

### 1. zoxide (skip if you already have it)

```bash
brew install zoxide
```

Add this line to `~/.zshrc`, then `source ~/.zshrc`:

```bash
eval "$(zoxide init zsh)"
```

> zoxide learns the directories you visit so you can jump with `z <folder>`. Visit a directory once with `cd` before relying on it.

### 2. Build and install the app

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
./install.sh
```

`install.sh` builds the app, installs it to `~/Applications/Terminal Checkout.app`, and launches it. No sudo, non-interactive, idempotent.

### 3. Finish in the setup window

When the app opens, walk through the setup window in order. Native Host registration and extension-folder preparation finish automatically at launch; the window is state-driven — completed cards disappear, remaining only as the pipeline lights (●) at the top.

1. **Extension** — click [Install in Chrome]. The extension folder path is copied to your clipboard, `chrome://extensions` opens, and the window shows a ①→④ guide:
   - Turn on **Developer mode** (top right)
   - Click **Load unpacked** (top left)
   - In the file picker: **⇧⌘G → ⌘V (paste) → Enter → [Select]**
   - **Keep Developer mode on** — from Chrome 133, turning it off disables unpacked extensions
   - This step is marked complete when a request actually arrives — i.e. the first time you press a button on a GitHub PR page
2. **Terminal** — choose iTerm2, WezTerm, or Warp
3. **iTerm2 control permission** (shown only when iTerm2 is selected and not yet granted) — click [Request iTerm2 Permission] and allow the prompt. The permission goes to this app only; WezTerm and Warp need none.
   - **Warp claude input** (shown only when Warp is selected and not granted) — allow the Accessibility permission. It's used to confirm on the Warp screen that claude received the input; without it, commands still run but scheduled claude input is not delivered. Keep the tab visible during delivery.
4. **Run Test** — click [Run in Terminal]; you're done when `echo` runs in a new terminal tab

Once setup completes, the window keeps only the terminal selection, Run Test, [Open Extension Options Page], and [Show Setup Guide Again].

> Already using Terminal Checkout on another machine? If Chrome syncs under the same Google account, your buttons and commands come down automatically after you load the extension — no reconfiguration needed.

> Once distribution moves to the Chrome Web Store (unlisted), this whole process will shrink to a single store-link click.

The app is invisible in daily use — no menu-bar icon, and it appears in the Dock only while the setup window is open. Reopen the window any time by launching **Terminal Checkout** from Spotlight (⌘Space) or Launchpad. Pressing an extension button starts the app automatically if it's off.

## Usage

### PR pages

A button appears next to the branch name in the PR header. The default command checks out the PR branch; if checkout fails (e.g. the branch is checked out in a worktree), it moves to the worktree at the conventional path `../{repo}-{branch_underbar}`:

```bash
z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }
```

### Issue pages

A button appears next to the status badge (Open/Closed), configured separately from PR buttons. The default **Read Issue** button launches claude in the repository directory, then feeds it these lines in order — a claude input starting with `!` is run in the shell by claude, so the `gh` output lands directly in claude's context:

```bash
!gh issue view {number}                       # body and metadata
!gh issue view {number} --comments            # comments
!gh api repos/{owner}/{repo}/issues/{number}/timeline \
  --jq '[.[]|select(.event=="cross-referenced")|.source.issue.number]'   # issues/PRs that mention this one
```

This preset needs `gh` (`brew install gh`, then `gh auth login`); the setup window warns you if it's missing.

### Repository pages

A button appears next to the repository name in the header. The default **Open in Terminal** button jumps to the repo directory (`z {repo}`). Since this button takes the shape of GitHub's green action button, a text label like `Open in Terminal` suits it better than an emoji. On GitHub pages that are neither PR nor issue, the extension icon runs this set's first button.

### claude input

If the command runs `claude`, the options page lets you schedule up to 5 inputs per button — e.g. `/review` followed by `Summarize the changes in PR {branch}`. The app types them in order only after confirming the new tab's foreground process has become claude, so nothing leaks into the shell; if claude doesn't appear within 2 minutes, the inputs are quietly dropped. Each input is submitted only after it's confirmed as actually typed on screen, so delivery holds while claude's trust prompt for a first-time folder is up — accept within 15 seconds and it continues; take longer and delivery is abandoned from that input on.

Known limits:

- Inputs are single-line only.
- Not delivered when WezTerm was off and a fresh process was started (fallback), or on Warp when the injection helper failed to launch or the Accessibility permission is missing — the command itself still runs.
- **On Warp, delivery happens only while you're looking at that tab.** Warp renders only the focused tab, so the app submits input only after confirming its own tab is on screen. Switching away pauses delivery; coming back resumes it.

## Configuration

Installation, terminal selection, and permissions live in the app's setup window. Buttons, commands, and the main branch live in the extension options page — [Open Extension Options Page] in the setup window, or `chrome://extensions` → Terminal Checkout → Extension options.

- Reorder button cards by dragging the `⠿` handle, or focus the handle and press `↑` `↓`. [Duplicate] creates a copy right after the original (its tooltip gets a `(1)`-style suffix). This order is the order buttons appear on GitHub, and the first button is what the extension icon runs.
- Settings are stored in Chrome's `storage.sync`. The extension ID is pinned by the manifest `key`, so Chromes signed into the same Google account (with "Extensions" enabled in sync) share settings across machines.
- The **backup** section's [Export (JSON)] / [Import…] cover account-less migration and reinstall insurance. Import only fills the form — review and press **Save** to apply.

### Variables

| Variable | Value | PR | Issue | Repo |
|:---|:---|:---:|:---:|:---:|
| `{repo}` | repository name | ✓ | ✓ | ✓ |
| `{owner}` | repository owner (for `gh api repos/{owner}/{repo}/…`) | ✓ | ✓ | ✓ |
| `{main}` | main branch (per-repo override → page detection → global default) | ✓ | ✓ | ✓ |
| `{number}` | PR/issue number (digits only) | ✓ | ✓ | — |
| `{branch}` | the PR's head branch (the side being merged) | ✓ | — | — |
| `{base}` | the PR's base branch (the side merged into — exactly as read from the PR page) | ✓ | — | — |
| `{branch_underbar}` | `{branch}` with `/` replaced by `_` (for worktree directory names etc.) | ✓ | — | — |

Variables work identically in commands and claude inputs. Using a variable the page doesn't have (the `{branch}` family on issue/repo buttons, `{number}` on repo buttons) gets the run rejected.

**`{main}`** is resolved as per-repo override → page detection → global default. Detection reads a different spot per page: PR pages read the base branch, while repository and issue pages read the repository's **default branch** that GitHub embeds in the page — so repos whose default branch is `master` are right without an override, on any `/tree/...` path. Register an override if you want to cover detection failure too.

**`{base}`** is the branch the PR actually merges into, read from the PR page as-is — no override, no fallback. `{main}` and `{base}` usually match, but they diverge when a per-repo override is set or the PR targets another branch (e.g. `release/2`). Use `{base}` for commands that must operate on the true merge target (`git merge --ff-only origin/{base}`, `git rebase origin/{base}`, …). If it can't be read from the page, it isn't sent and the run is rejected rather than silently substituted.

## Development

```bash
cd app && swift test   # Core unit tests
node --test            # extension (JS) pure-function unit tests — repo root, no dependencies
app/build.sh           # build the app bundle (app/build/Terminal Checkout.app)
app/e2e.sh             # relay ↔ socket ↔ server round-trip regression test (after building)
```

Architecture constraints and measured pitfalls are recorded in [`CLAUDE.md`](CLAUDE.md). Adding support for a new terminal? Start from [`docs/new-terminal-checklist.md`](docs/new-terminal-checklist.md).

## Security

- The Native Host relay only accepts calls from whitelisted extension IDs (`allowed_origins`)
- Variable values pass an alphanumeric + `-_./` whitelist, preventing command injection
- The app socket is restricted to same-user processes (mode 0600 + peer verification)
- The extension runs only on GitHub domains

## Troubleshooting

**"Native host has exited" / the extension doesn't respond** — Open the setup window (launch Terminal Checkout from Spotlight); problem cards appear automatically. If the Chrome connection card shows, press [Register/Update]. If you moved the repository or reinstalled the app, run `./install.sh` again.

**You denied a permission** — [Open System Settings] in the setup window → **Privacy & Security → Automation → Terminal Checkout → iTerm2**. Warp's screen reading is the **Accessibility** item on the same screen.

**claude input isn't delivered on Warp** — First: were you looking at that tab until delivery finished? Switching away makes the app wait (it resumes when you return). Then check the **Accessibility** permission in the setup window — without screen reading, the app gives up delivery rather than risk a wrong submission. If permission is fine, the injection helper likely failed to launch; the reason is in `log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info`. Reinstalling (`./install.sh`) also refreshes the bundled helper.

**Permission prompts again after rebuilding** — Ad-hoc signing means a rebuild changes the signing identity; allow the Automation prompt once more.

**`z` doesn't work** — Make sure your terminal uses a login shell and zoxide/z is set up in your shell config (`.zshrc`, `.bashrc`).

**Buttons don't appear** — GitHub UI updates can move button anchors. The extension icon always works.

## Uninstall

```bash
./uninstall.sh
```

Remove the Chrome extension yourself at `chrome://extensions`.
