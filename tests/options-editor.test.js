// Public contract and DOM-free model checks for the options popover editor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');
const source = read('options-editor.js');

function loadEditor() {
  const context = vm.createContext({ window: {}, tr: (key, ...args) => `${key}:${args.join('|')}` });
  vm.runInContext(read('defaults.js'), context);
  vm.runInContext(read('options-replica.js'), context);
  vm.runInContext(source, context);
  const model = vm.runInContext(`({
    calculatePopoverPosition: typeof calculatePopoverPosition === 'function' ? calculatePopoverPosition : null,
    presetConfirmationNeedsRender: typeof presetConfirmationNeedsRender === 'function' ? presetConfirmationNeedsRender : null,
    findReplicaAnchor: typeof findReplicaAnchor === 'function' ? findReplicaAnchor : null,
    isImeCompositionKeyEvent: typeof isImeCompositionKeyEvent === 'function' ? isImeCompositionKeyEvent : null,
    hasMeasurableViewport: typeof hasMeasurableViewport === 'function' ? hasMeasurableViewport : null,
    fitsFieldLimit: typeof fitsFieldLimit === 'function' ? fitsFieldLimit : null,
    appendFaceCharacter: typeof appendFaceCharacter === 'function' ? appendFaceCharacter : null,
    variablesForKind: typeof variablesForKind === 'function' ? variablesForKind : null,
    validationFor: typeof validationFor === 'function' ? validationFor : null,
    classifyClaudeInput: typeof classifyClaudeInput === 'function' ? classifyClaudeInput : null,
    exampleValuesForKind: typeof exampleValuesForKind === 'function' ? exampleValuesForKind : null,
    expandExampleTemplate: typeof expandExampleTemplate === 'function' ? expandExampleTemplate : null,
    splitCommandSteps: typeof splitCommandSteps === 'function' ? splitCommandSteps : null,
    inputMoveAction: typeof inputMoveAction === 'function' ? inputMoveAction : null,
    inputMoveTargetIndex: typeof inputMoveTargetIndex === 'function' ? inputMoveTargetIndex : null,
    canAddClaudeInput: typeof canAddClaudeInput === 'function' ? canAddClaudeInput : null,
    maxClaudeInputs: MAX_CLAUDE_INPUTS,
    faceMaxLength: FACE_MAX_LENGTH,
    requiresPresetConfirmation: typeof requiresPresetConfirmation === 'function' ? requiresPresetConfirmation : null,
    buttonMoveAction: typeof buttonMoveAction === 'function' ? buttonMoveAction : null,
    presetReplaceAction: typeof presetReplaceAction === 'function' ? presetReplaceAction : null,
    eventPathIncludesEditor: typeof eventPathIncludesEditor === 'function' ? eventPathIncludesEditor : null,
    editorSurfaceIsBlocked: typeof editorSurfaceIsBlocked === 'function' ? editorSurfaceIsBlocked : null,
    eventBelongsToEditorOrAnchor: typeof eventBelongsToEditorOrAnchor === 'function' ? eventBelongsToEditorOrAnchor : null,
    addChoiceAction: typeof addChoiceAction === 'function' ? addChoiceAction : null,
    findAddAnchor: typeof findAddAnchor === 'function' ? findAddAnchor : null,
  })`, context);
  return { context, model, api: context.window.optionsEditor };
}

