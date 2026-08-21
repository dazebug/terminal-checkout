# Terminal Checkout

A Chrome extension + macOS app that runs commands in your terminal (iTerm2 / WezTerm / Warp) with one click from GitHub PR, issue, and repository pages. You can set up buttons for things like checking out a branch, creating a worktree, or launching a claude session that has already read the issue.

## Why an app?

macOS attributes Automation (Apple Events) permission to the "responsible process". If Chrome spawned the native host directly to control the terminal, the permission subject would be **Chrome**, forcing you to grant broad permissions to Chrome as a whole.

With the Terminal Checkout.app architecture:

- The relay Chrome spawns executes nothing — it only forwards to the app
- Actual terminal control is performed by **Terminal Checkout.app**, launched via LaunchServices
- So you only grant **a single "Terminal Checkout → iTerm2 control" permission** (and only when using iTerm2 — WezTerm and Warp need no TCC permission). Chrome and python3 need no permissions at all.

```
┌──────────────┐   stdio    ┌──────────────────┐  unix socket  ┌───────────────────────┐  AppleScript /   ┌─────────────────────┐
│ Chrome ext.  │───────────▶│ relay (forwards  │──────────────▶│ Terminal Checkout.app │─────────────────▶│ iTerm2/WezTerm/Warp │
│ (JavaScript) │            │ only, in bundle) │               │  ← TCC lives here     │  wezterm cli /   │                     │
└──────────────┘            └──────────────────┘               └───────────────────────┘  Warp Tab Config └─────────────────────┘
```

Warp alone has one extra piece: Warp has no API for sending text to a pane, so a button with scheduled claude input first launches a small injection helper (`terminal-checkout-warp-helper`, installed inside the app bundle) inside the new tab, and the app hands the input to that helper. The helper writes only into that tab's tty and exits on its own when delivery finishes or the tab closes. Confirming that claude actually received the input requires reading the screen, so using claude input with Warp requires the Accessibility permission.

If the app isn't running, the relay launches it in the background automatically, so you don't need to keep the app open.

## Requirements

