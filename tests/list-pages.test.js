// Pure contracts for the list-page row selection seam. Run with `node --test` from the repository root.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const readExtension = name => fs.readFileSync(path.join(__dirname, '../extension', name), 'utf8');
vm.runInThisContext(readExtension('i18n.js'));
vm.runInThisContext(readExtension('defaults.js'));

const {
  parseListRowAnchor,
  listCheckboxMode,
  checkedListRowKeys,
  carryListRowChecks,
  attachedCheckedListRowKeys,
  selectedListRows,
  listSelectionStatus,
  validateListBatchSelection,
  buildListBatchItems,
  buildListBatchRequest,
  sameListSelectionKeys,
  buildListBatchMessage,
  interpretListBatchResponse,
  listBatchSelectionNotice,
  listBatchButtonIdentity,
  listBatchResultView,
} = vm.runInThisContext(`({
  parseListRowAnchor,
  listCheckboxMode,
  checkedListRowKeys,
  carryListRowChecks,
  attachedCheckedListRowKeys,
  selectedListRows,
  listSelectionStatus,
  validateListBatchSelection,
  buildListBatchItems,
  buildListBatchRequest,
  sameListSelectionKeys,
  buildListBatchMessage,
  interpretListBatchResponse,
  listBatchSelectionNotice,
  listBatchButtonIdentity,
  listBatchResultView,
})`);

test('parseListRowAnchor: normal and fork paths produce a stable row key and title', () => {
  assert.deepEqual(
    parseListRowAnchor('/owner/repo/pull/7', '  Fix the thing\n'),
    { key: 'owner/repo/pr/7', owner: 'owner', repo: 'repo', kind: 'pr', number: '7', title: 'Fix the thing' },
  );
  assert.deepEqual(
    parseListRowAnchor('https://github.com/fork-owner/fork-repo/issues/19?tab=comments', 'Triage this'),
    { key: 'fork-owner/fork-repo/issue/19', owner: 'fork-owner', repo: 'fork-repo', kind: 'issue', number: '19', title: 'Triage this' },
  );
});

test('parseListRowAnchor: non-list anchors and numberless links are rejected', () => {
  assert.equal(parseListRowAnchor('/owner/repo/pulls/7', 'not a row'), null);
  assert.equal(parseListRowAnchor('/owner/repo/pull/', 'missing number'), null);
  assert.equal(parseListRowAnchor('/owner/repo/issues', 'missing number'), null);
  assert.equal(parseListRowAnchor('/owner/repo/commit/7', 'not a row'), null);
});

test('listCheckboxMode: only complete native coverage selects native mode', () => {
  assert.equal(listCheckboxMode([
    { key: 'a', native: true },
    { key: 'b', native: true },
  ]), 'native');
  assert.equal(listCheckboxMode([
    { key: 'a', native: true },
    { key: 'b', native: false },
  ]), 'owned');
  assert.equal(listCheckboxMode([{ key: 'a', native: false }]), 'owned');
  assert.equal(listCheckboxMode([]), null);
});

test('carryListRowChecks: switching all-or-none modes transfers checked state by key', () => {
  const oldRows = [
    { key: 'owner/repo/pr/7', checked: true },
    { key: 'owner/repo/pr/8', checked: false },
  ];
  const selected = checkedListRowKeys(oldRows);
  assert.deepEqual(selected, ['owner/repo/pr/7']);
  assert.deepEqual(
    carryListRowChecks(oldRows.map(({ key }) => ({ key })), selected),
    [
      { key: 'owner/repo/pr/7', checked: true },
      { key: 'owner/repo/pr/8', checked: false },
    ],
  );
});

test('selectedListRows and listSelectionStatus expose zero and cap failures without DOM', () => {
  const rows = [
    { key: 'owner/repo/issue/1', title: 'one', checked: true },
    { key: 'owner/repo/issue/2', title: 'two', checked: false },
    { key: 'owner/repo/issue/3', title: 'three', checked: true },
  ];
  const selected = selectedListRows(rows);
  assert.deepEqual(selected, [
    { key: 'owner/repo/issue/1', title: 'one' },
    { key: 'owner/repo/issue/3', title: 'three' },
  ]);
  assert.deepEqual(listSelectionStatus([]), { count: 0, valid: false, error: 'empty' });
  assert.deepEqual(listSelectionStatus(selected), { count: 2, valid: true, error: null });
  assert.deepEqual(
    listSelectionStatus(Array.from({ length: 9 }, (_, i) => ({ key: String(i), title: '' }))),
    { count: 9, valid: false, error: 'too-many' },
  );
});

