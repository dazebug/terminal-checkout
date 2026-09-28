// Tests for the pure functions in extension/layout.js — run with `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// layout.js is a classic browser script, so it has no exports (same approach as tests/buttons.test.js).
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../extension/layout.js'), 'utf8'));
const { unclipButtonRow, UNCLIP_MAX_DEPTH } = vm.runInThisContext('({ unclipButtonRow, UNCLIP_MAX_DEPTH })');
// Looked up inside each test, so a missing function fails the test that needs it rather than the file
const pick = names => vm.runInThisContext(`({ ${names} })`);

// A fake DOM modeled on the real GitHub PR header. The overflow-x values are passed child → ancestor and chained up
function chain(...overflows) {
  const nodes = overflows.map(overflowX => ({ style: {}, overflowX }));
  nodes.forEach((node, i) => { node.parentElement = nodes[i + 1] || null; });
  return nodes;
}
const overflowXOf = node => node.overflowX;
const minWidths = nodes => nodes.map(n => n.style.minWidth);

// The measured structure from layout.js's header comment — the button cell and the header meta row clip, the branch row between them does not
const prHeader = () => chain('hidden', 'visible', 'hidden', 'visible');

test('unclipButtonRow: does not stop even though the button cell itself is overflow:hidden', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  // Stopping here would leave the branch row — the one that has to shrink — untouched, so the buttons stay clipped
  assert.equal(nodes[1].style.minWidth, '0');
});

test('unclipButtonRow: goes up to the clipping ancestor and no further', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  assert.deepEqual(minWidths(nodes), ['0', '0', '0', undefined]);
});

test('unclipButtonRow: stops at the depth limit when there is no clipping ancestor', () => {
  const nodes = chain(...Array(UNCLIP_MAX_DEPTH * 3).fill('visible'));
  unclipButtonRow(nodes[0], overflowXOf);
  assert.equal(minWidths(nodes).filter(v => v === '0').length, UNCLIP_MAX_DEPTH);
});

test('unclipButtonRow: lets the buttons fold onto the next line when that is still not enough', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  assert.equal(nodes[0].style.flexWrap, 'wrap');
  assert.equal(nodes[1].style.flexWrap, undefined); // wrapping the branch row too would separate "from" from the branch name
});

// The note popover hangs off a caret in a header that clips (the comment in layout.js), so it lives
// outside it, in <body>, placed from the caret's viewport rectangle. Page coordinates come back.
const viewport = { width: 1200, height: 800 };
const size = { width: 320, height: 90 };
const noScroll = { x: 0, y: 0 };
const caretAt = (left, top) => ({ left, top, right: left + 20, bottom: top + 24 });

test('notePopoverPosition: under the caret when there is room below', () => {
  const { notePopoverPosition, NOTE_POPOVER_GAP, NOTE_POPOVER_MARGIN } =
    pick('notePopoverPosition, NOTE_POPOVER_GAP, NOTE_POPOVER_MARGIN');
  assert.deepEqual(
    notePopoverPosition({ anchor: caretAt(100, 200), size, viewport, scroll: noScroll }),
    { placement: 'below', left: 100, top: 224 + NOTE_POPOVER_GAP, maxHeight: viewport.height - 2 * NOTE_POPOVER_MARGIN },
  );
});

test('notePopoverPosition: above the caret when below cannot hold it and above can', () => {
  const { notePopoverPosition, NOTE_POPOVER_GAP, NOTE_POPOVER_MARGIN } =
    pick('notePopoverPosition, NOTE_POPOVER_GAP, NOTE_POPOVER_MARGIN');
  const anchor = caretAt(100, 740);
  assert.deepEqual(
    notePopoverPosition({ anchor, size, viewport, scroll: noScroll }),
    {
      placement: 'above', left: 100, top: 740 - NOTE_POPOVER_GAP - size.height,
      maxHeight: viewport.height - 2 * NOTE_POPOVER_MARGIN,
    },
  );
});

test('notePopoverPosition: when neither side holds it, it stays inside the viewport and no taller than it', () => {
  // The reviewer's input: a 120-pixel viewport, a caret at 80–104, a popover 140 tall. Choosing the
  // roomier side alone put its top at -64, input and all off the screen.
  const { notePopoverPosition, NOTE_POPOVER_MARGIN } = pick('notePopoverPosition, NOTE_POPOVER_MARGIN');
  const small = { width: 800, height: 120 };
  const placed = notePopoverPosition({
    anchor: { top: 80, bottom: 104, left: 10, right: 30 }, size: { width: 320, height: 140 }, viewport: small, scroll: noScroll,
  });
  assert.equal(placed.maxHeight, small.height - 2 * NOTE_POPOVER_MARGIN);
  assert.ok(placed.top >= NOTE_POPOVER_MARGIN, `top ${placed.top} is above the viewport margin`);
  assert.ok(placed.top + placed.maxHeight <= small.height - NOTE_POPOVER_MARGIN, 'the capped popover runs past the bottom');
  // Neither side holding a shorter popover either: it moves in rather than hanging off an edge
  for (const caretTop of [20, 60, 100]) {
    const moved = notePopoverPosition({ anchor: caretAt(10, caretTop), size, viewport: { width: 800, height: 150 }, scroll: noScroll });
    assert.ok(moved.top >= NOTE_POPOVER_MARGIN && moved.top + size.height <= 150 - NOTE_POPOVER_MARGIN, `caret at ${caretTop}`);
  }
});

test('notePopoverPosition: when neither side holds it, the side with more room', () => {
  const { notePopoverPosition } = pick('notePopoverPosition');
  const short = { width: 1200, height: 150 };
  assert.equal(notePopoverPosition({ anchor: caretAt(100, 40), size, viewport: short, scroll: noScroll }).placement, 'below');
  assert.equal(notePopoverPosition({ anchor: caretAt(100, 100), size, viewport: short, scroll: noScroll }).placement, 'above');
});

test('notePopoverPosition: kept inside the viewport sideways, the left edge winning when it cannot fit', () => {
  const { notePopoverPosition, NOTE_POPOVER_MARGIN } = pick('notePopoverPosition, NOTE_POPOVER_MARGIN');
  const nearRight = notePopoverPosition({ anchor: caretAt(1150, 200), size, viewport, scroll: noScroll });
  assert.equal(nearRight.left, viewport.width - NOTE_POPOVER_MARGIN - size.width);
  const nearLeft = notePopoverPosition({ anchor: caretAt(-30, 200), size, viewport, scroll: noScroll });
  assert.equal(nearLeft.left, NOTE_POPOVER_MARGIN);
  const narrow = notePopoverPosition({ anchor: caretAt(100, 200), size, viewport: { width: 300, height: 800 }, scroll: noScroll });
  assert.equal(narrow.left, NOTE_POPOVER_MARGIN);
});

test('notePopoverPosition: page coordinates are the viewport ones plus the scroll offset', () => {
  const { notePopoverPosition } = pick('notePopoverPosition');
  const still = notePopoverPosition({ anchor: caretAt(100, 200), size, viewport, scroll: noScroll });
  const scrolled = notePopoverPosition({ anchor: caretAt(100, 200), size, viewport, scroll: { x: 15, y: 900 } });
  assert.deepEqual(scrolled, { ...still, left: still.left + 15, top: still.top + 900 });
});
