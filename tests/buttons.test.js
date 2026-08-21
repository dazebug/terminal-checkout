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
const { BUTTON_KINDS, pageTypeOf, APP_VARIABLES } =
  vm.runInThisContext('({ BUTTON_KINDS, pageTypeOf, APP_VARIABLES })');
const { adoptStoredButtons } = vm.runInThisContext('({ adoptStoredButtons })');

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
    // APP_VARIABLES are filled in by the app, not passed by the extension, so they are usable on
    // every page — but they are kept out of `variables` so that list keeps meaning "what the
    // extension actually sends"
    const allowed = new Set([...variables, ...APP_VARIABLES]);
    for (const btn of [...presets, ...defaults]) {
      for (const name of variablesUsed(btn)) {
        assert.ok(allowed.has(name), `${kind} "${btn.name || btn.label}": {${name}} is not available on this page`);
      }
    }
  });
}

test('the default repository button only moves to the repo', () => {
  // The Open in Terminal behavior from before it became customizable — changing the default changes
  // existing users' buttons. `{cd}` replaced the bare `z {repo}` (issue #30): with a cold zoxide DB
  // that first clause exits non-zero and the whole && chain dies silently, so the app now renders
  // the entry clause itself — and with no base directory configured it renders exactly `z {repo}`.
  assert.equal(BUTTON_KINDS.repo.defaults.length, 1);
  assert.equal(BUTTON_KINDS.repo.defaults[0].command, '{cd}');
});

// Every preset has to enter the repository through the app-rendered clause. A preset that opens
// with a bare `z {repo}` brings back the silent no-op of issue #30 on a cold zoxide DB.
test('every preset enters the repository through {cd}', () => {
  for (const [kind, { presets, defaults }] of Object.entries(BUTTON_KINDS)) {
    for (const btn of [...presets, ...defaults]) {
      const name = `${kind} "${btn.name || btn.label}"`;
      assert.ok(btn.command.startsWith('{cd}'), `${name}: command must start with {cd}`);
      assert.ok(!/\bz \{repo\}/.test(btn.command), `${name}: bare 'z {repo}' is back in the command`);
    }
  }
});

