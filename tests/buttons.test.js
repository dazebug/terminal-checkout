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

// --- The limits are part of the shape verdict, not an import-only afterthought ---
// They used to live on the import path alone, so a stored fourth button reached the app while the
// same array arriving as a file lost it silently. Every reader shares this decision now — the
// content script and the service worker included, which is why it is here and not in migrations.js.

test('adoptStoredButtons: entries past the button limit are skipped and counted', () => {
  const { MAX_BUTTONS } = vm.runInThisContext('({ MAX_BUTTONS })');
  const button = n => ({ face: 'x', label: `b${n}`, command: `{cd} && echo ${n}`, claudeInputs: [] });
  const stored = Array.from({ length: MAX_BUTTONS + 2 }, (_, i) => button(i + 1));
  const { buttons, skipped } = adoptStoredButtons(stored);
  assert.equal(buttons.length, MAX_BUTTONS);
  assert.equal(skipped, 2);
  assert.equal(buttons[0].command, '{cd} && echo 1', 'the ones kept are the first ones');
});

test('adoptStoredButtons: claude inputs past the limit make the whole entry unusable', () => {
  const { MAX_CLAUDE_INPUTS } = vm.runInThisContext('({ MAX_CLAUDE_INPUTS })');
  const claudeInputs = Array.from({ length: MAX_CLAUDE_INPUTS + 1 }, (_, i) => `input ${i}`);
  // Trimming the surplus would keep the button and lose the inputs — the same silent loss the field
  // rules exist to prevent, and it would be recorded by the next Save.
  const { buttons, skipped } = adoptStoredButtons([{ face: 'x', label: 'b', command: '{cd}', claudeInputs }]);
  assert.deepEqual(buttons, []);
  assert.equal(skipped, 1);
  assert.equal(adoptStoredButtons([{ command: '{cd}', claudeInputs: claudeInputs.slice(0, MAX_CLAUDE_INPUTS) }]).skipped, 0);
});

// --- What was clicked has to be what was shown ---
// The page draws a button and sends only its index; the service worker then reads storage again and
// runs whatever sits at that index *now*. Between those two reads the settings can have changed —
// or the page may have drawn defaults because its own read failed — and the command that runs is
// then one the user never saw. The click carries a fingerprint of the button that was drawn so the
// two reads can be compared.

test('buttonFingerprint: the same stored button fingerprints the same on both sides', () => {
  const { buttonFingerprint } = vm.runInThisContext('({ buttonFingerprint })');
  const stored = { face: '⏏️', label: 'Checkout', command: '{cd} && git fetch', claudeInputs: ['/a'] };
  // Both readers reach the button through adoptStoredButtons, so both fingerprint the normalized shape
  const [drawn] = adoptStoredButtons([stored]).buttons;
  const [reread] = adoptStoredButtons([stored]).buttons;
  assert.equal(buttonFingerprint(drawn), buttonFingerprint(reread));
});

test('buttonFingerprint: a button replaced under the page does not match what was drawn', () => {
  // The repro: the page drew the default Checkout Branch button because its own read failed, and
  // storage in fact held someone else's custom command at index 0.
  const { buttonFingerprint, BUTTON_KINDS } = vm.runInThisContext('({ buttonFingerprint, BUTTON_KINDS })');
  const [drawn] = adoptStoredButtons(BUTTON_KINDS.pr.defaults).buttons;
  const [reread] = adoptStoredButtons([
    { face: '⚠️', label: 'Remote custom', command: 'echo REMOTE', claudeInputs: [] },
  ]).buttons;
  assert.notEqual(buttonFingerprint(drawn), buttonFingerprint(reread));
});

