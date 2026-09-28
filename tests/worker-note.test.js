// The service worker's side of a click-time claude note, run for real: extension/background.js in a
// realm of its own (tests/worker-harness.js), driven through its runtime and icon listeners, with the
// native host's inbox as the observation. Run with `node --test` from the repo root.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { loadWorker, PAGES, NATIVE_HOST } = require('./worker-harness.js');

// This realm builds what a content script would send, from the same defaults.js
const readExtension = name => fs.readFileSync(path.join(__dirname, '../extension', name), 'utf8');
vm.runInThisContext(readExtension('i18n.js'));
vm.runInThisContext(readExtension('defaults.js'));
const { catalogueBackend } = require('./chrome-messages.js');
vm.runInThisContext('({ installMessageBackend })').installMessageBackend(catalogueBackend('en'));
const { BUTTON_KINDS, buttonFingerprint, pageTargetOfUrl, buildListBatchMessage } =
  vm.runInThisContext('({ BUTTON_KINDS, buttonFingerprint, pageTargetOfUrl, buildListBatchMessage })');

const cp = (...points) => String.fromCodePoint(...points);
const DETAIL_ACTION = { pr: 'execute_command', issue: 'execute_issue_command', repo: 'execute_repo_command' };
const LIST_KINDS = new Set(['pr-list', 'issue-list']);
const preset = id => Object.values(BUTTON_KINDS).flatMap(kind => kind.presets).find(p => p.id === id);
const kindOf = id => Object.entries(BUTTON_KINDS).find(([, kind]) => kind.presets.some(p => p.id === id))[0];
const stored = ({ face = 'x', command, claudeInputs = [] }) => ({ face, label: 'label', command, claudeInputs: [...claudeInputs] });

// What each page kind's click hands the app as variables, in the worker's own order
const VARIABLES = {
  pr: { repo: 'r', owner: 'o', number: '7', branch: 'feat/x', main: 'main', branch_underbar: 'feat_x', base: 'main' },
  issue: { repo: 'r', owner: 'o', number: '3', main: 'main' },
  repo: { repo: 'r', owner: 'o', main: 'main' },
};
const ITEMS = {
  'pr-list': [{ variables: { repo: 'r', owner: 'o', number: '7' } }, { variables: { repo: 'r', owner: 'o', number: '8' } }],
  'issue-list': [{ variables: { repo: 'r', owner: 'o', number: '3' } }, { variables: { repo: 'r', owner: 'o', number: '4' } }],
};

// The native call a click on `kind` must produce: to the host the app registers, a single command, or
// a batch on a list page — its items in the page's order unless a test reorders the page
function expected(kind, command, inputs, items = ITEMS[kind]) {
  const claude = inputs.length ? { claude_inputs: inputs } : {};
  const message = LIST_KINDS.has(kind)
    ? { command, items, ...claude }
    : { command_template: command, variables: VARIABLES[kind], ...claude };
  return { host: NATIVE_HOST, message };
}

// A worker whose storage holds `button` as the first button of `kind`, on a page of `page`'s kind
function workerWith(kind, button, page = kind, extra = {}) {
  return loadWorker({ store: { [BUTTON_KINDS[kind].storageKey]: [button], ...extra }, page: PAGES[page] });
}

// The message a content script sends for button 0 of `kind`. `options.note` is sent only when the key
// is present — a note-less click carries no `note` key at all.
function click(kind, button, options = {}) {
  const shown = options.shown ?? buttonFingerprint(button);
  const page = options.page ?? kind;
  const target = options.target ?? pageTargetOfUrl(PAGES[page].href);
  const hasNote = Object.hasOwn(options, 'note');
  if (LIST_KINDS.has(kind)) {
    const selected = options.selected ?? PAGES[page].selected;
    return hasNote
      ? buildListBatchMessage(0, shown, target, selected, options.note)
      : buildListBatchMessage(0, shown, target, selected);
  }
  const message = { action: DETAIL_ACTION[kind], buttonIndex: 0, shown, target };
  if (hasNote) message.note = options.note;
  return message;
}

