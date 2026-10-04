// Tests for the note a person adds to a claude button at click time: which buttons take one, what a
// note may hold, and how it joins the button's own inputs. Pure functions in extension/defaults.js —
// run with `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Same loading as tests/buttons.test.js: the manifest's order, so defaults.js has `tr` for the
// preset names it resolves lazily.
const readExtension = name => fs.readFileSync(path.join(__dirname, '../extension', name), 'utf8');
vm.runInThisContext(readExtension('i18n.js'));
vm.runInThisContext(readExtension('defaults.js'));
const { catalogueBackend } = require('./chrome-messages.js');
vm.runInThisContext('({ installMessageBackend })').installMessageBackend(catalogueBackend('en'));

// Looked up inside each test, so a missing function fails the test that needs it rather than the file
const pick = names => vm.runInThisContext(`({ ${names} })`);

// Characters are built from code points: an escape written into this file is one more layer that
// could turn into the character it names before the test ever runs.
const cp = (...points) => String.fromCodePoint(...points);

// Every shipped preset, by id. A preset added without a verdict here fails the coverage check below —
// whether a new preset starts claude is a decision, not a default.
const STARTS_CLAUDE = {
  'pr.checkout': false,
  'pr.checkoutClaude': true,
  'pr.worktreeClaude': true,
  'pr.worktree': false,
  'pr.review': true,
  'pr-list.checkoutClaude': true,
  'issue.read': true,
  'issue.startWork': true,
  'issue.open': false,
  'issue-list.triageClaude': true,
  'repo.open': false,
  'repo.openClaude': true,
  'repo.updateMain': false,
};

const allPresets = () => {
  const { BUTTON_KINDS } = pick('BUTTON_KINDS');
  return Object.values(BUTTON_KINDS).flatMap(kind => kind.presets);
};

// A plain copy of a preset's execution fields, deep-frozen: the functions under test get something
// they cannot mutate without throwing.
const frozenButton = ({ command, claudeInputs = [] }) =>
  Object.freeze({ command, claudeInputs: Object.freeze([...claudeInputs]) });

test('commandStartsClaude answers for every shipped preset', () => {
  const { commandStartsClaude } = pick('commandStartsClaude');
  const presets = allPresets();
  assert.deepEqual(
    presets.map(preset => preset.id).sort(), Object.keys(STARTS_CLAUDE).sort(),
    'a shipped preset has no verdict in this table, or the table names one that is gone',
  );
  for (const preset of presets) {
    assert.equal(commandStartsClaude(preset.command), STARTS_CLAUDE[preset.id], preset.id);
  }
  assert.equal(presets.filter(preset => commandStartsClaude(preset.command)).length, 8);
});

test('commandStartsClaude is the options warning\'s word test, false matches included', () => {
  // The predicate moved rather than changed: a command mentioning claude as a word counts, which is
  // why `echo claude` is a yes. A note sent through such a yes is lost the way a scheduled input is.
  const { commandStartsClaude } = pick('commandStartsClaude');
  assert.equal(commandStartsClaude('{cd} && claude --model opus'), true);
  assert.equal(commandStartsClaude('{cd} && echo claude'), true);
  assert.equal(commandStartsClaude('{cd} && myclaude'), false);
  assert.equal(commandStartsClaude('{cd} && claudette'), false);
  for (const notACommand of [undefined, null, 42, {}, ['claude']]) {
    assert.equal(commandStartsClaude(notACommand), false, JSON.stringify(notACommand));
  }
});

test('the claude word test has one home, and the options warning asks it', () => {
  // A lint over spellings, like the preset-lookup lint in buttons.test.js: the options page has no
  // runtime harness here. The regex literal lives in defaults.js once; every other script asks the
  // function, so the warning and the note cannot disagree about which buttons start claude.
  const regexLiteral = /\/\\bclaude\\b\//g;
  const extensionScripts = fs.readdirSync(path.join(__dirname, '../extension')).filter(name => name.endsWith('.js'));
  for (const file of extensionScripts) {
    const found = (readExtension(file).match(regexLiteral) ?? []).length;
    assert.equal(found, file === 'defaults.js' ? 1 : 0, `${file} spells the claude word test ${found} time(s)`);
  }
  const options = readExtension('options.js');
  const validation = options.slice(options.indexOf('function validateEditState('));
  assert.match(validation.slice(0, validation.indexOf('\n}\n')), /validateButtonValue\(button\)/,
    'the engine snapshot and Save no longer ask the shared validator');
  const defaults = readExtension('defaults.js');
  const validator = defaults.slice(defaults.indexOf('function validateButtonValue('));
  assert.match(validator.slice(0, validator.indexOf('\n}\n')), /commandStartsClaude\(button\.command\)/, 'the shared validator no longer uses the shared predicate');
});

test('the options warning counts inputs the way a click sends them', () => {
  // Also a lint. It counted with `trim()`, which drops a tab-only input that the send keeps and the
  // app then refuses — so the warning stayed hidden over a button that could only fail.
  const defaults = readExtension('defaults.js');
  const validation = defaults.slice(defaults.indexOf('function validateButtonValue('));
  const body = validation.slice(0, validation.indexOf('\n}\n'));
  assert.match(body, /normalizeClaudeInputs\(button\.claudeInputs\)/, 'the warning counts inputs by a rule of its own');
  assert.match(defaults, /function normalizeClaudeInputs\(inputs\)/);
  const { normalizeClaudeInputs } = pick('normalizeClaudeInputs');
  assert.deepEqual(normalizeClaudeInputs(['  command  ', '\t', '  ']), ['command', '\t']);
});

test('a button takes a note only when its command starts claude', () => {
  const { buttonTakesClaudeNote } = pick('buttonTakesClaudeNote');
  for (const preset of allPresets()) {
    assert.equal(buttonTakesClaudeNote(frozenButton(preset)), STARTS_CLAUDE[preset.id], preset.id);
  }
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd}', claudeInputs: [] })), false);
});

test('only normalized saved inputs count against the button cap', () => {
  // The note gets its own slot. Empty entries are removed by executionPayload, but U+200B is retained
  // as a saved input even though the app may drop it later.
  const { buttonTakesClaudeNote, MAX_CLAUDE_INPUTS } = pick('buttonTakesClaudeNote, MAX_CLAUDE_INPUTS');
  const atCap = Array.from({ length: MAX_CLAUDE_INPUTS }, (_, i) => `!echo ${i}`);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd} && claude', claudeInputs: [...atCap, '   '] })), true);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd} && claude', claudeInputs: [...atCap, cp(0x200B)] })), false);
});

test('the saved issue-list button with five claude inputs takes a note', () => {
  const { buttonTakesClaudeNote } = pick('buttonTakesClaudeNote');
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/saved-issue-list-buttons.json'), 'utf8'));
  const issueListButton = fixture.issueListButtons[0];
  assert.equal(buttonTakesClaudeNote(frozenButton(issueListButton)), true, 'the saved issue-list button gets a caret');
});

