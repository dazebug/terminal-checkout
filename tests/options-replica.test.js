// Replica model and source contracts; DOM interaction is covered by the disposable jsdom harness.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');
const source = read('options-replica.js');
const context = vm.createContext({
  window: {},
  tr: (key, ...args) => key.replace(/%1\$s/g, String(args[0] ?? '')),
});
vm.runInContext(read('defaults.js'), context, { filename: 'defaults.js' });
vm.runInContext(source, context, { filename: 'options-replica.js' });
const buttonKinds = vm.runInContext('BUTTON_KINDS', context);
const replica = context.window.optionsReplica;
const model = replica.model;
const asArray = value => JSON.parse(JSON.stringify(value));

test('replica publishes one immutable example context and the complete GitHub copy table', () => {
  assert.equal(replica.mount.length, 3);
  assert.equal(typeof replica.focusButton, 'function');
  assert.equal(typeof replica.openDrawer, 'function');
  assert.equal(typeof replica.closeDrawer, 'function');
  assert.equal(typeof replica.isDrawerOpen, 'function');
  assert.equal(replica.getExampleContext(), replica.EXAMPLE_CONTEXT);
  assert.deepEqual(asArray(replica.EXAMPLE_CONTEXT), {
    owner: 'octo-demo',
    repo: 'sample-repo',
    pullRequest: { number: 42, branch: 'example/options', base: 'main', title: 'Add button presets' },
    issue: { number: 17, title: 'Example tracking issue' },
    repoPath: '/work/sample-repo',
  });
  assert.equal(Object.isFrozen(replica.EXAMPLE_CONTEXT), true);
  assert.equal(Object.isFrozen(replica.EXAMPLE_CONTEXT.pullRequest), true);
  assert.equal(Object.isFrozen(replica.EXAMPLE_CONTEXT.issue), true);
  assert.equal(Object.isFrozen(replica.GITHUB_UI_COPY), true);
  assert.ok(Object.values(replica.GITHUB_UI_COPY).every(value => typeof value === 'string'));
  assert.equal(replica.GITHUB_UI_COPY.open, 'Open');
  assert.equal(replica.GITHUB_UI_COPY.pullRequests, 'Pull requests');
  assert.equal(replica.GITHUB_UI_COPY.allIssues, 'All issues');
});

test('page kinds and route suffixes come from the five live default kinds and carry all 13 presets', () => {
  const kinds = asArray(model.replicaKinds());
  assert.deepEqual(kinds.map(({ kind }) => kind), ['pr', 'pr-list', 'issue', 'issue-list', 'repo']);
  assert.deepEqual(kinds.map(({ route }) => route), [
    '/pull/42', '/pulls', '/issues/17', '/issues', '/',
  ]);
  assert.deepEqual(kinds.map(({ storageKey }) => storageKey), [
    'buttons', 'prListButtons', 'issueButtons', 'issueListButtons', 'repoButtons',
  ]);
  assert.deepEqual(kinds.map(({ presetCount }) => presetCount), [5, 1, 3, 1, 3]);
  assert.equal(kinds.reduce((sum, kind) => sum + kind.presetCount, 0), 13);
  assert.equal(kinds.some(({ kind }) => kind === 'conflict'), false);
});

test('GitHub button shape matches content.js for detail, list, and repository buttons', () => {
  assert.equal(model.replicaButtonLook('pr', { face: '🌳diff' }), 'text');
  assert.equal(model.replicaButtonLook('pr', { face: '🌳' }), 'emoji');
  assert.equal(model.replicaButtonLook('pr', { face: '' }), 'emoji');
  assert.equal(model.replicaButtonLook('pr-list', { face: '🌳' }), 'list-pill');
  assert.equal(model.replicaButtonLook('pr-list', { face: 'a long text face' }), 'list-pill');
  assert.equal(model.replicaButtonLook('issue-list', { face: '🤖' }), 'list-pill');
  assert.equal(model.replicaButtonLook('issue', { face: 'Review' }), 'text');
  assert.equal(model.replicaButtonLook('repo', { face: '📂' }), 'filled');
  assert.equal(model.replicaButtonLook('repo', { face: 'Open' }), 'filled');
  assert.equal(model.replicaButtonHasCaret({ command: '{cd} && claude', claudeInputs: ['!gh pr view {number}'] }), true);
  assert.equal(model.replicaButtonHasCaret({ command: '{cd}', claudeInputs: ['!gh pr view {number}'] }), false);
});

