# Subprocess execution

`runProcess` in `Core/TerminalRunner.swift` is the single door every child process goes through — CLI probes, `open`, `osascript`, `wezterm cli`, `cmux rpc`. Its contract is a bounded wait and a captured output; these are the two places where the obvious version of that contract is not the one shipped.

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
