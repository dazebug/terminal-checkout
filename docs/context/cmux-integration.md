# cmux integration

How the app reaches a cmux server, what it is allowed to ask of it, and what it deliberately does not do. The mechanisms and the measured pitfalls live in `CLAUDE.md`; this file holds the forks. Everything here was measured against cmux v0.64.22 unless an entry says otherwise.

## The socket control mode is the user's setting, and the app stopped short of writing it

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; `app/Sources/App/CmuxConfigHelp.swift`; denial measured from an external shell
**Revisit when:** cmux gains a supported way for an outside process to request automation mode, or `cmux settings automation` stops requiring a socket that automation mode is what grants

cmux only accepts socket commands from processes it can prove are its own descendants, so the app cannot talk to it until the user sets `socketControlMode` to `automation` in `~/.config/cmux/cmux.json`. The setup window's button copies the JSON fragment to the clipboard and opens that file — or its folder if the file does not exist yet — and writes nothing.

**Reason:** the default mode (`cmuxOnly`) authorizes by walking the peer pid's ancestor chain up to the cmux server. An app launched through LaunchServices is never in that chain, by construction, so no amount of care on our side makes the default mode work. `automation` removes only the ancestry test and keeps the same-uid test, which is the boundary the app's own socket already uses — so it adds no trust boundary that this machine did not already have. `password` and `allowAll` also pass, and the app does not object to them.

**Rejected alternative — write `cmux.json` for the user.** This was built and shipped inside this loop, then removed: a timestamped `.bak`, a JSONC text-splice edit that preserved comments and other keys rather than parsing and re-serializing, a 0600 temp file, an atomic replace, and a live `cmux ping` to confirm the daemon picked it up. It came out again because of what it cost to keep honest — roughly half the findings of the first seven cold-review rounds landed on this one feature (18 of them), and every failure mode it produced was of the same three kinds: damaging a file the app does not own, widening a permission on the user's behalf, or reporting a success the app had not actually verified. Removing it deleted 417 lines of edit logic, 387 of config parsing and 677 of tests, and left the feature the user actually needs: knowing which value to set and where.

**Rejected alternative — delegate to `cmux settings automation`.** The obvious escape from hand-editing JSON, and it does not work in the state where it is needed: measured from an external shell while `socketControlMode` was still `cmuxOnly`, the CLI answered `Error: ERROR: Access denied - only processes started inside cmux can connect`. The subcommand goes through the same socket that automation mode is what unlocks, so it can only turn on a setting that is already on.

**Rejected alternative — harvest a capability token.** cmux mints bearer tokens in the environment of the panes it starts, and they do not expire, so a token read out of a pane would authorize us without any setting being changed. Rejected on the boundary rather than on feasibility: it takes a credential from a context that never offered it, through an interface cmux does not support for this. Feasibility was never established either — the closest measurement, made while looking for the tty, is that `ps -E` does not show a system binary's environment at all.

**Rejected alternative — recommend `allowAll`.** It also lifts the ancestry test, and it does so by making the socket world-accessible. `automation` is the narrowest mode that solves the actual problem.

**Consequence, accepted:** cmux costs zero macOS TCC permissions — the same grade as WezTerm — in exchange for one setting the user changes by hand, once. A second consequence is diagnostic: with no socket the app cannot tell "cmux is not running" from "cmux refused us," so it never reads the settings file to guess which one it is; `Access denied` is reported as itself, because launching cmux cannot fix it.

## The send waits for raw mode, because the writer cannot see the truncation

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `app/Sources/Core/TerminalRunner.swift`, `app/Sources/Core/CmuxControl.swift`; Darwin 25.4.0 pty probe with the master drained as a terminal; PR #64
**Revisit when:** cmux exposes a reliable indication that the shell line editor is reading the new surface

The command waits until the pane's tty reports raw mode before sending its text and CR. If that observation does not arrive before the deadline, a payload within the canonical limit is sent through the existing path, while a larger payload is refused before it can be truncated.

**Reason:** canonical mode keeps exactly 1024 bytes of an unread line and silently discards the rest, including CR, even though the writer sees every byte as accepted. A 1023-byte payload plus CR survives, but a longer command can therefore appear successful while remaining truncated and unsubmitted. Raw mode is the observation that removes that buffer from the path; the bounded fallback preserves short commands and makes the unsafe case visible.

