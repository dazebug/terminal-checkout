// Migration registry for saved settings. Loaded by the options page only (options.html), after
// defaults.js — nothing else needs it: content.js and background.js run whatever command is stored,
// migrated or not, which is what lets a stale settings object keep working until its owner consents.
//
// The rules this file exists to hold:
//   - A candidate is either an old preset matched **verbatim**, or a customized command whose
//     **first clause** is exactly the old jump (only that clause is replaced). Any other shape is
//     never rewritten; it is listed with a note so its owner can decide.
//   - Every entry declares whether its replacement is unconditionally better or changes behavior.
//     An entry that cannot say which does not ship (issue #31).
//   - The version only ever moves as the result of an explicit act by the user.

// The v0 preset strings are history: they exist nowhere else in the tree (see
// `git show 294c46a:extension/defaults.js`), so they are written out here verbatim and must not be
// "tidied". The 11 v0 presets collapse to 8 distinct commands — `z {repo} && claude` was shared by
// three presets and `z {repo}` by two — and the same string always maps to the same replacement, so
// the map needs no per-page split.
//
// A Map, not an object literal. Every lookup is keyed by a command out of someone's settings, and on
// a plain object `rewrites['constructor']` — or 'toString', '__proto__', 'valueOf' — answers with an
// inherited member: those commands read as verbatim matches, were offered as candidates, and then
// threw on save. A Map has no prototype chain to fall through into.
const V0_TO_V1 = new Map(Object.entries({
  'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }':
    '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude':
    '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude',
  'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude':
    '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude',
  'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}':
    '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}',
  'z {repo} && claude': '{cd} && claude',
  'z {repo} && git fetch origin && ([ -d ../{repo}-issue-{number} ] || git worktree add -f ../{repo}-issue-{number} -b issue-{number} origin/{main}) && cd ../{repo}-issue-{number} && claude':
    '{cd} && git fetch origin && ([ -d ../{repo}-issue-{number} ] || git worktree add -f ../{repo}-issue-{number} -b issue-{number} origin/{main}) && cd ../{repo}-issue-{number} && claude',
  'z {repo}': '{cd}',
  'z {repo} && git checkout {main} && git pull --ff-only': '{cd} && git checkout {main} && git pull --ff-only',
}));

// The clause v0 opened with, and what replaces it. Kept apart from the verbatim map because the
// prefix rule below rewrites *only* this leading clause and leaves the rest of the command alone.
const V0_ENTRY_CLAUSE = 'z {repo}';
const V1_ENTRY_CLAUSE = '{cd}';

const MIGRATIONS = [
  {
    from: 0,
    to: 1,
    // `effect` answers one question and only that one: **is there any app configuration under
    // which this rewrite leaves the user worse off?** 'unconditional' means no; 'behavior-change'
    // means yes, and the preview must then make the user weigh it per item.
    //
    // By that definition this hop is unconditional. With no base directory the rendered command is
    // byte-identical. With one, the button gains fallbacks — but those come from a setting the user
    // switched on in the app themselves, and `{cd}` is how that setting was always meant to reach
    // the command; the rewrite is the wiring, not the decision. Neither case is worse than today.
    // (Without a stated definition "does more than before" would read as behavior-change, which is
    // why the definition is written down here rather than left to taste.)
    effect: 'unconditional',
    rewrites: V0_TO_V1,
    describe:
      'The command opens with {cd} instead of z {repo}. With no repository base folder set in the '
        + 'Terminal Checkout app this runs exactly what it runs today; if you have set one, z failing '
        + 'now falls back to that folder and clones the repository when it is not there.',
    customNote:
      'This command was edited, so it is left exactly as it is — `z {repo}` is not its first clause, '
        + 'and rewriting it safely would mean parsing the shell. Replace the leading jump with {cd} '
        + 'yourself if you want the same fallbacks.',
    // Rewrites a customized command whose **first clause** is exactly the old jump, leaving every
    // other byte alone. Anything looser (a `z {repo}` in the middle, `z {repo};`, `z {repo}&&x`,
    // different spacing) is refused and listed instead: matching those needs shell parsing, and
    // guessing wrong edits a command we were told not to touch.
    promote: command => {
      if (command === V0_ENTRY_CLAUSE) return V1_ENTRY_CLAUSE;
      if (!command.startsWith(`${V0_ENTRY_CLAUSE} && `)) return null;
      // `z {repo} && ` with nothing after it is not a jump with a tail, it is a broken command.
      // Rewriting it would hand back a differently broken one and claim it as an improvement.
      if (command.slice(`${V0_ENTRY_CLAUSE} && `.length).trim() === '') return null;
      return V1_ENTRY_CLAUSE + command.slice(V0_ENTRY_CLAUSE.length);
    },
    // Whether a command we are not going to rewrite still belongs to the old generation, and is
    // therefore worth mentioning. Without this, a custom command already written with {cd} would be
    // listed forever with nothing to do about it. The leading boundary keeps `xyz {repo}` out.
    isStale: command => /(?:^|[^\w])z\s+\{repo\}/.test(command),
  },
];

