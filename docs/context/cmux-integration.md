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

## Only an oversized send waits for raw mode, because the writer cannot see the truncation

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `app/Sources/Core/TerminalRunner.swift`, `app/Sources/Core/CmuxControl.swift`; Darwin 25.4.0 pty probe with the master drained as a terminal; PR #64; 2026-08-30 unified log
**Revisit when:** cmux exposes a reliable indication that the shell line editor is reading the new surface

When raw mode is observed, any payload is sent immediately. Without that observation, a payload at or below the 1024-byte canonical limit is sent immediately because Darwin's canonical buffer preserves the complete payload, including CR; only a larger payload waits for raw mode, and if raw mode is still not observed at the deadline it is refused before `surface.send_text`.

**Reason:** canonical mode keeps exactly 1024 bytes of an unread line and silently discards the rest, including CR, even though the writer sees every byte as accepted. A 1023-byte payload plus CR survives whole, so waiting for raw mode adds no safety to a payload within the limit. The 2026-08-30 unified log measured the cost of that wait on a slow shell-integration pane: a 24.7-second button press spent 10.4 seconds in this gate, and its 317-byte payload was sent the same way after the deadline.

**Rejected alternative — always send immediately.** This remains rejected for payloads over the 1024-byte limit: before raw mode, the canonical buffer can silently discard the excess and CR. The measured risk does not apply to payloads within the limit, so those now use immediate send.

**Rejected alternative — truncate based on length.** The app would change the user's command and still would not make the resulting command correct.

**Rejected alternative — always wait until the deadline.** A slow but healthy shell would add the full ten-second delay to every command, including payloads that could be sent safely; this concern precisely predicted the 2026-08-30 defect, where 10.4 seconds of a 24.7-second button press bought no additional safety for a 317-byte payload.

**Rejected alternative — send the text first and CR later.** The canonical buffer has already crossed its 1024-byte boundary before CR is sent, so delaying CR cannot restore the discarded bytes.

**Consequence, accepted:** payloads within the canonical limit leave immediately regardless of shell preparation; if the pty does not yet exist, cmux queues the payload and flushes it after warm-up (measured), while oversized payloads still wait for raw mode and fail visibly before transmission instead of being silently altered in the pane. Removing the command-gate wait means the scheduled Claude-input tty discovery deadline now carries the full window alone, so it is 30 seconds; previously the 10-second gate plus the 20-second discovery deadline happened to total the same amount. The `.refuseTooLong` path occurs after `workspace.create`, so it leaves one empty tab; that is accepted because a visible failure is safer than silent truncation and the error still reaches the button.

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
**Evidence:** confirmed; cmux 0.64.22 (102) [ddd4a01bc] issue #68 measurement plan; `app/Sources/Core/CmuxControl.swift`
**Source:** Issue #68 measurement round and PR #60
**Revisit when:** the pinned cmux version moves — the raw v2 method names are not a stable public API

Everything the app asks of cmux goes through `cmux rpc <method> <json>`, and for this feature the same four methods are unchanged: `workspace.create`, `surface.send_text`, `surface.read_text`, `debug.terminals`.

**Reason:** rpc is the only path that does not rewrite the payload. The parameters travel in argv because the CLI has no stdin JSON route, so non-ASCII is escaped as `\uXXXX` — Foundation re-encodes `Process.arguments` to NFD on Darwin, and a Korean or Japanese message would otherwise arrive at the terminal in a form the user never typed.

**Consequence, accepted:** the placement matrix below records probe coverage for cmux 0.64.22 (102) [ddd4a01bc], including capabilities measured for batch creation and layout, but it does not imply the app is issuing every method listed.

**Rejected alternative — `cmux send` / `--command`.** Both pass through `unescapeSendText`, which turns a literal `\n` into CR and does not handle `\\` at all. A user's text containing either is silently altered, and a newline submits the line early.

**Consequence, accepted:** the method names are internal to a cmux version. They are declared once as constants, every failure log names the method that failed, and `docs/new-terminal-checklist.md` carries "re-verify the four methods" as an item for whenever the pinned version moves.

## A launch retry is decided by the transport failure, never by matching a message

**Type:** decision
**Status:** active
**Evidence:** confirmed; cmux 0.64.22 (102) [ddd4a01bc] item 3
**Source:** Issue #68 measurement item 3 and PR #60
**Revisit when:** cmux changes either connection-phase error string, or gains an exit code that distinguishes them

