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
  assert.match(readExtension('options.js'), /commandStartsClaude\(/, 'the options warning no longer asks the shared predicate');
});

test('the options warning counts inputs the way a click sends them', () => {
  // Also a lint. It counted with `trim()`, which drops a tab-only input that the send keeps and the
  // app then refuses — so the warning stayed hidden over a button that could only fail.
  const options = readExtension('options.js');
  const warning = options.slice(options.indexOf('function updateClaudeWarn('));
  const body = warning.slice(0, warning.indexOf('\n}\n'));
  assert.match(body, /normalizeClaudeInputs\(btn\.claudeInputs\)/, 'the warning counts inputs by a rule of its own');
  assert.doesNotMatch(body, /\.trim\(\)/, 'the warning trims inputs with trim()');
});

test('a button takes a note only when it starts claude and has room for one more input', () => {
  const { buttonTakesClaudeNote, MAX_CLAUDE_INPUTS } = pick('buttonTakesClaudeNote, MAX_CLAUDE_INPUTS');
  for (const preset of allPresets()) {
    assert.equal(buttonTakesClaudeNote(frozenButton(preset)), STARTS_CLAUDE[preset.id], preset.id);
  }
  const inputs = count => Array.from({ length: count }, (_, i) => `!echo ${i}`);
  const claude = '{cd} && claude';
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: claude, claudeInputs: inputs(MAX_CLAUDE_INPUTS - 1) })), true);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: claude, claudeInputs: inputs(MAX_CLAUDE_INPUTS) })), false);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd}', claudeInputs: [] })), false);
});

test('the room left is counted over the inputs a click actually sends', () => {
  // The count is the normalized one — what executionPayload hands the app — so a blank entry takes
  // no room, while an input the extension keeps (a lone zero-width space) takes a slot even though
  // the app would drop it later.
  const { buttonTakesClaudeNote, MAX_CLAUDE_INPUTS } = pick('buttonTakesClaudeNote, MAX_CLAUDE_INPUTS');
  const four = Array.from({ length: MAX_CLAUDE_INPUTS - 1 }, (_, i) => `!echo ${i}`);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd} && claude', claudeInputs: [...four, '   '] })), true);
  assert.equal(buttonTakesClaudeNote(frozenButton({ command: '{cd} && claude', claudeInputs: [...four, cp(0x200B)] })), false);
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
