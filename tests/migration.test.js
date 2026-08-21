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
    // Two values only. "conditional" was dropped: for v0->v1 the base-directory fallbacks are
    // caused by a setting the user turned on in the app themselves, not by this rewrite, so the
    // rewrite is unconditionally safe and the base directory is a note rather than a verdict.
    assert.ok(
      ['unconditional', 'behavior-change'].includes(entry.effect),
      `${entry.from}->${entry.to}: effect must be declared`
    );
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
const stored = (key, ...commands) => ({
  [key]: commands.map((command, i) => ({ face: 'x', label: `b${i}`, command, claudeInputs: [] })),
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
  // Revised decision 4: strict prefix only, and only the first clause is replaced
  const plan = plan0(stored('buttons', 'z {repo} && npm test'));
  assert.equal(plan.informational.length, 0);
  assert.deepEqual(
    { to: plan.actionable[0].to, source: plan.actionable[0].source, effect: plan.actionable[0].effect },
    { to: '{cd} && npm test', source: 'prefix', effect: 'unconditional' }
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
  assert.deepEqual(ids(plan.actionable), ['issueButtons:0', 'issueButtons:1']);
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
  const next = applyMigrationPlan(data, plan, ['buttons:1']);
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
  const data = { buttons: [{ face: '🤖', label: 'mine', command: V0.claude, claudeInputs: ['/review'] }] };
  const next = applyMigrationPlan(data, plan0(data), ['buttons:0']);
  assert.deepEqual(next.buttons[0], {
    face: '🤖', label: 'mine', command: V1.claude, claudeInputs: ['/review'],
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
