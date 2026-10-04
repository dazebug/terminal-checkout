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
  vm.runInContext(source, context);
  const model = vm.runInContext(`({
    calculatePopoverPosition: typeof calculatePopoverPosition === 'function' ? calculatePopoverPosition : null,
    fitsFieldLimit: typeof fitsFieldLimit === 'function' ? fitsFieldLimit : null,
    appendFaceCharacter: typeof appendFaceCharacter === 'function' ? appendFaceCharacter : null,
    variablesForKind: typeof variablesForKind === 'function' ? variablesForKind : null,
    validationFor: typeof validationFor === 'function' ? validationFor : null,
    requiresPresetConfirmation: typeof requiresPresetConfirmation === 'function' ? requiresPresetConfirmation : null,
    buttonMoveAction: typeof buttonMoveAction === 'function' ? buttonMoveAction : null,
    presetReplaceAction: typeof presetReplaceAction === 'function' ? presetReplaceAction : null,
  })`, context);
  return { context, model, api: context.window.optionsEditor };
}

test('editor publishes mount, open, close, and isOpen contracts', () => {
  const { api } = loadEditor();
  assert.deepEqual(Object.keys(api), ['mount', 'open', 'close', 'isOpen']);
  assert.equal(api.mount.length, 2);
  assert.equal(api.open.length, 1);
  assert.equal(api.close.length, 0);
  assert.equal(api.isOpen.length, 0);
});

test('editor open contract keeps the placement anchor separate from focus restoration', () => {
  assert.match(source, /@typedef \{\{kind: OptionsButtonKind, uid: string, anchor: HTMLElement, restoreFocusTo: HTMLElement\}\} OptionsEditorOpenOptions/);
  assert.match(source, /@param \{OptionsEditorOpenOptions\} options/);
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

test('face limit uses the same UTF-16 length unit as maxlength', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.fitsFieldLimit, 'function');
  assert.equal(model.fitsFieldLimit('a'.repeat(24), 24), true);
  assert.equal(model.fitsFieldLimit('a'.repeat(25), 24), false);
  assert.equal(model.fitsFieldLimit('😀'.repeat(12), 24), true);
  assert.equal(model.fitsFieldLimit('😀'.repeat(13), 24), false);
  assert.equal(model.fitsFieldLimit(4, 24), false);
});

test('emoji palette appends a whole value only when it fits the face limit', () => {
  const { model } = loadEditor();
  assert.equal(typeof model.appendFaceCharacter, 'function');
  assert.equal(model.appendFaceCharacter('ab', '🌳', 24), 'ab🌳');
  assert.equal(model.appendFaceCharacter('a'.repeat(23), '🌳', 24), 'a'.repeat(23));
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
    'ext.validate.face:buttons|1',
    'ext.field.claudeInputs.warn:',
  ]);
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

test('the editor locale block follows its anchor in the same order in all five catalogues', () => {
  const keys = [
    'ext_d_editor_title', 'ext_d_editor_close', 'ext_d_editor_commandPlaceholder',
    'ext_d_editor_variableInsert', 'ext_d_editor_moveEarlier', 'ext_d_editor_moveLater',
    'ext_d_editor_replacePreset', 'ext_d_editor_confirmReplace', 'ext_d_editor_confirm',
    'ext_d_editor_cancel', 'ext_d_editor_cannotUpdate', 'ext_d_editor_limitReached',
    'ext_d_editor_deleteUnavailable',
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
