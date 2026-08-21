# Terminal Checkout

[![CI](https://github.com/dazebug/terminal-checkout/actions/workflows/ci.yml/badge.svg)](https://github.com/dazebug/terminal-checkout/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**One click from GitHub to your Mac terminal.**

Terminal Checkout puts configurable buttons on GitHub PR, issue, and repository pages. Press one and your command runs in a new tab of iTerm2, WezTerm, or Warp — check out the branch, create a worktree, or launch a [Claude Code](https://claude.com/claude-code) session that has already read the issue. It ships as a Chrome extension plus a native macOS app.

## Features

- **Buttons where you work** — up to 3 buttons each on PR, issue, and repository pages; labels are free-form (emoji or short text). Clicking the extension icon runs the first button for the page you're on.
- **Any command** — templates with `{repo}`, `{branch}`, `{base}`, `{number}`, … variables, validated against a strict character whitelist before anything runs.
- **Claude Code hand-off** — if your command runs `claude`, up to 5 scheduled inputs are handed over for you. `!` lines are typed into claude's shell mode so they really run as commands, with a run of them merged into one line; a list holding exactly one plain-text line is handed over as claude's opening message instead, with no typing at all.
- **Opens where you are** — new tabs are created in the terminal window you're currently looking at (best effort, with explicit fallbacks when no window can be found).
- **Minimal permissions by design** — Chrome itself gets no terminal control. Only the app holds a single "Terminal Checkout → iTerm2" Automation permission; WezTerm needs no TCC permission, and Warp needs the Accessibility permission for buttons whose claude inputs are typed — which is every shipped preset, since they all use `!`.
- **Settings that follow you** — buttons and commands live in Chrome `storage.sync` and follow your Google account across machines.

## How it works

macOS attributes Automation (Apple Events) permission to the "responsible process". If Chrome spawned a native host that drove the terminal directly, the permission would attach to **Chrome**, and you'd have to grant terminal control to the whole browser. Terminal Checkout splits the path so that never happens:

```mermaid
flowchart LR
    EXT["Chrome extension<br>(JavaScript)"] -->|stdio| RELAY["relay<br>(forwarding only, ships in the app bundle)"]
    RELAY -->|unix socket| APP["Terminal Checkout.app<br>(TCC permission attaches here only)"]
    APP -->|"AppleScript / wezterm cli / Warp Tab Config"| TERM["iTerm2 / WezTerm / Warp"]
```

- The relay Chrome spawns contains no terminal or command logic — it forwards bytes to the app's unix socket, and if the app isn't running it launches the app in the background, so you don't need to keep the app open.
- **Terminal Checkout.app** — launched via LaunchServices, so it is its own responsible process — validates the request, renders the command, and drives the terminal.
- Turning the scheduled inputs into "what gets typed" and "what rides in argv" happens in the app, before the terminal branch, so it works the same on all three terminals. A request either types everything or appends everything — never both in one session.
- Warp has one extra piece: it has no API for sending text to a pane, so a button whose claude inputs are **typed** first launches a small injection helper (`terminal-checkout-warp-helper`, shipped inside the app bundle) in the new tab, and the app hands the inputs to it. The helper writes only into that tab's tty and exits on its own when delivery finishes or the tab closes. Confirming that claude received the input requires reading the screen — that's why typed claude input on Warp needs the Accessibility permission. A button with no claude input, or whose one input is a plain-text line, launches no helper and needs no permission — no shipped preset is in that shape.

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

> **Note:** The app's own UI is still in Korean — localization is tracked in [#24](https://github.com/dazebug/terminal-checkout/issues/24). Until it lands, the English labels used in this README appear in the app as: Install in Chrome = 「Chrome에 설치하기」, Request iTerm2 Permission = 「iTerm2 권한 요청」, Run in Terminal = 「터미널에서 실행」, Run Test = 「동작 테스트」, Open Extension Options Page = 「확장 옵션 페이지 열기」, Show Setup Guide Again = 「설치 안내 다시 보기」, Open System Settings = 「시스템 설정 열기」, Register/Update = 「등록/업데이트」.

When the app opens, walk through the setup window in order. Native Host registration and extension-folder preparation finish automatically at launch; the window is state-driven — completed cards disappear, remaining only as the pipeline lights (●) at the top.

1. **Extension** — click [Install in Chrome]. The extension folder path is copied to your clipboard, `chrome://extensions` opens, and the window shows a ①→④ guide:
   - Turn on **Developer mode** (top right)
   - Click **Load unpacked** (top left)
   - In the file picker: **⇧⌘G → ⌘V (paste) → Enter → [Select]**
   - **Keep Developer mode on** — from Chrome 133, turning it off disables unpacked extensions
   - This step is marked complete when the app first receives a request from the extension — press any Terminal Checkout button on GitHub once
2. **Terminal** — choose iTerm2, WezTerm, or Warp
3. **iTerm2 control permission** (shown only when iTerm2 is selected and not yet granted) — click [Request iTerm2 Permission] and allow the prompt. The permission goes to this app only; WezTerm and Warp need none.
   - **Warp claude input** (shown only when Warp is selected and not granted) — allow the Accessibility permission. It's used to confirm on the Warp screen that claude received input that was **typed** into the session — which is every `!` input, and therefore every shipped preset. Without it such a button is **refused outright**: no tab opens, and the button shows ❌ rather than running the command with the input missing. Keep the tab visible during delivery. Only buttons with no claude input, or whose one input is a plain-text line, avoid this path.
4. **Run Test** — click [Run in Terminal]; you're done when `echo` runs in a new terminal tab

Once setup completes, the window keeps only the terminal selection, Run Test, [Open Extension Options Page], and [Show Setup Guide Again].

> Already using Terminal Checkout on another machine? If Chrome syncs under the same Google account, your buttons and commands come down automatically after you load the extension — no reconfiguration needed.

> Once distribution moves to the Chrome Web Store (unlisted), the unpacked-extension steps above will shrink to a store install; the app install and permission steps stay.

The app is invisible in daily use — no menu-bar icon, and it appears in the Dock only while the setup window is open. Reopen the window any time by launching **Terminal Checkout** from Spotlight (⌘Space) or Launchpad. Pressing an extension button starts the app automatically if it's off.

## Updating

```bash
git pull --ff-only
./install.sh
```

Then refresh the extension at `chrome://extensions` (↻ on the Terminal Checkout card). Rebuilding changes the ad-hoc signing identity, so macOS may ask for the Automation permission again — allow it once.

## Usage

### PR pages

A button appears next to the branch name in the PR header. The default command checks out the PR branch; if checkout fails (e.g. the branch is checked out in a worktree), it moves to the worktree at the conventional path `../{repo}-{branch_underbar}`:

```bash
z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }
```

The default command assumes the PR branch exists on `origin` — i.e. a same-repository PR. It doesn't fetch branches that live on a fork; a fork-safe preset (via `gh pr checkout {number}`) is planned.

### Issue pages

A button appears next to the status badge (Open/Closed), configured separately from PR buttons. The default **Read Issue** button launches claude in the repository directory and then types these lines into it — a claude input starting with `!` runs in claude's shell mode, so `gh` really runs in that session and its output is there as command output. The three of them go in as one merged line:

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

If the command runs `claude`, the options page lets you schedule up to 5 inputs per button — e.g. `!gh pr diff {number}` followed by `Summarize the risky parts`. Most of them are **typed into the session**, because that is the only way a `!` line becomes a real shell command; a list holding exactly one plain-text line skips the typing and rides along as claude's opening message instead.

**`!` inputs are typed, and a run of them is typed as one line.** A `!` line only means "run this in the shell" to claude's own input box: passed as an argument at startup it arrives as ordinary text, and claude then decides to run it with its Bash tool — which can stop for a permission prompt and costs a turn (measured). Typed, it runs as a command and stays in the session as one.

- **Consecutive `!` inputs are merged into a single line** joined with `;`, each preceded by a banner so the outputs can be told apart. Three inputs are then one type-and-submit cycle instead of three. `;` and not `&&`: separate `!` lines never stopped each other, and the merge keeps that — a failing command does not swallow the ones after it.
- **Merging is skipped when it would change what runs.** Submitted separately, each `!` line gets a fresh shell — `!export TOKEN=x` does not carry into the next input — but a merged line shares one. So a run containing anything that changes shell state (`cd`, `export`, `source`, `set`, `exit`, `VAR=…`) is typed one input at a time, as is a run whose syntax could run past its own end. That second test is deliberately blunt: **any unquoted `#` or `=` stops the merge wherever it sits**, and so do a heredoc, a trailing `&`, an unterminated quote, and a body that begins or ends with an operator. `echo a#b` is harmless and gets typed on its own anyway — the check does not try to prove which `#` is a comment, because it got that wrong twice. Quote it (`echo 'a#b'`) and the run merges again. It costs a cycle and keeps `["!cd sub", "!rm -rf build"]` deleting the directory you meant.
- **A merged line longer than 4 KiB is typed input by input instead.** Nothing is ever truncated — the limit exists because Warp's injection helper refuses more than 8 KiB in one request, and merging, being the optimisation, is what gives way.
- What runs is exactly the text you wrote, in the directory claude is running in, through claude's shell mode — so it appears in the session as a command, with its output, the way it would if you had typed it.
- A plain-text input, a slash command and a `#` memory line are each typed on their own; a run of `!` ends at the first input that is not one.
- An input containing a NUL byte is rejected outright rather than delivered altered — a tty cannot carry it.

**A list holding exactly one plain-text input becomes the opening message instead.** Plain text is just a message, so it is appended to your command as claude's first argument and the session starts with it already in — no typing, no screen reading, no waiting for claude to boot. The rules for that append:

- It is handed to **`command claude`**, not to `claude`. `command` is POSIX for "skip functions and aliases, run the executable", so a wrapper of that name cannot receive your text. It does **not** skip shell builtins, which is why a command that loads one (`zmodload`, `enable`) stops the append instead.
- Because of that, **appending needs a `claude` executable to exist**. The app asks your login shell at startup — in a child shell, so a function or an alias of yours does not hide the file behind it, and it checks the file is actually runnable. If `claude` is *only* a function or an alias, the inputs are typed instead, and the setup window says so.
- The append only happens when the rendered command is a plain chain (`&&`, `||`, `;`, `|`, groups, subshells) whose **last command is a bare `claude`** — no flags, not on the receiving end of a pipe, no redirect, nothing after it. Flags are out because some of them (`--resume`) swallow the argument as their own value.
- Beyond that, **every word of the command has to be one that would be safe as a command name**: nothing that can rebind a name in that shell (`function`, `alias`, `eval`, `source`/`.`, `hash`, `trap`, `export`, an assignment like `PATH=…`, a compound keyword such as `if`/`for`/`while`/`case`) and nothing quoted or expanded, which the app cannot read. The price is over-folding — `git add . && claude` and anything with a quoted argument are typed instead, which is what they did before.
- Your login shell has to be POSIX-family (`sh`, `bash`, `zsh`, `dash`, `ksh`…), and the message must be single-line. In csh/tcsh a `!` anywhere in your text is history-expanded **even inside single quotes** and takes the whole command line with it (measured: `echo START; /bin/echo -- 'do it!x'` prints only `x: Event not found.` — `START` never runs), and a newline would end the command line early in both iTerm2 and WezTerm.
- **Mixing is not allowed.** If the list has plain text *and* anything else, everything is typed. Sending an opening message and typing into the same session races claude's startup: submitting that message clears the input box 2–3 seconds in, and anything typed before then is wiped (measured).
- What the app still cannot see, because it needs your shell and filesystem at run time: a **`PATH` that resolves `claude` to a different program**, and a **`command` function or alias in your rc**, which would capture the invocation above.

**What typing costs, and what the app will and won't tell you.** Typed delivery is the normal path now, so it is worth knowing what it does to the session:

- The app waits up to **2 minutes** for claude to be ready in the new tab, then gives up and says so in its log. It never types into the shell: it waits for claude to be the foreground process with the tty in raw mode first.
- Before each input it types a short random marker, watches it appear, clears the box, and watches it go — that is how it knows the screen it reads is this pane, that what appears is really in the input box, and that the terminal's Ctrl+U was actually acted on. Then it types the input once and submits it.
- Those clears mean **a draft you start typing while delivery is running is erased**: one Ctrl+U per input, plus one when delivery ends. That is deliberate — the alternative is our line sitting in your box waiting for your Enter, and with a `!` line that Enter runs a command.
- Delivery holds while claude's trust prompt for a first-time folder is up. Accept within about **15 seconds** and it continues; take longer and it gives up from that input on.
- The log says **sent**, not delivered. Whether claude turned a submitted line into a message is not something anything outside the TUI can establish, so the app does not claim it. If a return key never took effect, that input is lost and the log still counts it as sent.
- **On Warp, delivery only runs while you're looking at that tab** (see below).

Known limits:

- Inputs are single-line only.
- A button whose inputs are typed — every button with a `!` input — is **refused before anything opens** when the app can already tell it couldn't deliver them: on Warp without the Accessibility permission or without the bundled injection helper, and on WezTerm when no WezTerm window is running (a fresh process gives no addressable pane). The button shows ❌ and no tab is created — better than a claude session sitting there with none of its context. Buttons whose inputs all merge, and buttons with no claude input, are unaffected.
- **On Warp, the typed route runs only while you're looking at that tab.** Warp renders only the focused tab, so the app submits input only after confirming its own tab is on screen. Switching away pauses delivery; coming back resumes it. The argv opening message is unaffected — it never touches the screen.

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

- Chrome launches the Native Host relay only for whitelisted extension IDs (`allowed_origins`) — enforced by Chrome, not by the relay itself
- Variable values pass an alphanumeric + `-_./` whitelist, preventing command injection
- The app socket and the Warp injection helper deliberately trust processes of the same user (uid): mode 0600 + peer verification on the socket, and the helper is killed the moment delivery ends — see [SECURITY.md](SECURITY.md) for the full trust model
- The extension runs only on `https://github.com`

## Troubleshooting

**"Native host has exited" / the extension doesn't respond** — Open the setup window (launch Terminal Checkout from Spotlight); problem cards appear automatically. If the Chrome connection card shows, press [Register/Update]. If you moved the repository or reinstalled the app, run `./install.sh` again.

**You denied a permission** — [Open System Settings] in the setup window → **Privacy & Security → Automation → Terminal Checkout → iTerm2**. Warp's screen reading is the **Accessibility** item on the same screen.

**claude input isn't delivered on Warp** — Typed input (every `!` input, so every shipped preset) needs the Accessibility permission; a lone plain-text input, which rides in the opening message, does not. If the button showed ❌ and no tab opened, the app knew up front it couldn't deliver: grant **Accessibility** in the setup window (the window comes forward on its own to show you) or reinstall to restore the bundled helper. If the tab did open and only the input is missing: were you looking at that tab until delivery finished? Switching away makes the app wait (it resumes when you return). Otherwise the reason is in `log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info`.

**A claude input was typed instead of riding in the opening message** — That is the normal path for anything with a `!`, a slash command or a `#` line in the list: only a list holding exactly one plain-text input is appended to the command (two plain lines would need a newline between them, so they are typed). If a single plain-text input is still being typed, the command has to end in a bare `claude` (no trailing flag, redirect, pipe or comment), every word of it has to be readable and safe as a command name (`git add .`, `-m 'msg'`, `export …` and `PATH=…` all stop it), the message must be single-line, your login shell has to be POSIX-family, and `claude` has to be a real executable rather than a function or an alias.

**Permission prompts again after rebuilding** — Ad-hoc signing means a build whose code changed also changes the signing identity; allow the Automation prompt once more. The Accessibility grant fails worse than that: the old entry stays listed in System Settings with its switch on but no longer applies, and toggling it does not revive it. `./install.sh` compares the installed and freshly built code hashes and, only when they differ, resets that entry so you can grant it again — it matters only if you use Warp claude input. If the reset can't run, the script prints the single command to run yourself instead of doing anything interactive.

**`z` doesn't work** — Make sure your terminal uses a login shell and zoxide/z is set up in your shell config (`.zshrc`, `.bashrc`).

**Buttons don't appear** — GitHub UI updates can move button anchors. Clicking the extension icon is an alternative path that doesn't depend on those anchors — it reads the same page data, so it can fail too; failures land in the service-worker console.

## Uninstall

```bash
./uninstall.sh
```

Remove the Chrome extension yourself at `chrome://extensions`.

## License

[MIT](LICENSE)