const functionBody = name => {
  const start = source.search(new RegExp(`\\n(?:async )?function ${name}\\(`));
  const end = source.slice(start + 1).search(/\n(?:async )?function |\n\/\*\* @type \{OptionsEditor\} \*\//);
  assert.ok(start >= 0 && end > 0, `${name} is missing`);
  return source.slice(start, start + 1 + end);
};

test('editor publishes mount, open, openAdd, close, and isOpen contracts', () => {
  const { api } = loadEditor();
  assert.deepEqual(Object.keys(api), ['mount', 'open', 'openAdd', 'close', 'isOpen']);
  assert.equal(api.mount.length, 2);
  assert.equal(api.open.length, 1);
  assert.equal(api.openAdd.length, 1);
  assert.equal(api.close.length, 0);
  assert.equal(api.isOpen.length, 0);
});

test('a choice in the add picker is a blank button or this kind\'s preset, added last', () => {
  const { model } = loadEditor();
  const plain = value => JSON.parse(JSON.stringify(value));
  assert.equal(typeof model.addChoiceAction, 'function');
  assert.deepEqual(plain(model.addChoiceAction('pr', null)), { type: 'button-add', kind: 'pr' });
  assert.deepEqual(plain(model.addChoiceAction('pr', 'pr.worktree')),
    { type: 'preset-add', kind: 'pr', presetId: 'pr.worktree', beforeUid: null });
  assert.equal(model.addChoiceAction('pr', 'issue.open'), null, 'another kind\'s preset cannot go in this slot');
  assert.equal(model.addChoiceAction('unknown', null), null);
});

test('the add picker anchors to its slot\'s + control, found again after every redraw', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.findAddAnchor, 'function');
  const plus = kind => ({ dataset: { action: 'slot-add', slotKind: kind } });
  const root = { querySelectorAll: selector => (selector.includes('slot-add') ? [plus('repo'), plus('pr')] : []) };
  assert.equal(model.findAddAnchor(root, 'pr').dataset.slotKind, 'pr');
  assert.equal(model.findAddAnchor(root, 'issue'), null);
  assert.equal(model.findAddAnchor(null, 'pr'), null);
  for (const name of ['positionPopover', 'handleKeydown']) {
    assert.match(functionBody(name), /activeAnchor\(\)/, `${name} must resolve the anchor of either mode`);
  }
  assert.match(functionBody('activeAnchor'), /findAddAnchor\([\s\S]*findReplicaAnchor\(/);
});

test('choosing in the add picker adds the button, then opens that button\'s editor', () => {
  const choose = functionBody('addFromChoice');
  assert.match(choose, /const action = addChoiceAction\(kind, presetId\);[\s\S]*?dispatchAction\(action\)/);
  assert.match(choose, /focusReplicaTarget\(kind, result\.createdUid\)/);
  assert.match(choose, /window\.optionsEditor\.open\(\{ kind, uid: result\.createdUid, anchor: target, restoreFocusTo: target \}\)/);
  assert.match(functionBody('acceptSnapshot'), /active\.mode === 'add'/,
    'a snapshot must not close the add picker for lacking a current button');
});

test('a whole-button preset replacement rewrites every field, the focused one included', () => {
  assert.match(functionBody('updatePanel'), /syncFieldValues\(button\);/);
  assert.match(functionBody('syncFieldValues'), /force \|\| document\.activeElement !== field/);
  assert.match(functionBody('replaceWithPreset'),
    /if \(result\?\.ok\) \{[\s\S]*?syncFieldValues\(currentButton\(\), \{ force: true \}\)/,
    'a dropped preset replaces the button while buildPopover has focused the face field');
});

test('open can start replacing the button with a preset dropped on it', () => {
  const choose = functionBody('choosePreset');
  assert.match(choose, /requiresPresetConfirmation\(currentButton\(\)\)[\s\S]*replaceWithPreset\(presetId\)/);
  assert.match(source, /case 'choose-preset':\s*choosePreset\(target\.dataset\.presetId\);/);
  assert.match(source, /if \(typeof options\.presetId === 'string'\) choosePreset\(options\.presetId\);/);
});

test('editor open contract keeps the placement anchor separate from focus restoration', () => {
  assert.match(source, /@typedef \{\{kind: OptionsButtonKind, uid: string, anchor: HTMLElement, restoreFocusTo: HTMLElement, presetId\?: string\}\} OptionsEditorOpenOptions/);
  assert.match(source, /@param \{OptionsEditorOpenOptions\} options/);
});

test('outside pointer classification follows the event path after the original target detaches', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.eventPathIncludesEditor, 'function');
  const marker = { dataset: { optionsEditorSurface: 'popover' } };
  const detachedControl = { isConnected: false };
  assert.equal(model.eventPathIncludesEditor({ composedPath: () => [detachedControl, marker] }), true);
  assert.equal(model.eventPathIncludesEditor({ composedPath: () => [detachedControl, { dataset: {} }] }), false);
  assert.ok(/panel\.dataset\.optionsEditorSurface = 'popover'/.test(source), 'popover path marker is missing');
  assert.ok(/if \(!active \|\| editorSurfaceIsBlocked\(root\) \|\| eventPathIncludesEditor\(event\)\) return;/.test(source),
    'outside pointer handling needs the inert guard and captured event path');
});

test('an inert ancestor blocks the editor surface', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.editorSurfaceIsBlocked, 'function');
  const blockedParent = { inert: true, parentElement: null };
  const editorRoot = { inert: false, parentElement: blockedParent };
  const unblockedRoot = { inert: false, parentElement: { inert: false, parentElement: null } };
  assert.equal(model.editorSurfaceIsBlocked(editorRoot), true);
  assert.equal(model.editorSurfaceIsBlocked(unblockedRoot), false);
  assert.equal(model.editorSurfaceIsBlocked(null), false);
});