When an RPC fails, the app decides whether it may launch cmux and retry by asking one question: did this failure happen before the request reached the server? Three measured transport forms answer yes to that, with `Error:` prefixes for all:

`Error: Socket not found at <path>`
`Error: Path exists at <path> but is not a Unix socket`
`Error: Failed to connect to socket at <path> (Connection refused, errno 61)`

The middle form is not currently classified in code, so it is a measured gap but remains fail-closed today because a retry there is still considered potentially unsafe by the current floor.

Measured server-side validation failures carried typed prefixes (`invalid_params:`, `not_found:`, `unavailable:`, `method_not_found:`) with body text that is locale-dependent, and they left `workspace.list` / `pane.list` / `surface.list` unchanged in the guarded checks (11→11 workspaces, 1→1 panes, 1→1 surfaces), so the proxy does not change the placement contract on those paths.

**Reason:** `workspace.create` is not idempotent. A retry after a request that did reach the server creates a second workspace, so the retry has to be gated on proof that nothing happened — not on a guess about what the message means. Classifying by transport fact rather than by substring is also what makes the gate fail closed: a message shape we have never measured falls into "may have had an effect," which is the safe side.

**Rejected alternative — substring matching.** A partial match cannot tell a connection refusal from a post-create failure that quotes the same words, and it silently starts matching different things when the wording drifts. An earlier version of this classifier also anchored on the error text *without* its `Error: ` prefix — the test passed while the real CLI output did not match, so the auto-launch path was dead. Requiring the prefix that the CLI always emits is what makes the anchor testable against something real.

**Rejected alternative — preflight with `cmux ping`.** The execution path deliberately does not ping first. `workspace.create` is tried immediately: a socket denial then fails at once with the reason the user needs, and a ping in front of it would only add a round trip and a second thing that can be wrong. The setup window's live status probe *does* use ping, because its question is different — it is asking about state, not performing an action.

## The workspace is created focused and unaddressed

**Type:** decision
**Status:** active
**Evidence:** confirmed in cmux 0.64.22 (102) [ddd4a01bc], issue #68 item 1
**Source:** Issue #68 measurement package and PR #60
**Revisit when:** cmux changes how an unaddressed or addressed `workspace.create` pick their window target

`workspace.create` is sent by the app with `focus:true` and no `window_id`; an unaddressed create follows the server's active-window pointer.

**Reason:** the server routes an unaddressed create to the most recently active window, so the new workspace appears where the user was looking. This is the same class of risk WezTerm handles with `--window-id`; with no comparable flag, WezTerm can fallback to the oldest window when targeting is absent, so cmux's conditional fallback ladder was measured unnecessary and dropped. The new fact is that `window_id` is supported and validated: an unknown window id returns `Error: unavailable: TabManager not available` with no list delta.

**Rejected alternative — `focus:false`.** A workspace created unfocused can have no pty at all, yielding `tty: null` and a send `queued:true` while the surface is still runtime-active. The queued bytes are not lost — the surface flushes after warm-up, measured in this round with focus:false and focused surfaces, and `tty` appeared after the flush within measured bounds (3.7 s for a focus:false surface). With no tty there is nothing to check raw mode against, so the code path is still `focus:true` for startup and reflection checks still must precede CR.

**Consequence, accepted:** this feature uses the unaddressed create path for now, because active-window targeting is stable and sufficient here; the placement contract now also records `window_id` as validated support when callers can supply it, and a `focus:false` surface can still become ready after queued flush rather than being permanently unavailable.

## The tty comes from `debug.terminals`, not from the pane

**Type:** decision
**Status:** active
**Evidence:** confirmed in cmux 0.64.22 (102) [ddd4a01bc]; issue #68 item 2, item 6
**Source:** Issue #68 measurement items 2 and 6 and PR #60
**Revisit when:** cmux exposes the tty on the workspace-creation response or changes `debug.terminals` semantics

The tty name for a new surface is read by polling `debug.terminals` for the surface id as a basename that cmux's shell integration pushes up. This contract now requires that `tty` is treated as evidence that a command was submitted, not that the surface is ready: in measured cases, focused and unfocused new surfaces reported `tty: null` while runtime was already active and only acquired a tty after `surface.send_text` with CR. The null state was still present at 16.6 s in one focused case; when it cleared, the command had already been running. Tty names also recycled across unrelated surfaces after close, so the name is not a stable identity.

**Rejected alternative — have the pane tell us (`tty >| file`).** It works, and it puts a line the user did not write into their shell history and leaves a file to clean up.