// A version is a non-negative **integer** or it is not a version. Anything else — a fraction, a
// negative, a string, NaN — is a value we cannot reason about, and the one that matters is the
// fraction: 0.5 used to pass as valid and then sat between two steps, so the whole 0->1 hop was
// skipped and the user was shown an empty review to confirm. Stored settings and imported files are
// judged here, together, so they cannot drift apart.
function normalizeVersion(raw) {
  return Number.isInteger(raw) && raw >= 0 ? raw : null;
}

// The generation a stored settings object has been reviewed against.
//
// A fresh profile and a legacy one both lack the version key; the only thing that tells them apart
// is whether anything else was ever saved. Getting this backwards is expensive in both directions —
// a new user greeted by a migration notice, or a legacy user promoted without ever seeing one.
function storedSchemaVersion(stored) {
  const version = normalizeVersion(stored?.[VERSION_KEY]);
  if (version !== null) return version;
  const hasSettings = SETTINGS_KEYS.some(key => stored?.[key] !== undefined);
  return hasSettings ? 0 : SETTINGS_VERSION;
}

// What the version becomes on save. `reviewed` is true only after an explicit act — applying the
// migration (in whole or in part), declining it, acknowledging that there was nothing to change, or
// resetting to defaults. Everything else preserves what was read, which is what stops an ordinary
// save from silently swallowing a pending migration.
// A version from the future is never lowered. That can only reach us through the normal load path —
// another machine on the account running a newer extension — because a newer *backup* is refused at
// import (see importedSchemaVersion) rather than filled in.
// The generation of an edit state assembled from more than one source — what was on screen plus an
// imported file. It answers for the **oldest** thing in it: reviewing the merged state has to cover
// the older half, or importing a current file would license stale commands that came from elsewhere.
function mergedSourceVersion(current, incoming) {
  return Math.min(current, incoming);
}

function versionToSave({ loadedVersion, reviewed }) {
  if (!reviewed) return loadedVersion;
  return Math.max(loadedVersion, SETTINGS_VERSION);
}

// Splits a stored settings object into what we may rewrite and what we may only point at.
//
// `actionable` items are candidates the user consents to one by one (checked by default);
// `informational` items are never rewritten by us. A key that was never saved is skipped entirely —
// those buttons are the current defaults, so there is nothing to migrate.
// `source` records how a candidate was found: 'verbatim' (it was an old preset, byte for byte) or
// 'prefix' (it was customized, but its first clause was exactly the old jump). The preview shows
// the difference so a user can see that we recognized their edit rather than ignoring it.
// Steps are chosen by where they land, not where they start: `step.to > fromVersion` still picks up
// the 0->1 hop for a version of 0.5, whereas `step.from >= 0.5` silently skipped it. normalizeVersion
// should keep fractions out entirely — this is the second lock on the same door.
function stepsFrom(fromVersion) {
  return MIGRATIONS.filter(step => step.to > fromVersion);
}

// The preview's wording, covering every step being applied rather than only the last one.
function migrationDescription(fromVersion) {
  return stepsFrom(fromVersion).map(step => step.describe).join(' ');
}

function planMigration(stored, fromVersion) {
  const steps = stepsFrom(fromVersion);
  const actionable = [];
  const informational = [];

  for (const [kind, { storageKey }] of Object.entries(BUTTON_KINDS)) {
    const buttons = stored?.[storageKey];
    if (!Array.isArray(buttons)) continue;

    buttons.forEach((button, index) => {
      const command = typeof button?.command === 'string' ? button.command : '';
      if (!command) return;

      let current = command;
      let source = null;
      let behaviorChange = false;
      for (const step of steps) {
        const verbatim = step.rewrites?.get(current);
        const promoted = verbatim === undefined ? step.promote?.(current) : verbatim;
        if (promoted === undefined || promoted === null || promoted === current) continue;
        // The first step that matched says how this entered the chain
        source = source || (verbatim === undefined ? 'prefix' : 'verbatim');
        behaviorChange = behaviorChange || step.effect === 'behavior-change';
        current = promoted;
      }

      // A candidate is named by the button's uid, never by where it sits. The plan is built from the
      // edit state and applied to the edit state, and in between the user can type, reorder, add and
      // delete — an index stops meaning the same button the moment any of that happens. Without a
      // uid we cannot name it, so we do not offer it.
      if (typeof button.uid !== 'string' && typeof button.uid !== 'number') return;
      const where = { id: button.uid, storageKey, kind, index, label: button.label || '' };
      if (current !== command) {
        actionable.push({
          ...where,
          from: command,
          to: current,
          source,
          // Worst case across the steps that applied: one behavior change anywhere makes the whole
          // hop a behavior change for this button
          effect: behaviorChange ? 'behavior-change' : 'unconditional',
        });
        return;
      }
      const stale = steps.find(step => step.isStale?.(command));
      if (stale) informational.push({ ...where, command, note: stale.customNote });
    });
  }

  return { fromVersion, targetVersion: SETTINGS_VERSION, actionable, informational };
}