test('Escape belongs only to the editor or its active button anchor', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.eventBelongsToEditorOrAnchor, 'function');
  const editorMarker = { dataset: { optionsEditorSurface: 'popover' } };
  const editorControl = {};
  const anchorControl = {};
  const otherControl = {};
  const panel = { contains: node => node === editorControl };
  const anchor = { contains: node => node === anchorControl };
  assert.equal(model.eventBelongsToEditorOrAnchor(
    { composedPath: () => [editorControl, editorMarker] }, panel, anchor, otherControl,
  ), true);
  assert.equal(model.eventBelongsToEditorOrAnchor(
    { composedPath: () => [anchorControl, anchor] }, panel, anchor, otherControl,
  ), true);
  assert.equal(model.eventBelongsToEditorOrAnchor(
    { composedPath: () => [otherControl] }, panel, anchor, editorControl,
  ), true);
  assert.equal(model.eventBelongsToEditorOrAnchor(
    { composedPath: () => [otherControl] }, panel, anchor, anchorControl,
  ), true);
  assert.equal(model.eventBelongsToEditorOrAnchor(
    { composedPath: () => [otherControl] }, panel, anchor, otherControl,
  ), false);
});

test('document key and pointer listeners leave a blocked editor alone', () => {
  const keydown = source.slice(source.indexOf('function handleDocumentKeydown'), source.indexOf('function handlePointerDown'));
  const editorKeydown = source.slice(source.indexOf('function handleKeydown'), source.indexOf('function handleDocumentKeydown'));
  const pointerdown = source.slice(source.indexOf('function handlePointerDown'), source.indexOf('function handleWindowChange'));
  const mouseup = source.slice(source.indexOf('function handleInputMouseUp'), source.indexOf('function editorMessage'));
  const windowChange = source.slice(source.indexOf('function handleWindowChange'), source.indexOf('function handleMouseDown'));
  assert.match(keydown, /function handleDocumentKeydown\(event\) \{\s*if \(editorSurfaceIsBlocked\(root\)\) return;\s*handleKeydown\(event\);/,
    'a blocked editor must not call its key handler');
  assert.match(source, /document\.addEventListener\('keydown', handleDocumentKeydown, true\)/,
    'the document capture listener must use the inert gate');
  assert.match(editorKeydown, /eventBelongsToEditorOrAnchor\(event, currentPanel\(\), anchor, document\.activeElement\)/,
    'Escape must be scoped to the editor or its current anchor');
  assert.match(pointerdown, /if \(!active \|\| editorSurfaceIsBlocked\(root\) \|\| eventPathIncludesEditor\(event\)\) return;/,
    'a blocked editor must not close in response to background pointer events');
  assert.match(mouseup, /if \(editorSurfaceIsBlocked\(root\)\) return;/,
    'the temporary document mouseup listener must not handle a blocked editor surface');
  const escape = editorKeydown.slice(editorKeydown.indexOf("if (event.key === 'Escape')"));
  assert.match(escape, /if \(!eventBelongsToEditorOrAnchor\(event, currentPanel\(\), anchor, document\.activeElement\)\) return;[\s\S]*event\.preventDefault\(\);[\s\S]*event\.stopPropagation\(\);/,
    'Escape cancellation must follow the editor-or-anchor ownership check');
  assert.doesNotMatch(pointerdown, /preventDefault\(\)|stopPropagation\(\)/,
    'outside-pointer detection must not cancel or stop the pointer event');
  assert.doesNotMatch(mouseup, /preventDefault\(\)|stopPropagation\(\)/,
    'the one-shot drag cleanup must not cancel or stop mouseup');
  assert.match(windowChange, /schedulePopoverPosition\(\);/);
  assert.doesNotMatch(windowChange, /preventDefault\(\)|stopPropagation\(\)/,
    'viewport changes must not cancel or stop unrelated events');
});

test('external snapshot close only restores focus when the focus owner was inside the popover', () => {
  assert.ok(/if \(!currentButton\(\)\) \{\s*const restoreFocus = currentPanel\(\)\?\.contains\(document\.activeElement\) \?\? false;\s*closePopover\(\{ restoreFocus \}\);/.test(source),
    'external close does not preserve focus ownership');
});

test('preset confirmation rendering recognizes unchanged confirmation content', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.presetConfirmationNeedsRender, 'function');
  const existing = { dataset: { presetId: 'pr.checkout', presetName: 'Checkout' } };
  assert.equal(model.presetConfirmationNeedsRender(existing, { id: 'pr.checkout', name: 'Checkout' }), false);
  assert.equal(model.presetConfirmationNeedsRender(existing, { id: 'pr.fetch', name: 'Fetch' }), true);
  assert.equal(model.presetConfirmationNeedsRender(existing, { id: 'pr.checkout', name: 'Checkout changed' }), true);
  assert.equal(model.presetConfirmationNeedsRender(existing, null), true);
  const renderer = source.slice(source.indexOf('function renderPresetConfirmation'), source.indexOf('function updatePanel'));
  assert.match(renderer, /presetConfirmationNeedsRender\(confirmation, selected\)/,
    'the confirmation renderer must skip rebuilding an unchanged region');
  assert.match(renderer, /confirmation\.contains\(document\.activeElement\)/);
  assert.match(renderer, /focusElement\(replacement \|\| toggle\)/,
    'a changed confirmation must move focus to the same action or its toggle');
});

