// Source contracts for the options page's storage boundary and module entry points.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

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
  for (const id of ['options-shell-root', 'options-replica-root', 'options-editor-root', 'options-shell-settings-root']) {
    assert.match(html, new RegExp(`id=["']${id}["']`));
  }
  assert.ok(html.indexOf('id="options-shell-root"') < html.indexOf('<main id="app"'));
  assert.ok(html.indexOf('id="options-shell-settings-root"') > html.indexOf('</main>'));
  const scripts = ['options-shell.js', 'options-replica.js', 'options-editor.js', 'options.js'];
  const positions = scripts.map(name => html.indexOf(`<script src="${name}"`));
  assert.equal(positions.every(position => position >= 0), true);
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
});

test('the linked module stylesheets exist as local assets', () => {
  const html = read('options.html');
  for (const name of ['options-shell.css', 'options-replica.css', 'options-editor.css']) {
    assert.match(html, new RegExp(`<link[^>]+href=["']${name}["']`));
    assert.equal(fs.statSync(path.join(extension, name)).isFile(), true);
  }
});

test('the app contains only the replica and editor roots, and legacy controls are removed', () => {
  const html = read('options.html');
  const options = read('options.js');
  const shell = read('options-shell.js');
  const styles = read('options-shell.css');
  const app = html.match(/<main id="app" inert>([\s\S]*?)<\/main>/)?.[1] || '';
  assert.deepEqual([...app.matchAll(/id="([^"]+)"/g)].map(([, id]) => id), [
    'options-replica-root', 'options-editor-root',
  ]);
  assert.ok(html.indexOf('id="options-shell-root"') < html.indexOf('<main id="app"'));
  assert.doesNotMatch(`${html}\n${options}`, /legacy-shell-ui|btn-card|pr-buttons|default-main|legacy-main-settings|legacy-backup-settings|migration-section|stale-banner|dirty-indicator|load-error/);
  assert.doesNotMatch(styles, /legacy-shell-ui|btn-card|migration-section|stale-banner|dirty-indicator/);
  assert.doesNotMatch(options, /renderButtons|renderOverrides|renderMigration|applyPreset|onCardInput|onCardClick/);
  for (const action of ['main-patch', 'override-add', 'override-patch', 'override-remove', 'export-saved', 'import-file', 'reset']) {
    assert.match(shell, new RegExp(`type: '${action}'`));
  }
});