// A new settings object with the selected candidates rewritten. Everything else — unselected
// candidates, other fields of the same button, keys we never looked at — is carried over untouched,
// and the input is never mutated: the caller still needs the original to show the "from" side.
function applyMigrationPlan(stored, plan, selectedIds) {
  const selected = new Set(selectedIds);
  const next = { ...stored };
  for (const item of plan.actionable) {
    if (!selected.has(item.id)) continue;
    const list = next[item.storageKey];
    if (!Array.isArray(list)) continue;
    // Find the button by name. `item.index` is only good for showing the user where it was.
    const index = list.findIndex(button => button?.uid === item.id);
    if (index === -1) continue; // deleted, or moved to another section, since planning
    // Even the right button may no longer hold the command that was planned — someone can type over
    // it while the preview is open. Rewrite only what was actually reviewed.
    if (list[index].command !== item.from) continue;
    // Copy each touched array once; later hits on the same key edit the copy
    const buttons = list === stored[item.storageKey] ? list.slice() : list;
    buttons[index] = { ...buttons[index], command: item.to };
    next[item.storageKey] = buttons;
  }
  return next;
}

// What the preview panel needs to know, without it having to count anything itself.
// `nothingToApply` (the user unchecked everything) and `reviewOnly` (there was nothing to check in
// the first place) are different states: both finish by promoting the version, but only the second
// one has no rewrite to describe.
function migrationSummary(plan, selectedIds) {
  const selected = new Set(selectedIds);
  const selectedCount = plan.actionable.filter(item => selected.has(item.id)).length;
  return {
    actionableCount: plan.actionable.length,
    informationalCount: plan.informational.length,
    selectedCount,
    nothingToApply: selectedCount === 0,
    reviewOnly: plan.actionable.length === 0,
  };
}

// The generation a *backup file* was written by.
//
// Unlike storedSchemaVersion this treats a missing version as legacy rather than fresh: an imported
// file always has content (parseImportedSettings refuses an empty one), so "no version" can only
// mean it predates the field. A version we do not understand is refused outright rather than
// half-imported — we cannot know what its keys mean, and filling the form with them would invite a
// Save that quietly downgrades the account.
function importedSchemaVersion(data) {
  const raw = normalizeVersion(data?.[VERSION_KEY]);
  if (raw === null) return 0;
  if (raw > SETTINGS_VERSION) {
    throw new Error(
      'This backup was exported by a newer version of the extension. '
        + 'Update the extension (`git pull` + refresh at chrome://extensions), '
        + 'or use Reset to Defaults to start from the current presets.'
    );
  }
  return raw;
}

// Whether a storage change that arrived from another machine should be pulled into the page.
// Unsaved edits always win: the whole point of the single write path is that nothing lands without
// a Save, and silently replacing what someone is typing would be the worst possible reading of
// "keep it in sync".
function shouldAdoptSyncedChange(dirty, changes) {
  if (dirty) return false;
  const ours = new Set([...SETTINGS_KEYS, VERSION_KEY]);
  return Object.keys(changes || {}).some(key => ours.has(key));
}

// The highest version this page has ever seen, from any source. It rises and never falls.
//
// The floor exists because reading and writing are far apart in time: the page loads a version,
// the user edits for a while, and another machine can save a newer one in between. Writing what was
// loaded would then downgrade the account and bring the notice back everywhere. A reading that is
// not a version at all changes nothing.
function raiseVersionFloor(floor, observed) {
  const version = normalizeVersion(observed);
  return version === null ? floor : Math.max(floor, version);
}

// The version a save actually writes: never below the floor, never below what is in storage right
// now, and at least what consent asks for. `live` is a fresh read taken immediately before the
// write, which is what closes the window the floor alone cannot see — another machine's save that
// landed after this page loaded.
function versionToWrite({ floor, live, loadedVersion, reviewed }) {
  return Math.max(
    raiseVersionFloor(floor, live),
    versionToSave({ loadedVersion, reviewed })
  );
}

// Whether a settings snapshot read from storage may still be applied to the page.
//
// Between asking storage for the settings and getting them back, the user can type, toggle a
// checkbox, or start editing. Any of that makes the snapshot older than the screen, and applying it
// would silently undo what they just did. `revision` counts every such act — including checkbox
// toggles, which are not "dirty" edits but are still the user speaking about this plan.
function shouldApplyLoadedSnapshot({ revisionAtStart, revisionNow, dirty }) {
  return !dirty && revisionAtStart === revisionNow;
}