test('replica anchors are resolved by kind and uid under the documented replica root', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.findReplicaAnchor, 'function');
  const replacement = { dataset: { kind: 'pr', uid: 'b2' } };
  const root = { querySelectorAll: selector => {
    assert.equal(selector, '[data-kind][data-uid]');
    return [{ dataset: { kind: 'issue', uid: 'b2' } }, replacement];
  } };
  assert.equal(model.findReplicaAnchor(root, 'pr', 'b2'), replacement);
  assert.equal(model.findReplicaAnchor(root, 'pr', 'missing'), null);
  assert.equal(model.findReplicaAnchor(null, 'pr', 'b2'), null);
  assert.match(source, /#options-replica-root[\s\S]*data-kind[\s\S]*data-uid/,
    'the JSDoc must record the replica anchor attribute contract');
  const placement = source.slice(source.indexOf('function positionPopover()'), source.indexOf('function updateEditorFacePreview'));
  assert.match(placement, /const anchor = activeAnchor\(\);/,
    'every placement must resolve the current replica node by the active identity');
  assert.match(source, /findReplicaAnchor\(replicaRoot, active\.kind, active\.uid\)/,
    'an open button editor resolves its button by kind and uid');
  assert.match(placement, /if \(!anchor\?\.isConnected\) return;/,
    'a temporarily missing anchor must leave the last panel coordinates alone');
});

test('snapshot renderers preserve focus in the confirmation and Claude input regions', () => {
  const claudeInputs = source.slice(source.indexOf('function renderClaudeInputs'), source.indexOf('function renderExampleDock'));
  assert.match(claudeInputs, /rows\.contains\(document\.activeElement\)/,
    'a Claude row that must be removed needs a focus bookmark');
  assert.match(claudeInputs, /focusElement\(usableTarget\)/,
    'a removed focused Claude control needs a same-role replacement');
});

test('popover placement flips above when below is short and keeps the surface inside the viewport', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.calculatePopoverPosition, 'function');
  const placed = model.calculatePopoverPosition(
    { left: 280, right: 320, top: 580, bottom: 600, width: 40, height: 20 },
    { width: 400, height: 240 },
    { width: 900, height: 800 },
  );
  assert.equal(placed.placement, 'top');
  assert.equal(placed.top, 328);
  assert.equal(placed.left, 280);
  assert.ok(placed.arrowX >= 16 && placed.arrowX <= placed.width - 16);
  assert.ok(placed.left >= 12);
  assert.ok(placed.left + placed.width <= 888);
  assert.ok(placed.top >= 12);
  assert.ok(placed.top + placed.height <= 788);
});

test('a low anchor in a narrow viewport flips above when there is room there', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 100, right: 150, top: 650, bottom: 680, width: 50, height: 30 },
    { width: 440, height: 560 },
    { width: 579, height: 700 },
  );
  assert.equal(placed.placement, 'top');
  assert.equal(placed.height, 560);
  assert.ok(placed.maxHeight >= placed.height);
  assert.ok(placed.top >= 12);
  assert.ok(placed.top + placed.height <= 688);
});

test('equally short sides break ties below when both sides constrain the popover', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 100, right: 150, top: 190, bottom: 210, width: 50, height: 20 },
    { width: 300, height: 320 },
    { width: 800, height: 400 },
  );
  assert.equal(placed.placement, 'bottom');
  assert.equal(placed.maxHeight, 166);
  assert.equal(placed.height, 166);
  assert.equal(placed.top, 222);
});

