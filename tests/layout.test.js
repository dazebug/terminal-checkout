// Tests for the pure functions in extension/layout.js — run with `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// layout.js is a classic browser script, so it has no exports (same approach as tests/buttons.test.js).
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../extension/layout.js'), 'utf8'));
const { unclipButtonRow, UNCLIP_MAX_DEPTH } = vm.runInThisContext('({ unclipButtonRow, UNCLIP_MAX_DEPTH })');

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
