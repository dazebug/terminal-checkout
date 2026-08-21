// Tests for the pure functions in extension/defaults.js — run with `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// defaults.js is a classic browser script, so it has no exports. Run the whole thing, then evaluate
// the names to pull them out (a script's top-level const doesn't land on globalThis, hence the
// second evaluation). It runs in this context rather than a separate one — objects created inside a
// vm context have a different prototype, so deepStrictEqual fails even on structurally equal values.
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../extension/defaults.js'), 'utf8'));
const { moveButton, duplicateButton } = vm.runInThisContext('({ moveButton, duplicateButton })');
const { BUTTON_KINDS, pageTypeOf } = vm.runInThisContext('({ BUTTON_KINDS, pageTypeOf })');
const { PR_PRESETS, ISSUE_PRESETS, REPO_PRESETS } =
  vm.runInThisContext('({ PR_PRESETS, ISSUE_PRESETS, REPO_PRESETS })');

const faces = list => list.map(b => b.face);
const sample = () => [
  { face: 'a', label: 'A', command: 'ca', claudeInputs: ['a1'] },
  { face: 'b', label: 'B', command: 'cb', claudeInputs: [] },
  { face: 'c', label: 'C', command: 'cc', claudeInputs: [] },
];

test('moveButton: moving later lands in the slot pulled back by the removal', () => {
  assert.deepEqual(faces(moveButton(sample(), 0, 3)), ['b', 'c', 'a']); // to the very end
  assert.deepEqual(faces(moveButton(sample(), 0, 2)), ['b', 'a', 'c']); // before c
});

test('moveButton: moving earlier lands exactly in that slot', () => {
  assert.deepEqual(faces(moveButton(sample(), 2, 0)), ['c', 'a', 'b']);
  assert.deepEqual(faces(moveButton(sample(), 2, 1)), ['a', 'c', 'b']);
});

test('moveButton: dropping in place does not change the order', () => {
  assert.deepEqual(faces(moveButton(sample(), 1, 1)), ['a', 'b', 'c']); // just before itself
  assert.deepEqual(faces(moveButton(sample(), 1, 2)), ['a', 'b', 'c']); // just after itself
});

test('moveButton: leaves the original array untouched', () => {
  const original = sample();
  moveButton(original, 0, 3);
  assert.deepEqual(faces(original), ['a', 'b', 'c']);
});

test('duplicateButton: the copy lands right after the original', () => {
  const next = duplicateButton(sample(), 0);
  assert.deepEqual(faces(next), ['a', 'a', 'b', 'c']);
  assert.deepEqual({ ...next[1], label: next[0].label }, next[0]); // identical apart from the tooltip
});

test('duplicateButton: the copy gets a number appended to its tooltip', () => {
  assert.equal(duplicateButton(sample(), 0)[1].label, 'A (1)');
});

test('duplicateButton: numbers already in use are skipped', () => {
  const once = duplicateButton(sample(), 0);       // A, A (1), B, C
  assert.equal(duplicateButton(once, 0)[1].label, 'A (2)'); // duplicating the original again
  assert.equal(duplicateButton(once, 1)[2].label, 'A (2)'); // duplicating the copy gives the same slot
});

test('duplicateButton: an empty tooltip gets just the number', () => {
  const empty = [{ face: 'a', label: '', command: '', claudeInputs: [] }];
  assert.equal(duplicateButton(empty, 0)[1].label, '(1)');
});

test('duplicateButton: claudeInputs is an array separate from the original', () => {
  const next = duplicateButton(sample(), 0);
  next[1].claudeInputs.push('added');
  assert.deepEqual(next[0].claudeInputs, ['a1']);
});

test('duplicateButton: leaves the original array untouched', () => {
  const original = sample();
  duplicateButton(original, 2);
  assert.deepEqual(faces(original), ['a', 'b', 'c']);
});

