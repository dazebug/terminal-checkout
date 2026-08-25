# Context index

- [claude-input-delivery.md](claude-input-delivery.md) — how scheduled input reaches a claude session, and the routes that were tried and dropped
- [localization.md](localization.md) — where the catalogues live, how macOS and Chrome independently choose each surface's language, the adjacent-generation compatibility boundary, and which strings may never become machine input
- [options-page-reordering.md](options-page-reordering.md) — why claude input rows stay in one card, why a redraw cancels a drag, and why the reorder tooltip key is shared by meaning
- [testing.md](testing.md) — the typed source-audit boundary, the distinction between a source lint and a runtime oracle, why a gate goes on passing after the thing it describes moves, and what a harness that drives its own layout stops measuring
- [setup-window-placement.md](setup-window-placement.md) — why the window's measured size is applied outside the pass that measured it, and why one layout cycle gets one screen decision
- [signing-and-permissions.md](signing-and-permissions.md) — the ad-hoc signing churn, and the permission it silently revoked
- [knowledge-capture.md](knowledge-capture.md) — why this directory exists and how its tooling is installed

Only decisions made or recovered so far are here; this is not yet a complete account of the project. `CLAUDE.md` still holds the mechanisms, invariants, and measured pitfalls — this directory holds the forks behind them.