**Rejected alternative — always send immediately.** This is the former behavior: it reaches the canonical buffer before the shell reads and can silently lose the tail and CR.

**Rejected alternative — truncate based on length.** The app would change the user's command and still would not make the resulting command correct.

**Rejected alternative — always wait until the deadline.** A slow but healthy shell would add the full ten-second delay to every command, including payloads that could be sent safely.

**Rejected alternative — send the text first and CR later.** The canonical buffer has already crossed its 1024-byte boundary before CR is sent, so delaying CR cannot restore the discarded bytes.

**Consequence, accepted:** short commands can still use the bounded fallback when raw mode is unavailable, while an oversized command fails visibly before transmission instead of being silently altered in the pane. The `.refuseTooLong` path occurs after `workspace.create`, so it leaves one empty tab; that is accepted because a visible failure is safer than silent truncation and the error still reaches the button.

## Each cmux channel is pinned to its own socket, because discovery crosses channels

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, `app/Sources/App/PermissionChecker.swift`; stable/NIGHTLY pointer and cross-channel PONG measurements; PR #64
**Revisit when:** cmux changes its per-channel pointer files or makes CLI discovery channel-safe without an explicit socket

Stable and NIGHTLY each write the same live socket path to two pointer files. The state-directory candidate is read first, followed by the `/tmp` candidate, and the first candidate whose target exists is passed through `CMUX_SOCKET_PATH`; the state copy is preferred because `/tmp` is periodically cleaned, while `/tmp` remains the only clue when state is absent. The socket basename is never cached as a fixed name, so each new request and launch retry resolves the candidates again, while later RPCs keep the target that created the surface. If the selected channel has no live pointer but another channel does, the app does not use unpinned discovery; if neither channel has a live pointer, `.discover` preserves the existing single-channel behavior.

> Superseded 2026-08: the fixed-name `cmux.sock` lookup is superseded by channel-specific socket-pointer resolution.

**Reason:** both channel binaries contain the names of all channel pointer files, and an unpinned NIGHTLY CLI reached the stable server while both were running. A pointer target is the only measured channel-specific socket identity, so carrying it from workspace creation through readiness, input, screen reads, and the setup ping keeps the server that answers deterministic.

**Rejected alternative — keep the fixed name `cmux.sock`.** That name was stale on this machine after a restart, while the live basename had changed.

**Rejected alternative — ignore the pointer and use CLI auto-discovery.** The cross-channel PONG measurement shows that auto-discovery can answer from the wrong server.

**Rejected alternative — use different CLIs but share one socket.** Choosing the right executable does not constrain the server when the CLI itself performs unpinned discovery, so the same cross-channel error remains.

**Rejected alternative — discover whenever the selected channel has no pointer.** With the selected channel stopped and the other channel running, this creates the workspace on the other channel's server and makes the setup window report a false reachable state.

**Consequence, accepted:** stable and NIGHTLY remain separate choices and never fall back to one another; a live pointer is always honored, a missing selected-channel pointer blocks cross-channel discovery, and discovery remains only when no channel has a live pointer. No settings file is modified by the app.

## `cmux rpc` is the only control path, and it carries four methods

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; `app/Sources/Core/CmuxControl.swift`
**Revisit when:** the pinned cmux version moves — the raw v2 method names are not a stable public API

Everything the app asks of cmux goes through `cmux rpc <method> <json>`: `workspace.create`, `surface.send_text`, `surface.read_text`, `debug.terminals`.

**Reason:** rpc is the only path that does not rewrite the payload. The parameters travel in argv because the CLI has no stdin JSON route, so non-ASCII is escaped as `\uXXXX` — Foundation re-encodes `Process.arguments` to NFD on Darwin, and a Korean or Japanese message would otherwise arrive at the terminal in a form the user never typed.

**Rejected alternative — `cmux send` / `--command`.** Both pass through `unescapeSendText`, which turns a literal `\n` into CR and does not handle `\\` at all. A user's text containing either is silently altered, and a newline submits the line early.

**Consequence, accepted:** the method names are internal to a cmux version. They are declared once as constants, every failure log names the method that failed, and `docs/new-terminal-checklist.md` carries "re-verify the four methods" as an item for whenever the pinned version moves.