test('only list slots hide buttons whose variables the page cannot supply', () => {
  const unsupported = { uid: 'bad', face: '🤖', command: '{cd} && git checkout {branch}', claudeInputs: [] };
  const supported = { uid: 'good', face: '📂', command: '{cd}', claudeInputs: [] };
  assert.deepEqual(asArray(model.replicaButtonsForSlot('pr-list', [unsupported, supported])), [supported]);
  assert.deepEqual(asArray(model.replicaButtonsForSlot('issue-list', [unsupported, supported])), [supported]);
  for (const kind of ['pr', 'issue', 'repo']) {
    assert.deepEqual(asArray(model.replicaButtonsForSlot(kind, [unsupported, supported])), [unsupported, supported]);
  }
});

test('extension icon preview follows the background page-to-kind rule and uses the first button', () => {
  const buttons = {
    pr: [{ uid: 'pr-first' }, { uid: 'pr-next' }],
    'pr-list': [{ uid: 'pr-list-first' }],
    issue: [{ uid: 'issue-first' }],
    'issue-list': [{ uid: 'issue-list-first' }],
    repo: [{ uid: 'repo-first' }, { uid: 'repo-next' }],
  };
  const snapshot = { buttons };
  assert.equal(model.iconRunKind('pr'), 'pr');
  assert.equal(model.iconRunKind('issue'), 'issue');
  assert.equal(model.iconRunKind('pr-list'), 'repo');
  assert.equal(model.iconRunKind('issue-list'), 'repo');
  assert.equal(model.iconRunKind('repo'), 'repo');
  assert.equal(model.iconButtonForPage('pr', snapshot).uid, 'pr-first');
  assert.equal(model.iconButtonForPage('issue', snapshot).uid, 'issue-first');
  assert.equal(model.iconButtonForPage('pr-list', snapshot).uid, 'repo-first');
  assert.equal(model.iconButtonForPage('issue-list', snapshot).uid, 'repo-first');
  assert.equal(model.iconButtonForPage('repo', snapshot).uid, 'repo-first');
  assert.equal(model.iconButtonForPage('repo', { buttons: { repo: [] } }), null);
});

test('keyboard movement and drag placement produce beforeUid actions without array indexes', () => {
  const buttons = [{ uid: 'a' }, { uid: 'b' }, { uid: 'c' }];
  assert.deepEqual(asArray(model.buttonMoveAction('pr', buttons, 'b', -1)), {
    type: 'button-move', kind: 'pr', uid: 'b', beforeUid: 'a',
  });
  assert.deepEqual(asArray(model.buttonMoveAction('pr', buttons, 'b', 1)), {
    type: 'button-move', kind: 'pr', uid: 'b', beforeUid: null,
  });
  assert.equal(model.buttonMoveAction('pr', buttons, 'a', -1), null);
  assert.equal(model.buttonMoveAction('pr', buttons, 'c', 1), null);
  assert.deepEqual(asArray(model.dropMoveAction('pr', buttons, 'a', 'b', true)), {
    type: 'button-move', kind: 'pr', uid: 'a', beforeUid: 'c',
  });
  assert.deepEqual(asArray(model.dropMoveAction('pr', buttons, 'c', 'a', false)), {
    type: 'button-move', kind: 'pr', uid: 'c', beforeUid: 'a',
  });
  assert.equal(model.dropMoveAction('pr', buttons, 'b', 'b', false), null);
});

test('drawer outside-click classification follows the dispatch path, including a detached old drawer', () => {
  const oldDrawerRoot = { dataset: { replicaDrawerSurface: 'true' }, isConnected: false };
  const replaceButton = { dataset: { action: 'preset-replace-picker' }, isConnected: false };
  const slotAddButton = { dataset: { action: 'slot-add' }, isConnected: true };
  const drawerToggle = { dataset: { action: 'drawer-toggle' }, isConnected: true };
  const outsideButton = { dataset: { action: 'placeholders-toggle' }, isConnected: true };

  assert.equal(model.isOutsideDrawerEventPath([replaceButton, oldDrawerRoot]), false);
  assert.equal(model.isOutsideDrawerEventPath([slotAddButton]), false);
  assert.equal(model.isOutsideDrawerEventPath([drawerToggle]), false);
  assert.equal(model.isOutsideDrawerEventPath([outsideButton, { nodeName: 'BODY' }]), true);
  assert.equal(model.isOutsideDrawerEventPath(null), true);
});