- macOS 13+
- Google Chrome
- One of iTerm2, WezTerm, or Warp
- Swift toolchain — for building (Command Line Tools via `xcode-select --install` is enough)
- [zoxide](https://github.com/ajeetdsouza/zoxide) or [z.sh](https://github.com/rupa/z) (directory jumper)
- Optional: [gh](https://cli.github.com) (issue presets), claude (claude input)

On every launch the app checks `z`, `gh`, and `claude` in a login shell and flags only the missing ones in the setup window.

## Installation

### 0. Install zoxide (skip if already installed)

```bash
brew install zoxide
```

Add the following line to `~/.zshrc`, then `source ~/.zshrc`:
```bash
eval "$(zoxide init zsh)"
```

> zoxide learns the directories you visit often so you can jump to them with `z <folder>`.
> A directory must be visited at least once with `cd` before it works.

### 1. Install the app

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
./install.sh
```

`install.sh` builds the app, installs it to `~/Applications/Terminal Checkout.app`, and launches it. No sudo, non-interactive, idempotent.

### 2. Finish in the app's setup window

When the app opens, walk through the setup window in order. Native Host registration and extension-folder preparation finish automatically at app launch. The window is state-driven — **completed cards disappear, remaining only as the pipeline lights (●) at the top.**

1. **Extension** — click [Install in Chrome] (the folder path is copied to the clipboard, chrome://extensions opens, and the window shows a ①→④ guide). Then:
   - Turn on **Developer mode** (top right)
   - Click **Load unpacked** (top left)
   - In the file picker: **⇧⌘G → ⌘V (paste) → Enter → [Select]**
   - **Keep Developer mode on** — from Chrome 133, turning it off disables unpacked extensions
   - This item is marked complete when a request actually arrives, i.e. the first time you press a button on a GitHub PR page
2. **Terminal** — choose the terminal to run commands in (iTerm2 / WezTerm / Warp)
3. **iTerm2 control permission** (shown only when iTerm2 is selected and permission isn't granted yet) — click [Request iTerm2 Permission] → allow in the prompt (the permission is granted to this app only; WezTerm and Warp need none)
   - **Warp claude input** (shown only when Warp is selected and permission isn't granted) — allow the Accessibility permission. It is used to confirm on the Warp screen that claude received the input; without it, button commands still run but scheduled claude input is not delivered. Keep the tab visible during delivery
4. **Run Test** — click [Run in Terminal]; done when echo runs in a new terminal tab

Once setup is complete, the window keeps only the terminal selection, Run Test, [Open Extension Options Page], and [Show Setup Guide Again].

> Already using it on another machine? After loading the extension, if Chrome is syncing under the same Google account, your button and command settings come down automatically — no need to set up the options page again.

> Once distribution moves to the Chrome Web Store (unlisted), this whole process will shrink to a single store-link click.

The app runs invisibly in the background — there is no menu-bar icon, and it appears in the Dock only while the setup window is open. To reopen the setup window, launch **Terminal Checkout** from Spotlight (⌘Space) or Launchpad. Pressing an extension button launches the app automatically if it's off, so there's no need to keep it running.

## Usage

### PR pages

Click the button that appears next to the branch name in the PR header, and the configured command runs in a new terminal tab. The button label is up to you — a single emoji, several (🌳🤖), or a short name (review, WT). Clicking the extension icon runs the first button.

Default command (when checkout fails — e.g. the branch is checked out in a worktree — it moves to the worktree at the conventional path `../{repo}-{branch_underbar}`):
```bash
z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }
```

### Issue pages

Click the button that appears next to the status badge (Open/Closed) in the issue header to run issue-specific commands. They are configured separately from PR buttons, and on issue pages the extension icon click also runs this set's first button.

The default button (**Read Issue**) launches claude in the repository directory, then feeds claude the lines below in order. When a claude input starts with `!`, claude runs that line in the shell, so the `gh` output accumulates directly in claude's context.

```bash
!gh issue view {number}                       # body and metadata
!gh issue view {number} --comments            # comments
!gh api repos/{owner}/{repo}/issues/{number}/timeline \
  --jq '[.[]|select(.event=="cross-referenced")|.source.issue.number]'   # issue/PR numbers that mention this issue
```

Without `gh` this preset doesn't work (`brew install gh`, then `gh auth login`). The app's setup window checks on every launch and tells you if it's missing.

### Repository pages

Click the button that appears next to the repository name in the header, and the configured command runs in a new terminal tab. The tab is created in the terminal window you're currently looking at (a new window only when WezTerm/Warp isn't running yet). On GitHub pages that are neither PR nor issue, the extension icon click also runs this set's first button.

The default button (**Open in Terminal**) jumps to that repository's directory:
```bash
z {repo}
```

Like PR/issue buttons, you can change the command and claude inputs freely and attach up to 3. But since this button takes the shape of GitHub's green action button, a name like `Open in Terminal` suits the label better than an emoji.

### claude input

If the command runs `claude`, the options page lets you schedule up to 5 inputs per button to send to claude — e.g. `/review` followed by `Summarize the changes in PR {branch}`. Lines starting with `!` are executed by claude in the shell, which is useful for feeding command output into claude. The app types the inputs in order only after confirming that the new tab's foreground process has become claude, so nothing is mistyped into the shell before claude is up. If claude doesn't appear within 2 minutes, the inputs are quietly dropped.

Known limits: inputs are single-line only. They are not delivered when WezTerm was off and a fresh process was started (fallback), or on Warp when the injection helper failed to launch or the Accessibility permission is missing (the command itself still runs). **On Warp, delivery happens only while you're looking at that tab** — Warp renders only the currently focused tab, so the app submits input only after confirming its own tab is on screen. Moving to another tab/app pauses delivery; coming back resumes it. Each input is submitted only after it is confirmed as actually typed on screen, so while claude's trust prompt for a first-time folder is up, delivery is held — accept within 15 seconds and it continues; take longer and delivery is abandoned from that input on.

## Configuration

- **Install, terminal selection, permissions, extension folder**: the Terminal Checkout.app setup window
- **PR/issue/repository buttons, commands, main branch**: the extension options page ([Open Extension Options Page] in the app's setup window, or `chrome://extensions` → Terminal Checkout → Extension options)

Button cards can be reordered by dragging the `⠿` handle on the left, or by focusing the handle and pressing `↑` `↓`; [Duplicate] creates a copy right after the original (the copy's tooltip gets a number suffix like `(1)` to tell it apart). This order is the order buttons attach on GitHub pages, and it decides which button (the first) the extension icon runs.

Options-page settings are stored in Chrome's account-sync area (`storage.sync`). Because the extension ID is pinned by the manifest `key`, Chromes signed into the **same Google account** with "Extensions" enabled in sync share the settings automatically across machines. The **backup** section's [Export (JSON)] and [Import…] are for account-less migration or reinstall insurance — import only fills the form, so review it and press **Save** to apply.

Variables available in commands:

| Variable | Value | PR | Issue | Repo |
|:---|:---|:---:|:---:|:---:|
| `{repo}` | repository name | ✓ | ✓ | ✓ |
| `{owner}` | repository owner (for `gh api repos/{owner}/{repo}/…`) | ✓ | ✓ | ✓ |
| `{main}` | main branch (resolved as per-repo override → page detection → global default) | ✓ | ✓ | ✓ |
| `{number}` | PR/issue number (digits only) | ✓ | ✓ | — |
| `{branch}` | the PR's head branch (the side being merged) | ✓ | — | — |
| `{base}` | the PR's base branch (the side merged into — exactly as read from the PR page) | ✓ | — | — |
| `{branch_underbar}` | `{branch}` with `/` replaced by `_` (for worktree directory names etc.) | ✓ | — | — |

Variables behave identically in commands and claude inputs. Using a variable the page doesn't have (the `{branch}` family on issue/repo buttons, `{number}` on repo buttons) gets the run rejected.

`{main}` detection reads a different spot per page — PR pages read the base branch, while repository and issue pages read the repository's **default branch** that GitHub embeds in the page. So repos whose default branch is `master` are correct without an override (it's the repo's default, not the branch being viewed, so it's the same on `/tree/other-branch`). On detection failure it falls back to the global default; register an override if you want to cover even that case.

`{main}` and `{base}` are usually the same value, but they diverge when a per-repo override is set or the PR is opened onto another branch (e.g. `release/2`). For commands that must operate on the branch this PR actually merges into (`git merge --ff-only origin/{base}`, `git rebase origin/{base}`, …), use `{base}`. If the base branch can't be read from the PR page, `{base}` is not sent and the run is rejected — it is never silently substituted with another branch.

## Development

```bash
cd app && swift test   # Core unit tests
node --test            # extension (JS) pure-function unit tests — from the repo root, no dependencies
app/build.sh           # build the app bundle (app/build/Terminal Checkout.app)
app/e2e.sh             # relay ↔ socket ↔ server round-trip regression test (after building)
```

## Uninstall

```bash
./uninstall.sh
```

Remove the Chrome extension yourself at `chrome://extensions`.

## Security

- The Native Host relay can only be invoked by specific extension IDs (`allowed_origins` whitelist)
- Variable values pass an alphanumeric + `-_./` whitelist check to prevent command injection
- The app socket is accessible only to processes of the same user (mode 0600 + peer verification)
- Works only on GitHub domains

## Troubleshooting

### "Native host has exited" or the extension doesn't respond

Open the app's setup window (launch Terminal Checkout from Spotlight). If something is wrong, the corresponding card appears automatically — if the Chrome connection card shows, press [Register/Update]. If you moved the repository or reinstalled the app, run `./install.sh` again.

### You denied a permission

Go to [Open System Settings] from the app's setup window and enable **Privacy & Security → Automation → Terminal Checkout → iTerm2**. Warp's screen reading (Accessibility) is the **Accessibility** item on the same screen.

### claude input isn't delivered on Warp

First check that **you were looking at that tab** until delivery finished — moving to another tab/app makes the app wait, unable to verify its own tab (it resumes when you come back). Next, check in the app's setup window that the **Accessibility** permission is granted — Warp uses it to read the screen and confirm claude received the input, and when it can't confirm, it gives up delivery to prevent a wrong submission. If the permission is fine and input still didn't arrive, the injection helper failed to launch. The reason is recorded in `log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info`. Reinstalling the app (`./install.sh`) also refreshes the helper inside the bundle.

### Permission prompts again after rebuilding

Ad-hoc signing is used, so rebuilding the app changes its signing identity and Automation permission may be requested again. Allow it once.

### The z command doesn't work

Check that your terminal is configured to use a login shell, and that zoxide/z is properly set up in your shell config (`.zshrc`, `.bashrc`).

### Buttons don't appear

GitHub UI updates can move button positions. Clicking the extension icon always works.
