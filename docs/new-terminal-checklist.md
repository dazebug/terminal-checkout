# New-terminal support checklist

Terminal branches are scattered across Core's execution and input delivery and the App's settings, permissions, and setup window, while the unit tests and `app/e2e.sh` never actually open a terminal (e2e exercises only error paths). So when wiring up a new terminal, a missed branch surfaces only in real use, after tests pass — this list exists to close that gap.

Per-terminal pitfalls already confirmed (WezTerm's window selection and GUI-app PATH, iTerm2's `current window`) are in `CLAUDE.md` and are not repeated here.

## 1. Code touch points

Terminal identifiers are defined by Core's `enum Terminal` (`Terminal.swift`), and the app stores the rawValue under the `terminal` key in `UserDefaults` (`iterm`, `wezterm`, `warp`). The extension doesn't know this value and gets no way to learn it — behaviorally there is nothing to touch on the extension side.

Adding a case makes every default-less switch (the execution dispatch; the setup window's radio restore, permission section, and pipeline nodes) surface as compile errors. But the compiler only catches switches — visibility conditions and guidance copy written as `==` comparisons, and everything outside code (scripts, docs), are still caught only by the tables below. Don't stop at chasing compile errors.

**Core**

| Spot | To do |
|:---|:---|
| `Terminal` (`Terminal.swift`) | Add the case. Also add a one-line rawValue literal to the stored-value oracle test (`TerminalIdentifierTests`) |
| `TerminalRunner.runInTerminal(command:terminal:injectsClaudeInput:)` | Add the execution branch (the compile error shows you where). `injectsClaudeInput` matters only for terminals that need separate preparation for input delivery — and it is **not** "this button has claude inputs", it is "inputs are left over after merging" (`ClaudeInputPlan.swift`), which for the shipped presets is never |
| `TerminalRunner.runInXxx(_:)` (new) | Create a new tab → send the command → return a `TerminalSessionHandle` |
| `TerminalSessionHandle` (`ClaudeInjector.swift`) | Add the case. If no handle can be made (`.none`), claude input is not delivered |
| `ClaudeInjector.deliverClaudeInputs` | The branch that obtains the tty path from the handle |
| `ClaudeInjector.sendKeys` | Three kinds: text, CR (`\r` = `claudeSubmitKey`, submit), and Ctrl+U (`\u{15}` = `claudeClearInputKey`, clear the input box) |
| `ClaudeInjector.screenText` | Screen-text lookup — snapshot **immediately before and after** typing and compare (`screenReflectsNewInput`). If the screen can't be read, the right answer is to not send input |
| `ClaudeSessionIO.screenNeedsPaneProof` | true for terminals whose screen lookup can't be pinned to the session — every input then first proves the pane with a nonce probe. Leave the default (false) for terminals that read exactly by pane/session id |

If even one of the three `ClaudeInjector` branches is missing, execution still works and only claude input silently stalls. In particular, without `screenText` the reflection check fails and CR is never sent.

Claude inputs reach the session by two routes and **only the second one is per-terminal.** `ClaudeInputPlan.swift` merges the longest mergeable prefix into the argv prompt of the `claude` the command starts, before any terminal branch is taken; the rest stays for `ClaudeInjector`. So a new terminal inherits the merged route for free and the table above only covers the leftovers. Two consequences when adding a terminal: the leftover route is exercised by fewer buttons than before (none of the shipped presets reach it, so you have to write a slash-command input by hand to test it at all — see the hands-on list), and a terminal that quotes or rewrites the command it is handed must survive `… claude "$(/bin/sh '<path>' || …)"` — the appended substitution is ordinary command text, but it is the first place a new escaping bug will show.

A terminal driven by a CLI needs explicit executable-path search; a terminal driven by AppleScript adds one more TCC automation target (along with the permission-request and status-lookup paths).

A terminal with no API to address a pane at all (Warp) is covered instead by a helper process running inside the pane — then the targets in `app/Package.swift` and the bundle copy/signing in `app/build.sh` grow too.

**App**

| Spot | To do |
|:---|:---|
| `Settings.terminal` | Auto-detection order when there is no stored value (the unknown-stored-value fallback to iTerm2 lives in `Terminal(storedValue:)` alone — nothing to touch) |
| `PermissionChecker.isXxxInstalled` | Install detection. If AppleScript-driven: status lookup, permission request, and opening System Settings too |
| `SetupWindowController` | Add the radio button, disable when not installed, save (`terminalChanged` — the radio→case mapping is an if-chain the compiler can't catch) and restore, permission-card visibility conditions (`isHidden` comparisons), per-terminal guidance notes, and the pipeline node's name/color/description |
| `app/Info.plist` | `NSAppleEventsUsageDescription` is the single one for the whole app — update it if the copy hard-codes a terminal name |
| `install.sh` | The preflight's terminal-detection list and guidance copy. Finding none exits 1 and blocks installation, so missing this makes installation itself fail on machines that have only the new terminal (its detection criteria differ from the app's) |
| `README.md` | Terminal names are hard-coded in the required-terminals list, the architecture diagram, setup steps, permission notes, fallback limits, and troubleshooting. If the code supports it but this is stale, users read it as unsupported |

Terminal names are also embedded in the description in `extension/manifest.json` — that copy is the only thing to touch in the extension.

**Tests**

Parts that parse CLI responses or script output (window picking, pane→tty lookup, and so on) get extracted as pure functions and pinned in `app/Tests/CoreTests` — `WezTermWindowTests` is the example. Execution itself is not covered by unit tests, so the hands-on list below is the only verification.

## 2. Hands-on checklist

Start with the new terminal selected in the app setup window and all 4 pipeline lights green.

**Launch and commands**

- [ ] Setup window [Run in Terminal] → echo runs in a new tab
- [ ] Repository-page button → the new tab's working directory is that repo (`{repo}` `{owner}` `{main}` substituted)
- [ ] PR button → new tab + `{repo}` `{branch}` `{base}` `{branch_underbar}` substituted
- [ ] Issue button → new tab + `{number}` `{owner}` substituted
- [ ] Extension-icon click → the first button on PR, issue, and repository pages respectively (three distinct branches)
- [ ] `{main}` substitution via repository/issue buttons on a repo whose default branch is `master` (read from the page; on failure it silently falls back to the global default)
- [ ] The `z {repo}` jump — without an interactive login shell the zoxide function isn't found and the first step dies
- [ ] A long `&&` chain (create worktree → cd → merge → claude) reaches its final step

**Window selection**

- [ ] With two or more windows open and the second one active, run → the tab appears in the window you were looking at
- [ ] Fallback when no window to attach the tab to is found
- [ ] Fallback when the chosen window closed just before tab creation (giving up here pops a new window)
- [ ] With the terminal not running at all — does it open as a new window, and is claude input abandoned in that case?

**claude input — merged route (no permission, no helper, no screen reading)**

- [ ] A shipped preset with `!` inputs (Review PR / Read Issue) → claude starts with the merged message already in it: banner + command output, in order, one response
- [ ] The `!` output was produced in the directory claude started in — check it on a preset whose command `cd`s into a worktree, not just `z {repo}`
- [ ] A command that can't take the append (`… && claude --resume`, `… | claude`, a trailing comment) → every input goes to the typed route instead, i.e. today's behaviour
- [ ] No `tc-prompt-*.sh` is left in `$TMPDIR` after the tab opens (the substitution deletes it); after a run that fails before the terminal opens, none is left either
- [ ] Tab Config / AppleScript / CLI argument quoting survives the appended `"$(…)"` — the command block shown in the pane must not be split or mangled

**claude input — typed route (leftovers only)**

- [ ] Scheduled inputs are typed and submitted in order — put a slash command first so nothing merges, then `!`-prefixed shell mode after it
- [ ] **Both routes at once** (e.g. `!gh pr diff {number}` then `/review`): nothing is typed until the merged message is on screen, and then the leftover is delivered. Submitting the merged message clears the input box, so typing early loses the leftovers outright — and the readiness gates are far too early to help (measured on claude 2.1.238: raw mode at 0.1∼0.19s, message render at 2.06∼3.41s). The app watches for the `==== terminal-checkout tc-… ====` first line, so **confirm that line really is visible in this terminal's screen read** — if the TUI collapses or hides it, the leftovers get dropped after 2 minutes and the app log says so
- [ ] Gates ①②: no input leaks into the shell before claude is up (including the canonical-mode window right after exec)
- [ ] Gate ③: quit the original claude and start a new claude on the same tty — remaining inputs must not flow into it
- [ ] Closing the session tab mid-way aborts delivery
- [ ] Submission is held while the trust prompt for a first-time folder is up
- [ ] Buttons with no scheduled claude input do no input-delivery preparation (helper etc.) — no clutter commands appear in the tab
- [ ] Same for buttons whose inputs **all merged**: no helper, no permission check, no clutter command — this is the case for every shipped preset, so it is what you will see by default

**Terminals using an in-pane helper (Warp)**

- [ ] Helper fails to launch (missing from the bundle, socket path over the limit) — the command still runs, only claude input is abandoned, and the reason lands in the app log
- [ ] The helper disappears after delivery ends (`ps -axo command= | grep warp-helper`; the socket file is deleted too)
- [ ] Closing the tab mid-delivery makes the helper exit on its own — no stray processes remain
- [ ] Without screen-reading permission, input is not delivered and the reason lands in the app log and the setup window (must be distinguishable from the command still running)
- [ ] Inputs over 512 bytes (multi-byte text included) are delivered untruncated — the branch that chunks around the tty input-queue cap
- [ ] Pressing two buttons in rapid succession opens two tabs each with its own command (the Tab Config files don't overwrite each other)
- [ ] A user-created Tab Config with the same name is not overwritten
- [ ] While the user is looking at another tab or app, submission is held and resumes to completion on return (no probe marker may remain in the input box in the meantime)
- [ ] Revoking the Accessibility permission mid-delivery stops any further injection, and leftover fragments get cleaned up
- [ ] Whether that terminal's way of persisting session history (per user report, Warp saves only GUI-launched sessions) applies to the tabs we create

## 3. Verification tools

To hit the app without going through the extension, feed the relay a payload with the same framing Chrome uses (4-byte little-endian length + JSON). The socket path is fixed relative to home, so any copy of the relay attaches to the running app — unless `TERMINAL_CHECKOUT_SOCKET` lingers in your shell, in which case it goes to that socket.

```bash
python3 -c 'import struct,subprocess,sys
p=sys.stdin.read().encode()
r=subprocess.run(["/Users/<you>/Applications/Terminal Checkout.app/Contents/MacOS/terminal-checkout-relay"],
                 input=struct.pack("=I",len(p))+p, capture_output=True)
n=struct.unpack("=I",r.stdout[:4])[0]; print(r.stdout[4:4+n].decode())' <<< \
'{"command_template":"z {repo} && claude","variables":{"repo":"terminal-checkout"},"claude_inputs":["!echo ok"]}'
```

The payload above merges (its one input is a `!` line and the command ends in `claude`), so it exercises the merged route. Put a slash command first — `"claude_inputs":["/help","!echo ok"]` — to exercise the pure typed route, or put it last — `["!echo ok","/help"]` — to exercise both routes and the render gate between them.

- **New tab and working directory**: compare the set of ttys with attached shells before and after the run (`ps -eo tty,command`), then check the new tty's shell pid with `lsof -a -p <pid> -d cwd` for its working directory. Verifiable without any permission to control the terminal app
- **Whether claude actually received a *typed* input**: look for `<bash-input>` (shell mode) and `<command-name>` (slash commands) in `~/.claude/projects/<cwd slug>/*.jsonl`. Order and timestamps are recorded without reading the screen
- **Whether claude actually received the *merged* message**: the same transcript, but it lands as the session's first plain user message — banner text (`==== !… ====`) and command output inline. A merged `!` leaves **no** `<bash-input>` record, because the shell ran it, not claude's Bash tool. Don't read that absence as a delivery failure
- **The app's verdict**: `/usr/bin/log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info` — on success it records a delivered-count line for the typed route (the app logs it in Korean today: `입력 N개 중 M개 전달`). A fully merged run logs nothing there, because nothing was delivered by injection. The absolute path matters because `log` can be shadowed by shell functions/aliases
- **What the merged message will be**: read the generated script before running it — `cat "$TMPDIR"/tc-prompt-*.sh`, or run it by hand (`/bin/sh "$TMPDIR"/tc-prompt-<token>.sh`) to see the exact text claude will receive. It deletes itself once the tab's command reaches `claude`
- **Pressing setup-window buttons**: synthesizing clicks at coordinates sends the event to whatever window overlaps that point (verified empirically). Pressing the button directly via the Accessibility API is more reliable. To capture just the window, use `screencapture -l <windowID>`

Even when the app delivers all 3 claude inputs, if claude starts autonomous work after seeing its first output, the rest sit in claude's own input queue (verified empirically) — the app log's delivered count and the transcript's executed count can differ, so don't misread that as delivery failure; check both pieces of evidence together.
