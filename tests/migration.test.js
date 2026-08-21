// Tests for the settings-schema version and the migration registry — `node --test` from the repo
// root, no dependencies. Same loading trick as buttons.test.js: these are classic browser scripts
// with no exports, so run them and then evaluate the names to pull them out. migrations.js reads
// BUTTON_KINDS from defaults.js, so defaults.js has to run first.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const read = name => fs.readFileSync(path.join(__dirname, '../extension', name), 'utf8');
vm.runInThisContext(read('defaults.js'));
vm.runInThisContext(read('migrations.js'));

const { BUTTON_KINDS, SETTINGS_VERSION, SETTINGS_KEYS, VERSION_KEY } =
  vm.runInThisContext('({ BUTTON_KINDS, SETTINGS_VERSION, SETTINGS_KEYS, VERSION_KEY })');
const { MIGRATIONS, storedSchemaVersion, versionToSave } =
  vm.runInThisContext('({ MIGRATIONS, storedSchemaVersion, versionToSave })');

// --- The stored version, and the only ways it may go up ---
// A save that stamps the current version without the user having seen anything would erase the
// migration silently: the icon goes away and the stale commands stay forever. That is the failure
// this whole feature exists to prevent, so the rule gets pinned here first.

test('an empty profile is already current — a fresh install must not see a migration', () => {
  assert.equal(storedSchemaVersion({}), SETTINGS_VERSION);
});

test('settings without a version are legacy (v0), not fresh', () => {
  // Telling the two apart is only possible by "is anything else stored at all"
  assert.equal(storedSchemaVersion({ buttons: [{ command: 'z {repo}' }] }), 0);
  assert.equal(storedSchemaVersion({ defaultMain: 'master' }), 0);
  assert.equal(storedSchemaVersion({ repoMainBranch: {} }), 0);
});

test('a stored version is taken as-is, including one from the future', () => {
  assert.equal(storedSchemaVersion({ version: 1, buttons: [] }), 1);
  assert.equal(storedSchemaVersion({ version: 7, buttons: [] }), 7);
});

test('a version that is not a number is not trusted — fall back to the presence rule', () => {
  assert.equal(storedSchemaVersion({ version: '1', buttons: [{}] }), 0);
  assert.equal(storedSchemaVersion({ version: null, buttons: [{}] }), 0);
  assert.equal(storedSchemaVersion({ version: '1' }), SETTINGS_VERSION); // nothing else stored: fresh
});

test('an ordinary save keeps the version it read — editing a tooltip is not consent', () => {
  assert.equal(versionToSave({ loadedVersion: 0, reviewed: false }), 0);
});

test('a reviewed save moves to the current version', () => {
  // "reviewed" covers all four consent paths: applying, applying part of it, [Keep mine], and Reset
  assert.equal(versionToSave({ loadedVersion: 0, reviewed: true }), SETTINGS_VERSION);
});

// The normal load path can still hand us a future version: another machine on the same account
// runs a newer extension and synced its marker down. Import can no longer produce this — a newer
// backup is refused outright (decision 5, revised) — but a save from here must not downgrade it.
test('a version from the future is never downgraded, reviewed or not', () => {
  assert.equal(versionToSave({ loadedVersion: 7, reviewed: false }), 7);
  assert.equal(versionToSave({ loadedVersion: 7, reviewed: true }), 7);
});

test('the settings key list carries every button kind plus the main-branch keys', () => {
  for (const { storageKey } of Object.values(BUTTON_KINDS)) {
    assert.ok(SETTINGS_KEYS.includes(storageKey), `${storageKey} missing from SETTINGS_KEYS`);
  }
  assert.ok(SETTINGS_KEYS.includes('defaultMain'));
  assert.ok(SETTINGS_KEYS.includes('repoMainBranch'));
  // The version rides alongside the settings, so it must not be one of them
  assert.ok(!SETTINGS_KEYS.includes(VERSION_KEY));
});

// --- The registry ---

test('the registry covers every step from 0 to the current version', () => {
  const steps = MIGRATIONS.map(m => `${m.from}->${m.to}`);
  const expected = Array.from({ length: SETTINGS_VERSION }, (_, i) => `${i}->${i + 1}`);
  assert.deepEqual(steps, expected, 'a version bump without a registry entry (or the reverse)');
});

test('every registry entry declares what kind of change it is, and can describe it', () => {
  // "A migration that cannot articulate which of the two it is doesn't ship" (issue #31)
  for (const entry of MIGRATIONS) {
    // Declared per candidate kind, not per step: replacing a preset we shipped is not the same
    // promise as replacing the first clause of a command someone else wrote.
    for (const field of ['verbatimEffect', 'prefixEffect']) {
      assert.ok(
        ['unconditional', 'behavior-change'].includes(entry[field]),
        `${entry.from}->${entry.to}: ${field} must be declared`
      );
    }
    assert.equal(typeof entry.prefixDescribe, 'string');
    assert.ok(entry.prefixDescribe.length > 0);
    assert.equal(typeof entry.describe, 'string');
    assert.ok(entry.describe.length > 0, `${entry.from}->${entry.to}: describe is empty`);
    assert.equal(typeof entry.customNote, 'string');
    assert.ok(entry.customNote.length > 0, `${entry.from}->${entry.to}: customNote is empty`);
  }
});

// --- Planning a migration ---
// The plan splits what is stored into what we may rewrite (actionable, consented per item) and what
// we may only point at (informational). Nothing here touches storage or the DOM.

const { planMigration, applyMigrationPlan } =
  vm.runInThisContext('({ planMigration, applyMigrationPlan })');

const V0 = {
  checkout: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  claude: 'z {repo} && claude',
  open: 'z {repo}',
};
const V1 = {
  checkout: '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  claude: '{cd} && claude',
  open: '{cd}',
};
// Buttons carry a runtime uid in the edit state — that, not their position, is what a candidate is
// keyed by. The helper mints one the way the options page does.
const stored = (key, ...commands) => ({
  [key]: commands.map((command, i) => ({ uid: `${key}#${i}`, face: 'x', label: `b${i}`, command, claudeInputs: [] })),
});
const plan0 = data => planMigration(data, 0);
const ids = list => list.map(item => item.id);

test('a verbatim old preset is an actionable candidate', () => {
  const plan = plan0(stored('buttons', V0.checkout));
  assert.equal(plan.actionable.length, 1);
  assert.equal(plan.informational.length, 0);
  assert.deepEqual(
    { from: plan.actionable[0].from, to: plan.actionable[0].to, source: plan.actionable[0].source },
    { from: V0.checkout, to: V1.checkout, source: 'verbatim' }
  );
});

test('the same old string maps the same way whichever page it was saved under', () => {
  // `z {repo} && claude` was three different presets in v0; the map is deliberately not per-page
  for (const key of ['buttons', 'issueButtons', 'repoButtons']) {
    const plan = plan0(stored(key, V0.claude));
    assert.equal(plan.actionable[0].to, V1.claude, key);
  }
});