test('a button that is not a button takes no note', () => {
  const { buttonTakesClaudeNote } = pick('buttonTakesClaudeNote');
  for (const value of [undefined, null, 'claude', 42, [], { command: 42 }, { command: '{cd} && claude', claudeInputs: 'x' }]) {
    assert.equal(buttonTakesClaudeNote(value), false, JSON.stringify(value));
  }
});

test('a note that is not a non-empty string is refused, never read as no note', () => {
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  for (const value of [undefined, null, 42, true, {}, [], ['hello']]) {
    assert.deepEqual(claudeNoteVerdict(value), { valid: false, error: 'not-string', note: null }, JSON.stringify(value));
  }
  for (const blank of ['', ' ', '      ']) {
    assert.deepEqual(claudeNoteVerdict(blank), { valid: false, error: 'empty', note: null }, JSON.stringify(blank));
  }
});

test('a note loses ordinary spaces at its ends and nothing else', () => {
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  assert.deepEqual(claudeNoteVerdict('  look at the flaky test  '), { valid: true, error: null, note: 'look at the flaky test' });
  // A tab is a control byte: refused, not trimmed away
  assert.equal(claudeNoteVerdict(`${cp(9)}hello`).error, 'control-character');
  // A no-break space is not an ordinary space: refused at the front, not trimmed away
  assert.equal(claudeNoteVerdict(`${cp(0xA0)}hello`).error, 'leading-character');
  // Inside the note, anything printable stays exactly as typed
  assert.equal(claudeNoteVerdict(`a${cp(0xA0)}b  c`).note, `a${cp(0xA0)}b  c`);
});

test('no first character the app could strip or read as a directive gets through', () => {
  // The app trims a wider set than any JavaScript whitespace notion before it reads `!`, `/` or `#`
  // off the front — U+0085 and U+200B are the measured cases `trim()` and `\p{Z}` both miss. Every
  // scalar the app strips is in Z or C (pinned on the Swift side), so refusing all of Z and C here
  // is what keeps the first character the app classifies the one checked here.
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  for (const directive of ['!x', '/x', '#x', ' !x', '  /help', ' #memory']) {
    assert.equal(claudeNoteVerdict(directive).error, 'leading-character', JSON.stringify(directive));
  }
  for (const point of [0x85, 0x200B, 0xA0, 0x3000, 0xFEFF, 0x180E, 0x2028]) {
    assert.equal(claudeNoteVerdict(`${cp(point)}!x`).valid, false, `U+${point.toString(16).toUpperCase()}`);
  }

  const escaped = [];
  let checked = 0;
  for (let point = 0; point <= 0x10FFFF; point += 1) {
    const character = cp(point);
    if (point === 0x20 || !/[\p{Z}\p{C}]/u.test(character)) continue;
    checked += 1;
    if (claudeNoteVerdict(`${character}x`).valid) escaped.push(point.toString(16));
  }
  assert.deepEqual(escaped, [], 'a leading Z or C character was accepted');
  assert.ok(checked > 900000, `only ${checked} code points were checked`);
});

test('any closed brace span is refused, whatever is inside it', () => {
  // The app substitutes `{name}` for any name its ICU `\w` accepts — Korean names included — and has
  // no escape syntax, so the only safe judgement is structural: a `{` followed by a `}` with no `}`
  // between them. Every placeholder the app can see is such a span, and a note without one renders
  // to itself in every batch item.
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  const refused = [
    '{repo}', 'look at {number} now', 'x{cd}y', `${cp(0xC774, 0xAC70)} {${cp(0xC774, 0xAC70)}}`, '{b_1}',
    '{{repo}}', '\\{repo}', '{}', '{ a }', '{"a":1}', 'a{b}c{d}',
  ];
  for (const note of refused) {
    assert.equal(claudeNoteVerdict(note).error, 'braces', JSON.stringify(note));
  }
  for (const note of ['{ open', 'close }', '}{', 'a { b', 'set {', '} then {']) {
    assert.equal(claudeNoteVerdict(note).valid, true, JSON.stringify(note));
  }
});

test('control characters and line breaks are refused wherever they sit', () => {
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  for (const point of [0x0, 0x9, 0xA, 0xD, 0x1B, 0x7F, 0x85, 0x9B, 0x2028, 0x2029]) {
    assert.equal(claudeNoteVerdict(`a${cp(point)}b`).error, 'control-character', `U+${point.toString(16).toUpperCase()}`);
  }
  // Format characters are refused only at the front: inside, a zero-width joiner holds an emoji together
  const family = cp(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467);
  assert.deepEqual(claudeNoteVerdict(`family ${family}`), { valid: true, error: null, note: `family ${family}` });
});

test('an unpaired surrogate is refused wherever it sits, and a paired one passes', () => {
  // Half of a surrogate pair is not text: UTF-8 cannot encode it, so the byte count saw U+FFFD in its
  // place while the note kept the half, and the app's JSON parser refused a request carrying it as a
  // JSON escape (measured). It is refused where it sits — never replaced.
  const { claudeNoteVerdict } = pick('claudeNoteVerdict');
  const unpaired = [
    ['high first', `${cp(0xD800)}x`], ['low first', `${cp(0xDC00)}x`],
    ['high inside', `a${cp(0xD800)}b`], ['low inside', `a${cp(0xDC00)}b`],
    ['high last', `a${cp(0xDBFF)}`], ['low last', `a${cp(0xDFFF)}`],
    ['pair reversed', `a${cp(0xDC00)}${cp(0xD800)}b`],
  ];
  for (const [label, note] of unpaired) {
    assert.deepEqual(claudeNoteVerdict(note), { valid: false, error: 'unpaired-surrogate', note: null }, label);
  }
  const whole = [
    `ok ${cp(0x1F600)}`, `${cp(0x1F600)} first`, `family ${cp(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467)}`,
    `e${cp(0x301)} and ${cp(0x301)}alone`, cp(0x1F600).repeat(3),
  ];
  for (const note of whole) {
    const verdict = claudeNoteVerdict(note);
    assert.equal(verdict.valid, true, JSON.stringify(note));
    // What was judged is what UTF-8 carries
    assert.equal(new TextDecoder().decode(new TextEncoder().encode(verdict.note)), verdict.note);
  }
});

test('a long unfinished brace run or a long inner run of spaces is judged in linear time', () => {
  // Both were rescanned before the length check could refuse them — each `{` searched ahead for a
  // `}`, and the trailing-space trim re-matched every inner run of spaces to the end: 95 ms at 8192
  // characters, over a second from 32768 (measured). The result is `too-long` either way, so the
  // return value cannot see the cost; the time bound is what fails when either comes back.
  const n = 131072;
  // Run inside the VM so that past the bound the call is stopped, and the case that ran over is named
  const timed = (label, source) => {
    try {
      return vm.runInThisContext(source, { timeout: 1500 });
    } catch (error) {
      return assert.fail(`${label}: ${error.message}`);
    }
  };
  try {
    for (const [label, input] of [['open braces', '{'.repeat(n)], ['inner spaces', `x${' '.repeat(n - 2)}x`]]) {
      globalThis.claudeNoteCostProbe = input;
      assert.equal(timed(label, 'claudeNoteVerdict(globalThis.claudeNoteCostProbe)').error, 'too-long', label);
      // The trim is shared with the inputs every click sends
      assert.equal(timed(label, 'normalizeClaudeInputs([globalThis.claudeNoteCostProbe])').length, 1, label);
    }
  } finally {
    delete globalThis.claudeNoteCostProbe;
  }
});

