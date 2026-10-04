// Replica model and source contracts, without a DOM implementation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');
const source = read('options-replica.js');
const shellSource = read('options-shell.js');
const editorSource = read('options-editor.js');
const engineSource = read('options.js');
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
  assert.equal(replica.describePlace('pr'), 'ext.d.replica.place.pr');
  assert.equal(replica.describePlace('issue-list'), 'ext.d.replica.place.issueList');
  assert.equal(replica.describePreset('pr.checkout'), 'ext.d.replica.presetDescription.prCheckout');
  assert.equal(replica.describePreset('missing.preset'), '');
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

test('only the trusted drag-generated click for the moved button is suppressed', () => {
  assert.equal(typeof model.shouldSuppressReplicaDragClick, 'function');
  assert.equal(model.shouldSuppressReplicaDragClick('moved', 'moved', { isTrusted: true, detail: 1 }), true);
  assert.equal(model.shouldSuppressReplicaDragClick('moved', 'moved', { isTrusted: false, detail: 0 }), false);
  assert.equal(model.shouldSuppressReplicaDragClick('moved', 'moved', { isTrusted: true, detail: 0 }), false);
  assert.equal(model.shouldSuppressReplicaDragClick('moved', 'other', { isTrusted: true, detail: 1 }), false);
  assert.equal(model.shouldSuppressReplicaDragClick(null, 'moved', { isTrusted: true, detail: 1 }), false);
  assert.equal(/(?:document|root\.ownerDocument)\.addEventListener\('pointerdown', handleReplicaPointerDown, true\)/.test(source), true,
    'a new pointer interaction clears a pending drag click when the drag made no click');
});

test('page selection closes both transient surfaces before changing page and restores focus to the selected card', () => {
  const selectStart = source.indexOf('function selectReplicaPage(kind) {');
  const selectEnd = source.indexOf('\nfunction ', selectStart + 1);
  assert.ok(selectStart >= 0 && selectEnd > selectStart, 'page changes need one shared transition');
  const selection = source.slice(selectStart, selectEnd);
  assert.match(selection, /mounted\.editor\.isOpen\(\)[\s\S]*?mounted\.editor\.close\(\)/);
  assert.match(selection, /mounted\.drawerOpen[\s\S]*?setDrawerVisible\(false\)/);
  assert.ok(selection.indexOf('mounted.editor.close()') < selection.indexOf('mounted.pageKind = kind'),
    'the editor must still have its connected old anchor when it restores focus');
  assert.ok(selection.indexOf('setDrawerVisible(false)') < selection.indexOf('mounted.pageKind = kind'),
    'closing the drawer must not restore its old opener over the new page');
  const clickStart = source.indexOf('function handleReplicaClick(event) {');
  const clickEnd = source.indexOf('\nfunction ', clickStart + 1);
  const clickHandler = source.slice(clickStart, clickEnd);
  assert.match(clickHandler, /selectReplicaPage\(pageCard\.dataset\.pageKind\)[\s\S]*?renderReplica\(\)[\s\S]*?selected\?\.focus\(\)/);
  const focusStart = source.indexOf('function focusReplicaButton(kind, uid) {');
  const focusEnd = source.indexOf('\nfunction ', focusStart + 1);
  assert.match(source.slice(focusStart, focusEnd), /selectReplicaPage\(kind\)/,
    'programmatic page changes must close a popover too');
});