test('a customized command with the exact old first clause is promoted to a candidate', () => {
  // Revised decision 4: strict prefix only, and only the first clause is replaced. Offered, but as
  // a behavior change — the tail is theirs, and with a base folder set it will run somewhere the old
  // command never reached.
  const plan = plan0(stored('buttons', 'z {repo} && npm test'));
  assert.equal(plan.informational.length, 0);
  assert.deepEqual(
    { to: plan.actionable[0].to, source: plan.actionable[0].source, effect: plan.actionable[0].effect },
    { to: '{cd} && npm test', source: 'prefix', effect: 'behavior-change' }
  );
});

test('shapes the prefix rule must not touch are listed, not rewritten', () => {
  // Anything where `z {repo}` is not exactly the first clause: rewriting these needs shell parsing,
  // and guessing wrong edits a command we were told to leave alone
  for (const command of ['cd x && z {repo}', 'z {repo};', 'z {repo}&&x', 'z  {repo} && claude']) {
    const plan = plan0(stored('buttons', command));
    assert.equal(plan.actionable.length, 0, `must not rewrite: ${command}`);
    assert.equal(plan.informational.length, 1, `must be listed: ${command}`);
    assert.equal(plan.informational[0].command, command);
    assert.ok(plan.informational[0].note.length > 0);
  }
});

test('a command already on the new generation is neither rewritten nor nagged about', () => {
  for (const command of [V1.checkout, '{cd} && npm test']) {
    const plan = plan0(stored('buttons', command));
    assert.equal(plan.actionable.length, 0, command);
    assert.equal(plan.informational.length, 0, command);
  }
});

test('a key that was never saved is not scanned — those buttons are the current defaults', () => {
  const plan = plan0({ defaultMain: 'master' });
  assert.equal(plan.actionable.length, 0);
  assert.equal(plan.informational.length, 0);
});

test('item ids are stable and carry where the button lives', () => {
  const plan = plan0(stored('issueButtons', V0.open, 'z {repo} && npm test'));
  assert.deepEqual(ids(plan.actionable), ['issueButtons#0', 'issueButtons#1']);
  assert.equal(plan.actionable[0].kind, 'issue');
});

test('nothing to do at the current version', () => {
  const plan = planMigration(stored('buttons', V0.checkout), 1);
  assert.equal(plan.actionable.length, 0);
  assert.equal(plan.targetVersion, SETTINGS_VERSION);
});

test('applying rewrites only the selected items and copies the rest byte for byte', () => {
  const data = stored('buttons', V0.checkout, V0.claude);
  const plan = plan0(data);
  const next = applyMigrationPlan(data, plan, ['buttons#1']);
  assert.equal(next.buttons[0].command, V0.checkout, 'unselected item must be untouched');
  assert.equal(next.buttons[1].command, V1.claude);
  assert.equal(data.buttons[0].command, V0.checkout, 'input must not be mutated');
  assert.equal(data.buttons[1].command, V0.claude, 'input must not be mutated');
});

test('applying nothing is a no-op, not a rewrite of everything', () => {
  const data = stored('buttons', V0.checkout);
  assert.equal(applyMigrationPlan(data, plan0(data), []).buttons[0].command, V0.checkout);
});

test('applying leaves every other field of the button alone', () => {
  const data = { buttons: [{ uid: 'u1', face: '🤖', label: 'mine', command: V0.claude, claudeInputs: ['/review'] }] };
  const next = applyMigrationPlan(data, plan0(data), ['u1']);
  assert.deepEqual(next.buttons[0], {
    uid: 'u1', face: '🤖', label: 'mine', command: V1.claude, claudeInputs: ['/review'],
  });
});

// --- The preview's view model (item 3) ---
// What the panel needs to render, kept out of the DOM so the three states that matter can be pinned.

const { migrationSummary } = vm.runInThisContext('({ migrationSummary })');

test('summary: everything checked is the default offer', () => {
  const data = stored('buttons', V0.checkout, V0.claude);
  const plan = plan0(data);
  const summary = migrationSummary(plan, ids(plan.actionable));
  assert.equal(summary.actionableCount, 2);
  assert.equal(summary.selectedCount, 2);
  assert.equal(summary.nothingToApply, false);
  assert.equal(summary.reviewOnly, false);
});

test('summary: unchecking everything still lets the user finish — as a review, not a rewrite', () => {
  const data = stored('buttons', V0.checkout);
  const summary = migrationSummary(plan0(data), []);
  assert.equal(summary.selectedCount, 0);
  assert.equal(summary.nothingToApply, true);
  assert.equal(summary.reviewOnly, false, 'there were candidates, the user just declined them');
});

test('summary: no candidates at all is a review-only notice', () => {
  // Decision 2: even with nothing to rewrite there is no silent promotion — the click is the consent
  const data = stored('buttons', 'cd x && z {repo}');
  const plan = plan0(data);
  assert.equal(plan.actionable.length, 0);
  const summary = migrationSummary(plan, []);
  assert.equal(summary.reviewOnly, true);
  assert.equal(summary.informationalCount, 1);
});

// --- Import (item 5) ---
// A backup carries the version too. Reading one that came from a newer extension is a refusal, not
// a partial import: we cannot know what its keys mean.

const { importedSchemaVersion } = vm.runInThisContext('({ importedSchemaVersion })');

test('a backup without a version reads as legacy and gets a plan', () => {
  const data = stored('buttons', V0.checkout);
  assert.equal(importedSchemaVersion(data), 0);
  assert.equal(plan0(data).actionable.length, 1);
});

test('a backup at the current version is taken as it is', () => {
  assert.equal(importedSchemaVersion({ version: SETTINGS_VERSION, buttons: [] }), SETTINGS_VERSION);
});

test('a backup from a newer extension is refused outright', () => {
  assert.throws(
    () => importedSchemaVersion({ version: SETTINGS_VERSION + 1, buttons: [] }),
    error => {
      // The message has to carry both ways out, or the user is simply stuck
      assert.match(error.message, /newer version of the extension/i);
      assert.match(error.message, /chrome:\/\/extensions/);
      assert.match(error.message, /Reset to Defaults/);
      return true;
    }
  );
});

test('a non-numeric version in a backup is ignored, not refused', () => {
  // Same convention as every other malformed key in parseImportedSettings: drop it and carry on
  assert.equal(importedSchemaVersion({ version: 'nope', buttons: [] }), 0);
});

// --- Adopting a change that arrived from another machine (item 6) ---

const { shouldAdoptSyncedChange } = vm.runInThisContext('({ shouldAdoptSyncedChange })');

test('a synced change is adopted when nothing is being edited', () => {
  assert.equal(shouldAdoptSyncedChange(false, { buttons: {} }), true);
  assert.equal(shouldAdoptSyncedChange(false, { version: {} }), true);
});

test('a synced change never overwrites unsaved edits', () => {
  assert.equal(shouldAdoptSyncedChange(true, { buttons: {} }), false);
});

test('changes to keys we do not own are ignored', () => {
  assert.equal(shouldAdoptSyncedChange(false, { somethingElse: {} }), false);
  assert.equal(shouldAdoptSyncedChange(false, {}), false);
});