test('the length limit is 4096 UTF-8 bytes of the trimmed note', () => {
  const { claudeNoteVerdict, MAX_CLAUDE_NOTE_BYTES } = pick('claudeNoteVerdict, MAX_CLAUDE_NOTE_BYTES');
  assert.equal(MAX_CLAUDE_NOTE_BYTES, 4096);
  const hangul = cp(0xAC00); // three bytes
  const emoji = cp(0x1F600); // four bytes, two UTF-16 units
  const cases = [
    ['a'.repeat(4096), true], ['a'.repeat(4097), false],
    [hangul.repeat(1365), true], [hangul.repeat(1366), false],
    [emoji.repeat(1024), true], [emoji.repeat(1025), false],
    [`${' '.repeat(8)}${'a'.repeat(4096)}${' '.repeat(8)}`, true],
  ];
  for (const [note, valid] of cases) {
    const verdict = claudeNoteVerdict(note);
    assert.equal(verdict.valid, valid, `${new TextEncoder().encode(note).length} bytes`);
    if (!valid) assert.equal(verdict.error, 'too-long');
  }
});

test('a refusal is one code from a closed list, never a sentence', () => {
  // The content script turns the code into a localized message and the worker into an English
  // diagnostic; the verdict itself says nothing a person reads.
  const { claudeNoteVerdict, CLAUDE_NOTE_ERRORS } = pick('claudeNoteVerdict, CLAUDE_NOTE_ERRORS');
  assert.ok(Object.isFrozen(CLAUDE_NOTE_ERRORS));
  for (const code of CLAUDE_NOTE_ERRORS) assert.match(code, /^[a-z]+(?:-[a-z]+)*$/);
  const samples = [undefined, '', `a${cp(0xD800)}b`, `a${cp(0xA)}b`, '!x', '{repo}', 'a'.repeat(4097)];
  const produced = samples.map(sample => claudeNoteVerdict(sample).error);
  assert.deepEqual([...new Set(produced)].sort(), [...CLAUDE_NOTE_ERRORS].sort(), 'a code is never produced, or one is missing from the list');
});

test('the note joins the button\'s own inputs once, at the end, and the button is untouched', () => {
  const { executionPayload, executionPayloadWithNote, buttonFingerprint } =
    pick('executionPayload, executionPayloadWithNote, buttonFingerprint');
  const note = 'check the retry path first';
  const buttons = [
    ...allPresets().filter(preset => STARTS_CLAUDE[preset.id]).map(frozenButton),
    frozenButton({ command: '{cd} && claude', claudeInputs: ['  !gh pr diff {number}  ', '', '   ', '/review'] }),
  ];
  for (const button of buttons) {
    const before = JSON.stringify(button);
    const fingerprint = buttonFingerprint(button);
    const payload = executionPayloadWithNote(button, note);
    assert.deepEqual(payload, {
      command: button.command,
      claudeInputs: [...executionPayload(button).claudeInputs, note],
    }, button.command);
    assert.equal(payload.claudeInputs.filter(input => input === note).length, 1);
    assert.equal(payload.claudeInputs.at(-1), note);
    assert.equal(JSON.stringify(button), before, 'the stored button changed');
    assert.equal(buttonFingerprint(button), fingerprint, 'the fingerprint of what was drawn moved');
    assert.notEqual(payload.claudeInputs, button.claudeInputs, 'the payload shares the stored array');
  }
});

// --- The popover's pure parts ---

const PR_7 = { kind: 'pr', owner: 'o', repo: 'r', number: '7' };

test('a popover lists the inputs a note follows exactly as the click sends them, and the fingerprint vouches for that list', () => {
  const { claudeInputsBeforeNote, executionPayloadWithNote, buttonFingerprint } =
    pick('claudeInputsBeforeNote, executionPayloadWithNote, buttonFingerprint');
  const tab = cp(0x9);
  const buttons = [
    frozenButton({ command: '{cd} && claude' }),
    frozenButton({ command: '{cd} && claude', claudeInputs: [] }),
    frozenButton({ command: 'claude', claudeInputs: ['!gh pr view {number} --comments', '!gh pr diff {number}', '!git log --oneline -5'] }),
    frozenButton({ command: 'claude', claudeInputs: ['  !echo padded  ', '', '   ', `${tab}!echo tab`, 'review {branch} against {main}'] }),
    ...allPresets().filter(preset => STARTS_CLAUDE[preset.id]).map(frozenButton),
  ];
  for (const button of buttons) {
    const before = claudeInputsBeforeNote(button);
    // What goes in front of the note is this list, in this order, and nothing else
    assert.deepEqual(before, executionPayloadWithNote(button, 'look here').claudeInputs.slice(0, -1));
    // And it is the list the drawing's fingerprint names, so a click after storage changed is refused
    assert.deepEqual(before, JSON.parse(buttonFingerprint(button)).claudeInputs);
  }
  // As stored: nothing filled in, only ordinary spaces off the ends, and empty inputs are not listed
  assert.deepEqual(claudeInputsBeforeNote(buttons[3]), ['!echo padded', `${tab}!echo tab`, 'review {branch} against {main}']);
  assert.deepEqual(claudeInputsBeforeNote(buttons[0]), []);
  assert.deepEqual(claudeInputsBeforeNote(buttons[1]), []);
});

test('a click without a note sends the message it sent before notes existed, byte for byte', () => {
  const { buildButtonMessage } = pick('buildButtonMessage');
  const shown = '{"command":"{cd} && claude","claudeInputs":[]}';
  // What the content script sent until now, in its key order
  const before = { action: 'execute_command', buttonIndex: 2, shown, target: PR_7 };
  const message = buildButtonMessage('execute_command', 2, shown, PR_7);
  assert.equal(JSON.stringify(message), JSON.stringify(before));
  assert.equal(Object.hasOwn(message, 'note'), false);
});

test('a click with a note carries it last, and only an absent note is no note', () => {
  const { buildButtonMessage } = pick('buildButtonMessage');
  const message = buildButtonMessage('execute_repo_command', 0, 'fingerprint', PR_7, 'look here');
  assert.deepEqual(Object.keys(message), ['action', 'buttonIndex', 'shown', 'target', 'note']);
  assert.equal(message.note, 'look here');
  // The worker judges a present key whatever it holds, so nothing but `undefined` may drop it
  for (const note of ['', null, 0]) {
    assert.equal(Object.hasOwn(buildButtonMessage('execute_command', 0, 'fingerprint', PR_7, note), 'note'), true);
  }
});

