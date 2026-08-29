# drive-agent-loop overlay — terminal-checkout

## Gate commands

The source of truth for check commands is the "Development" section of [`README.md`](../README.md). This loop's app gate is `cd app && swift test`, and the extension gate is `node --test`. Judge success or failure by each command's exit status and record the executed-test count separately.

## Checks that cannot run inside isolation

`cd app && swift test` does not run in the implementer sandbox. The driver re-runs the Swift gate in the clone, and the implementer never interprets an environment failure as a code regression or rounds it to green.

## Local asset env

None.

## ultrafast mode — implementer sandbox measurements

The Swift gate does not run in the implementer sandbox (measured in earlier loops) — the driver runs it instead with `cd <clone>/app && swift test`. `node --test` stays the extension gate per the README.md Development section; record its result as exit status plus executed-test count.

## Repo-specific lines to add to assignment messages

The cmux command send gate does not make raw mode a precondition for every payload: a payload within `darwinCanonicalLineLimit` is sent immediately inside the canonical buffer, and only an oversized payload waits for raw mode.