const refusals = worker => new Map(Array.from(worker.get('CLAUDE_NOTE_REFUSALS'), ([code, text]) => [code, text]));

test('every shipped preset clicked without a note sends exactly what it sent before', async () => {
  const ids = Object.values(BUTTON_KINDS).flatMap(kind => kind.presets.map(p => p.id));
  assert.equal(ids.length, 13);
  for (const id of ids) {
    const kind = kindOf(id);
    const button = stored(preset(id));
    const worker = workerWith(kind, button);
    const response = await worker.dispatch(click(kind, button));
    assert.equal(response?.success, true, `${id}: ${JSON.stringify(response)}`);
    assert.deepEqual(worker.native(), [expected(kind, button.command, button.claudeInputs)], id);
    assert.ok(worker.storageUntouched(), `${id}: the worker changed what storage handed it`);
  }
});

test('a note joins as the last claude input, once, on every branch', async () => {
  const note = 'look at the retry path first';
  const cases = [
    ['pr', 'pr.review'], ['issue', 'issue.read'], ['repo', 'repo.openClaude'],
    ['pr-list', 'pr-list.checkoutClaude'], ['issue-list', 'issue-list.triageClaude'],
  ];
  for (const [kind, id] of cases) {
    const button = stored(preset(id));
    const worker = workerWith(kind, button);
    const response = await worker.dispatch(click(kind, button, { note }));
    assert.equal(response?.success, true, `${id}: ${JSON.stringify(response)}`);
    assert.deepEqual(worker.native(), [expected(kind, button.command, [...button.claudeInputs, note])], id);
    assert.ok(worker.storageUntouched(), `${id}: the worker changed what storage handed it`);
  }
});

test('the note sent is the worker\'s own verdict on it, after the stored inputs as a click sends them', async () => {
  const button = stored({ command: '{cd} && claude', claudeInputs: ['  !gh pr diff {number}  ', '', '   '] });
  const worker = workerWith('pr', button);
  const response = await worker.dispatch(click('pr', button, { note: '   look here   ' }));
  assert.equal(response?.success, true, JSON.stringify(response));
  assert.deepEqual(worker.native(), [expected('pr', button.command, ['!gh pr diff {number}', 'look here'])]);
});

test('a refused note never reaches the native host, and is refused before anything is read', async () => {
  const button = stored(preset('pr.review'));
  const listButton = stored(preset('issue-list.triageClaude'));
  const cases = [
    [42, 'not-string'], [null, 'not-string'], [{}, 'not-string'], [[], 'not-string'], [true, 'not-string'],
    ['', 'empty'], ['    ', 'empty'],
    [`a${cp(0xD800)}b`, 'unpaired-surrogate'], [`a${cp(0xDC00)}`, 'unpaired-surrogate'],
    [`a${cp(10)}b`, 'control-character'], [`a${cp(0x7F)}b`, 'control-character'],
    ['!rm -rf ~', 'leading-character'], ['/login', 'leading-character'], ['#remember', 'leading-character'],
    [`${cp(0x200B)}!x`, 'leading-character'],
    ['look at {repo}', 'braces'], ['{{number}}', 'braces'],
    ['a'.repeat(4097), 'too-long'],
  ];
  for (const [kind, subject] of [['pr', button], ['issue-list', listButton]]) {
    for (const [note, code] of cases) {
      const worker = workerWith(kind, subject);
      const response = await worker.dispatch(click(kind, subject, { note }));
      const label = `${kind} ${JSON.stringify(note).slice(0, 30)}`;
      assert.deepEqual(response, { success: false, error: refusals(worker).get(code) }, label);
      assert.equal(worker.calls.native.length, 0, `${label}: sent anyway`);
      assert.deepEqual(worker.calls.storage, [], `${label}: storage was read before the note was judged`);
      assert.deepEqual(worker.calls.scripting, [], `${label}: the page was read before the note was judged`);
    }
  }
});