test('buttonFingerprint: a remote reorder is caught at the index that was clicked', () => {
  const { buttonFingerprint } = vm.runInThisContext('({ buttonFingerprint })');
  const A = { face: 'a', label: 'A', command: '{cd} && echo A', claudeInputs: [] };
  const B = { face: 'b', label: 'B', command: '{cd} && echo B', claudeInputs: [] };
  const drawn = adoptStoredButtons([A, B]).buttons;
  const reread = adoptStoredButtons([B, A]).buttons;
  assert.notEqual(buttonFingerprint(drawn[0]), buttonFingerprint(reread[0]));
  // Every field the user could see or that decides what runs is part of it
  const { buttons: [inputsChanged] } = adoptStoredButtons([{ ...A, claudeInputs: ['/extra'] }]);
  assert.notEqual(buttonFingerprint(drawn[0]), buttonFingerprint(inputsChanged));
  const { buttons: [labelChanged] } = adoptStoredButtons([{ ...A, label: 'A renamed' }]);
  assert.notEqual(buttonFingerprint(drawn[0]), buttonFingerprint(labelChanged));
});

test('the refusal a mismatch produces tells the user how to fix it', () => {
  const { BUTTON_CHANGED_ERROR } = vm.runInThisContext('({ BUTTON_CHANGED_ERROR })');
  assert.match(BUTTON_CHANGED_ERROR, /reload/i);
});

test('adoptStoredButtons: a hole hidden behind an extra property is still a hole', () => {
  // Object.keys(['ok', <hole>]) with a stray `note` property has the same length as the array, so
  // the count check passed by coincidence and `every` skipped the hole. The missing slot then
  // vanished at the next Save — two scheduled inputs became one.
  const claudeInputs = new Array(2);
  claudeInputs[0] = 'ok';
  claudeInputs.note = 'extra';
  assert.equal(claudeInputs.length, Object.keys(claudeInputs).length, 'the coincidence this relies on');
  assert.equal(adoptStoredButtons([{ command: '{cd}', claudeInputs }]).skipped, 1);
});

// --- Who pressed it, and on what page (R9) ---
// The fingerprint answers "which button"; these answer "who pressed it" and "where". A command that
// runs is the end of a chain that starts with a person clicking something they can see.

test('only a real click runs anything — a dispatched one is not a user', () => {
  // `document.querySelector('.terminal-cmd-btn').dispatchEvent(new MouseEvent('click'))` from any
  // script on the page ran the stored command with no one touching the mouse.
  const { isUserGesture } = vm.runInThisContext('({ isUserGesture })');
  assert.equal(isUserGesture({ isTrusted: true }), true);
  assert.equal(isUserGesture({ isTrusted: false }), false);
  assert.equal(isUserGesture({}), false);
  assert.equal(isUserGesture(null), false);
});

test('the click guard runs before the handler body, not inside it', () => {
  // Same lesson as userAction on the options page: an order kept by convention at each call site is
  // an order that gets reversed. One wrapper owns it.
  const { onUserClick } = vm.runInThisContext('({ onUserClick })');
  let handler = null;
  let ran = 0;
  const element = { addEventListener: (type, fn) => { if (type === 'click') handler = fn; } };
  onUserClick(element, () => { ran += 1; });
  assert.equal(typeof handler, 'function');

  const event = { isTrusted: false, preventDefault() {}, stopPropagation() {} };
  handler(event);
  assert.equal(ran, 0, 'a synthetic click must not reach the body');
  handler({ ...event, isTrusted: true });
  assert.equal(ran, 1);
});

test('pageTargetOf: what a request is built from, read off one pathname', () => {
  const { pageTargetOf } = vm.runInThisContext('({ pageTargetOf })');
  assert.deepEqual(pageTargetOf('/dazebug/terminal-checkout/pull/14'),
    { kind: 'pr', owner: 'dazebug', repo: 'terminal-checkout', number: '14' });
  assert.deepEqual(pageTargetOf('/dazebug/terminal-checkout/issues/3'),
    { kind: 'issue', owner: 'dazebug', repo: 'terminal-checkout', number: '3' });
  assert.deepEqual(pageTargetOf('/dazebug/terminal-checkout'),
    { kind: 'repo', owner: 'dazebug', repo: 'terminal-checkout', number: null });
  assert.equal(pageTargetOf('/settings/profile'), null);
});