// The app is the single source for {cd} — the extension neither knows nor sends its value, exactly
// like the terminal choice. Listing it in `variables` would make the extension pass it and the app
// reject the request ("Unknown variable: {cd}").
test('app-provided variables are not in any page\'s variable list', () => {
  for (const [kind, { variables }] of Object.entries(BUTTON_KINDS)) {
    for (const name of APP_VARIABLES) {
      assert.ok(!variables.includes(name), `${kind}: {${name}} must not be sent by the extension`);
    }
  }
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

// --- Reading a stored button array ---
// Storage was written by another device, another version of this extension, or by hand. Every
// reader has to survive it — the content script and the service worker included, which is why this
// lives in defaults.js: those two do not load migrations.js and must not have to.

test('adoptStoredButtons: nothing stored is not a problem', () => {
  assert.deepEqual(adoptStoredButtons(undefined), { buttons: [], skipped: 0 });
});

test('adoptStoredButtons: a value that is not an array is dropped whole', () => {
  // `{"buttons": {"length": 1}}` used to reach .map and throw
  for (const value of [{ length: 1 }, 'z {repo}', 42, null]) {
    assert.deepEqual(adoptStoredButtons(value), { buttons: [], skipped: 1 }, JSON.stringify(value));
  }
});

test('adoptStoredButtons: entries that are not buttons are dropped and counted', () => {
  const { buttons, skipped } = adoptStoredButtons([null, 'x', 42, ['nested'], undefined]);
  assert.equal(buttons.length, 0);
  assert.equal(skipped, 5);
});

test('adoptStoredButtons: the readable ones survive next to the broken ones', () => {
  const { buttons, skipped } = adoptStoredButtons([
    null,
    { face: '🤖', label: 'keep', command: '{cd} && claude', claudeInputs: ['/review'] },
  ]);
  assert.equal(skipped, 1);
  assert.deepEqual(buttons, [
    { face: '🤖', label: 'keep', command: '{cd} && claude', claudeInputs: ['/review'] },
  ]);
});

// --- Fields, not just containers ---
// Checking that an entry is an object stops the crash at the outer layer and lets a bad field
// straight through: `command: 42` reaches .trim(), and `claudeInputs: "hello"` used to be quietly
// replaced by [] — the user's scheduled inputs gone at the next Save with nothing said.

test('adoptStoredButtons: a non-string face, label or command makes the entry unreadable', () => {
  for (const bad of [{ command: 42 }, { face: null }, { label: [] }, { command: {} }]) {
    const entry = { face: 'x', label: 'b', command: 'c', claudeInputs: [], ...bad };
    const { buttons, skipped } = adoptStoredButtons([entry]);
    assert.deepEqual(buttons, [], JSON.stringify(bad));
    assert.equal(skipped, 1, JSON.stringify(bad));
  }
});

test('adoptStoredButtons: claudeInputs must be an array of strings, or the entry goes', () => {
  // Dropping the whole entry rather than the field: a button whose scheduled inputs we cannot read
  // is not a button we understand, and silently keeping it with [] is how they got lost before.
  for (const claudeInputs of ['hello', [1], [null], [{}], {}]) {
    const { buttons, skipped } = adoptStoredButtons([{ face: 'x', label: 'b', command: 'c', claudeInputs }]);
    assert.deepEqual(buttons, [], JSON.stringify(claudeInputs));
    assert.equal(skipped, 1, JSON.stringify(claudeInputs));
  }
});

test('adoptStoredButtons: absent fields are still fine — only present-and-wrong is unreadable', () => {
  const { buttons, skipped } = adoptStoredButtons([{ command: '{cd}' }]);
  assert.equal(skipped, 0);
  assert.deepEqual(buttons, [{ face: '', label: '', command: '{cd}', claudeInputs: [] }]);
});

test('adoptStoredButtons: the legacy emoji field still counts, and still has to be a string', () => {
  assert.deepEqual(
    adoptStoredButtons([{ emoji: '🤖', command: '{cd}' }]).buttons,
    [{ face: '🤖', label: '', command: '{cd}', claudeInputs: [] }]
  );
  assert.equal(adoptStoredButtons([{ emoji: 7, command: '{cd}' }]).skipped, 1);
});

test('adoptStoredButtons: one bad field does not take the good entries with it', () => {
  const { buttons, skipped } = adoptStoredButtons([
    { face: 'x', label: 'bad', command: 42, claudeInputs: [] },
    { face: 'y', label: 'good', command: '{cd} && claude', claudeInputs: ['/review'] },
  ]);
  assert.equal(skipped, 1);
  assert.deepEqual(buttons, [{ face: 'y', label: 'good', command: '{cd} && claude', claudeInputs: ['/review'] }]);
});

test('adoptStoredButtons: a hole in claudeInputs is not a string', () => {
  // `new Array(1).every(...)` is true — every skips holes — so a sparse array passed as "all
  // strings" and the missing slot became the literal "undefined" at the next Save.
  const sparse = new Array(1);
  assert.equal(adoptStoredButtons([{ command: '{cd}', claudeInputs: sparse }]).skipped, 1);
  const withHole = ['a', , 'b']; // eslint-disable-line no-sparse-arrays
  assert.equal(adoptStoredButtons([{ command: '{cd}', claudeInputs: withHole }]).skipped, 1);
  assert.equal(adoptStoredButtons([{ command: '{cd}', claudeInputs: ['a', 'b'] }]).skipped, 0);
});

// --- Adding a button ---
// Split out of the click handler so the guard-then-change order the handler is made of can be
// tested (tests/migration.test.js): the handler used to push the button and ask afterwards.

test('appendButton: the new button takes the first preset face not already in use', () => {
  const { appendButton } = vm.runInThisContext('({ appendButton })');
  const kind = BUTTON_KINDS.pr;
  const first = appendButton([], kind);
  assert.equal(first.length, 1);
  assert.equal(first[0].face, kind.presets[0].face);
  assert.equal(appendButton(first, kind)[1].face, kind.presets[1].face);
  assert.equal(first[0].command, '', 'a new button starts empty, not on a preset');
  assert.ok(first[0].uid, 'it enters the edit state with a uid of ours');
});

test('appendButton: leaves the original array alone and stops at the cap', () => {
  const { appendButton, MAX_BUTTONS } = vm.runInThisContext('({ appendButton, MAX_BUTTONS })');
  const kind = BUTTON_KINDS.pr;
  const original = [];
  appendButton(original, kind);
  assert.deepEqual(original, []);

  let list = [];
  for (let i = 0; i < MAX_BUTTONS; i++) list = appendButton(list, kind);
  assert.equal(appendButton(list, kind), list, 'at the cap it hands the same array back');
});
