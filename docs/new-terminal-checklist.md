# New-terminal support checklist

Terminal branches are scattered across Core's execution and input delivery and the App's settings, permissions, and setup window, while the unit tests and `app/e2e.sh` never actually open a terminal (e2e exercises only error paths). So when wiring up a new terminal, a missed branch surfaces only in real use, after tests pass — this list exists to close that gap.

Per-terminal pitfalls already confirmed (WezTerm's window selection and GUI-app PATH, iTerm2's `current window`) are in `CLAUDE.md` and are not repeated here.

## 1. Code touch points

Terminal identifiers are defined by Core's `enum Terminal` (`Terminal.swift`), and the app stores the rawValue under the `terminal` key in `UserDefaults` (`iterm`, `wezterm`, `warp`, `cmux`). The extension doesn't know this value and gets no way to learn it — behaviorally there is nothing to touch on the extension side.

Adding a case makes every default-less switch (the execution dispatch; the setup window's radio restore, permission section, and pipeline nodes) surface as compile errors. But the compiler only catches switches — visibility conditions and guidance copy written as `==` comparisons, and everything outside code (scripts, docs), are still caught only by the tables below. Don't stop at chasing compile errors.

**Core**

| Spot | To do |
|:---|:---|
| `Terminal` (`Terminal.swift`) | Add the case. Also add a one-line rawValue literal to the stored-value oracle test (`TerminalIdentifierTests`) |
| `TerminalRunner.runInTerminal(command:terminal:claudeInput: ClaudeDelivery.Admission?)` | Add the execution branch (the compile error shows you where). `claudeInput` is the admission reserved for typed input delivery — and it is **not** "this button has claude inputs", it is "these inputs will be typed rather than riding in argv" (`ClaudeInputPlan.swift`), which is **always** true for the three shipped presets that schedule claude input, since all three are `!`-only, and vacuously false for the other eight, which schedule none |
| `TerminalRunner.claudeInputBlocker` | Decide what makes typing impossible for this terminal **before anything is created**, and return it. The switch has no `default`, so the compile error brings you here — but returning nil is not the end of the job: if the answer only becomes known deeper in your `runInXxx` (WezTerm learns it when the mux does not answer), raise it there through `claudeInputRejection` while nothing has been spawned yet. Anything discovered *after* the tab exists is a log line, not a rejection |
| `TerminalRunner.runInXxx(_:)` (new) | Create a new tab → send the command → return a `TerminalSessionHandle` |
| `TerminalSessionHandle` (`ClaudeInjector.swift`) | Add the case. If no handle can be made (`.none`), claude input is not delivered |
| `ClaudeInjector.deliverClaudeInputs` | The branch that obtains the tty path from the handle |
| `ClaudeInjector.sendKeys` | Three kinds: text, CR (`\r` = `claudeSubmitKey`, submit), and the two-byte clear sequence (`\u{15}\u{7F}` = `claudeClearInputKey`, Ctrl+U then Backspace, clear the input box) |
| `ClaudeInjector.screenText` | Screen-text lookup — snapshot **immediately before and after** typing and compare (`screenReflectsNewInput`). If the screen can't be read, the right answer is to not send input |
| `ClaudeSessionIO.screenNeedsPaneProof` | true for terminals whose screen lookup can't be pinned to the session — every input then first proves the pane with a nonce probe. Leave the default (false) for terminals that read exactly by pane/session id |
| `ClaudeDelivery` (`ClaudeInjector.swift`) | Only if your terminal leaves a **process alive in the pane** (Warp's injection helper is the one today). The registry already brackets every delivery, so the language restart is blocked while yours runs — but `liveWarpSockets` and `endEveryHelper` match on `.warp` alone, so a second helper would need its own case or it is never told to stop. Nothing to do for a terminal that spawns no helper |

If even one of the three `ClaudeInjector` branches is missing, execution still works and only claude input silently stalls. In particular, without `screenText` the reflection check fails and CR is never sent.

Claude inputs reach the session by two routes and **only the second one is per-terminal.** `ClaudeInputPlan.swift` either appends a single plain-text input to the argv of the `claude` the command starts — before any terminal branch is taken — or hands all of them to `ClaudeInjector` to be typed; there is no request that uses both. (Mixing them meant racing claude's own startup submission, which clears the input box, and no gate over that race can be built from signals the user's shell cannot forge — a zsh with `set -x` prints the substituted argv, marker and all, before the exec.) So a new terminal inherits the argv route for free and the table above only covers the typed route. Two consequences when adding a terminal: **every shipped preset that schedules claude input is `!`-only, so all three of them take the typed route** — that route is what the buttons actually exercise, and on Warp it is why the Accessibility permission is required for all of them; and a terminal that quotes or rewrites the command it is handed must survive `… command claude -- '<message>'` — the appended argument is ordinary command text, but it is the first place a new escaping bug will show (to reach it at all you need a button whose inputs are one plain-text line, because that is the only shape that rides in argv).

A terminal driven by a CLI needs explicit executable-path search; a terminal driven by AppleScript adds one more TCC automation target (along with the permission-request and status-lookup paths).

**The bytes have to survive the carrier you pick, and only some carriers keep them.** Measured: `Process.arguments` and `Process.environment` both re-encode text to NFD on Darwin, while a pipe, a file, a unix socket and JSON decoding leave it alone. A user's claude message is free text in five languages, and a `!` one reaches a shell, so a terminal whose command or input travels in an argument or an environment variable changes what the user wrote. Two consequences when adding a terminal: **every AppleScript run goes through `runAppleScript`** (`AppleScriptSupport.swift`), which delivers on stdin and is enforced by a test that walks the sources counting call sites — do not add a second `osascript` call site; and if the only carrier available is an argument, make the argument **ASCII** the way `wezTermFallbackArguments` does rather than moving it to the environment. `ProcessArgumentBoundaryTests` pins the platform behaviour, so a change in it fails there.

A terminal with no API to address a pane at all (Warp) is covered instead by a helper process running inside the pane — then the targets in `app/Package.swift` and the bundle copy/signing in `app/build.sh` grow too.

**App**

| Spot | To do |
|:---|:---|
| `Settings.terminal` | Auto-detection order when there is no stored value (the unknown-stored-value fallback to iTerm2 lives in `Terminal(storedValue:)` alone — nothing to touch) |
| `PermissionChecker.isXxxInstalled` | Install detection. If AppleScript-driven: status lookup, permission request, and opening System Settings too |
| `SetupWindowController` | Add the radio button, disable when not installed, save (`terminalChanged` — the radio→case mapping is an if-chain the compiler can't catch) and restore, permission-card visibility conditions (`isHidden` comparisons), per-terminal guidance notes, and the pipeline node's name/color/description |
| `Socket access mode is a prerequisite (cmux)` | Add the live status enum, the setup-window card, the explicit settings-file button, the timestamped `.bak`, and the fact that a missing socket cannot distinguish a stopped cmux from a denied mode |
| `app/Info.plist` | `NSAppleEventsUsageDescription` is the single one for the whole app — update it if the copy hard-codes a terminal name |
| `install.sh` | The preflight's terminal-detection list and guidance copy. Finding none exits 1 and blocks installation, so missing this makes installation itself fail on machines that have only the new terminal (its detection criteria differ from the app's) |
| `README.md` | Terminal names are hard-coded in the required-terminals list, the architecture diagram, setup steps, permission notes, fallback limits, and troubleshooting. If the code supports it but this is stale, users read it as unsupported |

Terminal names are also embedded in the description messages in `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`; `extension/manifest.json` only references that key and remains unchanged.

**Tests**

Parts that parse CLI responses or script output (window picking, pane→tty lookup, and so on) get extracted as pure functions and pinned in `app/Tests/CoreTests` — `WezTermWindowTests` is the example. Execution itself is not covered by unit tests, so the hands-on list below is the only verification.

## 2. Hands-on checklist

Start with the new terminal selected in the app setup window and all 4 pipeline lights green.

**Launch and commands**

- [ ] Setup window [Run in Terminal] → echo runs in a new tab
- [ ] With two displays and another app focused on the other display, the setup window stays centered on its chosen display after its measured resize rather than ending at a screen edge
- [ ] After changing the app language, the setup window stays at its original position (not verified on the device; the custom language picker is not exposed in the Accessibility tree)
- [ ] Disconnect the chosen display while a measured resize is pending → the setup window is recovered onto an available display and clamped there
- [ ] Repository-page button → the new tab's working directory is that repo (`{repo}` `{owner}` `{main}` substituted)
- [ ] PR button → new tab + `{repo}` `{branch}` `{base}` `{branch_underbar}` substituted
- [ ] Issue button → new tab + `{number}` `{owner}` substituted
- [ ] Extension-icon click → the first button on PR, issue, and repository pages respectively (three distinct branches)
- [ ] `{main}` substitution via repository/issue buttons on a repo whose default branch is `master` (read from the page; on failure it silently falls back to the global default)
- [ ] `{cd}` with no base directory set — renders as a bare `z {repo}`, and without an interactive login shell the zoxide function isn't found and the first step dies. Compare the command printed in the tab against the pre-base-directory one: it has to be identical
- [ ] `{cd}` with a base directory set and a cold zoxide DB (or no zoxide at all) — the fallback lands in the repository and the chain runs to its end
- [ ] `{cd}` with a base directory set and the repository not cloned yet — the clone clause runs and the rest of the chain continues inside the fresh clone
- [ ] `{cd}` with a base directory set and `<base>/<repo>` existing but **not** a git repository (an empty folder is enough) — the chain must not settle there: `fatal: not a git repository` appears and the clone clause takes over (empty folder) or stops visibly (non-empty)
- [ ] A long `&&` chain (create worktree → cd → merge → claude) reaches its final step

**Window selection**

- [ ] With two or more windows open and the second one active, run → the tab appears in the window you were looking at
- [ ] Fallback when no window to attach the tab to is found
- [ ] Fallback when the chosen window closed just before tab creation (giving up here pops a new window)
- [ ] With the terminal not running at all — does it open as a new window, and is claude input abandoned in that case?

**claude input — argv route (a list holding exactly one plain-text input, and nothing else: no permission, no helper, no screen reading)**

- [ ] A **plain-text-only** button (no `!`, no slash, no `#`) → claude starts with that text already submitted, and nothing is typed. Shipped presets are all `!`, so they do **not** take this route any more — they are typed (see below)
- [ ] A shipped preset with `!` inputs (Review PR / Read Issue) → the commands **run in claude's shell mode**, one merged line, banners between them, in the directory claude started in (check one whose command `cd`s into a worktree). They appear in the session as commands, not as claude deciding to run something
- [ ] A command that can't take the append (`… && claude --resume`, `… | claude`, a trailing comment, a heredoc, a multi-line command, or **any word anywhere** that can rebind a name or that we cannot read — `function`/`alias`/`eval`/`source`/`export`/`PATH=…`/`if`/`'quoted'`/`$VAR`) → every input goes to the typed route instead, i.e. today's behaviour
- [ ] Nothing is written to `$TMPDIR` any more (the pre-run script and its context file are gone). What remains is a **legacy sweep**: directories named `tc-prompt-<8 hex>` left by older installations are cleared by any request and by `uninstall.sh`. Old note kept for reference: `prompt.sh` inside is gone once the tab's command reaches `claude`; **`context.txt` deliberately stays** — deleting it before `execve` would lose the assembled text if the exec then failed, so a sweep reclaims it instead. The sweep reads **consumption, not just age**: 6 hours once `prompt.sh` is gone, 7 days while it is still there (nothing has run it yet — `sleep 21601 && claude` was reclaimed out from under a pending command) or while `handed-to-claude` is present (claude was told to read the file during the session). A run that fails before the terminal opens removes the whole directory immediately, and `uninstall.sh` takes them all except the ones carrying `handed-to-claude`, which it lists instead of deleting
- [ ] Tab Config / AppleScript / CLI argument quoting survives the appended `command claude -- '<message>'` — the command block shown in the pane must not be split or mangled, and the single-quoted message must arrive as one argument
- [ ] With a `claude` **function or alias wrapping an executable**, the argv route **bypasses the wrapper**: the append invokes `command claude`, which skips functions and aliases (measured in zsh, bash and dash) but **not builtins**. Confirm the session starts from the executable — and that the append still happens, which needs the startup check to see past the wrapper (it asks a child `/bin/sh`, so the rc's function is not there to hide the file). With `claude` available *only* as a function or alias there must be **no append at all** — appending would end in `command not found` in the pane — and the setup window says why. Residuals to confirm as *documented*, not as bugs: a PATH that resolves `claude` elsewhere, a `command` function or alias in the rc, and a login shell whose answers do not match the shell this terminal opens tabs with. The word list in `commandAcceptsAppendedClaudePrompt` is a second layer over that structure, and its completeness is **not** claimed

**claude input — typed route (everything except a single plain-text input, so: every shipped preset that schedules claude input)**

- [ ] Scheduled inputs are typed and submitted in order — a slash command anywhere in the list is enough to put the whole list on this route, so `["/help", "!echo ok"]` exercises both an inert input and `!`-prefixed shell mode
- [ ] **A boundary anywhere sends everything down this route** (e.g. `!gh pr diff {number}` then `/review`): the command is left untouched, claude starts empty, and both inputs are typed. Confirm the command really is unchanged — one argv message plus typed leftovers in the same session is the combination that was removed, because submitting the argv message clears the input box and wipes anything typed before it renders (measured on claude 2.1.238: raw mode at 0.1∼0.19s, message render at 2.06∼3.41s)
- [ ] **The input box is emptied as part of every input and once when delivery ends** — that, not the screen, is what stops a leftover from being appended to the next input. Count them: one Ctrl+U per input (the marker experiment below) plus one at the end **unless the post-CR look happened to see our text gone from the screen** — a written CR is never evidence the box is empty, so that last one is the normal case, not the exception. Type into a session by hand while delivery is running: your draft is erased (accepted cost, issue #16), and nothing of ours is left behind for your Enter
- [ ] **Every input is preceded by a marker experiment**: a short random marker is typed, seen to appear, cleared, and seen to disappear — that is what establishes the screen is this pane, that what appears is in the input box, and that the TUI acted on the Ctrl+U. The **body is typed once**, into the empty box the experiment leaves behind (check a `!` input still enters shell mode there). Press Enter yourself while the marker is on screen: the marker gets submitted, and the command still runs exactly once — with the body in that position it ran twice
- [ ] **After the CR, the only question asked is "may the next input be typed?"** The app is not trying to establish that claude received anything — nothing outside the TUI can. It compares the region **from our input to the end of the screen** (everything the input box can occupy) and stops only when that region has not moved. It refuses to judge whenever our text is not uniquely identifiable there — a probe that also appears in a hint line below the box pinned the comparison and dropped every later input (reviewer reproduction: input `y` against "bypass permissions on") — and a read it could not make no longer erases what earlier reads showed. On terminals whose screen cannot be attributed to our pane (Warp) the look is skipped entirely, which is fine because the clearing rule above does not depend on it. For a new terminal: decide which of the two it is (`TerminalSessionHandle.screenNeedsPaneProof`), and check that switching tabs mid-delivery does not stop a delivery that was going fine
- [ ] **An input whose CR has gone out is never retyped.** Confirm that a transient send failure right at the CR does not produce two messages (with `!` inputs it would run the user's command twice) — the loop resends the CR only, then stops
- [ ] **Nothing of ours is left in the input box.** Writing the CR is not evidence that the TUI consumed it, so a stuck input is cleared with Ctrl+U from the single cleanup point in `submitClaudeInputs` — check the box is empty after a delivery that stopped part-way, and that the **end-of-delivery** Ctrl+U goes out in every case, including a delivery where everything worked — the earlier rule ("a completed delivery must not send a stray Ctrl+U") was reversed in round 7 and the cost accepted, because the alternative is our `!` line waiting in the box for the user's Enter
- [ ] Gates ①②: no input leaks into the shell before claude is up (including the canonical-mode window right after exec)
- [ ] Gate ③: quit the original claude and start a new claude on the same tty — remaining inputs must not flow into it
- [ ] Closing the session tab mid-way aborts delivery
- [ ] Submission is held while the trust prompt for a first-time folder is up
- [ ] Buttons with no scheduled claude input do no input-delivery preparation (helper etc.) — no clutter commands appear in the tab
- [ ] Same for a button whose only input is **plain text**: it rides in argv, so no helper, no permission check, no clutter command. Note this is **no longer** what the shipped presets do — they are all `!`, hence typed

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

**Terminals needing a socket access mode (cmux)**

- [ ] The setup window draws all four live cmux states: `notInstalled`, `notRunning`, `denied`, and `reachable`.
- [ ] With socket control mode disabled, pressing a button reports the automation-mode error immediately rather than a timeout.
- [ ] The [Allow Automation] button stays enabled for a repairable `.failed` state such as `Error: Failed to write to socket`, so the recovery path remains available.
- [ ] Clicking [Allow Automation] creates the timestamped `.bak`, changes `~/.config/cmux/cmux.json`, and confirms `cmux ping` → PONG without restarting cmux (live reflection measured 2026-08-23).
- [ ] Pressing [Allow Automation] twice in the same second does not remove the existing `.bak`; the button is disabled while the first operation is in flight.
- [ ] The setup window's [Allow Automation] button is disabled when the live cmux status is `reachable`.
- [ ] After [Allow Automation], the backup and a newly created cmux.json are mode 0600; an existing cmux.json keeps its original permissions (cmux-created files are 0600 because they may hold `socketPassword`).
- [ ] When `cmux.json` is a symlink, [Allow Automation] edits its resolved target, leaves the symlink in place, and writes the backup beside that target.
- [ ] If narrowing the backup permissions fails after the setting is applied, the card shows a backup-protection warning while retaining the live status diagnosis.
- [ ] After backup chmod fails, [Check Again], switching terminals, and pressing [Allow Automation] again keep the warning until that backup is mode 0600 or gone.
- [ ] With two cmux windows and the second active, the new workspace appears in that active window (R1-g measured: yes — with the second window active, the workspace landed there).
- [ ] Switching to another tab during delivery does not stop it; cmux surface delivery continues to completion (R1-e measured: yes).
- [ ] A `!` input enters claude's shell mode, and the clear sequence uses two separate `surface.send_text` calls, `0x15` then `0x7F`, to remove the shell-mode prefix as well as the text.
- [ ] The clear key (Ctrl+U, Backspace) was measured **inside a running claude TUI**, not in a raw shell — claude enables the kitty keyboard protocol, and a terminal's key-event path can encode control keys differently under it (cmux's key-event path did; measured 2.1.246).
- [ ] When cmux's version is raised, confirm all four RPC methods still exist, `debug.terminals` reports a tty basename, `workspace.create` returns `surface_id`, and `cmux ping` prints PONG.
- [ ] With shell integration disabled in a cmux pane, `debug.terminals` leaves tty null: the command runs, claude input is abandoned, and the reason is logged.

## 3. Verification tools

To hit the app without going through the extension, feed the relay a payload with the same framing Chrome uses (4-byte little-endian length + JSON). The socket path is fixed relative to home, so any copy of the relay attaches to the running app — unless `TERMINAL_CHECKOUT_SOCKET` lingers in your shell, in which case it goes to that socket.

```bash
python3 -c 'import struct,subprocess,sys
p=sys.stdin.read().encode()
r=subprocess.run(["/Users/<you>/Applications/Terminal Checkout.app/Contents/MacOS/terminal-checkout-relay"],
                 input=struct.pack("=I",len(p))+p, capture_output=True)
n=struct.unpack("=I",r.stdout[:4])[0]; print(r.stdout[4:4+n].decode())' <<< \
'{"command_template":"{cd} && claude","variables":{"repo":"terminal-checkout","owner":"dazebug"},"claude_inputs":["!echo ok"]}'
```

The payload above is typed (its input is a `!` line), which is the route every shipped preset that schedules claude input takes. To exercise the argv route instead, use a single plain-text input (`["summarise the diff"]`) with a command ending in a bare `claude`.

`{cd}` is filled in by the app from its base directory setting, so the same payload exercises the bare `z` clause or the full `z`→`cd`→`clone` chain depending on what the setup window holds. Sending a `cd` variable of your own is rejected (`Unknown variable: {cd}`), which is the point — the app is the only source for it.

- **New tab and working directory**: compare the set of ttys with attached shells before and after the run (`ps -eo tty,command`), then check the new tty's shell pid with `lsof -a -p <pid> -d cwd` for its working directory. Verifiable without any permission to control the terminal app
- **Whether claude actually received a *typed* input**: look for `<bash-input>` (shell mode) and `<command-name>` (slash commands) in `~/.claude/projects/<cwd slug>/*.jsonl`. Since round 10 a merged `!` run lands here too — one `<bash-input>` carrying the whole `;`-joined line, banners included. Order and timestamps are recorded without reading the screen
- **Whether claude actually received the *argv* message**: the same transcript, where it lands as the session's first user message with no `<bash-input>` around it.
- **The app's verdict**: `/usr/bin/log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info` — on success it records a count line for the typed route: `claude(pid N): sent M of K input(s) (receipt is not confirmed)`. It says **sent**, not delivered, on purpose — nothing outside the TUI can confirm claude took the message. A run that went entirely through argv logs nothing there, because nothing was delivered by injection. The absolute path matters because `log` can be shadowed by shell functions/aliases
- **What the merged `!` line will be**: it is built in `claudeTypedInputs` and nothing is written to disk — read it off the app log line for the request, or reproduce it with the same inputs in a unit test. A run merges only when every body provably joins (`claudeBodyJoinsSafely`); otherwise each input is typed on its own.
- **Pressing setup-window buttons**: synthesizing clicks at coordinates sends the event to whatever window overlaps that point (verified empirically). Pressing the button directly via the Accessibility API is more reliable. To capture just the window, use `screencapture -l <windowID>`

Even when the app delivers all 3 claude inputs, if claude starts autonomous work after seeing its first output, the rest sit in claude's own input queue (verified empirically) — the app log's delivered count and the transcript's executed count can differ, so don't misread that as delivery failure; check both pieces of evidence together.
