# batch-protocol

- Procedure source: `/Users/choongjaelee/.claude/skills/drive-agent-loop/assets/plan-template.md`
- Target: `batch-protocol` in `/Users/choongjaelee/Codes/terminal-checkout-batch-protocol-work`
- Starting commit: `42ba068` (`fix: send cmux payloads within the canonical limit without waiting for raw mode (#65)`)
- Current: R0b design review applied; no implementation or test edit has been made.
- Recent verdict: driver decisions D3–D12 are recorded below; `node --test` passed with 222 tests in R0, and the Swift gate belongs to the driver.

## Background — confirmed sources

- [Issue #66](https://github.com/dazebug/terminal-checkout/issues/66), as supplied in the assignment, defines an app-side batch protocol with shared templates, per-item variables, an item-cap proposal of 8, sequential launches, bounded parallel deliveries, and no extension or cmux-specific work in this step; D3 below records the driver’s compatibility choice for the old parser.
- [CLAUDE.md](../../CLAUDE.md) fixes the Chrome → relay → Unix socket → app boundary, the app-owned terminal choice, the normal `{success:false,error}` failure contract, the Claude delivery gates, and the measured cmux canonical-mode rule.
- [Request.swift](../../app/Sources/Core/Request.swift) currently accepts one `command_template`, one top-level variable map, and optional rendered `claude_inputs`, then runs one `ResolvedRequest`; it rejects a batch-shaped request today because `command_template` is missing.
- [HostServer.swift](../../app/Sources/App/HostServer.swift) records the framed request before parsing, serializes terminal launches on `execQueue`, calls the single-request handler once, returns after terminal launch and command send, and schedules Claude delivery on a global utility queue.
- [TerminalRunner.swift](../../app/Sources/Core/TerminalRunner.swift) and [ClaudeInputPlan.swift](../../app/Sources/Core/ClaudeInputPlan.swift) already provide the terminal-agnostic launch and per-request argv-versus-typed route; the batch path must reuse them per item.
- [ClaudeInjector.swift](../../app/Sources/Core/ClaudeInjector.swift) owns `TerminalSessionHandle`, per-session delivery admission, typed-input safety gates, and helper cleanup, but the current global dispatch has no active-delivery concurrency cap.
- [new-terminal-checklist.md](../new-terminal-checklist.md) is the source of truth for terminal support paths and currently has no batch fan-out or bounded-delivery entries.
- [README.md](../../README.md) defines `node --test` as the extension gate and `cd app && swift test` as the app gate; the latter is intentionally driver-only in this sandbox.

## Goal

Add one atomic app request carrying a shared command template, shared Claude-input templates, and per-item variable maps, with each item independently rendered and validated by the existing rules.

Launch one existing terminal session per item sequentially, return source-ordered per-item results after every terminal session and command send completes, and leave Claude input delivery asynchronous.

Bound active deliveries while allowing independent sessions to deliver in parallel, warn when a batch relies on Warp typed input, and preserve all existing terminal, TCC, Claude, and cmux behavior.

Keep the legacy single-request behavior and response bytes unchanged, and make structural failures, per-item failures, concurrency, and terminal-specific residuals observable through tests and the terminal checklist.

## Definition of done

- The exact batch shape from Issue #66 is accepted with the v1 maximum of 8 items, shared templates are rendered independently against each item’s variables, and every existing command and Claude-input validation rule is applied through one canonical per-item resolver.
- A batch with more than 8 items or an empty item list is rejected before any terminal side effect, and the cap is a Core constant named `batchItemLimit`.
- A batch response contains source-ordered item results, reports aggregate success only when every item succeeds, preserves useful per-item errors, and returns after all launches and command sends but without waiting for background Claude deliveries.
- Every batch item is rendered and validated before any launch; a content-validation failure rejects the whole batch with per-item results and zero launches, while a later launch failure records that item and allows subsequent validated items to continue.
- A pre-#66 app’s response to the batch shape is characterized as the normal `{"success":false,"error":"command_template is required"}` response rather than a crash or silence; this version adds no `update the app` string and preserves all legacy errors and response bytes.
- At least two deliveries can overlap in a deterministic test while the measured active count never exceeds the global cap of 4; the permit wraps the whole `deliverClaudeInputs` call, and permits, admissions, helpers, and termination barriers are released on success, failure, cancellation, and shutdown.
- The per-item route still uses `prepareRequest` and `runInTerminal`; typed delivery still uses the marker experiment, clear sequence, reflection check, CR submission, per-session gates, and one end-of-delivery cleanup; no input is retyped after a CR has been sent.
- Each item has one `DeliveryTimeline` labeled `item i/N`, a batch with Warp typed inputs emits one warning naming the affected item count, cmux remains addressable in a background tab, and cmux payloads within `darwinCanonicalLineLimit` are still sent without waiting for raw mode.
- New tests fail on the unimplemented tree for the new contracts, pass after implementation, and satisfy the commit rule: each committed test is either changed by reverting this work, names an invariant, or characterizes an inherited defect.
- The single-request byte corpus is captured before implementation and compared after implementation; any byte difference is treated as a discovered defect rather than normalized away.
- `node --test` is judged by exit status and executed-test count; `cd app && swift test` is run and judged by the driver, not by this sandbox, and no environment failure is rounded to green or regression.
- The terminal checklist covers the new structural and execution paths, `app/e2e.sh` adds only cap-excess, empty-items, and ambiguous-shape failures, and the final report contains rerunnable commands, outputs, file-and-line evidence, and no surviving background process.

## Assumed actors — who can cause the failure

- A current or future Chrome extension, or another direct native-messaging client, can send either the legacy single JSON shape or the new batch shape through the relay.
- The relay can forward malformed JSON, unknown request shapes, duplicate frames, disconnects, and old clients, but it remains a stdio-to-socket forwarder with no command execution logic.
- Any same-uid process that can reach the app socket can submit valid or hostile request values; the batch work does not broaden authentication beyond the existing socket boundary.
- User-controlled templates and per-item variables can be missing, empty, non-string, prototype-named, NUL-containing, line-breaking, control-containing, or otherwise outside the existing per-character whitelist.
- The app can be terminated or pass through the locale restart gate while items are queued, launching, admitted, or delivering Claude input.
- iTerm2, WezTerm, Warp, or cmux can fail to create a session, return a missing tty, lose a pane or surface, reject a command, or disappear after launch.
- The user can switch away from or type into a Warp tab while a typed batch is pending; the resulting visibility and draft-replacement behavior is part of the residual risk, not a reason to bypass the pane proof.
- Multiple batch requests can overlap, so the delivery cap must define whether it is global to the app or scoped only to one request.

## Non-goals — do not touch

- Do not change extension request construction, page classification, row badges, storage, presets, localization, or extension-side cap synchronization in this step.
- Do not group cmux items into one workspace, add placement presets, change cmux RPC routing, or infer state from the cmux settings file.
- Do not change the relay framing, 180-second wait, Unix-socket path rules, TCC process separation, or the Native Messaging host name.
- Do not add a terminal selector, change the app’s terminal source of truth, or refactor terminal-specific launch behavior out of the app.
- Do not wait for Claude to acknowledge or render an input before returning the batch response, and do not promise transactional rollback of sessions already launched.
- Do not merge Claude inputs across items or introduce batch-wide shell state; each item owns its rendered request, session handle, admission, and delivery.
- Do not replace the existing Claude safety gates, reflection oracle, Warp pane proof, cmux byte carrier, or cleanup semantics with queue-occupancy or focus heuristics.
- Do not increase the v1 item cap of 8, normalize user bytes, or make the base directory an extension variable without an explicit later decision.

## Invariants

- The accepted batch wire shape is `{ "command": "...", "claude_inputs": ["..."], "items": [{ "variables": { ... } }] }`; top-level presence of `items` selects batch, shared template text is not mutated between items, and each item gets an independent `ResolvedRequest` or an independent item error.
- The legacy `command_template` path remains the compatibility path; its public behavior, errors, launch order, and serialized response bytes are byte-identical after the change.
- Legacy and batch resolution call the same canonical per-item function for app-provided variables, scalar sanitization, command rendering, and Claude-input rendering and rejection; no caller duplicates whitelist logic.
- `batchItemLimit` is a Core constant with value 8; structural errors, empty `items`, malformed item objects or variables, and cap excess are returned as normal top-level failures before terminal side effects.
- If `items` and `command_template` coexist, the request is rejected as an explicitly ambiguous top-level shape; all other requests use the legacy path, including its pre-#66 `command_template is required` response for a batch sent to an old app.
- All items are resolved and validated before the first launch; any content error rejects the batch with that item’s error and `not launched — batch rejected during validation` for every other item, while a validated launch failure does not prevent later items from running.
- Item results retain input order; aggregate `success` is true if and only if every item result succeeds, successful batch responses are exactly `{"success":true,"items":[{"success":true},…]}`, and failed responses carry the prescribed summary or validation reason with no delivery state.
- Batch parsing and fan-out orchestration live in Core and remain testable; HostServer stays a thin framed transport adapter that preserves record-before-parse and delegates execution callbacks.
- Terminal launches remain serialized on the existing execution queue and use the existing terminal-independent preparation and `runInTerminal` path; HostServer does not acquire terminal-specific knowledge for batch branching.
- The response is written after every item’s terminal session and command send has completed, while Claude deliveries remain background work and do not extend the relay response wait.
- Each item with typed Claude inputs receives its own session handle and delivery admission; the existing foreground-claude, raw-tty, same-PID, process-group, marker, clear, reflection, CR, and final-cleanup gates remain in force.
- No input body is used as the throwaway marker, no body is typed again after any CR attempt, and all emitted bytes continue through the single per-session `send` gate.
- Delivery concurrency is bounded by a global semaphore with named constant value 4; its permit wraps the entire `deliverClaudeInputs` call, including tty acquisition and Claude waiting, is released with structured cleanup on every exit path, and the existing admission lifecycle and helper-kill barrier remain distinct from the new cap.
- Delivery permits do not block `execQueue` or the response path; queued work may wait for a permit, but an accepted item is not reported as a completed delivery merely because it was queued.
- Each item owns one `DeliveryTimeline` labeled `item i/N`; Warp warning classification is based on the actual prepared typed-input route and emits one batch-level line with the affected item count, not one line per item or a preference-only warning; cmux continues to use its addressed surface reads and `surface.send_text` carrier.
- The cmux send gate keeps the measured rule from commit `42ba068`: payloads at or below `darwinCanonicalLineLimit` are sent immediately in canonical mode, and only oversized payloads wait for raw mode.
- Every new normal-response sending path checks `{success:false}` explicitly; a response-level error is never turned into a successful page action or an item success by an unchecked message hop.
- R0 implementation work starts with red tests and a reproducible baseline; reverse-and-reapply or equivalent patch-toggle proof is required where a test claims to detect the new behavior, and stash or broad restore/reset commands are forbidden.
- Gate judgments use exit status and executed-test counts, not reporter text; all final claims carry a rerunnable command plus output, a file-and-line reference, or a measured count.

## Batch checks (round 0)

Mode: ultrafast

| Check | Result | Evidence |
|---|---|---|
| Checkout | ready | `batch-protocol` at `42ba068`; initial `git status --porcelain` was empty. |
| Worktree base | configured as `head` | `/Users/choongjaelee/.claude/settings.json:68-70` reports `"baseRef": "head"`. |
| Probe worktree ignore | not ignored; no probe created | `git check-ignore -q .claude/worktrees/probe` produced no match, and this R0 task created no probe worktree. |
| Repository overlay | present | `.claude/drive-agent-loop.md` supplies the app-only Swift gate limitation, Node gate, and cmux canonical-mode constraint. |
| cmux panel | pending — driver opens `cmux markdown open <plan path>` after first promotion and records the pane id here | Driver invocation context identifies cmux execution; the pane id is filled after the command. |
| Dependency sync | not applicable | The planned changes use the existing local SwiftPM and extension test setup; no dependency refresh is authorized in R0. |
| Local asset environment | none | The local drive-agent-loop overlay declares no additional asset environment. |
| App gate | deferred to driver | `cd app && swift test` is explicitly unavailable in the implementer sandbox and is not run here. |
| Extension gate | passed | `node --test` returned exit status 0 with `ℹ tests 222` and `ℹ pass 222`; judgment uses exit status and executed-test count. |

## Work items

Implementation order: 1 → 3 → 2 → 4.

| # | Item | Class | Confirmed defect | File set | Depends | Status | Evidence | Promotion |
|---|---|---|---|---|---|---|---|---|
| 1 | Core batch schema and canonical per-item resolution | protocol / validation | (a) `resolveRequest` currently requires `command_template` and returns one `ResolvedRequest`; (b) there is no `items[]` parser or item cap; (c) the pre-#66 batch-shaped response is not fixed by a red compatibility test; (d) legacy and batch item resolution have no shared entry point because the batch entry point does not exist. | `app/Sources/Core/Request.swift`; `app/Tests/CoreTests/BatchProtocolTests.swift` (new) | — | todo | `app/Sources/Core/Request.swift:20-72,143-154`; rerun with `rg -n 'command_template|claude_inputs|handleRequest' app/Sources/Core/Request.swift`. | — |
| 2 | Core batch fan-out orchestration and thin HostServer response path | execution / response | (a) Core currently models one resolved request and one run callback; (b) HostServer invokes the request handler and terminal runner once per frame; (c) there is no all-item validation preflight, ordered item result, or validated-launch failure continuation rule; (d) there is no batch-level Warp typed-delivery warning or per-item timeline path. | `app/Sources/Core/Request.swift`; `app/Sources/App/HostServer.swift`; `app/Tests/CoreTests/BatchProtocolTests.swift`; `app/Tests/AppTests/HostProtocolTests.swift` | 1, 3 | todo | `app/Sources/Core/Request.swift:143-154`; `app/Sources/App/HostServer.swift:150-223`; rerun with `rg -n 'execQueue|handleRequest|runInTerminal|deliverClaudeInputs|writeFrame' app/Sources/App/HostServer.swift`. | — |
| 3 | Bounded parallel Claude delivery | concurrency / lifecycle | (a) every current delivery is dispatched directly to a global utility queue; (b) `ClaudeDelivery.Admission` tracks lifecycle and helper cleanup but imposes no active-delivery cap; (c) batch fan-out would therefore run unbounded `ps`/`stty`/screen polling; (d) there is no scheduler test proving a global cap of 4, whole-call coverage, release, or shutdown behavior. | `app/Sources/Core/ClaudeInjector.swift`; `app/Tests/CoreTests/BatchDeliveryTests.swift` (new) | — | todo | `app/Sources/App/HostServer.swift:188-214`; `app/Sources/Core/ClaudeInjector.swift:709-784,953-1064`; rerun with `rg -n 'DispatchQueue\.global|Admission|deliverClaudeInputs' app/Sources/App/HostServer.swift app/Sources/Core/ClaudeInjector.swift`. | — |
| 4 | Verification corpus and terminal checklist | verification / documentation | (a) `app/e2e.sh` exercises only legacy failure cases; (b) `docs/new-terminal-checklist.md` has no batch launch, result, cap, or parallel-delivery path; (c) Warp fan-out visibility, the cross-terminal batch oracle, and the driver cmux pane check are not documented. | `app/e2e.sh`; `docs/new-terminal-checklist.md` | 1, 2, 3 | todo | `app/e2e.sh:1-85`; `docs/new-terminal-checklist.md:63-141`; rerun with `rg -n 'batch|fan|concurr|Warp|cmux' app/e2e.sh docs/new-terminal-checklist.md`. | — |

## Decision ledger

| # | Type | Claim/risk | Decision | Evidence | Residual uncertainty |
|---|---|---|---|---|---|
| D1 | User | Scope could expand into extension or cmux placement work. | This round is app-side protocol plus terminal-agnostic fallback only; extension and cmux-specific work are deferred. | Assignment and Issue #66 body supplied by the user. | Future wire-version and extension parity plan are not part of this round. |
| D2 | User | Fan-out could serialize all delivery work or wait for it in the response. | Launches are sequential, deliveries are parallel behind a cap, and the response waits only for terminal session plus command send. | Assignment and Issue #66 body supplied by the user. | Queued-delivery shutdown coverage is recorded under D8. |
| D3 | Driver | A new batch discriminator or update string could change legacy errors and response bytes. | Top-level presence of `items` selects batch. Coexistence of `items` and `command_template` is an explicit top-level ambiguity error. All other requests use the legacy path with its existing errors and response bytes. The pre-#66 app behavior is the forward-compatibility red oracle: a batch request receives normal `{success:false,error:"command_template is required"}` rather than a crash or silence, and this version adds no `update the app` string. | R0b driver design review; `app/Sources/Core/Request.swift:20-22`. | — |
| D4 | Driver | Structural errors and item-content errors have different side-effect boundaries. | Reject before execution when `items` is not an array, is empty, contains a non-object item, has malformed `variables`, or exceeds the cap. Render and validate every item first; if any content error occurs, launch zero items and return that item’s error plus `not launched — batch rejected during validation` for the others. After validation, launch sequentially; a launch failure is recorded and later validated items continue. | R0b driver design review. | — |
| D5 | Driver | The batch cap must be enforced in the app before any terminal side effect. | Define Core constant `batchItemLimit` with value 8 and reject any larger batch before launch. | R0b driver design review. | — |
| D6 | Driver | A terminal launch can fail independently after validation. | Run launches sequentially on `execQueue`, record the failed item, continue with the remaining items, and make rollback of already launched sessions a non-goal. | R0b driver design review. | — |
| D7 | Driver | Per-item status must be useful without claiming background delivery completion. | Return `{"success":true,"items":[{"success":true},…]}` with no top-level error when all items succeed. On failure return `success:false`, a top-level summary such as `N of M items failed` or the validation rejection reason, and ordered item results. A successful item payload is exactly `{"success":true}`; delivery state is not reported. | R0b driver design review. | — |
| D8 | Driver | Batch deliveries need a resource bound without changing admission lifecycle semantics. | Use a global semaphore with limit 4. A permit covers the entire `deliverClaudeInputs` call, including tty acquisition and Claude waiting. Keep `ClaudeDelivery.Admission` creation at launch as today and do not merge its role with the semaphore. Existing helper farewell coverage is accepted for queued delivery at shutdown pending measurement. | R0b driver design review; `app/Sources/Core/ClaudeInjector.swift:709-784,953-1064`. | Shutdown coverage for a delivery queued on the semaphore remains to be measured. |
| D9 | Driver | A batch needs item-level observability without multiplying the Warp warning. | Create one `DeliveryTimeline` per item labeled `item i/N`, and emit one batch-level Warp-plus-typed warning containing the affected item count. | R0b driver design review. | — |
| D10 | Driver | Putting batch branching in HostServer would weaken the existing thin-transport audit. | Keep batch parsing and fan-out orchestration in Core, share the canonical per-item resolver with legacy, and extend `HostProtocolTests` to ensure HostServer remains a thin framed delegate through batch frames. | R0b driver design review; `app/Tests/AppTests/HostProtocolTests.swift:76-121`. | — |
| D11 | Driver | Semantic equality is insufficient to prove legacy compatibility. | Capture legacy request and response fixtures before implementation from the existing tests and `app/e2e.sh` cases, then commit them as invariant-class tests that fail on response-byte drift. | R0b driver design review. | The exact fixture representation and selected case list remain a test-implementation detail. |
| D12 | Driver | A successful fake-terminal e2e path would expand this round’s scope. | Add only structural failure cases to `app/e2e.sh`: cap excess, empty `items`, and the ambiguous `items` plus `command_template` shape. Do not create a fake-terminal success path in this round. | R0b driver design review; `app/e2e.sh:1-85`. | — |

## Exhaustive sweep table

| Target | Verdict | Reason unknowable from code or file:line |
|---|---|---|
| `app/Sources/Core/Request.swift:17-72` | hole | The current resolver has no batch discriminator, item list, per-item result model, or cap, and its validation entry point is single-request only. |
| `app/Sources/Core/Request.swift:79-137` | preserve and reuse | The NUL, line-break, C0, per-character, `{cd}`, and app-provided-variable rules are the existing source of truth; the exact batch call site must be confirmed by tests. |
| `app/Sources/Core/Request.swift:143-154` | hole with compatibility constraint | The current handler catches one resolution or run error and returns one success map; changing it risks legacy response-byte drift. |
| `app/Sources/App/HostServer.swift:150-223` | hole | The server records before parsing and serializes one launch, then schedules one unbounded delivery; the batch orchestration and per-item response boundary are absent. |
| `app/Sources/Core/ClaudeInputPlan.swift:760-781` | preserve and reuse | `prepareRequest` already decides argv versus typed input per resolved request; batch must call it independently rather than add a second route. |
| `app/Sources/Core/TerminalRunner.swift:316-337` | preserve | `runInTerminal` is the existing terminal-agnostic launch boundary; no new terminal selector or HostServer terminal switch is justified by the specification. |
| `app/Sources/Core/TerminalRunner.swift:482-624` | preserve | cmux command gating already sends payloads within `darwinCanonicalLineLimit` without a raw-mode precondition and waits only for oversized payloads. |
| `app/Sources/Core/ClaudeInjector.swift:709-784` | extend without conflating roles | Admissions provide lifecycle and termination barriers, but no bounded-delivery permit; their current multi-admission behavior must remain intact. |
| `app/Sources/Core/ClaudeInjector.swift:953-1064` | preserve and schedule | `deliverClaudeInputs` owns tty acquisition, Warp permission checks, Claude PID/raw checks, submission, logging, and admission end; the scheduler must wrap it without bypassing cleanup. |
| `app/Sources/Relay/main.swift:33-49` | preserve | The relay forwards framed requests and waits for the existing 180-second response; the new response remains within that boundary and needs no relay execution logic. |
| `app/Sources/App/main.swift:5-16` | preserve | Headless mode already launches the same `HostServer`; no separate batch parser is warranted. |
| `app/Tests/CoreTests/CoreTests.swift:235-550` | extend corpus | Existing request and handler tests cover legacy rendering, validation, `{cd}`, and single success/error behavior; byte fixtures and shared-resolver tests must join this oracle or a new focused file. |
| `app/Tests/AppTests/HostProtocolTests.swift:76-146` | update oracle | The source audit currently forbids request branching in HostServer and the live transport test expects one handler result; the audit should continue to enforce Core-owned parsing while adding batch frames. |
| `app/Tests/CoreTests/ClaudeDeliveryLaunchAdmissionTests.swift:1-573` | preserve and cross-check | Existing admission, restart, and launch tests constrain lifecycle changes; a new bounded scheduler test must not weaken them. |
| `app/e2e.sh:1-85` | extend failure corpus | The harness deliberately avoids opening terminals and currently covers only legacy failures, so it can test cap, unknown-shape, and pre-side-effect batch rejection but not successful fan-out. |
| `extension/background.js:237-275` | non-goal | The current caller sends the legacy shape and already checks native `{success:false}`; extension batching and row badges are explicitly deferred. |
| `docs/new-terminal-checklist.md:63-141` | hole | Launch, argv, typed, Warp, and cmux paths are documented individually, but no batch ordering, partial-result, cap, warning, or parallel-delivery check exists. |

## Round log

#### Design review — R0b · promotion — · review — · round trips 1 · source —

- Objection: The R0 draft had an incorrect mode, an incomplete cmux-panel state, no explicit 1 → 3 → 2 → 4 start order, and unresolved questions that the driver had already decided.
- Handling: The mode is `ultrafast`, the cmux panel is pending the driver command after first promotion, the work-item order is explicit, and D3–D12 replace the closed questions; only genuine residuals remain open.
- Measurement: `node --test` returned exit status 0 with 222 executed and 222 passed; `cd app && swift test` remains driver-only.
- Verdict: Plan updated for driver review; implementation is still not promoted.

#### R1 — placeholder

- Objection: —
- Handling: —
- Measurement: —
- Verdict: —

## Open questions

- How will queued deliveries be proven to receive the existing helper farewell coverage during app termination, locale restart, and a never-started semaphore wait? (D8)
- What deterministic fake runner or injectable clock will test sequential launch, parallel delivery, cap enforcement, response timing, and cleanup without opening a real terminal, and which live transport assertions can remain in `HostProtocolTests`?
- Which exact legacy request cases and serialization fixture representation will be captured before implementation to prove byte identity rather than semantic equivalence? (D11)