test('a candidate is only rewritten while the command is still the one that was planned', () => {
  // The plan is computed against stored settings, but it is applied to the edit state, and the user
  // may have typed or reordered in between. Position alone is not identity: without this check the
  // rewrite lands on whatever now sits at that index.
  const data = stored('buttons', V0.claude);
  const plan = plan0(data);
  const edited = { buttons: [{ ...data.buttons[0], command: 'z {repo} && something else' }] };
  assert.equal(
    applyMigrationPlan(edited, plan, ids(plan.actionable)).buttons[0].command,
    'z {repo} && something else',
    'a command that changed since planning must be left alone'
  );
});

// --- Trust boundary: keys and values that arrive from a user's saved settings (class (b)) ---

test('a command that names a prototype member is not a candidate', () => {
  // `rewrites[command]` on a plain object answers for "constructor", "toString", "__proto__" and
  // friends, which made them look like verbatim matches and then blew up on save in .trim()
  for (const command of ['constructor', 'toString', 'hasOwnProperty', '__proto__', 'valueOf']) {
    const plan = plan0(stored('buttons', command));
    assert.equal(plan.actionable.length, 0, `must not be a candidate: ${command}`);
    assert.equal(plan.informational.length, 0, `must not be listed either: ${command}`);
  }
});

test('only a non-negative integer counts as a version', () => {
  const { normalizeVersion } = vm.runInThisContext('({ normalizeVersion })');
  assert.equal(normalizeVersion(0), 0);
  assert.equal(normalizeVersion(1.0), 1, '1.0 is an integer in JS and stays valid');
  assert.equal(normalizeVersion(0.5), null, 'a fraction would skip whole steps');
  assert.equal(normalizeVersion(-1), null);
  assert.equal(normalizeVersion('1'), null);
  assert.equal(normalizeVersion(NaN), null);
  assert.equal(normalizeVersion(Infinity), null);
  assert.equal(normalizeVersion(undefined), null);
});

test('stored and imported versions are judged by the same rule', () => {
  // 0.5 used to pass as "valid", and `step.from >= 0.5` then skipped the 0->1 step entirely: an
  // empty review screen, a confirming click, and the stale commands were marked as reviewed
  assert.equal(storedSchemaVersion({ version: 0.5, buttons: [{}] }), 0);
  assert.equal(importedSchemaVersion({ version: 0.5, buttons: [] }), 0);
  assert.equal(storedSchemaVersion({ version: -1, buttons: [{}] }), 0);
  assert.equal(importedSchemaVersion({ version: -1, buttons: [] }), 0);
});

test('a fractional version can never skip a step, even if one leaks in', () => {
  // Belt and braces for the above: steps are selected by where they land, not where they start
  const plan = planMigration(stored('buttons', V0.claude), 0.5);
  assert.equal(plan.actionable.length, 1);
});

// --- Registry coverage, derived from the presets that exist today (P3) ---

test('the registry covers exactly the current presets, pair for pair', () => {
  // Derived rather than listed: deleting a pair, or adding a preset without one, has to fail here.
  // This is the git-free half of the 294c46a cross-check, so it also runs on a shallow CI checkout.
  const entry = MIGRATIONS.find(step => step.to === 1);
  const current = new Set(
    Object.values(BUTTON_KINDS).flatMap(kind => [...kind.presets, ...kind.defaults].map(b => b.command))
  );
  const expected = new Set();
  for (const command of current) {
    assert.ok(command.startsWith('{cd}'), `v1 preset must open with {cd}: ${command}`);
    const old = `z {repo}${command.slice('{cd}'.length)}`;
    assert.ok(entry.rewrites.has(old), `no registry pair for preset: ${command}`);
    assert.equal(entry.rewrites.get(old), command);
    expected.add(old);
  }
  assert.deepEqual(new Set(entry.rewrites.keys()), expected, 'registry has pairs no preset asks for');
});

// --- The prefix rule's own edge (c) ---

test('an old jump with nothing after it is not a candidate', () => {
  for (const command of ['z {repo} && ', 'z {repo} &&   ']) {
    const plan = plan0(stored('buttons', command));
    assert.equal(plan.actionable.length, 0, `must not rewrite: ${JSON.stringify(command)}`);
    assert.equal(plan.informational.length, 1, `must be listed: ${JSON.stringify(command)}`);
  }
});

// --- The preview text covers every step that is being applied ---

test('the description covers all the steps between the stored version and now', () => {
  const { migrationDescription } = vm.runInThisContext('({ migrationDescription })');
  const text = migrationDescription(0);
  for (const step of MIGRATIONS.filter(s => s.to > 0)) {
    assert.ok(text.includes(step.describe), `step ${step.from}->${step.to} is missing from the preview`);
  }
  assert.equal(migrationDescription(SETTINGS_VERSION), '');
});

// --- Identity, not position (class (a)) ---
// The plan is built from the edit state and applied to the edit state, and in between the user can
// type, reorder, add and delete. An index is not a name for a button; the uid is.

test('candidates are keyed by the button uid', () => {
  const plan = plan0(stored('buttons', V0.claude));
  assert.deepEqual(ids(plan.actionable), ['buttons#0']);
});

test('unchecking one of two identical commands survives a reorder', () => {
  // The exact P1-2 repro: two buttons with the same command, decline the first, move the second to
  // the front, apply. With index identity this rewrote the button the user had just declined.
  const a = { uid: 'A', face: 'x', label: 'keep A', command: V0.claude, claudeInputs: [] };
  const b = { uid: 'B', face: 'x', label: 'apply B', command: V0.claude, claudeInputs: [] };
  const plan = plan0({ buttons: [a, b] });
  const reordered = { buttons: [b, a] };

  const next = applyMigrationPlan(reordered, plan, ['B']);
  assert.equal(next.buttons[0].command, V1.claude, 'B was the one selected');
  assert.equal(next.buttons[1].command, V0.claude, 'A was declined and must be untouched');
});

test('a button that lost its uid cannot be rewritten', () => {
  // Defence only — the options page mints one for every button through a single funnel. But a
  // candidate we cannot identify is one we must not apply, rather than one we apply by position.
  const plan = plan0(stored('buttons', V0.claude));
  const stripped = { buttons: [{ face: 'x', label: 'b0', command: V0.claude, claudeInputs: [] }] };
  assert.equal(applyMigrationPlan(stripped, plan, ids(plan.actionable)).buttons[0].command, V0.claude);
});

test('the uid is a runtime handle and never becomes part of the stored shape', () => {
  // If it leaked into storage it would ride storage.sync to other machines and into export files,
  // where it means nothing and would collide with the uids minted there.
  const { toStoredButton } = vm.runInThisContext('({ toStoredButton })');
  const shape = toStoredButton({ uid: 'u1', face: ' 🤖 ', label: ' mine ', command: 'x', claudeInputs: [' /a ', ''] });
  assert.deepEqual(shape, { face: '🤖', label: 'mine', command: 'x', claudeInputs: ['/a'] });
  assert.ok(!('uid' in shape));
});

// --- The generation of a merged edit state ---

test('merging sources takes the lowest generation of the two', () => {
  // The edit state after an import is part file, part what was already on screen. Reviewing it has
  // to answer for the oldest thing in it, or the newer half licenses the older half.
  const { mergedSourceVersion } = vm.runInThisContext('({ mergedSourceVersion })');
  assert.equal(mergedSourceVersion(1, 0), 0);
  assert.equal(mergedSourceVersion(0, 1), 0);
  assert.equal(mergedSourceVersion(1, 1), 1);
});

