// Public contract checks for the options shell module, without a DOM implementation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../extension/options-shell.js'), 'utf8');

test('options shell exposes its mount contract', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const api = context.window.optionsShell;
  assert.deepEqual(Object.keys(api), ['mount']);
  assert.equal(typeof api.mount, 'function');
  assert.equal(api.mount.length, 2);
});

test('options shell documents its root and engine parameters', () => {
  assert.match(source, /@param \{HTMLElement\} root/);
  assert.match(source, /@param \{OptionsEngine\} engine/);
});

test('save bar state comes from the engine snapshot and keeps the first-load gate closed', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const viewState = vm.runInContext('optionsShellViewState', context);
  const snapshot = overrides => ({
    load: { loaded: true, status: 'loaded', inFlight: 0, retryAvailable: false },
    save: { canSave: true, saving: false, hasUnsavedWork: false },
    sync: { staleSinceLoad: false },
    migration: { pending: false },
    status: { type: 'idle', message: '' },
    ...overrides,
  });

  const blocked = viewState(snapshot({
    load: { loaded: false, status: 'unloaded', inFlight: 0, retryAvailable: false },
    save: { canSave: false, saving: false, hasUnsavedWork: false },
  }));
  assert.equal(blocked.saveState, 'blocked');
  assert.equal(blocked.saveDisabled, true);
  assert.equal(blocked.discardDisabled, true);

  const failed = viewState(snapshot({
    load: { loaded: false, status: 'error', inFlight: 0, retryAvailable: true },
    save: { canSave: false, saving: false, hasUnsavedWork: false },
  }));
  assert.equal(failed.showLoadError, true);
  assert.equal(failed.retryDisabled, false);

  const dirty = viewState(snapshot({
    save: { canSave: true, saving: false, hasUnsavedWork: true },
    sync: { staleSinceLoad: true },
    migration: { pending: true },
    status: { type: 'error', message: 'Save failed' },
  }));
  assert.equal(dirty.saveState, 'dirty');
  assert.equal(dirty.discardDisabled, false);
  assert.equal(dirty.showStaleBanner, true);
  assert.equal(dirty.showMigration, true);
  assert.equal(dirty.showStatus, true);

  const saving = viewState(snapshot({ save: { canSave: false, saving: true, hasUnsavedWork: true } }));
  assert.equal(saving.saveState, 'saving');
  assert.equal(saving.saveDisabled, true);
  assert.equal(saving.discardDisabled, true);

  const clean = viewState(snapshot({ save: { canSave: true, saving: false, hasUnsavedWork: false } }));
  assert.equal(clean.saveState, 'saved');
  assert.equal(clean.discardDisabled, true);
  assert.equal(clean.showStatus, false);
});

test('sync conflict copy does not offer export as a way to preserve unsaved edits', () => {
  const root = path.join(__dirname, '../extension/_locales');
  const exportTerms = {
    en: /\bexport\b/i,
    ko: /내보내기/,
    ja: /エクスポート/,
    zh_CN: /导出/,
    zh_TW: /匯出/,
  };
  for (const [locale, term] of Object.entries(exportTerms)) {
    const messages = JSON.parse(fs.readFileSync(path.join(root, locale, 'messages.json'), 'utf8'));
    for (const key of ['ext_error_saveConflict', 'ext_d_shell_staleHelp']) {
      assert.doesNotMatch(messages[key].message, term, `${locale}/${key} recommends export`);
    }
  }

  const english = JSON.parse(fs.readFileSync(path.join(root, 'en/messages.json'), 'utf8'));
  assert.match(english.ext_error_saveConflict.message, /accept the latest settings, reapply your edits, then Save/i);
  assert.match(english.ext_d_shell_staleHelp.message, /accept the latest settings, reapply your edits, then Save/i);
});

test('global settings view state follows the snapshot and maps override validation', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const viewState = vm.runInContext('optionsShellSettingsViewState', context);
  const snapshot = {
    load: { loaded: true },
    save: { saving: false, importing: false },
    globalSettings: {
      defaultMain: '',
      repoMainBranch: [
        { index: 0, repo: 'partial-repo', branch: '' },
        { index: 1, repo: 'same-repo', branch: 'main' },
      ],
    },
    validation: {
      overrides: [
        { index: 0, errors: ['incomplete'] },
        { index: 1, errors: ['duplicate'] },
      ],
    },
  };
  const result = JSON.parse(JSON.stringify(viewState(snapshot)));
  assert.equal(result.disabled, false);
  assert.equal(result.defaultMain, '');
  assert.equal(result.showEmptyOverrides, false);
  assert.deepEqual(result.overrides.map(row => row.validationMessage), [
    { key: 'ext.validate.override.incomplete', args: [1] },
    { key: 'ext.validate.override.duplicate', args: [2, 'same-repo'] },
  ]);
  assert.equal(viewState({ ...snapshot, save: { saving: false, importing: true } }).disabled, true);
  assert.equal(viewState({ ...snapshot, load: { loaded: false } }).disabled, true);
});

test('a clean save bar uses a state label, not the successful-save announcement', () => {
  assert.match(source, /saved:\s*tr\('ext\.d\.shell\.saved'\)/);

  const expected = {
    en: 'Saved',
    ko: '저장됨',
    ja: '保存済み',
    zh_CN: '已保存',
    zh_TW: '已儲存',
  };
  const root = path.join(__dirname, '../extension/_locales');
  for (const [locale, label] of Object.entries(expected)) {
    const messages = JSON.parse(fs.readFileSync(path.join(root, locale, 'messages.json'), 'utf8'));
    assert.equal(messages.ext_d_shell_saved.message, label, `${locale} state label`);
    assert.notEqual(messages.ext_d_shell_saved.message, messages.ext_status_saved.message, `${locale} event copy`);
  }
});