**Rejected alternative — infer readiness from `tty` alone.** A `tty` appearing only after command submission is not a readiness signal for a new surface, so treating `tty` as "ready" would undercount warm-up cases and mis-handle `focus:false` delays.

**Rejected alternative — read the child's environment with `ps -E`.** Measured: the environment of a system binary is not visible this way, so the token cmux exports into the pane cannot be read back out.

**Rejected alternative — read the tty off the screen.** The screen is a rendering of a session, not a fact about it.

**Consequence, accepted:** keep the existing `queued`/readback flow; add a `tty` assertion only after a command has been sent and treat null as a delayed state, not a terminal fault. The null-to-non-null transition is the contract signal for command reachability, regardless of whether the surface was created focused or not.

## Split order and readable ceiling were measured from layout and pane splits

**Type:** decision
**Status:** active
**Evidence:** confirmed in cmux 0.64.22 (102) [ddd4a01bc]; issue #68 item 5 and item 7
**Source:** Issue #68 measurements `item5.jsonl`, `item5b.jsonl`, `item7.jsonl`, `item7b.jsonl`
**Revisit when:** layout geometry, minimum shell column rules, or cmux split defaults move on this machine

At 2320 × 1382 px and 15 × 30 px cells, repeated `surface.split direction:right` off the newest surface halves the newest pane and does not rebalance: N=1→`2320` / 154 columns, N=2→`1160,1160` / `154,154`, N=3→`1160,580,580` / `154,76,76`, N=4→`1160,580,290,290` / `154,76,38,38`. `workspace.equalize_splits {"workspace_id":W}` changed all four widths to `580` px.

Balanced split order is different: right, down off S0, then down off the returned right surface produces four equal 1160 × 691 px panes, 154 × 43 cells each, while right-down-right produced 1160×691 / 580×691 / 580×691 / 1160×1382. A newly created pane reported `columns: null` and `rows: null` until it rendered.

The binding constraint is columns per pane, not pane count: a 39-character command was readable in all panes at N=4 in both measured shapes because the balanced layout preserves width. `layout` creates with `workspace.create` remain the strongest fan-out route because they build the whole fan-out in one call and avoid extra sends.

Layout-aware creation was also measured with item 7: `workspace.create` accepts `layout` as an RPC argument and one call can produce all surfaces for the fan-out, with each command executed in its own leaf surface. `layout` accepts `window_id`, `focus`, `title`, `description`, and `cwd`; it ignores `name` (`title` stayed `Terminal`) and ignores `command` (`command` was not used by the server). The response still returns only one `surface_id`, so callers must enumerate through `pane.list` / `surface.list` and map by pane index to keep each command-to-surface assignment. The initial `workspace.create` response is complete for contracting, but each layout-created surface reports `initial_command: null`, so that field cannot be used as a matching key.
Because `title` is supported at creation, fixed-name flows can set it in the `workspace.create` call and no longer need a create→rename round trip in the successful path.

**Rejected alternative — `N ≤ 3`.** The earlier proposal failed on this server and window size because N=4 was measured to remain readable with a suitable split order and geometry.

**Consequence, accepted:** the placement contract now uses column width as the gating metric for split fan-out and prefers layout-aware construction over split chains when a balanced shape is required.

## cmux needs no pane proof, so delivery continues in a background tab

**Type:** decision
**Status:** active
**Evidence:** confirmed in cmux 0.64.22 (102) [ddd4a01bc]; issue #68 item 6
**Source:** Issue #68 item 6 and PR #60; contrasted with the Warp path in `claude-input-delivery.md`
**Revisit when:** `surface.read_text` no longer accepts an explicit surface id or no longer accepts `surface_id`

`surface.read_text` is addressed by surface UUID, so a screen read is provably a read of *our* surface. cmux therefore skips the nonce-based pane proof that Warp requires, and claude input keeps being delivered while the user is looking at another tab.

**Reason:** the pane proof exists only because Warp exposes one reused `AXTextArea` and no way to address a pane; where the terminal can answer "what is on surface X," the proof has nothing left to establish.

**Consequence, accepted:** the surface id must still be passed explicitly on every read — omitting it falls back to the focused surface, which is exactly the ambiguity the proof was built to remove. A prior in-repo observation saw cold reads erroring as `internal_error`; the current measured behavior is `exit 0` with queued payload text before tty exists, so queued text is treated as readback, not render proof. Sends and reads are asymmetric here: a send to a not-yet-warm surface queues, while a read can return the queued payload before the surface is ready. In background fan-out, all four sent surfaces returned `queued:false`, each acquired a distinct tty within 3 s while unfocused, and each `surface.read_text` returned only its own nonce; `/bin/stty -f /dev/ttysNNN -a` reported `43 rows; 154 columns; -icanon -echo` on each.

