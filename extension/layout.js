// Layout fixes needed when wedging buttons into the GitHub header, and where the note popover goes.
// This only touches DOM nodes and rectangles and knows nothing about the chrome APIs or the global
// document, so it is tested as pure functions (tests/layout.test.js). Its one global dependency,
// getComputedStyle, is passed in as an argument — node's test runner has no such global.

// PR header structure (measured): [button cell overflow:hidden] → [branch row] → [header meta row
// overflow:hidden].
// A flex item's default min-width:auto means "never shrink below the content", so the branch row
// grows by however much the buttons add, that row spills out of the header meta row, and the
// rightmost buttons get clipped away.
// Planting min-width:0 all the way up to the clipping ancestor makes GitHub ellipsize the branch
// name as it normally would and lets the buttons keep their space. The button cell itself is also
// overflow:hidden, so stopping there has no effect at all.
//
// If the window is narrow enough that even a fully shortened branch name doesn't leave room, the
// buttons get clipped anyway, so only the button cell gets flex-wrap:wrap — as a last resort they
// fold onto the next line. Wrapping the branch row too would separate "from" from the branch name
// and make the sentence read as broken.
const UNCLIP_MAX_DEPTH = 6; // upper bound so a missing clipping ancestor doesn't spread this across the whole page

function unclipButtonRow(buttonHost, overflowXOf) {
  buttonHost.style.flexWrap = 'wrap';
  for (let el = buttonHost, depth = 0; el && depth < UNCLIP_MAX_DEPTH; el = el.parentElement, depth++) {
    el.style.minWidth = '0';
    if (depth > 0 && overflowXOf(el) !== 'visible') return;
  }
}

// The note popover opens from a caret inside those clipping rows, so it cannot live there: it hangs in
// <body>, positioned absolutely from the caret's viewport rectangle. Under the caret when the space
// below holds it, above when only the space above does, and on the roomier side when neither does;
// sideways it stays inside the viewport, and when it is wider than that its left edge stays visible.
// The result is page coordinates (viewport plus scroll), so the popover scrolls with the page.
const NOTE_POPOVER_GAP = 4; // between the caret and the popover
const NOTE_POPOVER_MARGIN = 8; // between the popover and the viewport edge

function notePopoverPosition({ anchor, size, viewport, scroll }) {
  const spaceBelow = viewport.height - anchor.bottom - NOTE_POPOVER_GAP - NOTE_POPOVER_MARGIN;
  const spaceAbove = anchor.top - NOTE_POPOVER_GAP - NOTE_POPOVER_MARGIN;
  const below = size.height <= spaceBelow || spaceBelow >= spaceAbove;
  const top = below ? anchor.bottom + NOTE_POPOVER_GAP : anchor.top - NOTE_POPOVER_GAP - size.height;
  const left = Math.max(NOTE_POPOVER_MARGIN, Math.min(anchor.left, viewport.width - NOTE_POPOVER_MARGIN - size.width));
  return { placement: below ? 'below' : 'above', left: left + scroll.x, top: top + scroll.y };
}