test('a note is refused by a button that takes none, judged on the button storage holds', async () => {
  const notTaking = ['pr.checkout', 'pr.worktree', 'issue.open', 'repo.open', 'repo.updateMain']
    .map(id => [kindOf(id), stored(preset(id))]);
  const full = stored({ command: '{cd} && claude', claudeInputs: ['!a', '!b', '!c', '!d', '!e'] });
  for (const [kind, button] of [...notTaking, ['pr', full], ['pr-list', full]]) {
    const worker = workerWith(kind, button);
    const response = await worker.dispatch(click(kind, button, { note: 'please' }));
    assert.deepEqual(response, { success: false, error: worker.get('CLAUDE_NOTE_NOT_TAKEN_ERROR') }, button.command);
    assert.equal(worker.calls.native.length, 0, `${button.command}: sent anyway`);
    assert.ok(worker.calls.storage.length > 0, 'refused before storage was read');
  }
});

test('a note does not get past a changed button or a click from another page', async () => {
  const button = stored(preset('pr.review'));
  const drawn = stored(preset('pr.checkoutClaude'));

  const changed = workerWith('pr', button);
  const refusedButton = await changed.dispatch(click('pr', button, { note: 'hi', shown: buttonFingerprint(drawn) }));
  assert.deepEqual(refusedButton, { success: false, error: changed.get('BUTTON_CHANGED_ERROR') });
  assert.equal(changed.calls.native.length, 0);

  // Clicked on PR 7, but the tab — and so every value read from it — is on PR 8
  const moved = workerWith('pr', button);
  moved.navigate('https://github.com/o/r/pull/8');
  const refusedPage = await moved.dispatch(click('pr', button, { note: 'hi' }), { url: 'https://github.com/o/r/pull/8' });
  assert.deepEqual(refusedPage, { success: false, error: moved.get('PAGE_CHANGED_ERROR') });
  assert.equal(moved.calls.native.length, 0);
});

test('the final gate refuses a note whose page moved after every earlier read had answered', async () => {
  // The page moves on its own, right after the last read before the gate has answered — not inside the
  // gate's read — so it moves whether or not a gate is there to see it. Another page, not a sub-path:
  // `/pull/7/files` is still PR 7 to the gate.
  const cases = [
    ['pr', 'pr.review', 'repoMainBranch', 'https://github.com/o/r/pull/8'],
    ['issue', 'issue.read', 'repoMainBranch', 'https://github.com/o/r/issues/4'],
    ['repo', 'repo.openClaude', 'repoMainBranch', 'https://github.com/o/other'],
    ['pr-list', 'pr-list.checkoutClaude', 'readListSelectionFromPage', 'https://github.com/o/other/pulls'],
    ['issue-list', 'issue-list.triageClaude', 'readListSelectionFromPage', 'https://github.com/o/other/issues'],
  ];
  for (const [kind, id, lastRead, movedTo] of cases) {
    const button = stored(preset(id));
    const worker = workerWith(kind, button);
    let moved = false;
    worker.afterAnswer(lastRead, () => {
      worker.navigate(movedTo);
      moved = true;
    });
    const response = await worker.dispatch(click(kind, button, { note: 'hi' }));
    assert.equal(moved, true, `${kind}: the page never moved`);
    assert.deepEqual(worker.native(), [], `${kind}: sent past a moved page`);
    assert.deepEqual(response, { success: false, error: worker.get('PAGE_CHANGED_ERROR') }, kind);
    assert.equal(worker.calls.scripting.at(-1), 'readCurrentHref', `${kind}: the gate was not the last read`);
  }
});