test('extension copy is catalogued in the same contiguous ordered block in all five locales', () => {
  const logicalKeys = asArray(replica.messageKeys);
  assert.ok(logicalKeys.length >= 20);
  const physicalKeys = logicalKeys.map(key => key.replaceAll('.', '_'));
  for (const directory of ['en', 'ko', 'ja', 'zh_CN', 'zh_TW']) {
    const messages = JSON.parse(read(`_locales/${directory}/messages.json`));
    const keys = Object.keys(messages);
    const anchorIndex = keys.indexOf('ext_validate_tooltip');
    assert.ok(anchorIndex >= 0, `${directory} has no locale anchor`);
    assert.deepEqual(keys.slice(anchorIndex + 1, anchorIndex + 1 + physicalKeys.length), physicalKeys, directory);
    for (const key of physicalKeys) {
      assert.ok(messages[key]?.message, `${directory} is missing ${key}`);
    }
  }
  assert.equal(
    JSON.parse(read('_locales/ko/messages.json')).ext_d_replica_exampleBanner.message,
    '설정용 예시 화면(실제 GitHub 아님)',
  );
});

test('replica source uses no storage API and responsive CSS keeps the filmstrip above 900px', () => {
  const css = read('options-replica.css');
  assert.doesNotMatch(source, /chrome\.storage/);
  assert.match(source, /engine\.getSnapshot\(\)/);
  assert.match(source, /engine\.subscribe\(/);
  const editorStart = source.indexOf('function openButtonEditor(button) {');
  const editorEnd = source.indexOf('\nfunction ', editorStart + 1);
  assert.ok(editorStart >= 0 && editorEnd > editorStart, 'the button editor boundary is missing');
  const editorOpener = source.slice(editorStart, editorEnd);
  assert.match(editorOpener, /const options = \{ kind, uid, anchor: button, restoreFocusTo: button \};/);
  assert.match(editorOpener, /mounted\.editor\.open\(options\)/);
  const renderStart = source.indexOf('function renderReplica() {');
  const renderEnd = source.indexOf('\nfunction ', renderStart + 1);
  assert.ok(renderStart >= 0 && renderEnd > renderStart, 'the replica render boundary is missing');
  assert.match(source.slice(renderStart, renderEnd), /dragUid\s*=\s*null/,
    'a redraw no longer invalidates an in-flight drag');
  assert.match(css, /--gh-/);
  assert.match(css, /@media\s*\(max-width:\s*900px\)/);
  assert.match(css, /grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  const mediumStart = css.indexOf('@media (max-width: 900px)');
  const mediumEnd = css.indexOf('@media (max-width: 560px)', mediumStart);
  const mediumLayout = css.slice(mediumStart, mediumEnd);
  assert.match(mediumLayout, /\.replica-filmstrip\s*\{[\s\S]*?order:\s*-1/);
  assert.match(mediumLayout, /\.replica-editbar\s*\{[^}]*grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(css, /\.replica-editbar-controls\s*\{[^}]*flex-wrap:\s*wrap/);
  assert.match(css, /\.replica-control,\s*\.replica-drawer-close\s*\{[^}]*white-space:\s*nowrap/);
  assert.doesNotMatch(css, /word-break:\s*break-all/);
});

test('preset drawer groups all live defaults as localized cards with their real button shape', () => {
  const snapshot = {
    load: { loaded: true },
    buttons: Object.fromEntries(model.replicaKinds().map(({ kind }) => [kind, []])),
  };
  const groups = asArray(model.presetGroups(snapshot));
  const expectedDescriptions = {
    'pr.checkout': 'prCheckout',
    'pr.checkoutClaude': 'prCheckoutClaude',
    'pr.worktreeClaude': 'prWorktreeClaude',
    'pr.worktree': 'prWorktree',
    'pr.review': 'prReview',
    'pr-list.checkoutClaude': 'prListCheckoutClaude',
    'issue.read': 'issueRead',
    'issue.startWork': 'issueStartWork',
    'issue.open': 'issueOpen',
    'issue-list.triageClaude': 'issueListTriageClaude',
    'repo.open': 'repoOpen',
    'repo.openClaude': 'repoOpenClaude',
    'repo.updateMain': 'repoUpdateMain',
  };
  assert.deepEqual(groups.map(group => group.kind), ['pr', 'pr-list', 'issue', 'issue-list', 'repo']);
  assert.deepEqual(groups.map(group => group.cards.length), [5, 1, 3, 1, 3]);
  const cards = groups.flatMap(group => group.cards);
  const defaults = Object.values(buttonKinds).flatMap(kind => kind.presets);
  assert.equal(cards.length, 13);
  assert.deepEqual(cards.map(card => card.presetId), defaults.map(preset => preset.id));
  assert.deepEqual(cards.map(card => card.name), defaults.map(preset => preset.name));
  assert.deepEqual(cards.map(card => card.face), defaults.map(preset => preset.face));
  assert.deepEqual(cards.map(card => card.hasCaret), groups.flatMap(group =>
    buttonKinds[group.kind].presets.map(preset => model.replicaButtonHasCaret(preset)),
  ));
  assert.deepEqual(cards.map(card => card.look), groups.flatMap(group =>
    buttonKinds[group.kind].presets.map(preset => model.replicaButtonLook(group.kind, preset)),
  ));
  assert.deepEqual(
    Object.fromEntries(cards.map(card => [card.presetId, card.description])),
    Object.fromEntries(Object.entries(expectedDescriptions).map(([id, suffix]) => [
      id,
      `ext.d.replica.presetDescription.${suffix}`,
    ])),
  );
  assert.ok(cards.every(card => !card.inUse));
});

test('preset usage follows the snapshot presetId and does not guess a customized command family', () => {
  const presetId = buttonKinds.pr.presets[2].id;
  const snapshot = {
    buttons: {
      pr: [
        { uid: 'same-command', presetId, customCommand: false },
        { uid: 'edited-family', presetId: null, customCommand: true },
      ],
    },
  };
  assert.equal(model.presetInUse('pr', presetId, snapshot), true);
  assert.equal(model.presetInUse('pr', 'pr.checkout', snapshot), false);
  assert.equal(model.presetInUse('issue', presetId, snapshot), false);
  assert.equal(model.presetInUse('missing-kind', presetId, snapshot), false);
});

test('preset add availability and actions use the live cap and beforeUid contract', () => {
  const buttons = count => Array.from({ length: count }, (_, index) => ({ uid: `button-${index}` }));
  const snapshot = count => ({ load: { loaded: true }, buttons: { pr: buttons(count) } });
  assert.equal(model.presetAddAvailability('pr', snapshot(4)), 'available');
  assert.equal(model.presetAddAvailability('pr', snapshot(5)), 'limit');
  assert.equal(model.presetAddAvailability('pr', { load: { loaded: false }, buttons: { pr: [] } }), 'not-loaded');
  assert.equal(model.presetAddAvailability('unknown', snapshot(0)), 'invalid');
  assert.deepEqual(asArray(model.presetAddAction('pr', 'pr.checkout', null)), {
    type: 'preset-add', kind: 'pr', presetId: 'pr.checkout', beforeUid: null,
  });
  assert.deepEqual(asArray(model.presetAddAction('pr', 'pr.checkout', 'button-2')), {
    type: 'preset-add', kind: 'pr', presetId: 'pr.checkout', beforeUid: 'button-2',
  });
  assert.equal(model.presetAddAction('pr', 'repo.open', null), null);
  assert.equal(model.presetAddAction('unknown', 'pr.checkout', null), null);
});

test('preset drops choose the insertion slot and spotlight the matching page card', () => {
  const buttons = [{ uid: 'first' }, { uid: 'second' }];
  const rects = [
    { uid: 'first', left: 10, width: 20 },
    { uid: 'second', left: 40, width: 20 },
  ];
  assert.equal(model.presetInsertionBeforeUid('pr', buttons, rects, 19), 'first');
  assert.equal(model.presetInsertionBeforeUid('pr', buttons, rects, 35), 'second');
  assert.equal(model.presetInsertionBeforeUid('pr', buttons, rects, 70), null);
  assert.equal(model.presetInsertionBeforeUid('unknown', buttons, rects, 19), null);
  const wrappedButtons = [{ uid: 'row-one-a' }, { uid: 'row-one-b' }, { uid: 'row-two-a' }];
  const wrappedRects = [
    { uid: 'row-one-a', left: 0, width: 20, top: 0, height: 20 },
    { uid: 'row-one-b', left: 25, width: 20, top: 0, height: 20 },
    { uid: 'row-two-a', left: 0, width: 20, top: 30, height: 20 },
  ];
  assert.equal(model.presetInsertionBeforeUid('pr', wrappedButtons, wrappedRects, 5, 35), 'row-two-a');
  assert.equal(model.presetInsertionBeforeUid('pr', wrappedButtons, wrappedRects, 5, 25), 'row-two-a');
  assert.equal(model.presetInsertionBeforeUid('pr', wrappedButtons, wrappedRects, 30, 35), null);
  assert.deepEqual(asArray(model.presetHighlightTarget('issue-list')), {
    pageKind: 'issue-list', pageCardKind: 'issue-list', slotKind: 'issue-list',
  });
  assert.equal(model.presetHighlightTarget('unknown'), null);
  assert.deepEqual(asArray(model.presetAddAction(
    'pr', 'pr.worktree', model.presetInsertionBeforeUid('pr', buttons, rects, 35),
  )), {
    type: 'preset-add', kind: 'pr', presetId: 'pr.worktree', beforeUid: 'second',
  });
});

test('preset replacement sends confirmation only after the view receives needs-confirmation', () => {
  assert.deepEqual(asArray(model.presetReplaceAction('pr', 'custom-uid', 'pr.checkout')), {
    type: 'preset-replace', kind: 'pr', uid: 'custom-uid', presetId: 'pr.checkout',
  });
  assert.deepEqual(asArray(model.presetReplaceAction('pr', 'custom-uid', 'pr.checkout', true)), {
    type: 'preset-replace', kind: 'pr', uid: 'custom-uid', presetId: 'pr.checkout', confirmed: true,
  });
  assert.equal(model.presetReplaceAction('unknown', 'custom-uid', 'pr.checkout'), null);
});

test('narrow GitHub placements wrap below branch labels', () => {
  const css = read('options-replica.css');
  const narrowStart = css.indexOf('@media (max-width: 900px)');
  const narrowEnd = css.indexOf('@media (max-width: 560px)', narrowStart);
  const narrow = css.slice(narrowStart, narrowEnd);
  assert.equal(/\.options-replica\s*\{[^}]*word-break:\s*keep-all/.test(css), false);
  assert.match(narrow, /\.gh-branch-line\s*\{[^}]*flex-wrap:\s*wrap/);
  assert.match(narrow, /\.gh-branch\s*\{[^}]*overflow:\s*visible;[^}]*text-overflow:\s*clip;[^}]*white-space:\s*normal/);
  assert.match(narrow, /\.gh-branch-line\s*>\s*\.replica-slot\s*\{[^}]*flex:\s*0\s+0\s+100%/);
  assert.match(narrow, /\.gh-status-line\s*>\s*\.replica-slot\s*\{[^}]*flex:\s*0\s+0\s+100%/);
  assert.match(narrow, /\.gh-list-tools\s*\{[^}]*flex-direction:\s*column/);
  assert.match(narrow, /\.gh-list-tools\s*>\s*\.replica-slot\s*\{[^}]*width:\s*calc\(100%\s*-\s*18px\)/);
  assert.match(narrow, /\.gh-issue-list-heading\s*>\s*\.replica-slot\s*\{[^}]*flex:\s*0\s+0\s+100%/);
  assert.match(narrow, /\.gh-repo-header\s*>\s*\.replica-slot\s*\{[^}]*flex:\s*0\s+0\s+100%/);
  assert.match(narrow, /\.gh-repo-header\s*\{[^}]*flex-wrap:\s*wrap/);
});