test('a full redraw and the preset preview draw the shown page through one function', () => {
  const body = name => {
    const start = source.indexOf(`function ${name}(`);
    const end = source.indexOf('\nfunction ', start + 1);
    assert.ok(start >= 0 && end > start, `${name} is missing`);
    return source.slice(start, end);
  };
  const shown = body('syncShownPage');
  for (const part of [
    /routeAddress\(pageKind\)/,
    /renderIconPreview\(pageKind, snapshot\)/,
    /renderGitHubPage\(pageKind, snapshot, /,
    /'aria-current'/,
    /'is-preset-target'/,
    /'is-preview'/,
  ]) assert.match(shown, part);
  const pageDependent = /routeAddress\(|iconKindAndButton\(|renderIconPreview\(|renderGitHubPage\(|aria-current|is-preset-target|is-preview/;
  for (const name of ['renderReplica', 'updatePresetPreview']) {
    const path = body(name);
    assert.match(path, /syncShownPage\(\);/, `${name} must draw the shown page through syncShownPage`);
    assert.doesNotMatch(path, pageDependent, `${name} must not draw a part of the shown page on its own`);
  }
  for (const name of ['renderFilmstripCard', 'renderPresetCard']) {
    assert.doesNotMatch(body(name), /aria-current|is-preset-target|is-preview|previewPreset|mounted\.pageKind/,
      `${name} must leave the marks that follow the shown page to syncShownPage`);
  }
});

test('a slot\'s + opens the add picker beside it, not the preset drawer', () => {
  const click = source.slice(source.indexOf('function handleReplicaClick(event) {'), source.indexOf('\n/** @param {KeyboardEvent} event */\nfunction handleReplicaKeydown('));
  const slotAdd = click.slice(click.indexOf("action === 'slot-add'"));
  assert.match(slotAdd, /mounted\.editor\.openAdd\(\{ kind, anchor: actionTarget, restoreFocusTo: actionTarget \}\)/);
  assert.doesNotMatch(slotAdd.slice(0, slotAdd.indexOf('} else if')), /openDrawerInternal\(/);
  const slot = source.slice(source.indexOf('function renderSlot('), source.indexOf('\nfunction ', source.indexOf('function renderSlot(') + 1));
  assert.match(slot, /class="replica-slot-add"[^`]*aria-haspopup="dialog"/);
  assert.doesNotMatch(slot, /aria-controls="replica-drawer"/);
  const visible = source.slice(source.indexOf('function setDrawerVisible('), source.indexOf('\nfunction ', source.indexOf('function setDrawerVisible(') + 1));
  assert.doesNotMatch(visible, /slot-add/, 'the drawer no longer belongs to the + controls');
});

test('the drawer adds and drags presets; replacing a button happens in that button\'s editor', () => {
  const card = source.slice(source.indexOf('function renderPresetCard('), source.indexOf('\nfunction ', source.indexOf('function renderPresetCard(') + 1));
  assert.match(card, /data-action="preset-add"/);
  assert.doesNotMatch(card, /preset-replace/);
  for (const gone of ['replacePicker', 'pendingReplace', 'renderPresetReplaceTargets', 'preset-replace-confirm', 'function replacePreset(']) {
    assert.equal(source.includes(gone), false, `${gone} belonged to the drawer's own replace flow`);
  }
  const drop = source.slice(source.indexOf('function handleReplicaDrop(event) {'), source.indexOf('\nfunction ', source.indexOf('function handleReplicaDrop(event) {') + 1));
  assert.match(drop, /if \(isPreset && target\.hasAttribute\('data-replica-button'\)\) \{[\s\S]*?openButtonEditor\(target, source\.presetId\);/);
  const opener = source.slice(source.indexOf('function openButtonEditor('), source.indexOf('\nfunction ', source.indexOf('function openButtonEditor(') + 1));
  assert.match(opener, /presetId/);
  assert.match(opener, /mounted\.editor\.open\(options\)/);
});

test('a preset added from the drawer opens the new button\'s editor', () => {
  const add = source.slice(source.indexOf('async function addPreset('), source.indexOf('\nfunction ', source.indexOf('async function addPreset(') + 1));
  assert.match(add, /if \(result\?\.ok\) \{[\s\S]*?renderReplica\(\);[\s\S]*?openCreatedButtonEditor\(kind, result\.createdUid\)/);
});

test('replica event blocking recognizes an inert surface or inert event-path ancestor', () => {
  assert.equal(typeof model.isReplicaEventBlocked, 'function');
  assert.equal(model.isReplicaEventBlocked([], false), false);
  assert.equal(model.isReplicaEventBlocked([], true), true);
  assert.equal(model.isReplicaEventBlocked([{ inert: true }], false), true);
  assert.equal(model.isReplicaEventBlocked([{ hasAttribute: name => name === 'inert' }], false), true);
  assert.equal(model.isReplicaEventBlocked([{ inert: false }], false), false);
});

test('all replica document and surface interaction listeners ignore events while blocked', () => {
  for (const [name, event] of [
    ['handleReplicaPointerDown', 'PointerEvent'],
    ['handleReplicaClick', 'MouseEvent'],
    ['handleReplicaKeydown', 'KeyboardEvent'],
    ['handleReplicaMouseOver', 'MouseEvent'],
    ['handleReplicaMouseOut', 'MouseEvent'],
    ['handleReplicaFocusIn', 'FocusEvent'],
    ['handleReplicaFocusOut', 'FocusEvent'],
    ['handleReplicaDragStart', 'DragEvent'],
    ['handleReplicaDragOver', 'DragEvent'],
    ['handleReplicaDrop', 'DragEvent'],
    ['handleDocumentClick', 'MouseEvent'],
    ['handleDocumentKeydown', 'KeyboardEvent'],
  ]) {
    const start = source.indexOf(`function ${name}(`);
    const end = source.indexOf('\nfunction ', start + 1);
    assert.ok(start >= 0 && end > start, `${name} listener is missing`);
    const handler = source.slice(start, end);
    assert.match(handler, new RegExp(`replicaInteractionIsBlocked\\(event\\)`), `${name} (${event})`);
  }
  assert.doesNotMatch(source, /window\.addEventListener\(/,
    'the replica must not install an unguarded window listener');
  const documentRegistrations = [...source.matchAll(/root\.ownerDocument\.addEventListener\('([^']+)',\s*(\w+)(?:,\s*(true))?\)/g)]
    .map(([, event, handler, capture]) => [event, handler, capture === 'true']);
  assert.deepEqual(documentRegistrations, [
    ['pointerdown', 'handleReplicaPointerDown', true],
    ['click', 'handleDocumentClick', false],
    ['keydown', 'handleDocumentKeydown', false],
  ]);
  const mountStart = source.indexOf('function mountReplica(root, engine, editor) {');
  const mountEnd = source.indexOf('\nfunction ', mountStart + 1);
  const mount = source.slice(mountStart, mountEnd);
  for (const [event, handler, capture] of documentRegistrations) {
    const captureOption = capture ? ', true' : '';
    assert.ok(mount.includes(`ownerDocument.removeEventListener('${event}', ${handler}${captureOption})`),
      `${event} listener must be removed when its root is replaced`);
  }
});

test('GitHub copy and fixed example scenery declare English without labeling user button text', () => {
  assert.equal(/function gh\(key\) \{\s*return `<span[^>]*lang="en"/.test(source), true);
  assert.equal(/function ghScenery\(value\) \{\s*return `<span[^>]*lang="en"/.test(source), true);
  const pageStart = source.indexOf('function renderGitHubPage(kind, snapshot, showPlaceholders) {');
  const pageEnd = source.indexOf('\nfunction ', pageStart + 1);
  assert.ok(pageStart >= 0 && pageEnd > pageStart);
  const renderer = source.slice(pageStart, pageEnd);
  assert.equal(/replicaEscape\(context\.(?:owner|repo|pullRequest\.(?:title|base|branch)|issue\.title)\)/.test(renderer), false,
    'fixed textual scenery is marked English through its helper');
  assert.equal(/ghScenery\(context\.pullRequest\.title\)/.test(renderer), true);
  assert.equal(/ghScenery\(context\.issue\.title\)/.test(renderer), true);
  assert.equal(/ghScenery\(context\.owner\)/.test(renderer), true);
  assert.equal(/ghScenery\(context\.repo\)/.test(renderer), true);
  const buttonStart = source.indexOf('function renderEditButton(kind, button, loaded, describedBy = \'\') {');
  const buttonEnd = source.indexOf('\nfunction ', buttonStart + 1);
  assert.ok(buttonStart >= 0 && buttonEnd > buttonStart);
  assert.equal(/lang="en"/.test(source.slice(buttonStart, buttonEnd)), false,
    'user supplied button faces and labels inherit no forced language');
});

test('list buttons unavailable on GitHub remain editable and explain the unavailable variable', () => {
  const unsupported = { uid: 'bad', face: '🤖', command: '{cd} && git checkout {branch}', claudeInputs: [] };
  const supported = { uid: 'good', face: '📂', command: '{cd}', claudeInputs: [] };
  const unsupportedInput = { uid: 'bad-input', face: '📝', command: '{cd}', claudeInputs: ['!gh pr view {branch}'] };
  assert.deepEqual(asArray(model.replicaButtonsForSlot('pr-list', [unsupported, supported])), [unsupported, supported]);
  assert.deepEqual(asArray(model.replicaButtonsForSlot('issue-list', [unsupported, supported])), [unsupported, supported]);
  assert.deepEqual(asArray(model.replicaButtonPageStatus('pr-list', unsupported)), {
    hiddenOnGitHub: true,
    unavailableVariables: ['branch'],
  });
  assert.deepEqual(asArray(model.replicaButtonPageStatus('issue-list', supported)), {
    hiddenOnGitHub: false,
    unavailableVariables: [],
  });
  assert.deepEqual(asArray(model.replicaButtonPageStatus('pr-list', unsupportedInput)), {
    hiddenOnGitHub: true,
    unavailableVariables: ['branch'],
  });
  for (const kind of ['pr', 'issue', 'repo']) {
    assert.deepEqual(asArray(model.replicaButtonsForSlot(kind, [unsupported, supported])), [unsupported, supported]);
    assert.equal(model.replicaButtonPageStatus(kind, unsupported).hiddenOnGitHub, false);
  }
  const slotStart = source.indexOf('function renderSlot(kind, snapshot, showPlaceholders) {');
  const slotEnd = source.indexOf('\nfunction ', slotStart + 1);
  assert.ok(slotStart >= 0 && slotEnd > slotStart);
  const slotRenderer = source.slice(slotStart, slotEnd);
  assert.match(slotRenderer, /buttons\.map\(button => renderReplicaEditEntry\(kind, button/);
  assert.match(slotRenderer, /\$\{all\.length\}\/\$\{MAX_BUTTONS\}/);
  assert.match(source, /class="replica-button-hidden-note"/);
  assert.match(source, /replicaButtonsShownOnGitHub\(kind, buttons\)\[0\]/);
});

test('extension icon preview follows its routed kind instead of a hidden list button', () => {
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
  const unavailableListButton = { uid: 'hidden-list', command: '{cd} {branch}', claudeInputs: [] };
  assert.equal(model.iconButtonForPage('pr-list', {
    buttons: { 'pr-list': [unavailableListButton], repo: [{ uid: 'icon-runnable' }] },
  }).uid, 'icon-runnable');
});

test('transient option surfaces clear state and redraw or hide the matching view', () => {
  const shellCloseStart = shellSource.indexOf('function closeConfirmation(restoreFocus = true) {');
  const shellCloseEnd = shellSource.indexOf('\n    function ', shellCloseStart + 1);
  assert.ok(shellCloseStart >= 0 && shellCloseEnd > shellCloseStart);
  assert.match(shellSource.slice(shellCloseStart, shellCloseEnd), /pendingConfirmation = null;[\s\S]*confirmation\.hidden = true;/);
  const editorCloseStart = editorSource.indexOf('function closePopover({ restoreFocus = true } = {}) {');
  const editorCloseEnd = editorSource.indexOf('\nfunction ', editorCloseStart + 1);
  assert.ok(editorCloseStart >= 0 && editorCloseEnd > editorCloseStart);
  assert.match(editorSource.slice(editorCloseStart, editorCloseEnd), /active = null;[\s\S]*pendingPresetId = null;[\s\S]*root\?\.replaceChildren\(\);/);
});

test('every option keydown handler lets IME composition keys pass through', () => {
  const handlers = [
    {
      name: 'shell confirmation Escape',
      source: shellSource,
      pattern: /document\.addEventListener\('keydown', event => \{\s*if \(event\.isComposing \|\| event\.keyCode === 229\) return;/,
    },
    {
      name: 'editor Escape and input-row arrows',
      source: editorSource,
      pattern: /function handleKeydown\(event\) \{\s*if \(!active \|\| isImeCompositionKeyEvent\(event\)\) return;/,
    },
    {
      name: 'replica button reorder arrows',
      source,
      pattern: /function handleReplicaKeydown\(event\) \{\s*if \(event\.isComposing \|\| event\.keyCode === 229\) return;/,
    },
    {
      name: 'drawer Escape',
      source,
      pattern: /function handleDocumentKeydown\(event\) \{\s*if \(event\.isComposing \|\| event\.keyCode === 229\) return;/,
    },
  ];
  for (const handler of handlers) assert.match(handler.source, handler.pattern, handler.name);
  assert.match(editorSource, /function isImeCompositionKeyEvent\(event\) \{\s*return event\?\.isComposing === true \|\| event\?\.keyCode === 229;/);
  assert.doesNotMatch(engineSource, /keydown/, 'the engine must not own keyboard shortcuts');
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
  const detachedAddButton = { dataset: { action: 'preset-add' }, isConnected: false };
  const slotAddButton = { dataset: { action: 'slot-add' }, isConnected: true };
  const drawerToggle = { dataset: { action: 'drawer-toggle' }, isConnected: true };
  const outsideButton = { dataset: { action: 'placeholders-toggle' }, isConnected: true };

  assert.equal(model.isOutsideDrawerEventPath([detachedAddButton, oldDrawerRoot]), false);
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
  const editorStart = source.indexOf('function openButtonEditor(button, presetId = null) {');
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
    'issue.open': 'open',
    'issue-list.triageClaude': 'issueListTriageClaude',
    'repo.open': 'open',
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