test('a split button is named by its page, kind, index and what it runs, never by a DOM node', () => {
  const { splitButtonIdentity } = pick('splitButtonIdentity');
  const identity = splitButtonIdentity(PR_7, 'pr', 0, 'fingerprint');
  assert.equal(typeof identity, 'string');
  assert.equal(splitButtonIdentity({ ...PR_7 }, 'pr', 0, 'fingerprint'), identity, 'a redrawn button is the same button');
  const others = [
    splitButtonIdentity({ ...PR_7, number: '8' }, 'pr', 0, 'fingerprint'),
    splitButtonIdentity({ ...PR_7, owner: 'o2' }, 'pr', 0, 'fingerprint'),
    splitButtonIdentity(PR_7, 'repo', 0, 'fingerprint'),
    splitButtonIdentity(PR_7, 'pr', 1, 'fingerprint'),
    splitButtonIdentity(PR_7, 'pr', 0, 'other fingerprint'),
  ];
  for (const other of others) assert.notEqual(other, identity);
  assert.equal(new Set(others).size, others.length);
});

test('a split button runs once at a time, and a stale answer or timer cannot touch a later run', () => {
  const { createSplitButtonRuns } = pick('createSplitButtonRuns');
  const runs = createSplitButtonRuns();
  assert.equal(runs.phaseOf('a'), null);
  const first = runs.start('a');
  assert.equal(typeof first, 'number');
  assert.equal(runs.phaseOf('a'), 'busy');
  assert.equal(runs.start('a'), null, 'a second run started while the first was in flight');
  assert.notEqual(runs.start('b'), null, 'one button held another');
  assert.equal(runs.finish('a', first, 'done'), true);
  assert.equal(runs.phaseOf('a'), 'done');
  // The outcome marker is only shown, not held: a new run may start while it is up
  const second = runs.start('a');
  assert.notEqual(second, null);
  assert.equal(runs.clear('a', first), false, 'the first run\'s timer cleared the second run');
  assert.equal(runs.finish('a', first, 'error'), false, 'the first run\'s answer finished the second run');
  assert.equal(runs.phaseOf('a'), 'busy');
  assert.equal(runs.finish('a', second, 'error'), true);
  assert.equal(runs.clear('a', second), true);
  assert.equal(runs.phaseOf('a'), null);
});

test('a run refused before it sent keeps its reason for its own marker only: not for the next run, whatever the old timer does', () => {
  // The reviewer's sequence: the body pressed with no row selected, the selection fixed while its ❌ is
  // up, a note sent, the refused run's timer coming due while the note is in flight, and the note failing
  const { createSplitButtonRuns } = pick('createSplitButtonRuns');
  const runs = createSplitButtonRuns();
  const notice = { messageKey: 'ext.list.batch.selection.empty', args: [] };
  const refused = runs.start('list');
  assert.equal(runs.finish('list', refused, 'error', notice), true);
  assert.equal(runs.phaseOf('list'), 'error');
  assert.deepEqual(runs.reasonOf('list'), notice);
  const sent = runs.start('list');
  assert.equal(runs.phaseOf('list'), 'busy');
  assert.equal(runs.reasonOf('list'), null, "the note's run shows the refusal before it");
  assert.equal(runs.clear('list', refused), false);
  assert.equal(runs.reasonOf('list'), null);
  assert.equal(runs.finish('list', sent, 'error'), true);
  assert.equal(runs.reasonOf('list'), null, "the note's failure shows the refusal before it");
  assert.equal(runs.clear('list', sent), true);
  assert.equal(runs.reasonOf('list'), null);
  assert.equal(runs.reasonOf('never started'), null);
});

test('a run holds the page its message goes to, not the page its button was drawn on', () => {
  const { drawingIdentityOn, splitButtonRun, splitButtonIdentity, buildButtonMessage } =
    pick('drawingIdentityOn, splitButtonRun, splitButtonIdentity, buildButtonMessage');
  const drawing = { action: 'execute_command', kind: 'pr', index: 0, shown: 'fingerprint' };
  const PR_8 = { ...PR_7, number: '8' };
  const run = splitButtonRun(drawing, PR_8, 'look here');
  assert.deepEqual(run.message, buildButtonMessage('execute_command', 0, 'fingerprint', PR_8, 'look here'));
  // One target makes both halves: what is held is what is sent
  assert.equal(run.identity, drawingIdentityOn(drawing, run.message.target));
  assert.equal(run.identity, splitButtonIdentity(PR_8, 'pr', 0, 'fingerprint'));
  assert.notEqual(run.identity, drawingIdentityOn(drawing, PR_7));
  assert.equal(Object.hasOwn(splitButtonRun(drawing, PR_8).message, 'note'), false);
});

test('a list run sends the batch it sent before, with a note only when there is one, and holds the list page', () => {
  const { splitButtonRun, drawingIdentityOn, buildListBatchMessage, LIST_BATCH_ACTION } =
    pick('splitButtonRun, drawingIdentityOn, buildListBatchMessage, LIST_BATCH_ACTION');
  const list = { kind: 'pr-list', owner: 'o', repo: 'r', number: null };
  const selected = [{ key: 'o/r/pr/7', title: 'Seven' }, { key: 'o/r/pr/8', title: 'Eight' }];
  const drawing = { action: LIST_BATCH_ACTION, kind: 'pr-list', index: 1, shown: 'fingerprint' };
  const run = splitButtonRun(drawing, list, undefined, selected);
  // What a list click sent until now, in its key order
  const before = { action: 'execute_list_batch', buttonIndex: 1, shown: 'fingerprint', resultKeyProtocol: 1, target: list, selected };
  assert.equal(JSON.stringify(run.message), JSON.stringify(before));
  assert.equal(JSON.stringify(run.message), JSON.stringify(buildListBatchMessage(1, 'fingerprint', list, selected)));
  assert.equal(run.identity, drawingIdentityOn(drawing, list));
  const withNote = splitButtonRun(drawing, list, 'look here', selected).message;
  assert.deepEqual(Object.keys(withNote), [...Object.keys(before), 'note']);
  assert.equal(withNote.note, 'look here');
  // A list button and a header button with the same index and fingerprint are two buttons
  assert.notEqual(run.identity, drawingIdentityOn({ ...drawing, kind: 'pr', action: 'execute_command' }, list));
});