test('a plan over a merged edit state covers the sections the file never mentioned', () => {
  // The P1-1 repro at the level where it is decidable: importing {"defaultMain":"main"} leaves the
  // other sections holding their old commands, and those still have to appear in the plan.
  const merged = {
    ...stored('buttons', V0.checkout),
    ...stored('issueButtons', V0.claude),
    defaultMain: 'main',
  };
  const plan = plan0(merged);
  assert.deepEqual(ids(plan.actionable).sort(), ['buttons#0', 'issueButtons#0']);
});

// --- Snapshots that went stale mid-flight (class (c)) ---
// The two tests that used to sit here pinned a "version floor" — the highest version ever observed,
// written alongside whatever content the page held. That design was wrong and is gone: it protected
// the version marker while leaving the commands it describes unprotected, so a v1 marker could land
// on v0 commands and erase another device's migration. What replaces it is `saveConflict` above:
// a save that would land on settings that moved is refused outright.

test('a snapshot that was overtaken while loading is thrown away', () => {
  // P1-5: onChanged -> loadSettings() awaits storage, and the user types during the await. Applying
  // the snapshot afterwards overwrites what they just typed. Checkbox changes count too — they are
  // not "dirty", but they are the user having said something about this plan.
  const { shouldApplyLoadedSnapshot } = vm.runInThisContext('({ shouldApplyLoadedSnapshot })');
  const inFlight = { generation: 1, latestGeneration: 1 };
  assert.equal(shouldApplyLoadedSnapshot({ ...inFlight, revisionAtStart: 3, revisionNow: 3, dirty: false }), true);
  assert.equal(shouldApplyLoadedSnapshot({ ...inFlight, revisionAtStart: 3, revisionNow: 4, dirty: false }), false);
  assert.equal(shouldApplyLoadedSnapshot({ ...inFlight, revisionAtStart: 3, revisionNow: 3, dirty: true }), false);
});

// --- What each kind of candidate promises (class (d)) ---
// Replacing a preset we shipped is a different promise from replacing the first clause of a command
// someone else wrote: the rest of their command is arbitrary, and it will now run somewhere else.

test('a verbatim candidate is unconditional; a prefix candidate is a behavior change', () => {
  const verbatim = plan0(stored('buttons', V0.claude)).actionable[0];
  assert.equal(verbatim.effect, 'unconditional');

  const prefix = plan0(stored('buttons', 'z {repo} && git clean -fdx')).actionable[0];
  assert.equal(prefix.effect, 'behavior-change');
  // The scenario that forces this: with a base folder set, a failed jump now lands in
  // <base>/<repo> — possibly a different repository of the same name — and `git clean -fdx` runs there
  assert.ok(prefix.describe.length > 0, 'a behavior change has to say what changes');
  assert.notEqual(prefix.describe, verbatim.describe);
});

test('only unconditional candidates are checked to begin with', () => {
  const { defaultSelection } = vm.runInThisContext('({ defaultSelection })');
  const data = {
    buttons: [
      { uid: 'v', face: 'x', label: 'preset', command: V0.claude, claudeInputs: [] },
      { uid: 'p', face: 'x', label: 'custom', command: 'z {repo} && git clean -fdx', claudeInputs: [] },
    ],
  };
  const plan = plan0(data);
  assert.deepEqual(defaultSelection(plan), ['v'], 'the custom one is opt-in, not opt-out');
  assert.equal(migrationSummary(plan, defaultSelection(plan)).selectedCount, 1);
  assert.equal(migrationSummary(plan, defaultSelection(plan)).actionableCount, 2);
});

// --- The history oracle (class (e)) ---
// Deriving coverage from today's presets passes if a preset and its pair are deleted together. The
// fixture is what users actually have saved, so it cannot be edited to make a test go green.

test('every v0 command ever shipped still reaches a current preset', () => {
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/presets-v0.json'), 'utf8'));
  const current = new Set(
    Object.values(BUTTON_KINDS).flatMap(kind => [...kind.presets, ...kind.defaults].map(b => b.command))
  );
  assert.ok(fixture.commands.length > 0);
  for (const command of fixture.commands) {
    const plan = plan0(stored('buttons', command));
    assert.equal(plan.actionable.length, 1, `no candidate for shipped v0 command: ${command}`);
    assert.ok(
      current.has(plan.actionable[0].to),
      `v0 command migrates to something that is not a current preset: ${command} -> ${plan.actionable[0].to}`
    );
  }
});

// --- The uid is ours, not the stored data's (class (c)) ---
// It is a handle this page mints to tell buttons apart while they are edited. Anything arriving from
// storage or a file is data, and data does not get to name our handles.

test('a uid found in stored data is discarded, not adopted', () => {
  // A stored `"uid": 0` used to survive: the plan then carried the number 0 while the DOM dataset
  // carried the string "0", so unchecking that item did nothing and it was applied anyway.
  const { adoptButton } = vm.runInThisContext('({ adoptButton })');
  const adopted = adoptButton({ uid: 0, face: 'x', label: 'b', command: 'z {repo}', claudeInputs: [] });
  assert.equal(typeof adopted.uid, 'string');
  assert.notEqual(adopted.uid, 0);
  assert.notEqual(adopted.uid, '0');
});

test('two stored buttons claiming the same uid still get told apart', () => {
  const { adoptButton } = vm.runInThisContext('({ adoptButton })');
  const same = { uid: 'collide', face: 'x', label: 'b', command: 'z {repo}', claudeInputs: [] };
  const [a, b] = [adoptButton(same), adoptButton(same)];
  assert.notEqual(a.uid, b.uid);
  const plan = plan0({ buttons: [a, b] });
  assert.equal(new Set(ids(plan.actionable)).size, 2, 'two candidates must have two names');
});

test('an edit-state button keeps its uid when it is reshaped', () => {
  // Save tidies the buttons and puts them back on screen; that is the same button, and a candidate
  // the user is looking at must not be renamed underneath them.
  const { reshapeButton } = vm.runInThisContext('({ reshapeButton })');
  assert.equal(reshapeButton({ face: ' x ', label: 'b', command: 'c', claudeInputs: [] }, 'keep').uid, 'keep');
});

// --- A load result is only good for the page it was asked from (class (b)) ---

test('a load result from an overtaken request is discarded', () => {
  const { shouldApplyLoadedSnapshot } = vm.runInThisContext('({ shouldApplyLoadedSnapshot })');
  const base = { revisionAtStart: 3, revisionNow: 3, dirty: false, generation: 2, latestGeneration: 2 };
  assert.equal(shouldApplyLoadedSnapshot(base), true);
  // Two loads in flight (a sync event arriving during the first): whichever answers last used to
  // win, so the older settings could land on top of the newer ones
  assert.equal(shouldApplyLoadedSnapshot({ ...base, generation: 1, latestGeneration: 2 }), false);
  assert.equal(shouldApplyLoadedSnapshot({ ...base, revisionNow: 4 }), false);
  assert.equal(shouldApplyLoadedSnapshot({ ...base, dirty: true }), false);
});