test('the page makes the hidden attribute override module display styles', () => {
  const html = read('options.html');
  const shellStyles = read('options-shell.css');
  const baseStyles = html.match(/<style>([\s\S]*?)<\/style>/)?.[1] || '';
  assert.match(baseStyles, /^\s*\[hidden\]\s*\{\s*display:\s*none\s*!important;\s*\}\s*$/m);
  assert.doesNotMatch(shellStyles, /\[hidden\][^{]*\{[^}]*display\s*:\s*(?!none\b)/s);
});

test('the engine reads no rendered settings and only uses the module roots and inert gate', () => {
  const source = read('options.js');
  const lookups = [...source.matchAll(/document\.getElementById\('([^']+)'\)/g)].map(([, id]) => id);
  assert.deepEqual([...new Set(lookups)].sort(), [
    'app', 'options-editor-root', 'options-replica-root', 'options-shell-root', 'options-shell-settings-root',
  ]);
  assert.doesNotMatch(source, /document\.(?:querySelector|querySelectorAll)\s*\(/);
  assert.doesNotMatch(source, /(?:\.value|\.textContent|\.innerHTML)\s*(?:=|\+=)/,
    'engine state still depends on markup fields or legacy rendering');
});

test('the engine snapshot projects its global settings and status', () => {
  const source = read('options.js');
  assert.match(source, /const defaultMain = state\.defaultMain\.trim\(\) \|\| DEFAULT_MAIN/);
  assert.match(source, /loadErrorMessage: null/);
  assert.match(source, /status: \{ type: 'idle', message: '' \}/);
  assert.match(source, /errorMessage: state\.loadErrorMessage/);
  assert.match(source, /return \{ \.\.\.state\.status \};/);
});

test('the shell puts the localized page heading in the save bar', () => {
  const shell = read('options-shell.js');
  assert.match(shell, /optionsShellElement\('h1', 'options-shell-title', `Terminal Checkout — \$\{tr\('ext\.header\.options'\)\}`\)/);
  assert.match(shell, /saveBar\.append\(heading, saveState, discard, save\)/);
});

test('Korean wrapping rules follow only the Korean document language', () => {
  const html = read('options.html');
  const baseStyles = html.match(/<style>([\s\S]*?)<\/style>/)?.[1] || '';
  const languageRules = [...baseStyles.matchAll(/([^{}]*:lang\([^)]*\)[^{}]*)\{([^{}]*)\}/g)]
    .filter(([, , declarations]) => /\b(?:word-break|overflow-wrap)\s*:/.test(declarations));
  assert.equal(languageRules.length, 1);
  assert.equal(languageRules[0][1].trim(), ':lang(ko)');
  assert.match(languageRules[0][2], /\bword-break:\s*keep-all\s*;/);
  assert.match(languageRules[0][2], /\boverflow-wrap:\s*anywhere\s*;/);
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

test('the face editor reads its limit from defaults.js', () => {
  const defaults = read('defaults.js');
  const editor = read('options-editor.js');
  assert.match(defaults, /const FACE_MAX_LENGTH = 24;/);
  assert.match(editor, /maxLength: FACE_MAX_LENGTH/);
  assert.match(editor, /appendFaceCharacter\(face\.value, target\.dataset\.emoji, FACE_MAX_LENGTH\)/);
  assert.doesNotMatch(editor, /maxLength:\s*24\b/);
});

test('migration selection and panel state are owned by the engine and rendered by the shell', () => {
  const source = read('options.js');
  const shell = read('options-shell.js');
  assert.match(source, /@typedef \{\{type: 'migration-selection', uid: string, selected: boolean\}\} OptionsMigrationSelectionAction/);
  assert.match(source, /@typedef \{\{type: 'migration-panel-toggle'\}\} OptionsMigrationPanelToggleAction/);
  const dispatchStart = source.indexOf('async function dispatchOptionsEngineAction(');
  const dispatchEnd = source.indexOf('\n/** @type {OptionsEngine} */', dispatchStart);
  const dispatch = source.slice(dispatchStart, dispatchEnd);
  assert.match(dispatch, /case 'migration-selection':\s*outcome = runPreparedReview\(prepareMigrationSelection\(action\.uid, action\.selected\)\)/);
  assert.match(dispatch, /case 'migration-panel-toggle':\s*outcome = runPreparedReview\(prepareMigrationPanelToggle\(\)\)/);
  assert.match(source, /panelOpen: state\.migrationPanelOpen/);
  assert.match(source, /pending: state\.plan !== null && state\.loadedVersion !== null/);
  assert.match(shell, /type: 'migration-selection'/);
  assert.match(shell, /type: 'migration-panel-toggle'/);
});

test('page inert state is the union of independent engine reasons', () => {
  const engine = read('options.js');
  const shell = read('options-shell.js');
  assert.match(engine, /@typedef \{'first-load'\|'confirmation'\} OptionsInertReason/);
  assert.match(engine, /@property \{\(reason: OptionsInertReason, elements: ReadonlyArray<HTMLElement>, active: boolean\) => void\} setInertReason/);
  assert.match(engine, /function updateLoadedGate\(\)\s*\{[^}]*setOptionsPageInertReason\('first-load', \[document\.getElementById\('app'\)\], !state\.loaded\)/s);
  assert.match(engine, /setInertReason: setOptionsPageInertReason/);
  assert.match(shell, /engine\.setInertReason\('confirmation', confirmationBackground, inert\)/);
  assert.match(shell, /engine\.setInertReason\('first-load', \[settingsRegion\], settings\.inert\)/);
  const inertWriters = [...engine.matchAll(/\.inert\s*=/g)];
  assert.equal(inertWriters.length, 1, 'only the engine reason manager writes the inert property');
  for (const name of ['options-shell.js', 'options-replica.js', 'options-editor.js']) {
    assert.doesNotMatch(read(name), /\.inert\s*=(?!=)|setAttribute\('inert'|removeAttribute\('inert'/, `${name} delegates inert state to the engine`);
  }

  const start = engine.indexOf('const optionsPageInertReasons = new WeakMap();');
  const end = engine.indexOf('\nfunction updateLoadedGate()', start);
  assert.ok(start >= 0 && end > start, 'the engine must own the inert reason manager');
  const context = vm.createContext({});
  vm.runInContext(`${engine.slice(start, end)}\nglobalThis.setOptionsPageInertReason = setOptionsPageInertReason;`, context);
  const element = {
    attributes: new Set(),
    get inert() { return this.attributes.has('inert'); },
    set inert(value) { this.toggleAttribute('inert', value); },
    toggleAttribute(name, force) {
      if (force) this.attributes.add(name);
      else this.attributes.delete(name);
    },
  };
  context.setOptionsPageInertReason('first-load', [element], true);
  context.setOptionsPageInertReason('confirmation', [element], true);
  context.setOptionsPageInertReason('first-load', [element], false);
  assert.equal(element.inert, true, 'finishing the load cannot release an open confirmation');
  context.setOptionsPageInertReason('confirmation', [element], false);
  assert.equal(element.inert, false, 'closing the last blocker releases the element');
});