test('sameTarget: a navigation between two PRs is not the same target', () => {
  // The repro: the buttons were drawn on PR #1, the tab moved to PR #2 while storage was being
  // read, and the request went out with #1's number and #2's branch.
  const { pageTargetOf, sameTarget } = vm.runInThisContext('({ pageTargetOf, sameTarget })');
  const one = pageTargetOf('/o/r/pull/1');
  const two = pageTargetOf('/o/r/pull/2');
  assert.equal(sameTarget(one, one), true);
  assert.equal(sameTarget(one, two), false);
  assert.equal(sameTarget(one, pageTargetOf('/other/r/pull/1')), false);
  assert.equal(sameTarget(one, null), false);
  assert.equal(sameTarget(null, null), false, 'no target is not a match, it is an absence');
  // Moving between tabs of one repository keeps the target, so the drawn buttons stay valid
  assert.equal(sameTarget(pageTargetOf('/o/r/issues'), pageTargetOf('/o/r/pulls')), true);
});

test('storedItemBytes: an item is its key plus the UTF-8 bytes of its JSON', () => {
  const { storedItemBytes, MAX_STORED_ITEM_BYTES, SYNC_QUOTA_BYTES_PER_ITEM } =
    vm.runInThisContext('({ storedItemBytes, MAX_STORED_ITEM_BYTES, SYNC_QUOTA_BYTES_PER_ITEM })');
  assert.equal(storedItemBytes('k', 'ab'), 1 + 4); // "ab" is four characters of JSON
  // An emoji face is one JS character and four bytes — counting characters would under-measure it
  assert.ok(storedItemBytes('k', '🤖') > storedItemBytes('k', 'ab'));
  assert.ok(MAX_STORED_ITEM_BYTES < SYNC_QUOTA_BYTES_PER_ITEM, 'the budget has to leave room');
  assert.equal(SYNC_QUOTA_BYTES_PER_ITEM, 8192);
});

// --- One final gate, not a check after every await (R10) ---
// R9 put a target check after each await it could see, and the next await was the one it could not:
// a fetch that resolved after a navigation reported the page it had left, an executeScript failure
// returned before reaching its check, the icon path sent no target at all, and the storage read
// before the command went out had nothing after it. Enumerating await points misses the next one.

test('pageTargetOfUrl: a full URL reduces to the same four parts, or to nothing', () => {
  const { pageTargetOfUrl } = vm.runInThisContext('({ pageTargetOfUrl })');
  assert.deepEqual(pageTargetOfUrl('https://github.com/o/r/pull/7'),
    { kind: 'pr', owner: 'o', repo: 'r', number: '7' });
  assert.equal(pageTargetOfUrl('https://example.com/o/r/pull/7'), null, 'another host is not a page of ours');
  assert.equal(pageTargetOfUrl('not a url'), null);
  assert.equal(pageTargetOfUrl(undefined), null);
});

test('the final gate refuses unless every part of the request describes the clicked page', () => {
  // Checked once, immediately before the command leaves, so every await behind it is covered at once
  const { requestIsCoherent, pageTargetOf } = vm.runInThisContext('({ requestIsCoherent, pageTargetOf })');
  const one = pageTargetOf('/o/r/issues/7');
  const two = pageTargetOf('/o/r/issues/8');
  assert.equal(requestIsCoherent({ clicked: one, source: one, current: one }), true);
  // The shape shared by every report so far: the tab moved on while we were still working
  assert.equal(requestIsCoherent({ clicked: one, source: one, current: two }), false);
  assert.equal(requestIsCoherent({ clicked: one, source: one, current: pageTargetOf('/other/r/issues/7') }), false);
  // Fail closed: nothing to be coherent with, nothing read back, a tab that vanished
  assert.equal(requestIsCoherent({ clicked: null, source: null, current: null }), false);
  assert.equal(requestIsCoherent({ clicked: one, source: one, current: null }), false);
});

