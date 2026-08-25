# Options-page reordering

The implementation and invariants live in `CLAUDE.md`; this file preserves the forks and measurements that are not recoverable from the selectors and array operations alone.

## A row drag stays in its card

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured)
**Source:** PR #57 (commit `53d49e4`); measured with a disposable out-of-tree jsdom harness, not committed — see the testing entry for its shape and limits
**Revisit when:** cross-card row moves become an explicit product requirement

A row belongs to one button, so a row drag is confined to the card where it started. Moving it into another card would change two buttons' execution payloads at once and would need a destination `MAX_CLAUDE_INPUTS` check.

The same-card guard does not protect what its name might suggest. `reorderClaudeInputs` always uses `drag.cardIndex`, so removing the guard leaves the destination card untouched and silently reorders the origin card with an index calculated from the other card's row geometry: `["!two","!three","!one"]` became `["!three","!two","!one"]`. A destination with one row is a trap in a check for this: its computed index collapses into the in-place early return, so that check passes with the guard removed.

**Rejected alternative — allow a row to move across cards.** It couples two buttons' payload changes to one gesture and introduces a destination-cap decision that this feature does not need. The origin-only failure mode is also easy to misread as a destination mutation, which makes the guard worth keeping even though the visible symptom is elsewhere.

## A redraw cancels an in-flight drag

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured)
**Source:** PR #57 (commit `a24e27a`); measured with a disposable out-of-tree jsdom harness, not committed — see the testing entry for its shape and limits
**Revisit when:** the options page gains another redraw path or the drag state no longer shares one render lifecycle

Both item-6 protections stay. In the short-list reproduction, reverting only the `renderButtons` cancellation did not reproduce because the range guard caught the stale source; reverting only the `moveItem` range guard did not reproduce because cancellation removed the drag; reverting both reproduced the `TypeError` on `undefined.trim()`. Those protections overlap on that path, but not in what they cover.

A same-length replacement proves the difference. With cancellation enabled, replacing three inputs with three different inputs left `["!x","!y","!z"]` unchanged because the drag was cancelled. With only cancellation reverted, the picked `!one` moved and the new list became `["!y","!z","!x"]`; the source index was still in range, so a bounds guard had no signal. The pre-change card reproduction showed the same stale-index class on the card path, where the fabricated element reached `btn.face` instead.

**Rejected alternative — keep only the range guard.** It prevents `undefined` from entering a shorter replacement, but it cannot detect a same-length replacement and therefore moves a row the user never picked up.

**Rejected alternative — keep the drag across redraws with a render generation and revalidate identity and bounds before mutating.** After a redraw, the list the user grabbed from no longer exists, so every safe path through that revalidation ends in cancellation. It buys the same outcome as cancelling at the redraw with extra state and an additional identity contract.

## The tooltip key names the meaning, not one call site

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #57 (commits `fbdf584` and `4371901`)
**Revisit when:** the card and row tooltip sentences no longer have the same meaning, or the catalogue ownership model changes

The card tooltip key was renamed from `ext.card.reorder.tooltip` to `ext.reorder.tooltip` and is shared by the card and row handles. The card accessible name remains `ext.card.reorder.aria`; only the row accessible name is new, and it carries the 1-based row number because otherwise a screen reader cannot distinguish otherwise identical rows.

**Rejected alternative — reuse `ext.card.reorder.tooltip` on a row.** A key named for one call site would serve two meanings, the same class of small lie as a translatable `face`.

**Rejected alternative — add a second key with the identical sentence.** That would create five translated copies of one string and make later wording changes depend on keeping two keys synchronized.
