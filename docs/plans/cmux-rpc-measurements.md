# cmux RPC measurements for placement

- Canonical procedure: drive-agent-loop skill and its plan-template.md; after compaction or session replacement, reload both before continuing.
- Target: batch fan-out placement measurements from issue #68.
- Start commit: 692abd49305ae748fba7988270541f5951be0dc4.
- Base tree: main@692abd4 · worktree: /Users/choongjaelee/Codes/terminal-checkout-cmux-rpc-work (cmux-rpc-measurements).
- Current: R0 · last promotion: none · review: none · gate: N/A.
- Validator: the separate same-uid cmux driver transcript, followed by a review of docs/context/cmux-integration.md.
- Latest validator decision: not requested · transcript scratchpad: none.

## Background — confirmed sources

- [Issue #68](https://github.com/dazebug/terminal-checkout/issues/68) — the six required measurement groups, the driver boundary, the cmux 0.64.22 pin, and the v1 placement-contract outcome.
- [docs/context/cmux-integration.md](../context/cmux-integration.md) — the existing cmux decisions: four current app RPCs, focused unaddressed workspace creation, dynamic tty lookup, explicit surface reads, queued sends, and fail-closed create retry classification.
- [docs/context/index.md](../context/index.md) — the context-topic index and the existing cmux topic.
- [CLAUDE.md](../../CLAUDE.md) — the project cmux invariants, especially non-idempotent creation, socket pinning, raw-mode gating, and the separation between the relay and the app.
- [app/Sources/Core/CmuxControl.swift](../../app/Sources/Core/CmuxControl.swift) — the current RPC method constants, workspace.create parameters, response identifier parsing, failure classification, and cmux RPC transport.
- [app/Sources/Core/TerminalRunner.swift](../../app/Sources/Core/TerminalRunner.swift) — the app create/send path, one launch retry, socket pinning, and raw-mode command gate.
- [app/Sources/Core/ClaudeInjector.swift](../../app/Sources/Core/ClaudeInjector.swift) — debug.terminals polling, explicit surface send/read, and the cmux background-delivery path.
- [docs/new-terminal-checklist.md](../new-terminal-checklist.md) — the re-verification touch points when a cmux version or terminal execution path changes.
- README.md — the canonical development gates; no gate is run in this documentation-only R0.
- Read-only external asset: /Users/choongjaelee/.claude/skills/spawn-claude/scripts/launch_claude.sh and test_launch_layout.py — the prior cmux layout path and its stub-only grid assertion; these are hypotheses to remeasure, not runtime evidence.
- Installed CLI evidence: cmux --version returned cmux 0.64.22 (102) [ddd4a01bc]. The installed help identifies cmux rpc as the raw v2 entry point with an optional JSON object.
- Driver artifacts read for this review: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/capabilities.json contains the captured capabilities response and methods array; /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cli-help.txt contains the installed CLI help, including new-workspace --window, tree, current-window, and current-workspace.
- Evidence conflict resolved: `system.tree` and `system.identify` are present in `capabilities.json`, callable in this measurement set, and still only supplementary to placement decision logic; list/current-oracle and CLI `tree --all` remain the selected placement oracle for this round.
- Upstream method-name cross-check: the cmux v2 migration maps legacy new-split to surface.split and new-surface to surface.create. The driver result for the installed server is authoritative; surface.new_terminal remains a separate literal probe.

## Goal

The driver produces a lossless transcript for all six issue groups against the installed cmux 0.64.22 (102) [ddd4a01bc].
The transcript is interpreted into supported, unsupported, and conditional placement contracts for preset model v1.
The final context update records the raw evidence, the observed identifiers and tty behavior, method-specific retry boundaries, and cleanup results.
R0 writes only this plan and its repository overlay; this reviewed R0 permits the documentation commit, but it does not implement product code or alter cmux settings.

## Definition of done

- Failure that must be reproduced and prevented: a batch creates in the wrong window or pane, invokes an unsupported creator, duplicates a workspace or surface after an uncertain retry, or submits to a surface before queued data or raw-mode readiness is established.
- Acceptance oracle: each driver command has exact JSON, exit status, stdout, stderr, and before/after list evidence, with CLI tree and read-screen oracles marked as supplemental; all six groups have a conclusion; docs/context/cmux-integration.md contains a support matrix with capability, method and parameters, identifier or tty guarantee, retry class, condition, and v1 placement use, so placement v1 can cite it without rereading a live session.
- Corpus: the real cmux 0.64.22 (102) [ddd4a01bc] server; at least two windows; workspace.create plus surface.split, surface.create, and surface.new_terminal probes; fixed-name hit and miss paths; N=1, 2, 3, and 4 layout cases plus the first unreadable case; and focused, unfocused, and background surface send/read cases.
- Atomicity, partial failure, and rollback boundary: every creator is treated as non-idempotent until the transcript proves that a failure occurred before forwarding the request; an EOF, timeout, malformed response, or unknown forwarding result never authorizes a retry; cleanup is inspect-first and targets only identifiers created by this run.

## Assumed actors — who can cause this failure

- App through the HostServer cmux path: sends the selected RPC, interprets identifiers and queued responses, polls debug.terminals, and can accidentally retry or address the wrong surface if the contract is wrong.
- Installing user: can have multiple cmux windows, switch focus during creation, leave a workspace unfocused, and type or change the visible layout while a measurement is running.
- cmux server: resolves window, workspace, pane, and surface handles; creates non-idempotent objects; reports asynchronous tty and queued state; and may return transport or method errors.

## Non-goals — do not touch

- Product code, extension code, placement UI, preset schema, or production retry behavior: R0 supplies evidence for a later decision.
- cmux settings files, authentication modes, socket permissions, or launch configuration: the driver uses the already-installed and already-authorized server.
- Versions other than cmux 0.64.22 (102) [ddd4a01bc], or claims about undocumented future aliases.
- The spawn-claude scripts: they are read-only prior-measurement evidence.
- A broad cmux API inventory, performance benchmark, or visual redesign. Only the six issue groups and the cleanup RPCs needed to leave no residue are in scope.
- High-level cmux commands as evidence for v2 behavior. Raw cmux rpc calls are the measurement surface; a cleanup fallback is recorded separately if a raw close method is unavailable.

## Invariants

- The measured version is written in every driver transcript and in the final context entry: cmux 0.64.22 (102) [ddd4a01bc]. A live upgrade invalidates this plan's conclusions.
- Raw evidence is append-preserving: keep the exact method, substituted JSON, selected socket channel, exit status, stdout, stderr, response object, and before/after identifiers. A paraphrase is not a measurement.
- The implementer-side cmux ping is an environment probe only. It cannot stand in for a driver RPC result, and it does not alter the app rule that execution attempts workspace.create first instead of preflighting ping.
- Do not silently rename methods. The legacy labels new-split and new-surface are recorded as the v2 candidates surface.split and surface.create; surface.new_terminal is probed verbatim and a missing-method response is a result, not a substitution.
- State oracles for this review are workspace.list, pane.list, surface.list, workspace.current, and window.current. CLI cmux tree --all is a human-readable supplemental snapshot only; no plan conclusion depends on system.tree or system.identify.
- Every create probe takes a state snapshot before and after, records the returned workspace, window, pane, surface, and tty identifiers, and waits for the bounded asynchronous observation window before declaring no effect.
- Existing retry policy remains the floor: only a connection failure proven before request forwarding may be a retry candidate. Server validation, timeout, EOF, malformed JSON, access denial, and any post-forward failure remain no-retry unless a driver transcript and an explicit later decision establish a narrower method-specific exception.
- Cleanup never guesses an identifier and never repeats an uncertain creator. Close only IDs introduced by this run, prefer the measured raw close RPC, and use a whole dedicated workspace as the fallback containment boundary.
- Surface send/read tests use surface.send_text and surface.read_text with explicit surface_id. They do not use cmux send, because that path rewrites escape sequences and newlines.
- queued:true means delivery is pending, not lost. It is accepted only after a later addressed read or state observation proves the payload arrived; raw mode is established from the matching debug.terminals tty and never inferred from queue occupancy.
- The app and driver retain the existing same-uid socket boundary and the existing channel-specific socket pin. No test may cross from a selected stable or nightly channel to an unselected live server.

## Batch checks (round 0)

Mode: ultrafast

| Check | Result |
|:--|:--|
| git check-ignore -q .claude/worktrees/probe → ignored | Not established: exit 1, no output. |
| worktree.baseRef: head and first-report log | git config --get worktree.baseRef → exit 1, no value; assignment supplies main@692abd4. First report: /Users/choongjaelee/Codes/terminal-checkout-cmux-rpc-work · cmux-rpc-measurements · 692abd4 feat: batch fan-out from PR and issue list pages (#74), with 1f3ef87 immediately before it. |
| Agent first report: worktree path, branch, HEAD | Confirmed as above. |
| Repository overlay .claude/drive-agent-loop.md | Existing tracked overlay retained unchanged. |
| cmux panel | N/A: no cmux signal is enabled for the implementer; the driver owns the cmux panel and socket. |
| Dependency synchronization | N/A: documentation-only R0; no dependency or lockfile change. |
| Git-outside local asset env, name=absolute path | No environment variable was set; the read-only asset path is /Users/choongjaelee/.claude/skills/spawn-claude/scripts. |
| Incremental review duration, first three | N/A before the first promotion. |

## Work items

| # | Item | Class | Confirmed defect | File set | Depends | Status | Evidence | Promotion |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | Window-addressed workspace.create: establish whether a workspace can be created in explicit window W2. Commands: obtain two existing windows with cmux rpc window.list '{}'; if needed, create only a recorded helper with cmux rpc window.create '{}'; capture cmux rpc workspace.list '{}', cmux rpc window.current '{}', and cmux rpc workspace.current '{}'; focus W1 with cmux rpc window.focus '{"window_id":"<W1>"}'; run cmux rpc workspace.create '{"focus":true}' as the unaddressed baseline, then cmux rpc workspace.create '{"window_id":"<W2>","focus":true}' as the addressed probe; repeat the list and current-window/current-workspace calls, and add CLI cmux tree --all as a human-readable supplemental snapshot. Criteria: the installed CLI help already exposes new-workspace --window <id|ref|index>, so support is likely, but the raw RPC parameter name remains the measurement; support requires the addressed call to succeed and its returned or listed workspace to be a member of W2; an ignored window_id or placement in active W1 is unsupported; an accepted alternate handle is conditional and must be recorded verbatim. Cleanup: close both probe workspaces with cmux rpc workspace.close '{"workspace_id":"<W>"}'; close a helper window with cmux rpc window.close '{"window_id":"<helper>"}' only after its probe workspaces are gone; recover IDs from before/after lists if a response is lost. | placement / window | — | app/Sources/Core/CmuxControl.swift; app/Sources/Core/TerminalRunner.swift; docs/context/cmux-integration.md | — | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item1.py; transcript: item1.jsonl; decisive: workspace.create with window_id and unknown window_id; known window_id landed in requested window while unknown id returned Error: unavailable: TabManager not available and left workspace.list unchanged (11 -> 11) | — |
| 2 | Creator semantics and tty contract for the split and surface candidates. Commands: create one dedicated anchor with cmux rpc workspace.create '{"focus":true}'; enumerate it with cmux rpc pane.list '{"workspace_id":"<W>"}' and cmux rpc surface.list '{"workspace_id":"<W>"}'; probe cmux rpc surface.split '{"workspace_id":"<W>","surface_id":"<S>","direction":"right","focus":false}'; probe cmux rpc surface.create '{"workspace_id":"<W>","pane_id":"<P>","type":"terminal","focus":false}'; probe cmux rpc surface.new_terminal '{"workspace_id":"<W>","pane_id":"<P>","focus":false}'; for each accepted method, remove one candidate parameter at a time and preserve the server error or success; poll cmux rpc debug.terminals '{}' until the returned surface_id has a tty or the bounded deadline expires. Criteria: a pane creator increases pane topology and returns workspace, pane, and surface identifiers; a surface or tab creator adds a surface inside the requested pane without inventing a new pane; for surface.new_terminal, compare the captured capabilities membership with the call result and require the review's expected unsupported verdict to have both list absence and call rejection, with a mismatch left open; a creator is usable by the Claude pipeline only when its response has a stable surface_id and debug.terminals reports its tty in the same shape as workspace.create, with null and delayed tty recorded as conditions rather than failures. Cleanup: use a dedicated workspace per method and cmux rpc workspace.close '{"workspace_id":"<W>"}'; if a method creates in an existing workspace, close only returned surfaces through the measured cmux rpc surface.close '{"surface_id":"<S>"}' or document the raw close failure before using a dedicated-workspace fallback. | creator semantics / tty | — | app/Sources/Core/CmuxControl.swift; app/Sources/Core/ClaudeInjector.swift; docs/context/cmux-integration.md | — | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item2.py + item2b.py + item2c.py; transcript: item2.jsonl, item2b.jsonl, item2c.jsonl; decisive: surface.split requires direction; surface.create supports default params and adds a surface within an existing pane; unknown pane returns not_found; surface.new_terminal is method_not_found and absent from capabilities.json; focused/unfocused new surfaces showed tty null for many polls until a command was sent | — |
| 3 | Retry classification for every creating RPC, staged from cheap transport evidence to an expensive proxy only when needed. Commands: (a) for each creator, point CMUX_SOCKET_PATH at a nonexistent path and run CMUX_SOCKET_PATH=/private/tmp/cmux-r0-missing.sock cmux rpc workspace.create '{"focus":false}', then the same form for surface.split, surface.create, and surface.new_terminal with valid target-shaped IDs; capture exact exit/stdout/stderr and compare against Error: Failed to connect to socket at  and Error: Socket not found at . (b) using the real socket and item 2's valid targets, omit one measured required parameter per creator, for example cmux rpc surface.split '{"workspace_id":"<W>","surface_id":"<S>"}' and corresponding surface.create and surface.new_terminal forms; snapshot workspace.list, pane.list, and surface.list before and after. (c) only if (a) and (b) do not settle the placement v1 retry contract, use a driver-owned Unix-socket proxy with CMUX_SOCKET_PATH=/private/tmp/cmux-r0-proxy.sock to run each creator once through a proxy that blocks before forwarding and once through a proxy that forwards exactly once then drops or corrupts the response; preserve the proxy forwarded-byte log and the real-server list snapshots. Criteria: v1 inherits the existing fail-closed floor by default; a nonexistent-socket result is comparable to a retryable form only when the proxy or socket setup proves no request forwarding, and the exact CLI wording is recorded; a validation error is a creator-specific no-effect result only when before/after lists and the server response establish it, but it does not authorize retrying a different valid request; the post-forward proxy case is effect-uncertain and never expands retry, even if an immediate list is unchanged. Cleanup: (a) creates no server objects; after (b) and (c), diff workspace.list, pane.list, and surface.list, close every newly observed workspace or surface through measured close RPCs, and never retry cleanup after an unknown response without a fresh list snapshot. | non-idempotent create / retry | — | app/Sources/Core/CmuxControl.swift; app/Sources/Core/TerminalRunner.swift; docs/context/cmux-integration.md | 2 | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item34.py; transcript: item34.jsonl; decisive: three non-socket classes all exit 1 with exact forms, including regular-file/socket-refused/absent-path; validation errors include typed prefixes and left no list/pane/surface delta, so no-retry | — |
| 4 | Fixed-name workspace lookup and rename addressability. Commands: choose a unique recorded name and run cmux rpc workspace.list '{}'; if it is absent, run cmux rpc workspace.create '{"focus":false}', then cmux rpc workspace.rename '{"workspace_id":"<returned W>","title":"<unique name>"}'; run workspace.list again, workspace.current '{}', and CLI cmux tree --all as a human-readable supplemental snapshot; repeat the list step with the same name and count whether a second create occurred. Criteria: the miss path is list → create → rename; the post-rename list must show the same workspace_id and exact title, and the ID returned by workspace.create must be accepted by workspace.rename; the hit path returns the existing ID and performs no create; a response without a stable ID or a rename that silently targets another workspace is a contract failure. Cleanup: close only the workspace created by this run with cmux rpc workspace.close '{"workspace_id":"<created W>"}'; if the sentinel existed before the run, mark it pre-existing and do not close it; if create returned no ID, use the before/after list delta to contain and close the new workspace without retrying create. | fixed-name identity | — | app/Sources/Core/CmuxControl.swift; docs/context/cmux-integration.md | 1 | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item34.py; transcript: item34.jsonl; decisive: `workspace.rename` requires title; unknown workspace_id returns not_found; rename with workspace_id from create preserves id and sets `has_custom_title`; workspace.create also accepts title directly | — |
| 5 | Layout topology and practical pane ceiling. Commands: create a dedicated workspace with cmux rpc workspace.create '{"focus":true}'; record cmux rpc workspace.list '{}', cmux rpc pane.list '{"workspace_id":"<W>"}', cmux rpc surface.list '{"workspace_id":"<W>"}', and cmux rpc surface.read_text '{"surface_id":"<S>"}'; use CLI cmux tree --all as the human-readable topology snapshot and use a driver-reasonable macOS screenshot method only if visual geometry is needed, recording its path and hash without naming it as an RPC. For a linear case, repeatedly call cmux rpc surface.split '{"workspace_id":"<W>","surface_id":"<last S>","direction":"right","focus":false}' until N=4 and snapshot lists plus read-screen text after N=1, 2, 3, 4; in a separate dedicated workspace, exercise a mixed-axis sequence by splitting the original surface right, then down, then the returned down surface right; snapshot lists, read-screen text, and any discretionary screenshot after each call. Criteria: record whether N=4 is linear or grid-shaped from list topology and any visual artifact, whether mixed directions produce a readable grid, and the highest N at the recorded window size and font for which every pane shows a prompt plus a 40-character command without overlap or unusable truncation; N≤3 is a proposal to test, not a result to assume. Cleanup: close each dedicated workspace with cmux rpc workspace.close '{"workspace_id":"<W>"}'; preserve list, read-screen, and optional screenshot artifacts and hashes with the raw RPC transcript before cleanup. | layout / readability | — | app/Sources/Core/TerminalRunner.swift; /Users/choongjaelee/.claude/skills/spawn-claude/scripts/launch_claude.sh; /Users/choongjaelee/.claude/skills/spawn-claude/scripts/test_launch_layout.py; docs/context/cmux-integration.md | 2 | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item5.py + item5b.py; transcript: item5.jsonl; item5b.jsonl; decisive: `split:right` grows panes linearly to 2320/1160/580/290 px and equalize_splits makes equalized widths; mixed-axis split sequence yields true 2x2 readable columns at measured size | — |
| 6 | Background send/read, queued flush, and raw-mode transfer for every creator that item 2 accepts. Commands: record cmux rpc window.current '{}' and cmux rpc workspace.current '{}'; create a focus:false workspace with cmux rpc workspace.create '{"focus":false}' and send cmux rpc surface.send_text '{"surface_id":"<S>","text":"printf CMUX_R0_<nonce>\r"}'; poll cmux rpc debug.terminals '{}' and read cmux rpc surface.read_text '{"surface_id":"<S>"}' immediately and after warm-up; for a tty-bearing background case create with cmux rpc workspace.create '{"focus":true}', select a different existing workspace with cmux rpc workspace.select '{"workspace_id":"<other W>"}', verify focus with window.current and workspace.current, then repeat surface.create or surface.split, debug.terminals, surface.send_text, and surface.read_text using explicit IDs; inspect the matching tty with /bin/stty -f /dev/<tty> -a; repeat the small send and the recorded 1023-byte and over-1024-byte payload cases without cmux send. Criteria: queued:true is confirmed as a flush only when a later addressed read contains the token while focus remains on the other workspace; an immediate cold read error is recorded separately from later success; raw mode is confirmed only by stty on the debug.terminals tty; a focus:false surface with no tty is a queued-send condition and cannot satisfy Claude raw-mode delivery, while a background tty-bearing surface must preserve the existing immediate-small-payload and oversized-wait behavior. Cleanup: close only the dedicated workspaces with cmux rpc workspace.close '{"workspace_id":"<W>"}', after a final list snapshot; do not close the pre-existing workspace used to keep the test background. | background I/O / readiness | — | app/Sources/Core/ClaudeInjector.swift; app/Sources/Core/TerminalRunner.swift; docs/context/cmux-integration.md | 2 | claimed | script: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cmuxlab.py + item6a.py + item6b.py; transcript: item6a.jsonl, item6b.jsonl; decisive: cold read on unready surface returns exit 0 with queued payload, not internal_error; background sends in deselected workspace return per-surface tokens and distinct ttys with stty -f /dev/tty showing -icanon -echo | — |

- One work item is one later promotion-sized measurement outcome. No item is claimable beyond todo in R0 because no driver result has been supplied.
- Any driver conclusion that reopens an item becomes a new prime or letter row; do not overwrite the prior verdict.

## Decision ledger

The R0 ledger records the user's measurement boundary and the local capability probe. Future driver decisions append rows; they do not replace this evidence.

| # | Type | Claim or risk | Decision | Evidence (command, value, path, SHA, or review) | Remaining uncertainty |
|:--|:--|:--|:--|:--|:--|
| D1 | User | A sandbox socket failure could be mistaken for a cmux product result, and a retry could duplicate a non-idempotent create. | The driver owns all six socket measurements; the implementer records cmux ping as environment evidence only, writes the plan, and stops without code or commit. | Assignment #68 R0; cmux ping exit status 1; combined output exactly: Error: Failed to connect to socket at /Users/choongjaelee/.local/state/cmux/cmux.sock (Operation not permitted, errno 1) | The separate driver session must provide the actual server transcript and forwarding evidence. |
| D2 | User | Placement v1 must not rely on a method or topology that the installed server has not demonstrated. | Pin every conclusion to cmux 0.64.22 (102) [ddd4a01bc] and leave unsupported or conditional capabilities out of the v1 contract until raw evidence says otherwise. | Issue #68 R0; cmux --version → cmux 0.64.22 (102) [ddd4a01bc] | A server upgrade invalidates this plan's conclusions and requires a new measurement round. |
| D3 | Driver | The method names used by the measurement commands were cross-checked against the server's capabilities capture. | Keep the capabilities list and CLI help as the method-selection evidence, while treating a live call as the final acceptance test. | /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/capabilities.json; /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/cli-help.txt; cmux 0.64.22 (102) [ddd4a01bc] | The capabilities methods array is not proof that the server accepts every listed method; the call measurement is final. |
| D4 | User | The R0 stop boundary changed after the design review. | Commit only docs/plans/cmux-rpc-measurements.md and .claude/drive-agent-loop.md; do not add product code or other files. | Current review instruction; planned git add of the two paths followed by git commit -F | None for this commit; later driver evidence remains a separate round. |

## Exhaustive sweep

| Target | Verdict | Reason not knowable from code or file:line |
|:--|:--|:--|
| workspace.create with no window_id | Covered by item 1 | The current code omits the address; server routing is external behavior. |
| workspace.create with window_id | Covered by item 1 | The current code has no target parameter or response membership assertion. |
| surface.split and legacy new-split | Covered by item 2, retries by item 3, layout by item 5 | Pane topology and required source handles are server behavior. |
| surface.create and legacy new-surface | Covered by item 2, retries by item 3, background I/O by item 6 | Surface-versus-pane placement and tty creation are server behavior. |
| surface.new_terminal | Covered by item 2 and item 3 | The installed server may not expose the literal candidate; source mapping cannot substitute for a probe. |
| workspace.list, workspace.rename, workspace.close | Covered by item 4 and cleanup in items 1–6 | Fixed-name identity and safe cleanup depend on server response identifiers. |
| window.list, window.current, workspace.current, window.focus, window.close, pane.list, surface.list | Covered as setup and state oracles in items 1–5 | The server's returned membership, current focus, and topology are the placement oracle. |
| CLI cmux tree --all | Covered as a human-readable supplement in items 1, 4, and 5 | The CLI help exposes tree, while the reviewed RPC oracle is the list/current-method combination. |
| debug.terminals | Covered by items 2 and 6 | tty timing and null behavior are asynchronous and not derivable from Swift parsing. |
| surface.send_text and surface.read_text | Covered by item 6 | Queue flush, cold reads, focus independence, and raw-mode transfer are live surface behavior. |
| TerminalRunner.swift and CmuxControl.swift | Covered by items 1, 2, 3, and 5 | Existing app behavior is the contract consumer; R0 does not modify it. |
| ClaudeInjector.swift | Covered by item 6 | The delivery pipeline's explicit surface and tty assumptions need live confirmation. |
| spawn-claude external scripts | Covered by item 5 | The prior four-pane result is a stub or historical observation, not current live topology. |
| docs/context/cmux-integration.md | Future final target for all six results | R0 deliberately stops at the plan; no driver evidence is available yet. |

## Round log

Rounds are the intervals between validator decisions. R0 is a design round; this documentation commit is not an implementation promotion.

### R0

#### Design review — R0 draft · promotion: this docs-only commit · review: driver review supplied in current turn · round trips: 1 · source: /Users/choongjaelee/.claude/scratch/tc-cmux-rpc/

- Challenge: (1) the oracle named methods absent from the installed capabilities list; (2) the proxy was too expensive to run first; (3) the overlay omitted this sandbox's cmux denial; (4) the ledger lacked the driver method-list decision.
- Handling: (1) replace RPC tree, identify, and screenshot oracles with list/current RPCs, CLI tree --all as supplement, and driver-discretion screenshots; (2) stage retries as missing-socket, validation, then conditional proxy; (3) add the measured ping line to the overlay; (4) append D3. The explicit review decision is followed; the raw capabilities discrepancy is retained as an open evidence conflict.
- Measurement: read capabilities.json and cli-help.txt; cmux 0.64.22 (102) [ddd4a01bc]; implementer cmux ping exited 1 with the exact combined output recorded in D1; no driver RPC was run by the implementer.
- Decision: skeleton approved; revise the plan and overlay, commit only those two files, and leave the six live measurements to the driver.

### R1

#### Review 1 — incremental or final · commit: none · promotion: none · review: not requested · round trips: 0 · source: no scratchpad

- Blocker: not requested.
- Change: not requested.
- Measurement: not requested.
- Decision: not requested.

## Open questions

- Does workspace.create accept which raw RPC window-address parameter on the installed server, and do response/list membership plus the supplemental CLI tree prove placement in that requested window? The CLI already advertises new-workspace --window; this blocks item 1 and the window level of placement v1.
- Are surface.split, surface.create, and the literal surface.new_terminal all available, and which fields are required for each? This blocks item 2 and the creator rows in the v1 contract.
- Which failure modes can the driver prove occurred before forwarding for each creator, and do any method-specific validation rules add evidence without weakening the existing fail-closed retry floor? This blocks item 3.
- Does workspace.rename accept the workspace_id returned by workspace.create and preserve that identity through workspace.list? This blocks item 4.
- Is the current live layout linear at N=4, and what is the highest readable pane count at the recorded window size from list topology, read-screen results, and any driver-discretion visual artifact? This blocks item 5.
- Do queued sends, delayed tty discovery, explicit reads, and raw-mode observations transfer to background surfaces produced by each accepted creator? This blocks item 6.
- `system.tree` and `system.identify` were present in this measurement set; both are callable and were recorded in `RESULTS.md`, but the final placement contract uses the list/current oracle and `cmux tree --all` only as supplemental human-readable evidence.
