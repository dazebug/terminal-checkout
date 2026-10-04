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