// --- Writing only on top of what we loaded (class (a)) ---
// storage.sync has no compare-and-set, so the only honest thing to do with a settings object that
// moved underneath us is to refuse and say so. Overwriting would be a silent, unrecoverable merge.

const { saveConflict, planSave, SAVE_CONFLICT_MESSAGE } =
  vm.runInThisContext('({ saveConflict, planSave, SAVE_CONFLICT_MESSAGE })');

test('an untouched settings object is not a conflict', () => {
  const snapshot = { buttons: [{ command: 'z {repo}' }], defaultMain: 'main', version: 0 };
  assert.equal(saveConflict(snapshot, { ...snapshot }), false);
  assert.equal(saveConflict({}, {}), false);
  // Keys we never wrote read back as undefined — that is the same settings object, not a change
  assert.equal(saveConflict({ defaultMain: 'main' }, { defaultMain: 'main', buttons: undefined }), false);
});

test('any change to our keys since the load is a conflict', () => {
  const loaded = { buttons: [{ command: 'z {repo}' }], version: 0 };
  assert.equal(saveConflict(loaded, { buttons: [{ command: '{cd}' }], version: 1 }), true);
  assert.equal(saveConflict(loaded, { buttons: [{ command: 'z {repo}' }], version: 1 }), true);
  assert.equal(saveConflict(loaded, { buttons: [], version: 0 }), true);
  assert.equal(saveConflict(loaded, {}), true);
});

test('a save onto a settings object that moved is refused, not merged', () => {
  // The scenario in full. Device A loads v0 settings and starts editing. Device B reviews the
  // migration and saves the rewritten commands as v1. A now presses Save: its payload still holds
  // the old commands, and writing it would erase B's explicit decision with no trace and no notice.
  const loadedByA = { buttons: [{ command: 'z {repo} && claude' }], version: 0 };
  const savedByB = { buttons: [{ command: '{cd} && claude' }], version: 1 };
  const payloadFromA = {
    buttons: [{ command: 'z {repo} && claude' }],
    version: versionToSave({ loadedVersion: 0, reviewed: false }),
  };

  const outcome = planSave({ capturedSnapshot: loadedByA, liveSnapshot: savedByB, payload: payloadFromA });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.write, undefined, 'nothing may be written');
  assert.equal(outcome.message, SAVE_CONFLICT_MESSAGE);
  // The way out has to be in the message: what happened, how to see it, how not to lose your edits
  assert.match(SAVE_CONFLICT_MESSAGE, /another device/i);
  assert.match(SAVE_CONFLICT_MESSAGE, /reload/i);
  assert.match(SAVE_CONFLICT_MESSAGE, /export/i);
  // B's settings stay exactly as B left them
  assert.deepEqual(savedByB, { buttons: [{ command: '{cd} && claude' }], version: 1 });
});

test('a save onto the settings we loaded goes through unchanged', () => {
  const snapshot = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const payload = { buttons: [{ command: 'z {repo}' }], version: 0, defaultMain: 'main' };
  const outcome = planSave({ capturedSnapshot: snapshot, liveSnapshot: { ...snapshot }, payload });
  assert.equal(outcome.refused, false);
  assert.equal(outcome.write, payload);
});

// --- Nothing to protect before the first load (class (a)-1) ---

test('the first load applies even if the page moved while it was in flight', () => {
  const { shouldApplyLoadedSnapshot } = vm.runInThisContext('({ shouldApplyLoadedSnapshot })');
  // There are no settings on screen yet, so there is nothing a late arrival could overwrite.
  // Discarding it left the page with loaded=false forever, and nothing retried.
  assert.equal(shouldApplyLoadedSnapshot({
    initial: true, revisionAtStart: 0, revisionNow: 3, dirty: true, generation: 1, latestGeneration: 1,
  }), true);
  // Being overtaken by a newer request still wins over "initial"
  assert.equal(shouldApplyLoadedSnapshot({
    initial: true, revisionAtStart: 0, revisionNow: 0, dirty: false, generation: 1, latestGeneration: 2,
  }), false);
  // Once loaded, the edit state is real and the old rules apply again
  assert.equal(shouldApplyLoadedSnapshot({
    initial: false, revisionAtStart: 0, revisionNow: 3, dirty: false, generation: 1, latestGeneration: 1,
  }), false);
});

// --- A review in progress is unsaved work (class (a)-2) ---

test('only our own keys raise the stale banner', () => {
  const { ownedChangedKeys } = vm.runInThisContext('({ ownedChangedKeys })');
  assert.deepEqual(ownedChangedKeys({ buttons: {}, somethingElse: {} }), ['buttons']);
  assert.deepEqual(ownedChangedKeys({ somethingElse: {} }), []);
  assert.deepEqual(ownedChangedKeys({}), []);
});

test('our own write coming back is not another device changing things', () => {
  const { isOwnEcho } = vm.runInThisContext('({ isOwnEcho })');
  const written = { buttons: [{ command: '{cd}' }], version: 1 };
  assert.equal(isOwnEcho({ buttons: { newValue: [{ command: '{cd}' }] }, version: { newValue: 1 } }, written), true);
  assert.equal(isOwnEcho({ buttons: { newValue: [{ command: 'z {repo}' }] } }, written), false);
  assert.equal(isOwnEcho({}, written), false, 'nothing of ours changed is not an echo');
});

test('a review the user has touched blocks a remote change from resetting it', () => {
  // Codex's order exactly: uncheck a candidate, another device saves defaultMain, the change
  // arrives. Adopting it re-planned and re-selected everything, so Apply then rewrote the very
  // button the user had just declined.
  const { shouldAdoptSyncedChange, defaultSelection } = vm.runInThisContext('({ shouldAdoptSyncedChange, defaultSelection })');
  const data = stored('buttons', V0.claude);
  const plan = plan0(data);
  const selection = new Set(defaultSelection(plan));
  assert.equal(selection.size, 1);

  selection.delete('buttons#0'); // the user unchecks it
  const reviewTouched = true;
  assert.equal(shouldAdoptSyncedChange(false || reviewTouched, { defaultMain: {} }), false);

  // The selection therefore still says "no", and applying honours it
  assert.equal(applyMigrationPlan(data, plan, selection).buttons[0].command, V0.claude);
});

// --- Stored settings are as untrusted as an imported file (class (b)) ---

test('unreadable stored entries are skipped, counted, and never crash the page', () => {
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  // Every one of these used to throw before the page finished loading, leaving it stuck
  const cases = [
    { buttons: [null] },
    { buttons: { length: 1 } },
    { buttons: 'z {repo}' },
    { buttons: [['nested']] },
    { buttons: [undefined, 42, 'x'] },
  ];
  for (const raw of cases) {
    const adopted = adoptStoredSettings(raw);
    assert.ok(adopted.skipped > 0, `must report what it dropped: ${JSON.stringify(raw)}`);
    assert.ok(!adopted.settings.buttons?.length, JSON.stringify(raw));
  }
});