test('the ABA repro: a page that went 1 → 2 → 1 must not mix the two', () => {
  // `clicked` is where the user pressed the button; `source` is the tab as the message was
  // dispatched, and it is where the repository, owner and number are actually read from. Nobody
  // compared those two, so a tab that left page 1 and came back produced a request holding page 2's
  // number and page 1's branch — and the other two checks both agreed, because both saw page 1.
  const { requestIsCoherent, pageTargetOf } = vm.runInThisContext('({ requestIsCoherent, pageTargetOf })');
  const clicked = pageTargetOf('/o/r/pull/1');
  const source = pageTargetOf('/o/r/pull/2'); // sender.tab.url at dispatch
  const current = pageTargetOf('/o/r/pull/1'); // live location at the gate — back on page 1
  assert.equal(requestIsCoherent({ clicked, source, current }), false, 'the number came from page 2');
  assert.equal(requestIsCoherent({ clicked, source: clicked, current }), true);
});

test('a page message without a target is not a request we can check', () => {
  // onMessage required `shown` and not `target`, so anything that omitted it — a content script from
  // before the update, still running in an open tab — sailed past the page check in silence.
  const { isPageTarget } = vm.runInThisContext('({ isPageTarget })');
  const { pageTargetOf } = vm.runInThisContext('({ pageTargetOf })');
  assert.equal(isPageTarget(pageTargetOf('/o/r/pull/7')), true);
  assert.equal(isPageTarget(pageTargetOf('/o/r')), true, 'a repository page has no number');
  assert.equal(isPageTarget(undefined), false);
  assert.equal(isPageTarget(null), false);
  assert.equal(isPageTarget({}), false);
  assert.equal(isPageTarget({ kind: 'pr', owner: 'o', repo: 'r', number: 7 }), false, 'the number is a string');
  assert.equal(isPageTarget([{ kind: 'pr', owner: 'o', repo: 'r', number: '7' }]), false);
});

test('a GitHub page on a non-standard port is not a page of ours', () => {
  // scheme and host were checked one at a time and the port was the axis left over. `pageTargetOf`
  // keeps only the pathname, so `clicked` on github.com, `source` on github.com:8443 and `current`
  // from the live location all normalized to the same target and the gate agreed with itself.
  // Chrome's match patterns do not help: a pattern with no port matches every port, so the
  // manifest's `https://github.com/*` covers `:8443` too.
  const { pageTargetOfUrl } = vm.runInThisContext('({ pageTargetOfUrl })');
  assert.equal(pageTargetOfUrl('https://github.com:8443/o/r/pull/1'), null);
  // The default port is written out by some links and normalizes away — it is the same origin
  assert.deepEqual(pageTargetOfUrl('https://github.com:443/o/r/pull/1'),
    { kind: 'pr', owner: 'o', repo: 'r', number: '1' });
  assert.deepEqual(pageTargetOfUrl('https://github.com/o/r/pull/1'),
    { kind: 'pr', owner: 'o', repo: 'r', number: '1' });
  assert.equal(pageTargetOfUrl('http://github.com:80/o/r/pull/1'), null);
  assert.equal(pageTargetOfUrl('https://evil.com/o/r/pull/1'), null);
  // A host that merely starts with ours is a different host, and always was
  assert.equal(pageTargetOfUrl('https://github.com.evil.com/o/r/pull/1'), null);
});

test('an http:// GitHub page is not a page of ours', () => {
  // The host was checked and the scheme was not, so `http://github.com/o/r/pull/1` came back as a
  // perfectly good target. The manifest only injects the content script over https, but the icon
  // path never goes through it: `activeTab` grants executeScript on the tab that was clicked, so an
  // http page could still be read for the branch and the default branch. An http response is not a
  // GitHub document — it is whatever was on the wire — and it decides what the command runs against.
  const { pageTargetOfUrl } = vm.runInThisContext('({ pageTargetOfUrl })');
  assert.equal(pageTargetOfUrl('http://github.com/o/r/pull/1'), null);
  assert.equal(pageTargetOfUrl('ftp://github.com/o/r'), null);
  assert.equal(pageTargetOfUrl('javascript:alert(1)//github.com/o/r'), null);
  assert.deepEqual(pageTargetOfUrl('https://github.com/o/r/pull/1'),
    { kind: 'pr', owner: 'o', repo: 'r', number: '1' });
});