// --- Variables per page ---
// Using a variable the extension doesn't pass makes the app reject the request with
// "Variable {x} not provided", and the button does nothing. Presets and defaults are values we
// ship, so they are pinned right here.

// Commands and claude inputs are substituted from the same variable table (the app's resolveRequest)
const variablesUsed = btn => [btn.command, ...(btn.claudeInputs || [])]
  .flatMap(text => [...text.matchAll(/\{(\w+)\}/g)].map(m => m[1]));

for (const [kind, { presets, defaults, variables }] of Object.entries(BUTTON_KINDS)) {
  test(`${kind} presets and defaults only use variables that page provides`, () => {
    const allowed = new Set(variables);
    for (const btn of [...presets, ...defaults]) {
      for (const name of variablesUsed(btn)) {
        assert.ok(allowed.has(name), `${kind} "${btn.name || btn.label}": {${name}} is not available on this page`);
      }
    }
  });
}

test('the default repository button only moves to the repo', () => {
  // The Open in Terminal behavior from before it became customizable — changing the default changes existing users' buttons
  assert.equal(BUTTON_KINDS.repo.defaults.length, 1);
  assert.equal(BUTTON_KINDS.repo.defaults[0].command, 'z {repo}');
});

test('each page type has its own storage key', () => {
  // If two pages shared a key, one page's settings would overwrite the other's
  const keys = Object.values(BUTTON_KINDS).map(k => k.storageKey);
  assert.equal(new Set(keys).size, keys.length);
});

// --- Page type detection ---
// content.js (button insertion) and background.js (extension icon routing) must reach the same
// verdict. An icon click never goes through the content script, so if the two diverge, a path that
// isn't a repository reads as one and a command runs against the wrong name.

test('pageTypeOf: PR, issue, repository', () => {
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/pull/14'), 'pr');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/issues/3'), 'issue');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout'), 'repo');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/issues'), 'repo');   // the list is a repository tab
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/tree/feat/x'), 'repo');
});

test('pageTypeOf: reserved paths in the owner position are not repositories', () => {
  // Reading /settings/profile as a repository would make an extension icon click run `z profile`
  assert.equal(pageTypeOf('/settings/profile'), null);
  assert.equal(pageTypeOf('/notifications'), null);
  assert.equal(pageTypeOf('/marketplace/actions/checkout'), null);
  assert.equal(pageTypeOf('/orgs/watcha/projects'), null);
  assert.equal(pageTypeOf('/trending/javascript'), null);
});

test('pageTypeOf: no verdict without a repository name', () => {
  assert.equal(pageTypeOf('/'), null);
  assert.equal(pageTypeOf('/dazebug'), null);
});

// The app merges scheduled claude inputs into claude's opening message only when the rendered
// command's last word is a bare `claude` (it then invokes it as `command claude`), and only when
// no input is a boundary. That judgement lives in Swift, so nothing on this side would notice a
// preset drifting out of the shape — and a preset that stops merging silently brings back the Warp
// Accessibility requirement the merge exists to remove. Deliberately narrow: only the shape.
test('presets carrying claude inputs stay mergeable', () => {
  const withInputs = [...PR_PRESETS, ...ISSUE_PRESETS, ...REPO_PRESETS]
    .filter(p => (p.claudeInputs || []).length > 0);
  assert.ok(withInputs.length >= 3, 'presets carrying claude inputs disappeared');
  for (const preset of withInputs) {
    assert.match(preset.command, /(^|&&|\|\||;|\(|\{|\s)\s*claude$/, preset.name);
    let sawPlainText = false;
    for (const input of preset.claudeInputs) {
      // A slash command or a `#` memory line anywhere, or a `!` after plain text, sends every
      // input down the typed route instead
      assert.ok(!input.startsWith('/') && !input.startsWith('#'), `${preset.name}: ${input}`);
      assert.ok(!(sawPlainText && input.startsWith('!')), `${preset.name}: ${input}`);
      if (!input.startsWith('!')) sawPlainText = true;
    }
  }
});