test('good stored entries survive alongside bad ones', () => {
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  const adopted = adoptStoredSettings({
    buttons: [null, { face: 'x', label: 'keep', command: V0.claude, claudeInputs: [] }],
    defaultMain: 'master',
  });
  assert.equal(adopted.skipped, 1);
  assert.equal(adopted.settings.buttons.length, 1);
  assert.equal(adopted.settings.buttons[0].command, V0.claude);
  assert.equal(adopted.settings.defaultMain, 'master');
});

test('the non-button keys are shape-checked too', () => {
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  // Object.entries('abc') would have produced override rows named 0, 1, 2
  const adopted = adoptStoredSettings({ defaultMain: 42, repoMainBranch: 'abc' });
  assert.equal(adopted.settings.defaultMain, undefined);
  assert.equal(adopted.settings.repoMainBranch, undefined);
  assert.equal(adopted.skipped, 2);
  assert.deepEqual(adoptStoredSettings({ repoMainBranch: { a: 'main', b: 7 } }).settings.repoMainBranch, { a: 'main' });
});

test('a sparse or padded array is not the same stored value', () => {
  const loaded = { buttons: [] };
  assert.equal(saveConflict(loaded, { buttons: new Array(1) }), true, 'holes still make it longer');
  assert.equal(saveConflict({ buttons: [1] }, { buttons: [1, undefined] }), true);
});

// --- One signal for "the user said something" (class (a)) ---
// dirty, revision and reviewTouched were three half-signals, and every boundary between them leaked.
// revision is now the primary: every interaction bumps it, and every async step asks the same
// question — did anything happen since I started?

const { nothingHappenedSince, shouldAcceptUserAction, LOAD_FAILED_MESSAGE } =
  vm.runInThisContext('({ nothingHappenedSince, shouldAcceptUserAction, LOAD_FAILED_MESSAGE })');

test('a save that was overtaken does not get to declare the page settled', () => {
  // Codex (1): reviewTouched was cleared on the success path *before* the revision check, so a
  // checkbox toggled during the save was forgotten. The next remote change was then adopted, the
  // selection reset to the defaults, and Apply rewrote a candidate the user had declined.
  assert.equal(nothingHappenedSince(1, 2), false, 'a toggle during the save must be noticed');
  assert.equal(nothingHappenedSince(1, 1), true);

  // With the toggle noticed, reviewTouched survives the save and still blocks adoption
  const stillTouched = true;
  assert.equal(shouldAdoptSyncedChange(false || stillTouched, { buttons: {} }), false);
});

test('a review in progress blocks a load answer, not just a typed edit', () => {
  // Codex (2): the badge click did not bump the revision, so an in-flight load applied its answer
  // and wiped the review. Both are covered now — the click bumps it, and the predicate reads
  // reviewTouched as well, so neither half alone can let the answer through.
  const inFlight = { generation: 1, latestGeneration: 1, initial: false, dirty: false };
  assert.equal(shouldApplyLoadedSnapshot({
    ...inFlight, revisionAtStart: 1, revisionNow: 2, reviewTouched: true,
  }), false);
  assert.equal(shouldApplyLoadedSnapshot({
    ...inFlight, revisionAtStart: 1, revisionNow: 1, reviewTouched: true,
  }), false, 'reviewTouched alone is enough to refuse');
  assert.equal(shouldApplyLoadedSnapshot({
    ...inFlight, revisionAtStart: 1, revisionNow: 1, reviewTouched: false,
  }), true);
});

// --- Nothing changes before there are settings (class (d)) ---

test('a user action before the load is ignored, however it arrived', () => {
  // inert stops clicks, but a dispatched event or a programmatic .click() walks straight past it.
  // The chokepoint is the state change itself, not the listener list.
  assert.equal(shouldAcceptUserAction(false), false);
  assert.equal(shouldAcceptUserAction(true), true);
});

// --- A failed load is recoverable (class (c)) ---

test('a failed load leaves the page shut, and says how to reopen it', () => {
  // A rejected storage.get left loaded=false and the page inert forever, with nothing on screen.
  // The gate must stay shut — opening it would bring back writing an empty settings object — so the
  // way out is a retry, and the message has to offer one.
  assert.equal(shouldAcceptUserAction(false), false);
  assert.match(LOAD_FAILED_MESSAGE, /could not|failed/i);
  assert.match(LOAD_FAILED_MESSAGE, /retry/i);
});

// --- An async task settles against the world it started in (class (a)) ---
// Save, load, import and adoption are all "read something, come back later, change the page". The
// world moves in between: another device saves, a sync event is adopted, the user types. Each of
// them therefore captures what it started from and settles against that capture, never against
// `state` — which is precisely what the adoption underneath a save had rewritten.

const { planImport, IMPORT_STALE_MESSAGE, SAVE_RELOADED_MESSAGE, shouldStartSave } =
  vm.runInThisContext('({ planImport, IMPORT_STALE_MESSAGE, SAVE_RELOADED_MESSAGE, shouldStartSave })');

test('a save writes against the world it started in, not the one adoption left behind', () => {
  // Codex R5 P1, exactly. Clean page, Save pressed: the payload is built from S0 and the live read
  // goes out. While it is pending another device saves S1; onChanged adopts it, so `loadedSnapshot`
  // becomes S1 — and the pre-write comparison was S1 against S1, saw no conflict, and wrote S0 over
  // S1. Adoption is not a user action and bumps no revision, so nothing else caught it either.
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const S1 = { buttons: [{ command: '{cd}' }], version: 1 };
  const outcome = planSave({
    capturedSnapshot: S0, // what the save started from — not what the page holds now
    liveSnapshot: S1,
    payload: { buttons: [{ command: 'z {repo}' }], version: 0 },
  });
  assert.equal(outcome.refused, true, 'S0 must not be written over S1');
  assert.equal(outcome.write, undefined);
  assert.equal(outcome.message, SAVE_CONFLICT_MESSAGE);
});

test('a change that arrived during the save refuses it even if the live read raced', () => {
  // The live get can be answered from before the remote write landed, while the change event says
  // it landed. The event is the stronger fact: the store moved, so this payload is stale.
  // (R7 renamed this input to `storeMovedSinceLoad`: an event that arrived just *before* the save
  // disqualifies it exactly as much as one that arrives during it, and the narrower name was the
  // reason the earlier arrival was not being checked at all.)
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const outcome = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0, storeMovedSinceLoad: true,
  });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.message, SAVE_CONFLICT_MESSAGE);
});

test('a save whose page reloaded under it is refused rather than written', () => {
  // A load that landed mid-save replaced the edit state on screen; the payload describes what was
  // there before it. Writing it would store something the user is no longer looking at.
  // (R7: compared against the *applied* generation. The request counter this used to read could not
  // see a load that was requested before the save started.)
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const outcome = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0,
    appliedGenerationAtStart: 1, appliedGenerationNow: 2,
  });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.message, SAVE_RELOADED_MESSAGE);
  assert.match(SAVE_RELOADED_MESSAGE, /save again/i);
});

test('only one save is in flight at a time', () => {
  // Two saves started from the same captured world would both pass their own check and the later
  // write would win with information from before the earlier one landed.
  assert.equal(shouldStartSave({ loaded: true, saving: false }), true);
  assert.equal(shouldStartSave({ loaded: true, saving: true }), false);
  assert.equal(shouldStartSave({ loaded: false, saving: false }), false);
});

