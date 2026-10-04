// Public contract checks for the options shell module, without a DOM implementation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../extension/options-shell.js'), 'utf8');

test('options shell exposes the save area, engine, and settings mount contract', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const api = context.window.optionsShell;
  assert.deepEqual(Object.keys(api), ['mount']);
  assert.equal(typeof api.mount, 'function');
  assert.equal(api.mount.length, 3);
});

test('options shell documents both roots and the engine parameter', () => {
  assert.match(source, /@param \{HTMLElement\} root/);
  assert.match(source, /@param \{OptionsEngine\} engine/);
  assert.match(source, /@param \{HTMLElement\} settingsRoot/);
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
  assert.equal(result.inert, false);
  assert.equal(result.defaultMain, '');
  assert.equal(result.showEmptyOverrides, false);
  assert.deepEqual(result.overrides.map(row => row.validationMessage), [
    { key: 'ext.validate.override.incomplete', args: [1] },
    { key: 'ext.validate.override.duplicate', args: [2, 'same-repo'] },
  ]);
  assert.equal(viewState({ ...snapshot, save: { saving: false, importing: true } }).disabled, true);
  const blocked = viewState({ ...snapshot, load: { loaded: false } });
  assert.equal(blocked.disabled, true);
  assert.equal(blocked.inert, true);
});

test('every shell text input has an associated label or accessible name', () => {
  assert.match(source, /defaultMainLabel\.htmlFor = 'shell-default-main';[\s\S]*?defaultMain\.id = 'shell-default-main';/);
  assert.match(source, /repoLabel\.htmlFor = `shell-override-\$\{row\.index\}-repo`;[\s\S]*?repoInput\.id = repoLabel\.htmlFor;/);
  assert.match(source, /branchLabel\.htmlFor = `shell-override-\$\{row\.index\}-branch`;[\s\S]*?branchInput\.id = branchLabel\.htmlFor;/);
  assert.match(source, /const importFileLabel = optionsShellElement\('label', 'options-shell-sr-only', importButton\.textContent\)/);
  assert.match(source, /importFileLabel\.htmlFor = 'shell-import-file'/);
  assert.match(source, /importFile\.className = 'options-shell-sr-only'/);
  assert.match(source, /importFile\.tabIndex = -1/);
  assert.doesNotMatch(source, /importFile\.hidden = true/);
  assert.match(source, /backupActions\.append\(exportButton, importButton, resetButton, importFileLabel, importFile\)/);

  const start = source.indexOf('function renderMigration(');
  const end = source.indexOf('\n    function createOverrideRow(', start);
  const renderMigration = source.slice(start, end);
  assert.match(renderMigration, /label\.append\(checkbox, optionsShellElement\('span', '', optionsShellMessage\(item\.label\)\)\)/);
  assert.doesNotMatch(renderMigration, /heading\.append\(checkbox, label/);
  assert.match(renderMigration, /heading\.append\(label, position, source\)/);
});

test('shell key handling leaves IME composition keys to the input method', () => {
  const start = source.indexOf("document.addEventListener('keydown', event => {");
  const end = source.indexOf('\n    });', start);
  const handler = source.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.match(handler, /if \(event\.isComposing \|\| event\.keyCode === 229\) return;/);
  assert.ok(handler.indexOf('event.isComposing') < handler.indexOf("event.key === 'Escape'"));
});

test('shell confirmations isolate the whole page and reject background edits', () => {
  const targetsStart = source.indexOf('const confirmationBackground = [');
  const targetsEnd = source.indexOf('\n    function canRestoreFocus(', targetsStart);
  const targets = source.slice(targetsStart, targetsEnd);
  assert.ok(targetsStart >= 0 && targetsEnd > targetsStart);
  assert.match(source, /const appRoot = document\.getElementById\('app'\)/);
  assert.match(targets, /appRoot/);
  assert.match(targets, /settingsRoot/);
  assert.match(targets, /saveBar/);
  assert.match(targets, /stale, migrationBadge, migrationPanel, loadError, status/);
  assert.match(source, /function setConfirmationBackgroundInert\(inert\)\s*\{\s*engine\.setInertReason\('confirmation', confirmationBackground, inert\);\s*\}/);
  assert.doesNotMatch(source, /\.inert\s*=|setAttribute\('inert'|removeAttribute\('inert'/);
  assert.match(source, /document\.addEventListener\('focusin', event => \{\s*if \(!confirmation\.hidden && !confirmation\.contains\(event\.target\)\) keepEditing\.focus\(\);/);

  const actionStart = source.indexOf('async function runAction(action)');
  const actionEnd = source.indexOf('\n    function appendMigrationDiff(', actionStart);
  const runAction = source.slice(actionStart, actionEnd);
  assert.match(runAction, /if \(!confirmation\.hidden\)/);
});

test('the confirmation consumes the Escape that closes it, so nothing behind it acts on the same key', () => {
  const start = source.indexOf("document.addEventListener('keydown', event => {");
  const end = source.indexOf('\n    });', start);
  const handler = source.slice(start, end);
  assert.ok(start >= 0 && end > start);
  const escape = handler.slice(handler.indexOf("if (event.key === 'Escape') {"), handler.indexOf("if (event.key === 'Tab') {"));
  const consumed = escape.indexOf('event.stopImmediatePropagation();');
  assert.ok(consumed >= 0 && consumed < escape.indexOf('closeConfirmation();'),
    'closing lifts inert from the page, so a document listener after this one (the drawer) would act on the same Escape');
});

test('shell modal traps Tab and restores focus on every close path', () => {
  const start = source.indexOf("document.addEventListener('keydown', event => {");
  const end = source.indexOf('\n    });', start);
  const handler = source.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.match(handler, /event\.key === 'Tab'/);
  assert.match(handler, /event\.shiftKey/);
  assert.match(handler, /event\.preventDefault\(\)/);
  assert.match(source, /if \(restoreFocus && canRestoreFocus\(returnFocus\)\) returnFocus\.focus\(\)/);
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
