// Public contract checks for the editor module, without rendering a DOM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../extension/options-editor.js'), 'utf8');

test('editor publishes mount and open contracts', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const api = context.window.optionsEditor;
  assert.deepEqual(Object.keys(api), ['mount', 'open']);
  assert.equal(api.mount.length, 2);
  assert.equal(api.open.length, 1);
});

test('editor documents the opener identity and focus return target', () => {
  assert.match(source, /@param \{HTMLElement\} root/);
  assert.match(source, /@param \{OptionsEngine\} engine/);
  assert.match(source, /@typedef \{\{kind: OptionsButtonKind, uid: string, restoreFocusTo: HTMLElement\}\} OptionsEditorOpenOptions/);
  assert.match(source, /@param \{OptionsEditorOpenOptions\} options/);
});