test('a synced change is held, not adopted, while a save is in flight', () => {
  // Adoption during a save is what replaced the snapshot the save was comparing against. A save in
  // flight is unsaved work like any other.
  const saving = true;
  assert.equal(shouldAdoptSyncedChange(false || false || saving, { buttons: {} }), false);
});

test('an import that finished reading after the form moved is refused, not applied', () => {
  // `file.text()` is awaited with the form live. Applying the file over what was typed in that
  // window is the same defect as a stale load answer landing on top of typing.
  const refused = planImport({
    revisionAtStart: 4, revisionNow: 5, generationAtStart: 1, generationNow: 1, settings: { defaultMain: 'x' },
  });
  assert.equal(refused.refused, true);
  assert.equal(refused.apply, undefined);
  assert.equal(refused.message, IMPORT_STALE_MESSAGE);
  assert.match(IMPORT_STALE_MESSAGE, /import again/i);

  const reloaded = planImport({
    revisionAtStart: 4, revisionNow: 4, generationAtStart: 1, generationNow: 2, settings: {},
  });
  assert.equal(reloaded.refused, true, 'a load that landed mid-read replaced the form too');
});

test('an import onto a form that did not move is applied', () => {
  const settings = { defaultMain: 'master' };
  const outcome = planImport({
    revisionAtStart: 4, revisionNow: 4, generationAtStart: 1, generationNow: 1, settings,
  });
  assert.equal(outcome.refused, false);
  assert.equal(outcome.apply, settings);
});

test('an older backup is refused while the stored settings come from the future', () => {
  // Stored version 2 (a newer extension on the account) + a {"version": 0} backup used to merge to
  // 0 through Math.min, and the next Save then wrote that 0 down — the newer machine's decision
  // demoted by a file we understood and settings we did not.
  assert.throws(() => mergedSourceVersion(SETTINGS_VERSION + 1, 0), error => {
    assert.match(error.message, /newer version of the extension/i);
    assert.match(error.message, /chrome:\/\/extensions/);
    return true;
  });
});

test('merging two generations this extension understands still takes the oldest', () => {
  assert.equal(mergedSourceVersion(1, 0), 0);
  assert.equal(mergedSourceVersion(0, 1), 0);
  assert.equal(mergedSourceVersion(SETTINGS_VERSION, SETTINGS_VERSION), SETTINGS_VERSION);
});

// --- The guard comes before the change (class (b)) ---

const { userAction } = vm.runInThisContext('({ userAction })');
const { appendButton } = vm.runInThisContext('({ appendButton })');

test('a user action is the guard and then the change, never the other way round', () => {
  let changed = false;
  assert.equal(userAction(() => false, () => { changed = true; }), false);
  assert.equal(changed, false, 'a refused action must not have changed anything');
  assert.equal(userAction(() => true, () => { changed = true; }), true);
  assert.equal(changed, true);
});

test('the add handler cannot change the edit state before the first load', () => {
  // Codex R5, unresolved from R4: `pr-add.click()` pushed the button onto the edit state and called
  // touch() afterwards, so the guard could only ever refuse a change that had already happened.
  // Same shape for add-override, the card inputs, delete, duplicate, reorder and the checkboxes.
  const page = { buttons: [] };
  const add = loaded => userAction(
    () => shouldAcceptUserAction(loaded),
    () => { page.buttons = appendButton(page.buttons, BUTTON_KINDS.pr); }
  );

  assert.equal(add(false), false);
  assert.deepEqual(page.buttons, [], 'nothing may be added before there are settings');
  assert.equal(add(true), true);
  assert.equal(page.buttons.length, 1);
});

// --- One validator, every reader (class (c)) ---

const { adoptStoredMainBranch } = vm.runInThisContext('({ adoptStoredMainBranch })');

test('a stored override that is not a string is not a branch name', () => {
  // The service worker looked these up with Object.hasOwn only, so `{widget: 42}` sent `main=42`
  // to the app, and a stored string "abc" answered `Object.hasOwn("abc", "0")` — making "a" the
  // main branch of a repository called `0`.
  assert.deepEqual(adoptStoredMainBranch({ repoMainBranch: { widget: 42 } }).overrides, {});
  assert.equal(adoptStoredMainBranch({ repoMainBranch: { widget: 42 } }).skipped, 1);

  const asString = adoptStoredMainBranch({ repoMainBranch: 'abc' });
  assert.equal(asString.overrides, undefined, 'a string is not an override map');
  assert.equal(asString.skipped, 1);

  assert.deepEqual(adoptStoredMainBranch({ repoMainBranch: { a: 'main', b: 7 } }).overrides, { a: 'main' });
  assert.equal(adoptStoredMainBranch({ defaultMain: 42 }).defaultMain, undefined);
  assert.equal(adoptStoredMainBranch({ defaultMain: 'master' }).defaultMain, 'master');
  assert.deepEqual(adoptStoredMainBranch({}), { defaultMain: undefined, overrides: undefined, skipped: 0 });
});

test('a bad entry inside a good key is counted per key, not silently dropped', () => {
  // A file with one unreadable button and one good one imported the good one and said nothing: the
  // key was present in `settings`, so it never reached the "skipped keys" list.
  const { adoptStoredSettings, describeSkipped } = vm.runInThisContext('({ adoptStoredSettings, describeSkipped })');
  const adopted = adoptStoredSettings({
    buttons: [{ face: 'x', label: 'good', command: '{cd}', claudeInputs: [] }, { command: 42 }],
  });
  assert.equal(adopted.settings.buttons.length, 1);
  assert.deepEqual(adopted.skippedByKey, { buttons: 1 });
  assert.deepEqual(describeSkipped({ buttons: 1 }), ['1 entry in buttons could not be used and was skipped']);
  assert.deepEqual(describeSkipped({ issueButtons: 2 }), ['2 entries in issueButtons could not be used and were skipped']);
  assert.deepEqual(describeSkipped({}), []);
});

// --- A signal that arrived is never dropped (R7, class (a)) ---
// "The store moved" reaches this page as a change event or as a read, and both can arrive at a
// moment when the page cannot act on them. Not acting is fine; forgetting is not — every arrival
// ends either adopted or on the banner.

const { classifyStorageChange, SAVE_LOADING_MESSAGE } =
  vm.runInThisContext('({ classifyStorageChange, SAVE_LOADING_MESSAGE })');

test('a save refuses while this page has not caught up with a change it already saw', () => {
  // Codex R6 P1-A, the half that does not lean on read ordering. Another device saved S1, the event
  // arrived, and the re-read is still in flight — so the page knows it is behind the store and its
  // payload describes the world before that change. The live read agreeing with the capture proves
  // nothing here: that read can be answered from before the remote write committed.
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const outcome = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0, storeMovedSinceLoad: true,
  });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.message, SAVE_CONFLICT_MESSAGE);
  assert.equal(outcome.stale, true, 'and the banner has to stay up');
});