test('when neither side fits, the larger side gets a minimum scroll height', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 100, right: 150, top: 70, bottom: 90, width: 50, height: 20 },
    { width: 300, height: 320 },
    { width: 579, height: 150 },
  );
  assert.equal(placed.placement, 'top');
  assert.ok(placed.maxHeight >= 120);
  assert.ok(placed.height >= 120);
  assert.ok(placed.top >= 12);
  assert.ok(placed.top + placed.height <= 138);
});

test('zero-sized viewports produce zero-sized popover geometry', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 },
    { width: 440, height: 560 },
    { width: 0, height: 0 },
  );
  assert.equal(placed.placement, 'bottom');
  assert.equal(placed.top, 0);
  assert.equal(placed.left, 0);
  assert.equal(placed.width, 0);
  assert.equal(placed.height, 0);
  assert.equal(placed.maxHeight, 0);
});

test('every editor keydown shortcut leaves IME composition events untouched', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.isImeCompositionKeyEvent, 'function');
  assert.equal(model.isImeCompositionKeyEvent({ key: 'Escape', isComposing: true, keyCode: 229 }), true);
  assert.equal(model.isImeCompositionKeyEvent({ key: 'Enter', isComposing: false, keyCode: 229 }), true);
  assert.equal(model.isImeCompositionKeyEvent({ key: 'ArrowUp', isComposing: false, keyCode: 38 }), false);
  assert.match(source, /function handleKeydown\(event\) \{\s*if \(!active \|\| isImeCompositionKeyEvent\(event\)\) return;/,
    'all editor shortcuts must check composition before Escape or arrow handling');
});

test('narrow viewports keep the popover below and clamp its width and horizontal position', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 350, right: 390, top: 300, bottom: 320, width: 40, height: 20 },
    { width: 500, height: 320 },
    { width: 420, height: 700 },
  );
  assert.equal(placed.placement, 'bottom');
  assert.equal(placed.left, 12);
  assert.equal(placed.width, 396);
  assert.equal(placed.top, 332);
  assert.equal(placed.arrowX, 358);
});

test('a taller editor gets an internal height bound instead of leaving the viewport', () => {
  const { model } = loadEditor();
  const placed = model.calculatePopoverPosition(
    { left: 80, right: 120, top: 180, bottom: 200, width: 40, height: 20 },
    { width: 300, height: 900 },
    { width: 700, height: 500 },
  );
  assert.equal(placed.height, 276);
  assert.equal(placed.maxHeight, 276);
  assert.ok(placed.top >= 12);
  assert.ok(placed.top + placed.height <= 488);
});

test('popover placement waits for a nonzero viewport and recalculates after resize', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.hasMeasurableViewport, 'function');
  assert.equal(model.hasMeasurableViewport({ width: 0, height: 600 }), false);
  assert.equal(model.hasMeasurableViewport({ width: 800, height: 0 }), false);
  assert.equal(model.hasMeasurableViewport({ width: 800, height: 600 }), true);

  const anchor = { left: 740, right: 780, top: 120, bottom: 140, width: 40, height: 20 };
  const large = model.calculatePopoverPosition(anchor, { width: 440, height: 360 }, { width: 800, height: 600 });
  const resized = model.calculatePopoverPosition(anchor, { width: 440, height: 360 }, { width: 380, height: 500 });
  assert.equal(large.width, 440);
  assert.equal(resized.width, 356);
  assert.equal(resized.left, 12);
  assert.equal(resized.placement, 'bottom');
  assert.equal(model.hasMeasurableViewport({ width: 0, height: 0 }), false);
});

test('face limit uses the same UTF-16 length unit as maxlength', () => {
  const { model } = loadEditor();
  const limit = model.faceMaxLength;
  assert.equal(typeof model.fitsFieldLimit, 'function');
  assert.equal(Number.isInteger(limit), true);
  assert.equal(model.fitsFieldLimit('a'.repeat(limit), limit), true);
  assert.equal(model.fitsFieldLimit('a'.repeat(limit + 1), limit), false);
  assert.equal(model.fitsFieldLimit('😀'.repeat(limit / 2), limit), true);
  assert.equal(model.fitsFieldLimit('😀'.repeat(limit / 2 + 1), limit), false);
  assert.equal(model.fitsFieldLimit(4, limit), false);
});

