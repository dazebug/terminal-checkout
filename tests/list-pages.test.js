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
  selectedListRows,
  listSelectionStatus,
} = vm.runInThisContext(`({
  parseListRowAnchor,
  listCheckboxMode,
  checkedListRowKeys,
  carryListRowChecks,
  selectedListRows,
  listSelectionStatus,
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