## A launch retry is decided by the transport failure, never by matching a message

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; `classifyCmuxCLIFailure` in `app/Sources/Core/CmuxControl.swift`
**Revisit when:** cmux changes either connection-phase error string, or gains an exit code that distinguishes them

When an RPC fails, the app decides whether it may launch cmux and retry by asking one question: did this failure happen before the request reached the server? Only two stderr forms answer yes, both carrying the CLI's required `Error: ` prefix — `Error: Failed to connect to socket at …` and `Error: Socket not found at …`. Anything else, including a message with no prefix, is treated as a failure that may have had a server-side effect, and is rethrown.

**Reason:** `workspace.create` is not idempotent. A retry after a request that did reach the server creates a second workspace, so the retry has to be gated on proof that nothing happened — not on a guess about what the message means. Classifying by transport fact rather than by substring is also what makes the gate fail closed: a message shape we have never measured falls into "may have had an effect," which is the safe side.

**Rejected alternative — substring matching.** A partial match cannot tell a connection refusal from a post-create failure that quotes the same words, and it silently starts matching different things when the wording drifts. An earlier version of this classifier also anchored on the error text *without* its `Error: ` prefix — the test passed while the real CLI output did not match, so the auto-launch path was dead. Requiring the prefix that the CLI always emits is what makes the anchor testable against something real.

**Rejected alternative — preflight with `cmux ping`.** The execution path deliberately does not ping first. `workspace.create` is tried immediately: a socket denial then fails at once with the reason the user needs, and a ping in front of it would only add a round trip and a second thing that can be wrong. The setup window's live status probe *does* use ping, because its question is different — it is asking about state, not performing an action.

## The workspace is created focused and unaddressed

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; measured twice with two windows open
**Revisit when:** cmux changes how an unaddressed `workspace.create` picks its window

`workspace.create` is sent with `focus:true` and no window id.

**Reason:** the server routes an unaddressed create to the most recently active window, so the new workspace appears where the user was looking. This is the problem WezTerm has — without `--window-id`, `wezterm cli spawn` falls back to the mux's oldest window — and cmux simply does not have it. The conditional-fallback ladder that WezTerm needs was planned, measured to be unnecessary, and dropped.

**Rejected alternative — `focus:false`.** A workspace created unfocused can have no pty at all: `debug.terminals` reports `tty: null` and a send comes back `queued: true`. The queued bytes are not lost — the surface flushes them once it warms up, observed both in cmux and in the app's own log — but with no tty there is nothing to check raw mode against, so the gate that decides whether claude is really at a raw-mode prompt cannot be answered and the input is given up.

## The tty comes from `debug.terminals`, not from the pane

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; `ps -E` behaviour measured on this machine
**Revisit when:** cmux exposes the tty on the workspace-creation response

The tty name for a new surface is read by polling `debug.terminals` for the surface id, as a basename that cmux's shell integration pushes up. If it never appears, the command has already started; only the claude input is given up, with a log line.

**Rejected alternative — have the pane tell us (`tty >| file`).** It works, and it puts a line the user did not write into their shell history and leaves a file to clean up.

**Rejected alternative — read the child's environment with `ps -E`.** Measured: the environment of a system binary is not visible this way, so the token cmux exports into the pane cannot be read back out.

**Rejected alternative — read the tty off the screen.** The screen is a rendering of a session, not a fact about it.

## cmux needs no pane proof, so delivery continues in a background tab

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; contrasted with the Warp path in `claude-input-delivery.md`
**Revisit when:** `surface.read_text` stops accepting an explicit surface id

`surface.read_text` is addressed by surface UUID, so a screen read is provably a read of *our* surface. cmux therefore skips the nonce-based pane proof that Warp requires, and claude input keeps being delivered while the user is looking at another tab.

**Reason:** the pane proof exists only because Warp exposes one reused `AXTextArea` and no way to address a pane; where the terminal can answer "what is on surface X," the proof has nothing left to establish.

**Consequence, accepted:** the surface id must be passed explicitly on every read — omitting it falls back to the focused surface, which is exactly the ambiguity the proof was built to remove. A cold surface answers `internal_error`; that is mapped to "could not read," never to "nothing is there," so the reflection check fails closed. Sends and reads are asymmetric here: a send to a not-yet-warm surface queues, while a read of it errors.
