# Context index

- [claude-input-delivery.md](claude-input-delivery.md) — how scheduled input reaches a claude session, and the routes that were tried and dropped
- [cmux-integration.md](cmux-integration.md) — why the app asks the user to set one cmux option instead of setting it, why `rpc` is the only control path, how a launch retry is decided, and the measured placement contract for batch fan-out
- [subprocess-execution.md](subprocess-execution.md) — what actually bounds a timed-out child process, and why its output is decoded lossily
- [localization.md](localization.md) — where the catalogues live, how macOS and Chrome independently choose each surface's language, the adjacent-generation compatibility boundary, and which strings may never become machine input
- [options-page-reordering.md](options-page-reordering.md) — why claude input rows stay in one card, why a redraw cancels a drag, and why the reorder tooltip key is shared by meaning
- [testing.md](testing.md) — the typed source-audit boundary, the distinction between a source lint and a runtime oracle, why a gate goes on passing after the thing it describes moves, what a harness that drives its own layout stops measuring, and why options-page help is checked against the variable contract rather than as strings
- [batch-fan-out.md](batch-fan-out.md) — why a whole-batch rejection keeps the app's own error text and hedges about the app's age instead of asserting it
- [setup-window-placement.md](setup-window-placement.md) — why the window's measured size is applied outside the pass that measured it, and why one layout cycle gets one screen decision
- [signing-and-permissions.md](signing-and-permissions.md) — the ad-hoc signing churn, and the permission it silently revoked
- [knowledge-capture.md](knowledge-capture.md) — why this directory exists and how its tooling is installed

Only decisions made or recovered so far are here; this is not yet a complete account of the project. `CLAUDE.md` still holds the mechanisms, invariants, and measured pitfalls — this directory holds the forks behind them.