test('a load that applied under a save refuses it — the form is not what the payload describes', () => {
  // The generation used to count load *requests*, which cannot answer "was the form replaced?".
  // A load requested before the save started and applied during it never moved that counter.
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  const outcome = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0,
    appliedGenerationAtStart: 1, appliedGenerationNow: 2,
  });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.message, SAVE_RELOADED_MESSAGE);
  assert.equal(outcome.stale, false, 'the page just caught up — it is not behind the store');
});

test('a save does not start while a load is in flight', () => {
  assert.equal(shouldStartSave({ loaded: true, saving: false, loading: false }), true);
  assert.equal(shouldStartSave({ loaded: true, saving: false, loading: true }), false);
  assert.match(SAVE_LOADING_MESSAGE, /again/i);
});

test("Codex's P1-A combination cannot happen: a load applies, or the save is allowed, never both", () => {
  // The reported measurement was `loadApplies:true, saveRefused:false`. Two independent locks make
  // that pair unreachable: the save never starts while the load is in flight, and if one applies
  // anyway the applied-generation check refuses the write.
  const S0 = { buttons: [{ command: 'z {repo}' }], version: 0 };
  assert.equal(shouldStartSave({ loaded: true, saving: false, loading: true }), false, 'lock 1');
  const ifItHadStarted = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0,
    appliedGenerationAtStart: 1, appliedGenerationNow: 2, storeMovedSinceLoad: true,
  });
  assert.equal(ifItHadStarted.refused, true, 'lock 2');
});

test('every arrival of a remote change ends adopted or on the banner, never nowhere', () => {
  const ours = { buttons: {} };
  const base = { changes: ours, loaded: true, saving: false, busy: false, isOwnWrite: false };
  assert.equal(classifyStorageChange(base), 'adopt');
  assert.equal(classifyStorageChange({ ...base, busy: true }), 'banner');
  assert.equal(classifyStorageChange({ ...base, saving: true }), 'defer');
  // Codex R6 P1-B: dropped outright before the first load, with a comment claiming the load in
  // flight would pick it up — it cannot, because its read may predate the change.
  assert.equal(classifyStorageChange({ ...base, loaded: false }), 'defer');
  assert.equal(classifyStorageChange({ ...base, isOwnWrite: true }), 'ignore');
  assert.equal(classifyStorageChange({ ...base, changes: { somethingElse: {} } }), 'ignore');
  assert.equal(classifyStorageChange({ ...base, changes: {} }), 'ignore');
});

test('a load answer that had to be discarded still reports that the store moved', () => {
  // shouldApplyLoadedSnapshot says "do not apply this"; it does not say "forget what you read".
  // The answer is the evidence, so it is what decides the banner.
  const loaded = { buttons: [{ command: 'z {repo}' }], version: 0 };
  assert.equal(saveConflict(loaded, { buttons: [{ command: '{cd}' }], version: 1 }), true);
  assert.equal(saveConflict(loaded, { ...loaded }), false, 'an unchanged store raises no banner');
});

// --- What a filtered-out stored value costs, and who may write over it (R7, class (b)) ---
// The quarantine panel that was drafted here is gone (decision 9): the only realistic producer of
// entries this page cannot read was version skew between machines, and the storage-namespace
// contract removes that at the source. What is left — a hand edit, or a bug of ours — is served by
// skipping loudly, refusing to invent replacements, and saying what Save will do.

const { seedFromStorage, STORED_FROM_FUTURE_MESSAGE, SKIP_CONSEQUENCE } =
  vm.runInThisContext('({ seedFromStorage, STORED_FROM_FUTURE_MESSAGE, SKIP_CONSEQUENCE })');

test('settings written by a newer generation may be read but never written over', () => {
  // Insurance against a breach of decision 9: a future version is supposed to write its own
  // namespace and leave this one alone. If one did not, this page must not answer by recording its
  // own older shape on top.
  const S0 = { buttons: [], version: SETTINGS_VERSION + 1 };
  const outcome = planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0, loadedVersion: SETTINGS_VERSION + 1,
  });
  assert.equal(outcome.refused, true);
  assert.equal(outcome.message, STORED_FROM_FUTURE_MESSAGE);
  assert.equal(outcome.write, undefined);
  assert.match(STORED_FROM_FUTURE_MESSAGE, /newer version of the extension/i);
  assert.match(STORED_FROM_FUTURE_MESSAGE, /chrome:\/\/extensions/);
  // The current generation is not the future, and neither is one we have already caught up to
  assert.equal(planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0, loadedVersion: SETTINGS_VERSION,
  }).refused, false);
  assert.equal(planSave({
    capturedSnapshot: S0, liveSnapshot: { ...S0 }, payload: S0, loadedVersion: 0,
  }).refused, false);
});

test('a key that lost entries is not refilled with our defaults', () => {
  // Codex R6 P1-C: `claudeInputs: "!secret"` made the entry unreadable, the section fell back to the
  // shipped preset, and an ordinary Save then recorded that preset over a command the user had
  // written. "Nothing stored" and "stored something we could not use" are different answers.
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  const adopted = adoptStoredSettings({
    buttons: [{ face: 'x', label: 'mine', command: 'z {repo} && git clean -fdx', claudeInputs: '!secret' }],
  });
  assert.equal(adopted.settings.buttons.length, 0);
  assert.equal(adopted.skippedByKey.buttons, 1);

  const defaults = [{ command: '{cd} && claude' }];
  assert.deepEqual(seedFromStorage(adopted.settings.buttons, defaults, 1), [], 'read nothing usable: stay empty');
  assert.equal(seedFromStorage(undefined, defaults, 0), defaults, 'a key that was never saved still gets presets');
  assert.equal(seedFromStorage([], defaults, 0), defaults, 'a clean empty array keeps its old meaning');
});

test('entries beyond the button limit are skipped and counted, never silently trimmed', () => {
  // The limits used to be enforced only on the import path, so storage readers passed a fourth
  // button through to the app while import quietly dropped it — and a quiet drop is the same defect
  // as P1-C, because the next Save records the trimmed list.
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  const button = n => ({ face: 'x', label: `b${n}`, command: `{cd} && echo ${n}`, claudeInputs: [] });
  const adopted = adoptStoredSettings({ buttons: [button(1), button(2), button(3), button(4)] });
  assert.equal(adopted.settings.buttons.length, 3);
  assert.equal(adopted.skippedByKey.buttons, 1);
  assert.equal(adopted.settings.buttons[2].command, '{cd} && echo 3', 'the ones kept are the first ones');
});

test('claude inputs beyond the limit make the whole entry unusable rather than being trimmed', () => {
  const { adoptStoredSettings } = vm.runInThisContext('({ adoptStoredSettings })');
  const claudeInputs = ['1', '2', '3', '4', '5', '6'];
  const adopted = adoptStoredSettings({ buttons: [{ face: 'x', label: 'b', command: '{cd}', claudeInputs }] });
  assert.equal(adopted.settings.buttons.length, 0);
  assert.equal(adopted.skippedByKey.buttons, 1);
});

test('the report says what Save is going to do about what it skipped', () => {
  // Skipping is only honest if the consequence is stated: the entries are not in the edit state, so
  // the next Save writes them out of existence.
  assert.match(SKIP_CONSEQUENCE, /saving will remove/i);
  assert.match(SKIP_CONSEQUENCE, /export/i);
});
