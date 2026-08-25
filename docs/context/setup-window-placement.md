# Setup window sizing and placement

This file holds the forks behind how the setup window arrives at its size and its position on screen. The mechanisms and the invariants are in `CLAUDE.md` and in the code; what is here is why each of them is shaped that way, and what was tried and dropped.

## The measured size is applied outside the layout pass it was measured in

**Type:** decision
**Type:** incident
**Status:** active
**Evidence:** confirmed — reverting only the deferral turns 12 assertions red in the measured shapes; a 155pt shrink applied inside the pass left the window at 702 points with a 547-point clip, and the fixture clip read 0 against a 437-point window
**Source:** issue #34; PR #54 (commits `37887c7`, `31fc333`); `FittedContentStackView` in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** AppKit gives the document view a way to re-dirty its enclosing scroll view from inside a layout pass, or the window stops being sized from its content

The window is sized from its content, so the stack that knows the content measures it. Measuring has to happen inside `layout()` — that is the one moment the value is valid. **Applying it there does not work.** By the time the document view's `layout()` runs, the enclosing scroll view has already laid itself out against the old window size, and changing the window size at that point leaves nothing to re-dirty it: the clip view stays short by the delta and never self-heals. So the pass keeps the measurement and the application moves to the next main-queue turn.

**Rejected — `enclosingScrollView?.tile()` and `needsLayout = true` at that site.** Both were measured and both left the stale clip unchanged. They are the obvious things to reach for, which is why they are named here rather than merely absent.

**Rejected — clamping the scroll origin when it goes out of range.** This was proposed before the cause was known and would have corrected the symptom while the resize kept producing it. The clamp would then also be load-bearing for a defect nobody could name.

Two consequences the deferral creates, and how each is handled. A queued block must read `lastRequestedSize` at execution time rather than a captured target, so a later measurement wins. And the window can be closed while a block is still queued, so `windowWillClose` drops the queued state and `windowDidBecomeKey` allows measuring again — the controller outlives its window's visibility.

A separate, smaller cause was found in the same investigation and fixed first: `NSScrollView.automaticallyAdjustsContentInsets` added a title-bar inset that duplicated the stack's own 38-point top edge inset, because this window uses `.fullSizeContentView` and already clears the title bar itself. That was 32 of the missing points. Fixing it did not fix the device, which is what identified the resize as a second, independent cause rather than the same one measured imprecisely.

## One screen decision per layout cycle, and only the first measured size is centred

**Type:** decision
**Type:** incident
**Status:** active
**Evidence:** confirmed — on a portrait plus landscape pair the window finished launch flush against the left edge at X=0 where centred on that display is X=420, and the final origin was exactly `visible.minX` for a window centred on the other screen; after the fix the window stays at the centre of one display while it grows
**Source:** issue #34; PR #54 (commits `56baa0d`, `7b39ea9`, `5645d14`); `centerInside`, `moveInside` and `buildContent` in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** the window stops being `isMovableByWindowBackground`, or the launch display becomes something the user can choose

Growth is paired with sliding the window back inside the visible frame, because `setContentSize` keeps the top-left corner fixed and a window that grows past the screen edge gets its height clamped by AppKit. Centring and that slide-back must consume **the same** visible rect: `layout()` captures one, and both operations read it.

**Rejected — `NSWindow.center()`.** It consults `NSScreen.main` at the moment it is called, which follows keyboard focus rather than the window. With two displays attached, centring and clamping then read different screens and the clamp undoes the centring, leaving the window against an edge. `NSScreen.main` is now read exactly once, at window creation, to place the placeholder before anything measures it; after that only the window's own screen is consulted.

**Rejected — leaving the placeholder unplaced until the first measured size arrives.** Deferring the size means the window reaches the screen before that size does, so an unplaced placeholder is a window the user sees in the default lower-left corner for a few frames before it teleports to the centre. The measured duration was around 75ms — four or five frames at 60Hz. A centred placeholder that then shifts by a few tens of points is not in the same category, and the comparison had been made against the wrong alternative.

**Rejected — re-centring on every cycle.** This window is movable by its background, so pulling it back to the centre whenever its content grows takes it away from wherever the user put it. Only the placeholder and the first measured size are centred; later changes clamp without centring.

That "first" belongs to the window's lifetime, not to a document stack. A language change rebuilds the content view, so a per-stack flag makes every language change a re-centring: a window left near a corner came back at the middle of the screen. The same distinction had already been written one line away — the screen stand-in is carried across a rebuild because the display does not change just because the language did — and had been applied to only one of the two pieces of state. **What generalises: state that survives a rebuild is state about the window, and each new piece of it has to be asked about separately, because carrying one across is not a rule anybody reads before adding the next.**

**The captured rect can outlive its display.** Disconnect a screen between the measurement and the next main-queue turn and the clamp aims at coordinates that no longer exist; afterwards a window on no screen at all skipped centring and clamping entirely, with nothing watching for the configuration change. Screen-parameter changes therefore invalidate the captured rect, and a window with no screen clamps into the main one. That fallback is not the one removed above: reading `NSScreen.main` again *before* placement is what let a second display in, while a window that has ended up on no screen has nowhere else to be recovered to. The two are separate judgements and are documented separately, because merging them is what invites the next reader to reverse both at once.