test('validateListBatchSelection rejects malformed, empty, and over-cap snapshots', () => {
  assert.deepEqual(validateListBatchSelection('not an array'), { valid: false, error: 'not-array' });
  assert.deepEqual(validateListBatchSelection([]), { valid: false, error: 'empty' });
  assert.deepEqual(
    validateListBatchSelection(Array.from({ length: 9 }, (_, i) => ({ key: String(i), title: '' }))),
    { valid: false, error: 'too-many' },
  );
  assert.deepEqual(
    validateListBatchSelection([{ key: 7, title: 'seven' }]),
    { valid: false, error: 'invalid-row' },
  );
  assert.deepEqual(
    validateListBatchSelection([{ key: 'owner/repo/pr/7', title: 'Fix it' }]),
    { valid: true, error: null },
  );
});

test('buildListBatchItems maps re-read rows in document order using target repo and list kind', () => {
  assert.deepEqual(
    buildListBatchItems(
      { kind: 'pr-list', owner: 'owner', repo: 'repo' },
      [
        { key: 'owner/repo/pr/19', title: 'second in the document' },
        { key: 'owner/repo/pr/7', title: 'first in the document' },
      ],
    ),
    [
      { variables: { repo: 'repo', owner: 'owner', pr: '19' } },
      { variables: { repo: 'repo', owner: 'owner', pr: '7' } },
    ],
  );
  assert.deepEqual(
    buildListBatchItems(
      { kind: 'issue-list', owner: 'owner', repo: 'repo' },
      [{ key: 'owner/repo/issue/3', title: 'triage' }],
    ),
    [{ variables: { repo: 'repo', owner: 'owner', issue: '3' } }],
  );
});

test('buildListBatchItems includes owner so {cd} clone fallback stays correct', () => {
  assert.deepEqual(
    buildListBatchItems(
      { kind: 'pr-list', owner: 'octo', repo: 'repo' },
      [{ key: 'octo/repo/pr/7', title: 'needs owner' }],
    ),
    [{ variables: { repo: 'repo', owner: 'octo', pr: '7' } }],
  );
});

test('buildListBatchRequest uses the batch command key and conditionally carries claude inputs', () => {
  const request = buildListBatchRequest(
    { command: '{cd} && claude', claudeInputs: ['!gh issue view {issue} --comments'] },
    [{ variables: { repo: 'repo', issue: '3' } }],
  );
  assert.deepEqual(request, {
    command: '{cd} && claude',
    claude_inputs: ['!gh issue view {issue} --comments'],
    items: [{ variables: { repo: 'repo', issue: '3' } }],
  });
  assert.equal(Object.hasOwn(request, 'command_template'), false);
  assert.deepEqual(
    buildListBatchRequest({ command: 'echo {pr}' }, [{ variables: { repo: 'repo', pr: '7' } }]),
    { command: 'echo {pr}', items: [{ variables: { repo: 'repo', pr: '7' } }] },
  );
});

test('sameListSelectionKeys rejects a changed key set while ignoring document order', () => {
  assert.equal(
    sameListSelectionKeys(
      [{ key: 'owner/repo/pr/7', title: '7' }, { key: 'owner/repo/pr/8', title: '8' }],
      [{ key: 'owner/repo/pr/8', title: '8 now' }, { key: 'owner/repo/pr/7', title: '7 now' }],
    ),
    true,
  );
  assert.equal(
    sameListSelectionKeys(
      [{ key: 'owner/repo/pr/7', title: '7' }],
      [{ key: 'owner/repo/pr/9', title: '9' }],
    ),
    false,
  );
});

test('attachedCheckedListRowKeys keeps only keys whose controls are still attached', () => {
  const staleElement = {
    contains: node => node?.id === 'native-keep',
  };
  const liveElement = {
    contains: node => node?.id === 'native-keep',
  };
  const rows = [
    {
      key: 'owner/repo/pr/7',
      checked: true,
      nativeCheckboxes: [{ id: 'native-keep' }],
      element: liveElement,
    },
    {
      key: 'owner/repo/pr/8',
      checked: true,
      nativeCheckboxes: [{ id: 'native-drop' }],
      element: staleElement,
    },
  ];
  assert.deepEqual(attachedCheckedListRowKeys(rows, 'native'), ['owner/repo/pr/7']);
});