test('emoji palette appends a whole value only when it fits the face limit', () => {
  const { model } = loadEditor();
  const limit = model.faceMaxLength;
  assert.equal(typeof model.appendFaceCharacter, 'function');
  assert.equal(model.appendFaceCharacter('ab', '🌳', limit), 'ab🌳');
  assert.equal(model.appendFaceCharacter('a'.repeat(limit - 1), '🌳', limit), 'a'.repeat(limit - 1));
});

test('variable chips come from the actual kind definition and include app variables once', () => {
  const { model, context } = loadEditor();
  assert.equal(typeof model.variablesForKind, 'function');
  const names = vm.runInContext(`Object.keys(BUTTON_KINDS)`, context);
  for (const kind of names) {
    const expected = Array.from(vm.runInContext(`[...APP_VARIABLES, ...BUTTON_KINDS[${JSON.stringify(kind)}].variables]`, context));
    assert.deepEqual(Array.from(model.variablesForKind(kind)), expected.filter((name, index) => expected.indexOf(name) === index));
  }
  assert.deepEqual(Array.from(model.variablesForKind('unknown')), []);
});

test('editor validation is projected from the engine snapshot and uses existing messages', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.validationFor, 'function');
  const button = { uid: 'runtime-1', validation: { errors: [], warnings: [] } };
  const snapshot = {
    validation: {
      buttons: [{ kind: 'pr', uid: 'runtime-1', errors: ['face'], warnings: ['claude-inputs-without-claude-command'] }],
    },
  };
  assert.deepEqual(Array.from(model.validationFor(snapshot, 'pr', button)), [
    'ext.validate.face:buttons|0',
    'ext.field.claudeInputs.warn:',
  ]);
});

test('validation button positions match the zero-based storage key used by Save', () => {
  const { model } = loadEditor();
  const buttons = [{ uid: 'first' }, { uid: 'second' }];
  const snapshot = {
    buttons: { pr: buttons },
    validation: { buttons: [
      { kind: 'pr', uid: 'first', errors: ['face'] },
      { kind: 'pr', uid: 'second', errors: ['command'] },
    ] },
  };
  assert.equal(model.validationFor(snapshot, 'pr', buttons[0])[0], 'ext.validate.face:buttons|0');
  assert.equal(model.validationFor(snapshot, 'pr', buttons[1])[0], 'ext.validate.command:buttons|1');
});

test('Claude input type is classified without changing the entered value', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.classifyClaudeInput, 'function');
  for (const [value, kind] of [
    ['  !gh issue view {number}', 'shell'],
    ['/review', 'slash'],
    ['# remember this', 'directive'],
    ['summarize this issue', 'message'],
    ['\t!not-trimmed-as-space', 'message'],
  ]) {
    const original = value;
    assert.equal(model.classifyClaudeInput(value), kind);
    assert.equal(value, original);
  }
});

test('example variables come from the replica example context and the real kind definitions', () => {
  const { model, context } = loadEditor();
  const replica = context.window.optionsReplica;
  assert.equal(typeof model.exampleValuesForKind, 'function');
  const values = model.exampleValuesForKind('pr', replica.getExampleContext());
  assert.equal(values.repo, 'sample-repo');
  assert.equal(values.owner, 'octo-demo');
  assert.equal(values.number, 42);
  assert.equal(values.branch, 'example/options');
  assert.equal(values.branch_underbar, 'example_options');
  assert.equal(values.base, 'main');
  assert.equal(values.main, 'main');
  assert.equal(values.cd, '/work/sample-repo');
  const issueList = model.exampleValuesForKind('issue-list', replica.getExampleContext());
  assert.equal(issueList.number, 17);
  assert.equal(Object.hasOwn(issueList, 'branch'), false);
});

test('example expansion leaves unsupported or absent variables unchanged and identifies them', () => {
  const { model, context } = loadEditor();
  const example = context.window.optionsReplica.getExampleContext();
  assert.equal(typeof model.expandExampleTemplate, 'function');
  const pr = model.expandExampleTemplate(
    '{cd} && gh pr view {number} {branch} {missing}', 'pr', example,
  );
  assert.equal(pr.text, "cd /work/sample-repo && gh pr view 42 example/options {missing}");
  assert.equal(model.splitCommandSteps(pr.text)[0], 'cd /work/sample-repo',
    '{cd} must appear as one example command step');
  assert.deepEqual(Array.from(pr.unsupported), ['missing']);
  assert.deepEqual(Array.from(pr.missing), []);
  const issue = model.expandExampleTemplate('checkout {branch}', 'issue', example);
  assert.equal(issue.text, 'checkout {branch}');
  assert.deepEqual(Array.from(issue.unsupported), ['branch']);
});

