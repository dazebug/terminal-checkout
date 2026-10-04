// Source contracts for the options page's storage boundary and module entry points.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');

test('the typed storage write site is the only sync.set call and belongs to Save', () => {
  const source = read('options.js');
  const pageSources = [
    'options.js', 'options-shell.js', 'options-replica.js', 'options-editor.js',
  ].map(name => ({ name, source: read(name) }));
  const calls = pageSources.flatMap(({ name, source: text }) =>
    [...text.matchAll(/chrome\.storage\.sync\.set\s*\(/g)].map(match => ({ name, index: match.index })));
  assert.deepEqual(calls.map(call => call.name), ['options.js']);
  const saveStart = source.indexOf('async function saveSettings()');
  const saveEnd = source.indexOf('\nfunction settleSave(', saveStart);
  assert.ok(saveStart >= 0 && saveEnd > saveStart);
  assert.ok(calls[0].index > saveStart && calls[0].index < saveEnd);
  assert.match(source, /@typedef \{Object\} OptionsStorageWriteSite[\s\S]*?@property \{'extension\/options\.js'\} file[\s\S]*?@property \{'saveSettings'\} functionName[\s\S]*?@property \{'chrome\.storage\.sync\.set'\} api/);
});

test('the page contains all module roots and loads the contract modules before the engine', () => {
  const html = read('options.html');
  for (const id of ['options-shell-root', 'options-replica-root', 'options-editor-root']) {
    assert.match(html, new RegExp(`id=["']${id}["']`));
  }
  const scripts = ['options-shell.js', 'options-replica.js', 'options-editor.js', 'options.js'];
  const positions = scripts.map(name => html.indexOf(`<script src="${name}"`));
  assert.equal(positions.every(position => position >= 0), true);
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  for (const name of ['options-shell.css', 'options-replica.css', 'options-editor.css']) assert.ok(html.includes(name));
});

test('the linked module stylesheets exist as local assets', () => {
  const html = read('options.html');
  for (const name of ['options-shell.css', 'options-replica.css', 'options-editor.css']) {
    assert.match(html, new RegExp(`<link[^>]+href=["']${name}["']`));
    assert.equal(fs.statSync(path.join(extension, name)).isFile(), true);
  }
});

test('the engine snapshot typedef names every view state group and button value', () => {
  const source = read('options.js');
  assert.match(source, /@typedef \{Object\} OptionsEngineSnapshot/);
  for (const field of [
    'buttons', 'uid', 'face', 'label', 'command', 'claudeInputs', 'validation', 'dirty',
    'errors', 'warnings', 'load', 'save', 'hasUnsavedWork', 'sync', 'migration', 'globalSettings', 'status',
  ]) assert.ok(source.includes(field), `missing snapshot contract field ${field}`);
  for (const field of ['summary', 'actionable', 'informational', 'fromInputs', 'toInputs']) {
    assert.ok(source.includes(field), `missing migration snapshot contract field ${field}`);
  }
  assert.match(source, /@property \{\(\) => OptionsEngineSnapshot\} getSnapshot/);
  assert.match(source, /@property \{\(listener: \(snapshot: OptionsEngineSnapshot\) => void\) => \(\) => void\} subscribe/);
  assert.match(source, /@property \{\(action: OptionsEngineAction\) => OptionsEngineDispatchResult\} dispatch/);
  for (const action of [
    'save', 'discard', 'retry-load', 'reload-latest', 'adopt-latest', 'defer-latest', 'reset',
    'export-saved', 'import-file', 'migration-apply', 'migration-keep', 'main-patch', 'override-add',
    'override-patch', 'override-remove', 'button-patch', 'button-add', 'button-duplicate',
    'button-remove', 'button-move', 'preset-add', 'preset-replace', 'input-add', 'input-patch',
    'input-remove', 'input-move',
  ]) assert.ok(source.includes(`type: '${action}'`), `missing dispatch action ${action}`);
});