test('buildListBatchMessage carries snapshot comparison data and the clicked button identity', () => {
  const target = { kind: 'issue-list', owner: 'owner', repo: 'repo', number: null };
  const selected = [{ key: 'owner/repo/issue/3', title: 'triage' }];
  assert.deepEqual(
    buildListBatchMessage(1, 'fingerprint', target, selected),
    {
      action: 'execute_list_batch',
      buttonIndex: 1,
      shown: 'fingerprint',
      target,
      selected,
    },
  );
});

test('interpretListBatchResponse preserves transport and app failure layers with per-item results', () => {
  const outcome = interpretListBatchResponse({
    success: true,
    batch: {
      success: false,
      error: 'one item failed validation',
      items: [
        { success: false, error: 'Unknown variable: {pr}' },
        { success: false, error: 'not launched — batch rejected during validation' },
      ],
    },
  });
  assert.deepEqual(outcome, {
    transportSuccess: true,
    appSuccess: false,
    error: 'one item failed validation',
    itemKeys: [],
    items: [
      { success: false, error: 'Unknown variable: {pr}' },
      { success: false, error: 'not launched — batch rejected during validation' },
    ],
  });
  assert.equal(interpretListBatchResponse({ success: false, error: 'page changed' }).transportSuccess, false);
});

test('parseListRowAnchor: a different repository is excluded before row collection', () => {
  const expected = { owner: 'owner', repo: 'repo' };
  assert.equal(parseListRowAnchor('/other/repo/pull/99', 'Other repository PR', expected), null);
  assert.ok(parseListRowAnchor('/owner/repo/pull/99', 'This repository PR', expected));
});

test('buildListBatchItems: a different repository cannot be remapped into the target repo', () => {
  assert.equal(
    buildListBatchItems(
      { kind: 'pr-list', owner: 'owner', repo: 'repo' },
      [{ key: 'other/repo/pr/99', title: 'Other repository PR' }],
    ),
    null,
  );
});

test('list row readers keep their structural literals and repository filter in sync', () => {
  const content = readExtension('content.js');
  const background = readExtension('background.js');
  const literals = {
    rowSelector: '[role="row"], [role="listitem"], li, div[class~="Box-row"]',
    ownedClass: 'terminal-list-checkbox',
    anchorPattern: String.raw`/^\/([^/]+)\/([^/]+)\/(pull|issues)\/(\d+)\/?$/`,
  };

  for (const [name, literal] of Object.entries(literals)) {
    assert.equal(content.split(literal).length - 1, 1, `content ${name} literal drifted`);
    assert.equal(background.split(literal).length - 1, 1, `background ${name} literal drifted`);
  }
  assert.match(content, /expectedTarget\.owner/);
  assert.match(content, /expectedTarget\.repo/);
  assert.match(background, /expected\.owner/);
  assert.match(background, /expected\.repo/);
});

test('listBatchSelectionNotice turns empty and cap verdicts into localized button diagnostics', () => {
  assert.deepEqual(
    listBatchSelectionNotice({ count: 0, valid: false, error: 'empty' }),
    { messageKey: 'ext.list.batch.selection.empty', args: [] },
  );
  assert.deepEqual(
    listBatchSelectionNotice({ count: 9, valid: false, error: 'too-many' }),
    { messageKey: 'ext.list.batch.selection.tooMany', args: [9, 8] },
  );
  assert.equal(listBatchSelectionNotice({ count: 2, valid: true, error: null }), null);
});

test('listBatchResultView maps ordered item results without crossing button identities', () => {
  const selected = [
    { key: 'owner/repo/pr/7', title: 'first' },
    { key: 'owner/repo/pr/8', title: 'second' },
  ];
  const first = listBatchResultView('pr-list:0', selected, {
    appSuccess: false,
    itemKeys: ['owner/repo/pr/8', 'owner/repo/pr/7'],
    items: [
      { success: true },
      { success: false, error: 'not launched — response deadline exceeded' },
    ],
  });
  assert.deepEqual(first, {
    buttonIdentity: 'pr-list:0',
    phase: 'error',
    badges: [
      { key: 'owner/repo/pr/8', success: true, error: null },
      { key: 'owner/repo/pr/7', success: false, error: 'not launched — response deadline exceeded' },
    ],
  });
  assert.notEqual(listBatchButtonIdentity('pr-list', 0), listBatchButtonIdentity('pr-list', 1));
  assert.notEqual(listBatchButtonIdentity('pr-list', 0), listBatchButtonIdentity('issue-list', 0));
  assert.deepEqual(
    listBatchResultView('pr-list:0', selected, { appSuccess: null, items: [] }),
    { buttonIdentity: 'pr-list:0', phase: 'error', badges: [] },
  );
});