test('a drawing that outlived a page change holds and shows the run of the page it now sends for', () => {
  // The reviewer's reproduction, measured in a browser: drawn on PR 86, the page moved to PR 87 with
  // nothing taking the button away, the body pressed, and the header rebuilt mid-request — the rebuilt
  // button was free, and a second press sent the same PR 87 request again
  const { createSplitButtonRuns, drawingIdentityOn, splitButtonRun } =
    pick('createSplitButtonRuns, drawingIdentityOn, splitButtonRun');
  const runs = createSplitButtonRuns();
  const PR_8 = { ...PR_7, number: '8' };
  const drawn = { action: 'execute_command', kind: 'pr', index: 0, shown: 'fingerprint' }; // on PR 7
  const sent = [];
  const press = (drawing, onScreen) => {
    const run = splitButtonRun(drawing, onScreen, undefined);
    if (runs.start(run.identity) !== null) sent.push(run.message);
  };
  press(drawn, PR_8);
  const rebuilt = { ...drawn }; // GitHub rebuilt the header, now on PR 8
  assert.equal(runs.phaseOf(drawingIdentityOn(rebuilt, PR_8)), 'busy', 'the rebuilt button is free');
  assert.equal(runs.phaseOf(drawingIdentityOn(drawn, PR_8)), 'busy', 'the surviving drawing does not show its run');
  press(rebuilt, PR_8);
  press(drawn, PR_8);
  assert.equal(sent.length, 1, 'the same request went out twice');
  assert.deepEqual(sent[0].target, PR_8);
  assert.equal(runs.phaseOf(drawingIdentityOn(drawn, PR_7)), null, 'another page was held');
});

test('the control-character rule is one function, and the verdict refuses with it', () => {
  const { claudeNoteHasControlCharacter, claudeNoteVerdict } = pick('claudeNoteHasControlCharacter, claudeNoteVerdict');
  const refused = [[0xA], [0xD, 0xA], [0xD], [0x9], [0x0], [0x1B], [0x7F], [0x85], [0x9B], [0x2028], [0x2029]];
  for (const points of refused) {
    const text = `alpha${cp(...points)}beta`;
    assert.equal(claudeNoteHasControlCharacter(text), true, JSON.stringify(text));
    assert.equal(claudeNoteVerdict(text).error, 'control-character', JSON.stringify(text));
  }
  for (const text of ['alpha beta', `family ${cp(0x1F468, 0x200D, 0x1F469)}`, `e${cp(0x301)}`, `a${cp(0xA0)}b`, `a${cp(0x200B)}b`]) {
    assert.equal(claudeNoteHasControlCharacter(text), false, JSON.stringify(text));
  }
  const defaults = readExtension('defaults.js');
  const verdict = defaults.slice(defaults.indexOf('function claudeNoteVerdict('));
  assert.match(verdict.slice(0, verdict.indexOf('\n}\n')), /if \(claudeNoteHasControlCharacter\(trimmed\)\) return refuse\('control-character'\);/);
});

test('every refusal code has its own message in every language the content script can paint', () => {
  const { CLAUDE_NOTE_ERRORS, MAX_CLAUDE_NOTE_BYTES, claudeNoteRefusalNotice } =
    pick('CLAUDE_NOTE_ERRORS, MAX_CLAUDE_NOTE_BYTES, claudeNoteRefusalNotice');
  const locales = ['en', 'ko', 'ja', 'zh_CN', 'zh_TW'];
  const catalogues = Object.fromEntries(locales.map(locale => [locale, JSON.parse(readExtension(`_locales/${locale}/messages.json`))]));
  const keys = new Set();
  for (const code of CLAUDE_NOTE_ERRORS) {
    const notice = claudeNoteRefusalNotice(code);
    assert.match(notice?.messageKey ?? '', /^ext\.claudeNote\.refused\.[A-Za-z]+$/, code);
    keys.add(notice.messageKey);
    for (const locale of locales) {
      const entry = catalogues[locale][notice.messageKey.replace(/\./g, '_')];
      assert.ok(entry && entry.message.trim(), `${locale} has no message for ${code}`);
    }
  }
  assert.equal(keys.size, CLAUDE_NOTE_ERRORS.length, 'two codes share one message');
  assert.deepEqual(claudeNoteRefusalNotice('too-long').args, [MAX_CLAUDE_NOTE_BYTES]);
  // A code this content script does not know yet has no message of its own; the page falls back
  assert.equal(claudeNoteRefusalNotice('no-such-code'), null);
});

// --- The content script's wiring: lints, not proofs ---
// The content page has no DOM harness (docs/context/testing.md), so what the pure parts above cannot
// carry is pinned as source structure. Every lint first finds its subject — a lint that found nothing
// would pass by saying nothing.
const content = () => readExtension('content.js');
const bodyOf = (source, signature) => {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `${signature} is gone`);
  const rest = source.slice(start);
  return rest.slice(0, rest.indexOf('\n}\n') + 2);
};
const count = (text, needle) => text.split(needle).length - 1;