## Placement contract matrix for cmux 0.64.22 (102) [ddd4a01bc]

| capability | method and parameters | identifier or tty guarantee | retry class | condition | v1 placement use |
|:--|:--|:--|:--|:--|:--|
| window-addressed create | `workspace.create` with `window_id` (plus `focus`) | returns `workspace_id` and `window_id`; unknown `window_id` rejects with `Error: unavailable: TabManager not available` and no list delta | fail-closed floor plus method-level validation; no retry on validation errors | address only by probing membership in the target `window_id` | use when the caller can resolve and require deterministic window placement |
| layout-built fan-out create | `workspace.create` with `layout` plus optional `window_id`, `title`, `description`, `cwd`, `focus` | returns first `surface_id` only; enumerate `pane.list`/`surface.list` for all surfaces; `surface.list.initial_command` is null | same floor; validation errors with typed prefix are no-retry | layout must be a binary tree with exactly two children per branch and `direction` fields | preferred for `N` fan-out paths because one RPC creates all panes and commands without extra sends |
| `surface.split` | `surface.split` with `direction` and optional `workspace_id`/`surface_id` | returns new `pane_id`, `surface_id` with updated panes list; `direction` required, unknown ids return `not_found` | same floor; `invalid_params` / `not_found` and `Error: ...` forms are no-retry | explicit handles are required to avoid current-focus fallback; unaddressed calls split the current surface | use only with explicit current-target resolution and fallback accounted for |
| `surface.create` | `surface.create` with optional `type` / `workspace_id` / `pane_id` | returns `surface_id` and `index_in_pane`; unknown `pane_id` returns `not_found` | same floor; missing params are valid defaults | creates a tab in an existing pane, does not create a new pane | use when caller needs another surface in one pane |
| `surface.new_terminal` | `surface.new_terminal` with `pane_id` and optional `type` | method is `method_not_found`; command is absent from `capabilities.json` and returns no identifiers | no retry; unsupported method | no supported probe target; command stays unsupported | do not route placement paths here |
| `workspace.rename` | `workspace.rename` with `workspace_id` and `title` | returns the requested `workspace_id`; list shows `title` and `has_custom_title: true` | same floor; `not_found` or `invalid_params` are terminal for that call | unknown `workspace_id` fails; `title` required | set `title` at create time when possible; use rename for post-create reconciliation where the caller could not set it |
| `workspace.equalize_splits` | `workspace.equalize_splits` with `workspace_id` | returns `{equalized:true, workspace_id, workspace_ref}`; pane pixel geometry becomes equalized | same floor; validation/no-found failures are terminal | only meaningful for split-heavy layouts; `pane.list` columns may be stale briefly | use as a readability correction step after split-based fan-out |
| `workspace.close` | `workspace.close` with `workspace_id` | removes the workspace from subsequent `workspace.list` results | same floor; `not_found` and validation are terminal | deterministic cleanup target | use as standard per-measurement cleanup boundary |
| `window.close` | `window.close` with `window_id` | closes window only when its final workspace is gone; otherwise it remains in `window.list` with `visible:false` | same floor; validation/no_found terminal | visible windows may need workspace-level cleanup first to remove from topology | avoid for placement; use for targeted test/window cleanup |
| `surface.send_text` | `surface.send_text` with `surface_id` and `text` | response includes `queued` plus IDs; queued indicates warm-up state, not loss | same floor; transport failures only retry | with no tty yet, `queued:true` is expected and flushes on warm-up | use as the command delivery step for split/surface-created surfaces |
| `surface.read_text` | `surface.read_text` with `surface_id` (or default/focused) | response includes `text`; cold reads can return queued text before tty exists and should not be treated as a render confirmation | no retry behavior in placement contract; read result becomes an observation point | empty-queue reads can still return `text` and cannot be used as proof of rendering | use queued content only as readback, not as TUI-provenance proof |
| `debug.terminals` | `debug.terminals` with no params | returns `surface_id` entries with `tty`, and the value is a basename in `<surface>/ttysNNN` form | no retry gate for placement; no transport failure branch here | `tty` can be null through warm-up and appears only after command submission; values can be recycled across surfaces | use for readiness polling and mapping surface IDs to terminal names |
