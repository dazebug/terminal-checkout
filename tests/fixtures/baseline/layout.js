// Layout fixes needed when wedging buttons into the GitHub header. This only touches DOM nodes and
// knows nothing about the chrome APIs or the global document, so it is tested as pure functions
// (tests/layout.test.js). Its one global dependency, getComputedStyle, is passed in as an
// argument — node's test runner has no such global.

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