test('every split button run goes through one function, held before its first await (lint)', () => {
  const source = content();
  const run = bodyOf(source, 'async function runSplitButton(');
  // The identity held and the message sent come out of one call, from the one target the run carries
  const made = run.indexOf('const run = splitButtonRun(view, target, note, selected);');
  const held = run.indexOf('splitButtonRuns.start(run.identity)');
  const refused = run.indexOf('if (token === null) return;');
  const firstAwait = run.indexOf('await ');
  assert.ok(made !== -1 && held > made && refused > held && firstAwait > refused, 'the run is held after an await, or not at all');
  assert.ok(run.includes('await sendListBatchMessage(run.message)'), 'a list run sends something other than what it holds');
  assert.ok(run.includes('await sendButtonMessage(run.message);'), 'a header run sends something other than what it holds');
  assert.equal(count(run, 'await '), 2, 'the run waits on something else too');
  assert.equal(count(run, 'splitButtonRun('), 1);
  assert.equal(count(run, 'drawingIdentityOn('), 0, 'the run computes a second identity');
  // Declared once, and entered from a body's click — header and list alike — and from a note's send
  assert.equal(count(source, 'runSplitButton('), 3);
  assert.match(bodyOf(source, 'function splitButton('), /onUserClick\(body, \(\) => runSplitButton\(view, /);
  assert.match(bodyOf(source, 'function submitNote('), /runSplitButton\(popover\.view, /);
  // And a split button's message leaves from one of two places, one per kind of message
  assert.equal(count(source, 'sendButtonMessage('), 2, 'declared once and called once');
  assert.equal(count(source, 'sendListBatchMessage('), 2, 'declared once and called once');
  assert.equal(count(source, 'chrome.runtime.sendMessage('), 2, 'a message leaves some other way');
  assert.ok(bodyOf(source, 'async function sendButtonMessage(').includes('chrome.runtime.sendMessage('));
  assert.ok(bodyOf(source, 'async function sendListBatchMessage(').includes('chrome.runtime.sendMessage('));
});

test('a list button is a split button: its rows are read once as the run starts, before any await (lint)', () => {
  const source = content();
  const create = bodyOf(source, 'function createListBatchButton(');
  assert.match(create, /return splitButton\(button, buttonConfig, index, \{/);
  assert.match(create, /action: LIST_BATCH_ACTION,/);
  assert.match(create, /look: 'pill'/);
  assert.equal(count(create, 'onUserClick('), 0, 'the list body has a click path of its own');
  const run = bodyOf(source, 'async function runSplitButton(');
  const read = run.indexOf('const selected = view.list ? readSelectedListRows(document, ');
  assert.ok(read !== -1 && read < run.indexOf('splitButtonRuns.start(') && read < run.indexOf('await '), 'the rows are read after the run is held or after an await');
  assert.equal(count(run, 'readSelectedListRows('), 1, 'the rows are read more than once');
  // A selection the batch cannot take: in the popover, its line and nothing sent; on the body, the marker
  const refusedInPopover = run.indexOf('showNoteStatus(popover, listSelectionNoticeText(notice), true);');
  assert.ok(refusedInPopover !== -1 && refusedInPopover < run.indexOf('splitButtonRuns.start('), 'a refused selection reaches the send');
  // The answer is read the way the list always read it: result view, then row badges
  assert.ok(run.includes('const result = listBatchResultView(view.resultIdentity, selected, outcome);'));
  assert.ok(run.includes('renderListBatchResultView(result, view.kind, generation);'));
  assert.equal(count(source, 'runListBatchCommand'), 0, 'the old list send path is still there');
});

test("a run ends in the phase its answer gave, and that one phase is what the body shows and the popover obeys (lint)", () => {
  // A batch the app answered with a failure arrives inside an outer success, and a list run's phase is
  // its result view's. With the list branch's assignment gone, a partly failed batch drew its badges
  // while the body showed ✅ and the popover closed and dropped the note — and every test passed. The
  // mapping from the answer to the view's phase is `listBatchResultView`'s own tests; this pins that the
  // run takes that phase and that the one variable ends the run, settles the popover and times the marker.
  const source = content();
  const run = bodyOf(source, 'async function runSplitButton(');
  // Every write of the phase, in order: the default, a refused selection, the list's answer, a failure
  const writes = [...run.matchAll(/^\s*(?:let )?phase = [^;\n]+;/gm)].map(match => match[0].trim());
  assert.deepEqual(writes, ["let phase = 'done';", "phase = 'error';", 'phase = result.phase;', "phase = 'error';"], 'the phase is written differently');
  const view = run.indexOf('const result = listBatchResultView(view.resultIdentity, selected, outcome);');
  const answer = run.indexOf('        phase = result.phase;\n');
  const single = run.indexOf('await sendButtonMessage(run.message);');
  assert.ok(view !== -1 && answer > view && single > answer, "a list run's phase is not its result view's, or is taken outside the list branch");
  const end = run.slice(run.indexOf("console.error('command error:', failure);"));
  for (const read of ['splitButtonRuns.finish(run.identity, token, phase, reason);', 'if (popover) settleNoteSend(popover, phase, typed);', '}, view.delays[phase]);']) {
    assert.ok(end.includes(read), `the run does not end with ${read}`);
  }
  // And the popover closes and forgets the note only on `done`; anything else keeps the note, open or not
  assert.ok(bodyOf(source, 'function settleNoteSend(').includes(
    "  if (phase === 'done') {\n    if (notePopover === popover) closeNotePopover();\n    noteDrafts.delete(popover.identity);\n    return;\n  }\n  noteDrafts.set(popover.identity, typed);\n",
  ), 'the popover is settled by something other than whether the run is done');
});

test('a list selection notice is drawn in the popover through its own literal lookups (lint)', () => {
  const text = bodyOf(content(), 'function listSelectionNoticeText(');
  assert.ok(text.includes("tr('ext.list.batch.selection.empty')"));
  assert.ok(text.includes("tr('ext.list.batch.selection.tooMany', notice.args[0], notice.args[1])"));
});

test('a drawing shows, and its caret and send button obey, the run of the page on screen now (lint)', () => {
  const source = content();
  const head = bodyOf(source, 'function splitButton(');
  const takes = head.indexOf('if (!buttonTakesClaudeNote(config))');
  const caret = head.indexOf('createNoteCaret(view, look)');
  assert.ok(takes !== -1 && caret > takes, 'the caret is drawn before, or without, asking whether the button takes a note');
  assert.equal(count(source, 'createNoteCaret('), 2, 'the caret is created somewhere else too');
  assert.equal(count(head, 'paintSplitButton(view)'), 2, 'a drawing does not start from its run');
  // A drawing keeps no identity of its own: the page it was drawn on can be gone
  assert.equal(count(source, 'view.identity'), 0, 'a drawing carries the identity of the page it was drawn on');
  const onScreen = 'splitButtonRuns.phaseOf(drawingIdentityOn(view, pageTargetOfUrl(location.href)))';
  const paint = bodyOf(source, 'function paintSplitButton(');
  assert.ok(paint.includes('  const onScreen = drawingIdentityOn(view, pageTargetOfUrl(location.href));\n  const phase = splitButtonRuns.phaseOf(onScreen);\n'), 'a drawing is painted from another page');
  assert.ok(bodyOf(source, 'function toggleNotePopover(').includes(`${onScreen} === 'busy'`), 'the caret obeys another page');
  assert.ok(bodyOf(source, 'function syncNoteSend(').includes(
    "splitButtonRuns.phaseOf(drawingIdentityOn(popover.view, pageTargetOfUrl(location.href))) === 'busy'",
  ), 'the send button obeys another page');
  // After a run moves, every drawing on screen is painted again, whichever page it was drawn for
  assert.match(bodyOf(source, 'function repaintSplitButtons('), /else paintSplitButton\(view\);/);
});

test('the popover lists the inputs a note follows above it, in order, as text under their label, for header and list buttons alike (lint)', () => {
  const source = content();
  // Made from the one stored button at the one moment the fingerprint is, for every split button
  const head = bodyOf(source, 'function splitButton(');
  assert.ok(head.includes('shown: buttonFingerprint(config), before: claudeInputsBeforeNote(config),'), 'the list is not made beside the fingerprint, from the same button');
  assert.equal(count(source, 'claudeInputsBeforeNote('), 1, 'the list is made somewhere else too');
  // Drawn only when there is something to list, and above the note's own row
  const open = bodyOf(source, 'function openNotePopover(');
  const drawn = open.indexOf('  if (view.before.length) root.append(noteBeforeList(view.before));\n');
  const row = open.indexOf('  root.append(row, status);\n');
  assert.ok(drawn !== -1 && row > drawn, 'the list is drawn when empty, under the note, or not at all');
  assert.equal(count(source, 'noteBeforeList('), 2, 'the list is drawn from somewhere else too');
  // An ordered list named by its label, each input written as text, in the order given
  const list = bodyOf(source, 'function noteBeforeList(');
  assert.ok(list.includes("const list = document.createElement('ol');"), 'the order is not an ordered list');
  assert.ok(list.includes('label.id = NOTE_BEFORE_LABEL_ID;') && list.includes("list.setAttribute('aria-labelledby', NOTE_BEFORE_LABEL_ID);"), 'the list is not named by its label');
  assert.ok(list.includes("label.textContent = tr('ext.claudeNote.before');"));
  assert.ok(list.includes('  for (const input of inputs) {\n') && list.includes("    const item = document.createElement('li');\n") && list.includes('    item.textContent = input;\n'), 'an input is not written as a list item of text, in order');
  // Text to read and copy, not a field: nothing else is created, and nothing is made focusable or editable
  const created = [...list.matchAll(/document\.createElement\('(\w+)'\)/g)].map(match => match[1]);
  assert.deepEqual(created, ['div', 'div', 'ol', 'li'], 'the list is drawn with something besides text elements');
  assert.doesNotMatch(list, /contenteditable|tabindex/i, 'an input shown before the note can be focused or edited');
  // Nothing this script draws is markup
  assert.doesNotMatch(source, /\.(?:innerHTML|outerHTML)\s*\+?=|insertAdjacentHTML\s*\(|document\.write\s*\(/, 'something is written as markup');
  // A long input wraps inside the popover's width, and a long list scrolls on its own
  assert.match(source, /const NOTE_BEFORE_LIST_STYLE = `[^`]*overflow-wrap: anywhere;/);
  assert.match(source, /const NOTE_BEFORE_LIST_STYLE = `[^`]*overflow-y: auto;/);
});

test("a split button's tooltip is painted from its run like the rest of it, and nothing else writes it (lint)", () => {
  // A refused selection's reason was written into the body's tooltip and put back by the refused run's
  // timer, which stands down once a later run has started — so the reason stayed on the next run's ⏳
  // and on its outcome. The reason now lives in the run, and the paint derives the tooltip from it.
  const source = content();
  const paint = bodyOf(source, 'function paintSplitButton(');
  assert.ok(paint.includes('view.body.title = splitButtonTooltip(view, splitButtonRuns.reasonOf(onScreen));'), 'the tooltip is not painted from the run on screen');
  assert.match(bodyOf(source, 'function splitButtonTooltip('), /return reason \? listSelectionNoticeText\(reason\) : view\.label;/);
  // Every tooltip this script writes, by receiver: a split button body's only in the paint
  const receivers = [...source.matchAll(/([\w.]+)\.title\s*=(?!=)/g)].map(match => match[1]);
  assert.deepEqual(receivers.sort(), ['badge', 'caret', 'checkbox', 'view.body'], 'a tooltip is written outside the paint');
  // A run's end writes nothing to the page itself: it records the refusal with the phase, and its timer
  // clears the run and paints
  const run = bodyOf(source, 'async function runSplitButton(');
  assert.ok(run.includes('splitButtonRuns.finish(run.identity, token, phase, reason);'), 'the refusal is not kept with the run');
  assert.ok(run.includes('    if (splitButtonRuns.clear(run.identity, token)) repaintSplitButtons();\n  }, view.delays[phase]);'), 'the timer does more than clear and paint');
  assert.equal(count(source, 'restoreTitle'), 0);
});

test('a multi-line paste or drop is refused as it arrives by the verdict\'s own rule, never let in changed (lint)', () => {
  const source = content();
  const guard = bodyOf(source, 'function refuseControlCharacterInsert(');
  const tested = guard.indexOf('claudeNoteHasControlCharacter(original)');
  const stopped = guard.indexOf('event.preventDefault();');
  assert.ok(tested !== -1 && stopped > tested, 'the insert is not tested with the verdict\'s rule before it is stopped');
  assert.match(guard, /noteRefusalText\(claudeNoteRefusalNotice\('control-character'\)\)/);
  assert.doesNotMatch(guard, /\.value\s*=/, 'a changed replacement is written into the input');
  const open = bodyOf(source, 'function openNotePopover(');
  assert.ok(open.includes("input.addEventListener('paste', event => refuseControlCharacterInsert(popover, event, event.clipboardData?.getData('text/plain')));"));
  assert.ok(open.includes("input.addEventListener('drop', event => refuseControlCharacterInsert(popover, event, event.dataTransfer?.getData('text/plain')));"));
});

test('the popover is placed again whenever its size changes, and never grows past the viewport (lint)', () => {
  const source = content();
  const open = bodyOf(source, 'function openNotePopover(');
  assert.ok(open.includes('popover.onSizeChange = new ResizeObserver(() => placeNotePopover(popover));'));
  assert.ok(open.includes('popover.onSizeChange.observe(root);'));
  assert.match(bodyOf(source, 'function closeNotePopover('), /popover\.onSizeChange\.disconnect\(\);/);
  assert.match(bodyOf(source, 'function placeNotePopover('), /popover\.root\.style\.maxHeight = `\$\{maxHeight\}px`;/);
  assert.match(source, /const NOTE_POPOVER_STYLE = `[^`]*overflow: auto;/);
});

test('a note is for the page its popover opened on, read once, and judged before anything is sent (lint)', () => {
  const source = content();
  assert.match(bodyOf(source, 'function openNotePopover('), /const target = pageTargetOfUrl\(location\.href\);/);
  const submit = bodyOf(source, 'function submitNote(');
  assert.equal(count(submit, '.value'), 1, 'the note is read more than once, or not at all');
  const judged = submit.indexOf('const verdict = claudeNoteVerdict(typed);');
  assert.ok(judged !== -1 && judged < submit.indexOf('runSplitButton('), 'sent before it is judged, or never judged');
  assert.match(submit, /note: verdict\.note/);
  assert.match(submit, /target: popover\.target/);
  assert.doesNotMatch(submit, /location\.|pageTargetOfUrl/);
  assert.doesNotMatch(bodyOf(source, 'async function runSplitButton('), /\.value\b|location\.|pageTargetOfUrl/);
});

test('Enter sends only for a person and never mid-composition, and keys stop at the popover (lint)', () => {
  const open = bodyOf(content(), 'function openNotePopover(');
  const enter = open.slice(open.indexOf("input.addEventListener('keydown'"));
  const handler = enter.slice(0, enter.indexOf('});'));
  assert.ok(handler.includes("event.key !== 'Enter' || event.isComposing"), 'Enter is taken while composing');
  const guarded = handler.indexOf('if (isUserGesture(event)) submitNote(popover);');
  assert.ok(guarded !== -1 && count(handler, 'submitNote(') === 1, 'a synthetic Enter sends');
  assert.ok(open.includes("for (const type of ['keydown', 'keyup', 'keypress']) root.addEventListener(type, event => event.stopPropagation());"));
  assert.match(open, /onUserClick\(send, \(\) => submitNote\(popover\)\)/);
});

test('a held Enter sends once: its repeats lose their default and send nothing, in the box and on the send button (lint)', () => {
  // A key held down repeats its keydown, as trusted as the first one. The note and the focus stay after a
  // failed send and a run in `error` takes a new start, so a repeat that arrived after the answer sent the
  // same note again — a partly failed batch would have run its successful items a second time.
  const open = bodyOf(content(), 'function openNotePopover(');
  const enter = open.slice(open.indexOf("input.addEventListener('keydown'"));
  const handler = enter.slice(0, enter.indexOf('});'));
  const composing = handler.indexOf("if (event.key !== 'Enter' || event.isComposing) return;");
  const prevented = handler.indexOf('event.preventDefault();');
  const repeat = handler.indexOf('if (event.repeat) return;');
  const sent = handler.indexOf('submitNote(popover)');
  // An Enter that ends an IME composition returns before the default is taken, so the page leaves that key
  // to the IME; only a key that got past it loses its default
  assert.ok(composing !== -1 && prevented > composing, 'an Enter that ends a composition loses its default');
  assert.ok(prevented !== -1 && repeat > prevented && sent > repeat, 'a repeated Enter sends, or keeps its default');
  // The send button is activated from the keyboard through a click, and a click says nothing of repeats,
  // so the button's own repeated keydown loses its default before it can activate it
  assert.ok(open.includes("send.addEventListener('keydown', event => { if (event.repeat) event.preventDefault(); });"), 'a held key can activate the send button again');
});

test('every refusal the notice names is drawn through its own literal lookup (lint)', () => {
  const { CLAUDE_NOTE_ERRORS, claudeNoteRefusalNotice } = pick('CLAUDE_NOTE_ERRORS, claudeNoteRefusalNotice');
  const source = content();
  for (const code of CLAUDE_NOTE_ERRORS) {
    const { messageKey } = claudeNoteRefusalNotice(code);
    assert.equal(count(source, `'${messageKey}': `), 1, `${code} has no row in NOTE_REFUSAL_TEXT`);
    assert.equal(count(source, `tr('${messageKey}'`), 1, `${code} is not drawn through a literal lookup`);
  }
});

test('every insert pass asks whether the page moved before it draws, so a move the history wrappers missed is seen (lint)', () => {
  // A navigation made through a `pushState` the wrappers do not wrap left the previous PR's buttons —
  // and an open popover — on the next PR. The poll, the observer and GitHub's navigation events all run
  // an insert pass, so the pass is where such a move is noticed, through the one function that removes
  // what belonged to the old page. What this pins is the call and its order; it cannot show that GitHub's
  // navigations reach an insert pass. The poll is what keeps passes coming — about every second in a
  // foreground tab, an interval rather than a deadline — and it is pinned here too.
  const source = content();
  const insert = bodyOf(source, 'async function tryInsertButton(');
  const reconcile = insert.indexOf('onUrlChange();');
  assert.ok(reconcile !== -1, 'an insert pass does not ask whether the page moved');
  assert.ok(reconcile < insert.indexOf('forgetDetachedSplitButtons();') && reconcile < insert.indexOf('await '), 'the pass draws before it asks');
  assert.match(source, /setInterval\(tryInsertButton, 1000\);/);
  // Asked on every pass, it has to stay a no-op for a URL that has not moved, and to remove only on a new target
  const change = bodyOf(source, 'function onUrlChange(');
  assert.ok(change.includes('function onUrlChange() {\n  if (location.href === lastUrl) return;\n'), 'onUrlChange does more than nothing for an unmoved URL');
  assert.match(change, /if \(!sameTarget\(target, lastTarget\)\) removeInsertedButtons\(\);/);
});

test('a pass that started on a page draws nothing once that page is gone: every await in it is followed by a page check (lint)', () => {
  // An insert pass reads the page, waits for storage, then draws. A pass that waited on PR A and resumed
  // after the page had moved to B drew A's buttons onto B, and the pass that started on B then found
  // buttons there and drew nothing. Every removal moves the page generation on; a pass holds the one it
  // started with and asks again after every await, before it reads or writes the page. This pins where
  // the checks sit. The interleavings themselves were played against the real script out of tree; that
  // GitHub's pages reach these passes at all is outside what either can show.
  const source = content();
  // The generation moves in one place: the removal
  const generationWrites = source.match(/\bpageGeneration\s*(?:[-+*/]?=(?!=)|\+\+|--)|(?:\+\+|--)\s*pageGeneration\b/g) ?? [];
  assert.deepEqual(generationWrites, ['pageGeneration =', 'pageGeneration +='], 'the page generation is not declared once and moved in exactly one place');
  assert.ok(bodyOf(source, 'function removeInsertedButtons(').includes('pageGeneration += 1;'), 'a removal leaves the page generation where it was');
  // The check reconciles first, so a move nothing has reported yet counts as well
  assert.ok(bodyOf(source, 'function pageChangedSince(').startsWith('function pageChangedSince(generation) {\n  onUrlChange();\n  return generation !== pageGeneration;\n}'), 'the page check does not reconcile, or compares something else');
  // The pass holds the generation of the page it has just reconciled to, before anything waits
  const pass = bodyOf(source, 'async function tryInsertButton(');
  const held = pass.indexOf('  onUrlChange();\n  const generation = pageGeneration;\n');
  assert.ok(held !== -1 && held < pass.indexOf('await '), 'the pass holds no generation, or holds it before reconciling or after waiting');
  // After its first await it reads and draws nothing until the page is checked, and what it calls gets its generation
  assert.ok(pass.includes('result = await tryInsertRepoButtons(target, generation) || result;'));
  const passCheck = pass.indexOf('if (pageChangedSince(generation)) return result;');
  assert.ok(passCheck > pass.indexOf('await '), 'the pass does not check the page after its first await');
  for (const call of ['tryInsertPRButtons(generation)', 'tryInsertIssueButtons(generation)', 'tryInsertListSelection(target.kind)', 'tryInsertListButtons(target.kind, generation)']) {
    assert.ok(pass.indexOf(call) > passCheck, `${call} is not reached only past the page check`);
  }
  assert.equal(count(pass, 'await '), 4, 'the pass waits somewhere new: whatever follows that wait has to check the page first');
  // Each insert waits once, for storage, and checks the page before its first write
  const writes = ['attachToRepoCrumb(', 'insertAdjacentElement(', 'appendChild(', 'insertBefore(', 'unclipButtonRow('];
  for (const signature of ['async function tryInsertRepoButtons(target, generation) {', 'async function tryInsertPRButtons(generation) {', 'async function tryInsertIssueButtons(generation) {', 'async function tryInsertListButtons(kind, generation) {']) {
    const insert = bodyOf(source, signature);
    assert.equal(count(insert, 'await '), 1, `${signature} waits on something besides storage`);
    const check = insert.indexOf('if (pageChangedSince(generation)) return false;');
    assert.ok(check > insert.indexOf('await loadButtonConfigs('), `${signature} does not check the page after its wait`);
    assert.equal(count(insert, 'pageChangedSince('), 1);
    for (const write of writes) {
      for (let at = insert.indexOf(write); at !== -1; at = insert.indexOf(write, at + 1)) {
        assert.ok(at > check, `${signature} writes the page (${write}) before the page check`);
      }
    }
  }
});

test('taking the buttons away takes the popover and the split buttons with them (lint)', () => {
  const source = content();
  const remove = bodyOf(source, 'function removeInsertedButtons(');
  assert.match(remove, /closeNotePopover\(\{ restoreFocus: false \}\)/);
  assert.match(remove, /\.\$\{SPLIT_BUTTON_CLASS\}/);
  assert.match(bodyOf(source, 'async function tryInsertButton('), /forgetDetachedSplitButtons\(\)/);
  assert.match(bodyOf(source, 'function forgetDetachedSplitButtons('), /closeNotePopover\(\{ restoreFocus: false \}\)/);
  assert.match(bodyOf(source, 'function onUrlChange('), /removeInsertedButtons\(\)/);
});