test('a list note does not survive a selection the worker reads differently', async () => {
  const button = stored(preset('pr-list.checkoutClaude'));
  const worker = loadWorker({
    store: { [BUTTON_KINDS['pr-list'].storageKey]: [button] },
    page: { ...PAGES['pr-list'], selected: [{ key: 'o/r/pr/7', title: 'Seven' }] },
  });
  const response = await worker.dispatch(click('pr-list', button, { note: 'hi', selected: PAGES['pr-list'].selected }));
  assert.deepEqual(response, { success: false, error: worker.get('LIST_SELECTION_CHANGED_ERROR') });
  assert.equal(worker.calls.native.length, 0);
});

test('a click the app refused is the click\'s failure, with the app\'s own reason', async () => {
  // Success on the page means the app took the request; a refusal from the app has to arrive as a
  // failure, not be read as one more success
  const refusal = { success: false, error: 'Variable {base} not provided' };
  for (const [kind, id] of [['pr', 'pr.review'], ['issue', 'issue.read'], ['repo', 'repo.openClaude']]) {
    const button = stored(preset(id));
    const worker = loadWorker({ store: { [BUTTON_KINDS[kind].storageKey]: [button] }, page: PAGES[kind], reply: () => refusal });
    const response = await worker.dispatch(click(kind, button, { note: 'hi' }));
    assert.deepEqual(response, refusal, kind);
    assert.deepEqual(worker.native(), [expected(kind, button.command, [...button.claudeInputs, 'hi'])], kind);
  }
});

test('a batch the app ran in part arrives as the app\'s own result, keyed in the order the worker read', async () => {
  // A batch answers per item, so an item that failed does not fail the click: the app's result comes
  // back whole inside an outer success, and `itemKeys` names the rows in the order the worker read
  // them from the page — the order of the items it sent — not the order the click's snapshot had
  const outcome = { success: false, items: [{ success: true }, { success: false, error: 'worktree already exists' }] };
  for (const [kind, id] of [['pr-list', 'pr-list.checkoutClaude'], ['issue-list', 'issue-list.triageClaude']]) {
    const button = stored(preset(id));
    const current = [...PAGES[kind].selected].reverse();
    const worker = loadWorker({
      store: { [BUTTON_KINDS[kind].storageKey]: [button] },
      page: { ...PAGES[kind], selected: current },
      reply: () => outcome,
    });
    const response = await worker.dispatch(click(kind, button, { note: 'hi' }));
    assert.deepEqual(response, { success: true, batch: outcome, itemKeys: current.map(row => row.key) }, kind);
    // One request, its items in the page's current order — an item that failed is not sent again
    const currentItems = [...ITEMS[kind]].reverse();
    assert.deepEqual(worker.native(), [expected(kind, button.command, [...button.claudeInputs, 'hi'], currentItems)], kind);
  }
});

test('the extension icon still runs the first button of the page, with no note, on every page kind', async () => {
  const firstOf = { pr: 'pr.review', issue: 'issue.read', repo: 'repo.openClaude' };
  for (const page of Object.keys(PAGES)) {
    const runKind = LIST_KINDS.has(page) ? 'repo' : page;
    const button = stored(preset(firstOf[runKind]));
    const worker = workerWith(runKind, button, page);
    await worker.clickIcon();
    assert.deepEqual(worker.native(), [expected(runKind, button.command, button.claudeInputs)], page);
  }
});

test('every refusal code has one English diagnostic, and none is a message id', () => {
  const worker = loadWorker();
  const codes = Array.from(worker.get('CLAUDE_NOTE_ERRORS'));
  const map = refusals(worker);
  assert.deepEqual([...map.keys()].sort(), [...codes].sort());
  for (const text of [...map.values(), worker.get('CLAUDE_NOTE_NOT_TAKEN_ERROR')]) {
    assert.equal(typeof text, 'string');
    assert.ok(text.length > 0 && !/^ext\./.test(text), JSON.stringify(text));
  }
});
