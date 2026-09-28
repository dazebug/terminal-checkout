# Subprocess execution

`runProcess` in `Core/TerminalRunner.swift` is the single door every child process goes through — CLI probes, `open`, `osascript`, `wezterm cli`, `cmux rpc`. Its contract is a bounded wait and a captured output; these are the places where the obvious version of that contract is not the one shipped.

## The timeout's bound is closing the pipe readers, not killing a process group

**Type:** constraint
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; measured on Darwin 25.4.0 — `setpgid` from the parent, 20 attempts out of 20
**Revisit when:** a `runProcess` caller starts launching a long-lived GUI child directly, or Foundation exposes a child-side spawn attribute

`runProcess` asks for its child to be in its own process group so a timeout can tear down everything the child started. On Darwin that request effectively never succeeds: by the time `Process.run()` has returned a pid, the `/bin/sh` child has already exec'd, and `setpgid` from the parent answers EACCES — 20 out of 20 attempts. The three `kill(-pid, …)` branches are therefore best effort for a race that is essentially never won, and the real bound on the timeout is that the pipe readers get closed.

**Reason it stays anyway:** the branches cost nothing when the group is not ours, and they are correct on the day the race is won. What matters is not mistaking them for the mechanism — a measured `sleep` descendant survived the timeout (`pgrep` rose from 1 to 2), so this is not process-tree cleanup and is not documented as such.

**Rejected alternative — spawn the child ourselves.** Setting the process group at spawn time is the only way to win reliably, and Foundation's `Process` has no public hook for a child-side `posix_spawn` attribute. Dropping to `posix_spawn` directly would mean re-implementing pipe setup, environment handling and termination status for every caller, to fix a leak whose current worst case is a descendant that outlives its parent.

**Consequence, accepted:** a descendant can remain after a `runProcess` timeout. That is bounded in practice because no current caller launches a long-lived GUI child inside this group — WezTerm's GUI fallback uses a raw `Process`, and `open -b`/`-a` hands off to LaunchServices — which is an assumption to re-check before adding one.

## Output decodes lossily, and the invalid bytes are logged rather than repaired

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #60; `decoded(_:stream:)` in `app/Sources/Core/TerminalRunner.swift`
**Revisit when:** a caller starts needing the exact original bytes of a child's output

Output is decoded with `String(decoding:as: UTF8.self)`, which substitutes replacement characters for anything invalid. When the raw bytes were not valid UTF-8, that fact goes to the log.

**Reason:** the forced pipe close that bounds a timeout can cut a multibyte sequence mid-character. The optional decoder (`String(data:encoding:)`) returns nil for that, and the previous code turned nil into an empty string — so one truncated character at the end discarded a whole valid prefix, including the part that would have explained the failure.

**Rejected alternative — keep failing the whole read.** It is the stricter option, and strictness here throws away the diagnosis at exactly the moment something has already gone wrong.

**Rejected alternative — decode lossily and say nothing.** Silently substituting characters in a value the app then parses or matches against is the kind of quiet alteration this project refuses elsewhere; logging the invalid original keeps the substitution visible without changing it.

## The exit is observed with `terminationHandler`, not `waitUntilExit()`

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured on this machine, 10–1000 calls per variant)
**Source:** the delivery-speed investigation that followed the maintainer's question about the marker
**Revisit when:** a caller needs `NSTaskDidTerminateNotification`, which a handler suppresses

`runProcess` sets `terminationHandler` before `run()` and waits on the semaphore it signals.

**Reason:** `waitUntilExit()` on a GCD thread polls a run loop, and that poll was the cost of every child the app ran: 66.7ms per call whether the child was `ps`, `stty`, `cmux ping` or `cmux rpc surface.read_text`, against 3.2, 2.4, 30.0 and 33.6ms with the handler. One claude input on cmux makes about 33 calls, and the app's delivery log matched the product to the millisecond — the CR step's seven calls took 0.462–0.469s. Nothing about the protocol changed; the same checks run in the same order, only sooner, which also narrows the window between the session gate and the byte it guards.

**Kept as it was:** the two pipe readers and their bounded drain. An exit, however it is observed, is not end-of-file on the pipes, and a descendant can keep them open.

## The session gate's `ps` and `stty` get their own short limits, and a failure is logged

**Type:** decision
**Status:** active
**Evidence:** confirmed for the symptom; the cause is not established
**Source:** field deliveries on cmux, the app's unified log, and a `sample` of the app during a stall
**Revisit when:** a stall of the old length shows up again with these limits in place

`probeAcceptingClaudePID` runs `ps` and `stty` with a 1s timeout, 0.5s grace before SIGKILL and 0.5s after it (`claudeGateProbeLimits`), and logs any call that does not answer.

**Reason:** 8 of 12 cmux deliveries measured in one session lost 9.3–9.6s before the first input — before "claude ready", or as "failed to send the marker/typing" with no RPC error — and the length matched the general escalation (5s + 2s + 2s) exactly. A `sample` taken during one of them had the delivery thread inside the gate's `ps` call, in those three timed waits in turn, while the gate conditions measured from outside with the same commands held throughout. Both commands answer in milliseconds, and an unanswered probe is already "cannot tell", which closes the gate — so the long escalation bought nothing but delay, and `try?` kept it out of the log.

**Not established:** whether the child really hung or its exit went unobserved. An isolated 1000-call stress of the old wait did not reproduce it (maximum 81ms), a child watcher saw no long-lived `ps` during one stall, and the `sample` showed four waiter threads blocked in `waitUntilExit` for its whole 11s window. Both explanations end in the same place: the gate answers "cannot tell" within about a second, and the log says so.
