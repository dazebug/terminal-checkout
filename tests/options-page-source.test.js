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

test('the shell replaces the legacy global settings, backup, and reset surfaces', () => {
  const html = read('options.html');
  const shell = read('options-shell.js');
  const styles = read('options-shell.css');
  assert.match(html, /<section class="section legacy-shell-ui" id="legacy-main-settings">/);
  assert.match(html, /<section class="section legacy-shell-ui" id="legacy-backup-settings">/);
  assert.match(html, /<div class="actions legacy-shell-ui">/);
  assert.match(styles, /\.legacy-shell-ui\s*\{\s*display:\s*none\s*!important;/);
  for (const action of ['main-patch', 'override-add', 'override-patch', 'override-remove', 'export-saved', 'import-file', 'reset']) {
    assert.match(shell, new RegExp(`type: '${action}'`));
  }
  assert.match(read('options.js'), /const defaultMain = state\.defaultMain\.trim\(\) \|\| DEFAULT_MAIN/);
});

test('the engine dispatch contract is promise-based with structured outcomes', () => {
  const source = read('options.js');
  assert.match(source, /@typedef \{Object\} OptionsDispatchResult[\s\S]*?@property \{boolean\} ok[\s\S]*?@property \{\('not-loaded'\|'busy'\|'limit'\|'not-found'\|'needs-confirmation'\|'invalid'\|'failed'\)=\} \[reason\][\s\S]*?@property \{string=\} \[createdUid\][\s\S]*?@property \{OptionsEngineSnapshot\} snapshot/);
  assert.match(source, /@property \{\(action: OptionsEngineAction\) => Promise<OptionsDispatchResult>\} dispatch/);
});

test('dispatch mutates engine state without DOM edits, synthetic events, or browser dialogs', () => {
  const source = read('options.js');
  const start = source.indexOf('async function dispatchOptionsEngineAction(');
  const end = source.indexOf('\n/** @type {OptionsEngine} */', start);
  assert.ok(start >= 0 && end > start);
  const dispatch = source.slice(start, end);
  assert.doesNotMatch(dispatch, /document\.|\.click\s*\(|dispatchEvent\s*\(|\.value\s*=|\b(?:confirm|alert|prompt)\s*\(/);
});

test('legacy face inputs read their limit from defaults.js', () => {
  const defaults = read('defaults.js');
  const options = read('options.js');
  assert.match(defaults, /const FACE_MAX_LENGTH = 24;/);
  assert.match(options, /maxlength="\$\{FACE_MAX_LENGTH\}"/);
  assert.doesNotMatch(options, /maxlength=["']24["']/);
});

test('legacy migration controls and the shell dispatch share selection and panel actions', () => {
  const source = read('options.js');
  assert.match(source, /@typedef \{\{type: 'migration-selection', uid: string, selected: boolean\}\} OptionsMigrationSelectionAction/);
  assert.match(source, /@typedef \{\{type: 'migration-panel-toggle'\}\} OptionsMigrationPanelToggleAction/);
  const legacy = source.slice(
    source.indexOf("document.getElementById('migration-badge').addEventListener"),
    source.indexOf("document.getElementById('migration-apply').addEventListener"),
  );
  assert.match(legacy, /runPreparedReview\(prepareMigrationPanelToggle\(\)\)/);
  assert.match(legacy, /runPreparedReview\(prepareMigrationSelection\(id, checked\)\)/);
  const dispatchStart = source.indexOf('async function dispatchOptionsEngineAction(');
  const dispatchEnd = source.indexOf('\n/** @type {OptionsEngine} */', dispatchStart);
  const dispatch = source.slice(dispatchStart, dispatchEnd);
  assert.match(dispatch, /case 'migration-selection':\s*outcome = runPreparedReview\(prepareMigrationSelection\(action\.uid, action\.selected\)\)/);
  assert.match(dispatch, /case 'migration-panel-toggle':\s*outcome = runPreparedReview\(prepareMigrationPanelToggle\(\)\)/);
  assert.match(source, /panelOpen: state\.migrationPanelOpen/);
  assert.match(source, /pending: state\.plan !== null && state\.loadedVersion !== null/);
});
