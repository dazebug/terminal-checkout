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