test('example command splitting only separates certain top-level double ampersands', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.splitCommandSteps, 'function');
  assert.deepEqual(Array.from(model.splitCommandSteps('cd repo && git status && claude')),
    ['cd repo', 'git status', 'claude']);
  assert.deepEqual(Array.from(model.splitCommandSteps('printf "a && b" && next')),
    ['printf "a && b"', 'next']);
  assert.deepEqual(Array.from(model.splitCommandSteps('(echo a && echo b) && next')),
    ['(echo a && echo b)', 'next']);
  assert.deepEqual(Array.from(model.splitCommandSteps('if a && b; then c; fi && next')),
    ['if a && b; then c; fi && next']);
  assert.deepEqual(Array.from(model.splitCommandSteps('[[ a && b ]] && next')),
    ['[[ a && b ]] && next']);
  assert.deepEqual(Array.from(model.splitCommandSteps("echo $(printf 'a && b') && next")),
    ["echo $(printf 'a && b')", 'next']);
  assert.deepEqual(Array.from(model.splitCommandSteps('echo "unfinished && next')), ['echo "unfinished && next']);
  assert.deepEqual(Array.from(model.splitCommandSteps('cat <<EOF\na && b\nEOF\nnext')),
    ['cat <<EOF\na && b\nEOF\nnext']);
});

test('input movement actions use the engine beforeIndex convention and respect no-op edges', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.inputMoveAction, 'function');
  const inputs = ['first', 'second', 'third'];
  const plain = value => JSON.parse(JSON.stringify(value));
  assert.deepEqual(plain(model.inputMoveAction('pr', 'u1', inputs, 1, 0)), {
    type: 'input-move', kind: 'pr', buttonUid: 'u1', fromIndex: 1, beforeIndex: 0,
  });
  assert.deepEqual(plain(model.inputMoveAction('pr', 'u1', inputs, 1, 3)), {
    type: 'input-move', kind: 'pr', buttonUid: 'u1', fromIndex: 1, beforeIndex: 3,
  });
  assert.equal(model.inputMoveAction('pr', 'u1', inputs, 1, 1), null);
  assert.equal(model.inputMoveAction('pr', 'u1', inputs, 1, 2), null);
  assert.equal(model.inputMoveTargetIndex(1, 3), 2);
  assert.equal(model.inputMoveTargetIndex(1, 0), 0);
});

test('input add availability follows MAX_CLAUDE_INPUTS', () => {
  const { model, context } = loadEditor();
  assert.equal(typeof model.canAddClaudeInput, 'function');
  const max = model.maxClaudeInputs;
  assert.equal(model.canAddClaudeInput(max - 1), true);
  assert.equal(model.canAddClaudeInput(max), false);
  assert.equal(model.canAddClaudeInput(max + 1), false);
});

test('only custom commands require the editor confirmation step for preset replacement', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.requiresPresetConfirmation, 'function');
  assert.equal(model.requiresPresetConfirmation({ customCommand: true }), true);
  assert.equal(model.requiresPresetConfirmation({ customCommand: false }), false);
  assert.equal(model.requiresPresetConfirmation({}), false);
});

test('up and down controls translate to the engine beforeUid ordering', () => {
  const { model } = loadEditor();
  const snapshot = { buttons: { pr: [{ uid: 'a' }, { uid: 'b' }, { uid: 'c' }, { uid: 'd' }] } };
  const plain = value => JSON.parse(JSON.stringify(value));
  assert.deepEqual(plain(model.buttonMoveAction(snapshot, 'pr', 'b', -1)), {
    type: 'button-move', kind: 'pr', uid: 'b', beforeUid: 'a',
  });
  assert.deepEqual(plain(model.buttonMoveAction(snapshot, 'pr', 'b', 1)), {
    type: 'button-move', kind: 'pr', uid: 'b', beforeUid: 'd',
  });
  assert.deepEqual(plain(model.buttonMoveAction(snapshot, 'pr', 'c', 1)), {
    type: 'button-move', kind: 'pr', uid: 'c', beforeUid: null,
  });
  assert.equal(model.buttonMoveAction(snapshot, 'pr', 'a', -1), null);
  assert.equal(model.buttonMoveAction(snapshot, 'pr', 'd', 1), null);
});

test('preset replacement adds confirmed only after the editor confirmation step', () => {
  const { model } = loadEditor();
  const plain = value => JSON.parse(JSON.stringify(value));
  assert.deepEqual(plain(model.presetReplaceAction('pr', 'u1', 'pr.checkout')),
    { type: 'preset-replace', kind: 'pr', uid: 'u1', presetId: 'pr.checkout' });
  assert.deepEqual(plain(model.presetReplaceAction('pr', 'u1', 'pr.checkout', true)),
    { type: 'preset-replace', kind: 'pr', uid: 'u1', presetId: 'pr.checkout', confirmed: true });
});

test('editor does not call browser dialogs or define mockup settings data', () => {
  assert.doesNotMatch(source, /\b(?:window\.)?(?:confirm|alert|prompt)\s*\(/);
  assert.doesNotMatch(source, /\bchrome\./);
  assert.doesNotMatch(source, /\bconst\s+(?:KINDS|SAVED|PRESETS)\s*=/);
});

test('hidden editor surfaces only receive flex display while visible', () => {
  const css = read('options-editor.css');
  for (const name of ['validation', 'presets', 'preset-confirmation']) {
    const escaped = `\\.options-editor-${name}:not\\(\\[hidden\\]\\)`;
    assert.match(css, new RegExp(`${escaped}\\s*\\{[^}]*display:\\s*flex\\s*;`, 's'));
  }
});

test('variables are inline accessible insertion controls inside their explanatory text', () => {
  assert.match(source, /replaceVariableReferences\(variablesHelp, kind\)/);
  assert.doesNotMatch(source, /makeElement\('div', 'options-editor-variables'\)/);
  assert.doesNotMatch(source, /options-editor-command-example/);
  assert.doesNotMatch(source, /commandPlaceholder/);
});

test('the action bar is an opaque sticky end to the scrollable editor content', () => {
  const css = read('options-editor.css');
  assert.match(css, /\.options-editor-actions\s*\{[^}]*position:\s*sticky/s);
  assert.match(css, /\.options-editor-actions\s*\{[^}]*background:\s*var\(--panel\)/s);
  assert.match(css, /\.options-editor-actions\s*\{[^}]*padding:\s*\d+px\s+0\s+\d+px/s);
});

test('the editor locale block follows its anchor in the same order in all five catalogues', () => {
  const keys = [
    'ext_d_editor_title', 'ext_d_editor_close',
    'ext_d_editor_variableInsert', 'ext_d_editor_moveEarlier', 'ext_d_editor_moveLater',
    'ext_d_editor_replacePreset', 'ext_d_editor_confirmReplace', 'ext_d_editor_confirm',
    'ext_d_editor_cancel', 'ext_d_editor_cannotUpdate', 'ext_d_editor_limitReached',
    'ext_d_editor_deleteUnavailable', 'ext_d_editor_inputLimit', 'ext_d_editor_inputExample',
    'ext_d_editor_inputLabel', 'ext_d_editor_inputRemove',
    'ext_d_editor_inputTypeShell', 'ext_d_editor_inputTypeSlash', 'ext_d_editor_inputTypeDirective',
    'ext_d_editor_inputTypeMessage', 'ext_d_editor_exampleTitle', 'ext_d_editor_exampleNotice',
    'ext_d_editor_exampleCommand', 'ext_d_editor_exampleEmptyCommand', 'ext_d_editor_exampleInputs', 'ext_d_editor_exampleNoInputs',
    'ext_d_editor_exampleCdNote', 'ext_d_editor_exampleUnsupported',
    'ext_d_editor_addTitle', 'ext_d_editor_addCount', 'ext_d_editor_addBlank', 'ext_d_editor_addBlankDescription',
  ];
  const catalogues = ['en', 'ko', 'ja', 'zh_CN', 'zh_TW'].map(locale => ({
    locale,
    messages: JSON.parse(fs.readFileSync(path.join(extension, '_locales', locale, 'messages.json'), 'utf8')),
  }));
  for (const { locale, messages } of catalogues) {
    const names = Object.keys(messages);
    const anchor = names.indexOf('ext_migration_badge');
    assert.ok(anchor >= 0, `${locale} has no migration anchor`);
    assert.deepEqual(names.slice(anchor + 1, anchor + 1 + keys.length), keys, `${locale} editor block is misplaced`);
    for (const key of keys) assert.ok(messages[key].message.trim(), `${locale}/${key} is empty`);
  }
  const placeholders = entry => Object.keys(entry.placeholders || {}).sort();
  for (const key of keys) {
    const expected = placeholders(catalogues[0].messages[key]);
    for (const { locale, messages } of catalogues.slice(1)) {
      assert.deepEqual(placeholders(messages[key]), expected, `${locale}/${key} placeholder set differs`);
    }
  }
});
