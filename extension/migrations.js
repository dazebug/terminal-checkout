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

// The v0 preset strings exist nowhere else in the tree, so they are written out here verbatim and must not be
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
    // `effect` answers one question and only that one: **within the base directory's own contract —
    // that `<base>/<repo>` is the repository it is named after — does this rewrite leave the user
    // worse off under any app configuration?** 'unconditional' means no; 'behavior-change' means
    // yes, and the preview then makes the user weigh it per item, unchecked by default.
    //
    // The contract has to be named, because outside it nothing here is unconditional: if
    // `<base>/<repo>` is a *different* repository that happens to share the name, `{cd}` runs the
    // command there. That is a residual #32 accepted knowingly (it is the same class as `z`'s fuzzy
    // jump, and it is the user's own directory layout), and it propagates into every judgment on
    // this page. Saying "under any configuration whatsoever" would simply be false.
    //
    // The effect is declared per *candidate kind*, because the two make very different promises.
    //
    // Replacing a preset we shipped, byte for byte, is unconditional: we know the entire command.
    // With no base directory the render is identical; with one, the fallbacks come from a setting
    // the user switched on themselves, and `{cd}` is how that setting was always meant to reach the
    // command — the rewrite is the wiring, not the decision.
    verbatimEffect: 'unconditional',
    // Replacing the first clause of a command someone else wrote is not, because the rest of it is
    // arbitrary and will now run somewhere else. `z {repo} && git clean -fdx` did nothing when the
    // jump failed; with a base directory it lands in <base>/<repo> — possibly a different
    // repository that happens to share the name — and deletes there. "No configuration makes this
    // worse" cannot be claimed over a command we did not write, so the user opts in per item.
    prefixEffect: 'behavior-change',
    rewrites: V0_TO_V1,
    // Getters, not values: this object is built when the file loads, and a sentence read then
    // is the language the page started in. Every one of these is drawn by the options page.
    get describe() { return tr('ext.migration.v1.describe'); },
    get prefixDescribe() { return tr('ext.migration.v1.prefixDescribe'); },
    get customNote() { return tr('ext.migration.v1.customNote'); },
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
  {
    from: 1,
    to: 2,
    // The list-page settings are a new namespace, not a rewrite of a command the user already owns.
    // The review still matters: it is the explicit acknowledgement that the form now includes the
    // two current list presets, and only that act may move the stored generation to 2.
    reviewOnly: true,
    rewrites: new Map(),
    get describe() { return tr('ext.migration.v2.describe'); },
  },
  {
    from: 2,
    to: 3,
    // The v2 list generation named its variables {pr}/{issue}; they were renamed to the {number}
    // the detail pages already use — the same value under a new name, so the rendered command is
    // byte-identical and the rewrite is unconditional. Without it, a saved list button holding the
    // old names silently stops rendering (the visibility predicate fails closed).
    //
    // Scoped to the two list kinds: elsewhere those names were never provided, so a command holding
    // them there is the owner's own experiment and renaming it would guess at an intent the page
    // never defined.
    appliesTo: kind => kind === 'pr-list' || kind === 'issue-list',
    verbatimEffect: 'unconditional',
    prefixEffect: 'unconditional',
    rewrites: new Map(),
    get describe() { return tr('ext.migration.v3.describe'); },
    get prefixDescribe() { return tr('ext.migration.v3.describe'); },
    promote: command => {
      const renamed = command.split('{pr}').join('{number}').split('{issue}').join('{number}');
      return renamed === command ? null : renamed;
    },
    promoteInput: input => {
      const renamed = input.split('{pr}').join('{number}').split('{issue}').join('{number}');
      return renamed === input ? null : renamed;
    },
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

// A generation newer than this extension understands can arrive two ways, and neither may be
// papered over: from a backup file, and from the account's own storage (another machine running a
// newer extension). Both messages have to carry the way out, or the user is simply stuck.
// A getter for the same reason the step's sentences are, and it quotes the [Reset to Defaults]
// button through a placeholder rather than spelling the label out again.
const BACKUP_FROM_FUTURE_MESSAGE = () => tr('ext.error.backupFromFuture', tr('ext.button.reset'));

// Read yes, write no. This page can show settings from a newer generation and export them; anything
// it writes would be its own older shape recorded on top of theirs. One message serves both the
// import refusal and the save refusal, because the reason is the same in both.
//
// Under the storage-version contract this should be unreachable — a version that raises
// SETTINGS_VERSION writes its
// own namespace and never touches this one. It is the insurance against that contract being broken.
const STORED_FROM_FUTURE_MESSAGE = () => tr('ext.error.storedFromFuture');

// Every report of something skipped carries this. Skipping is only honest if the consequence is
// stated: the entries are not in the edit state, so the next Save writes them out of existence, and
// the copy the user can still take is an export of what is stored right now.
// Quotes the [Export (JSON)] button by key, so a translation cannot make the sentence name a
// control by a different word than the control itself uses.
const SKIP_CONSEQUENCE = () => tr('ext.error.skipConsequence', tr('ext.button.export'));

// What a section of the edit state starts from.
//
// "Nothing was stored under this key" and "something was stored and none of it could be used" are
// different answers, and answering the second one with our presets is a rewrite: the presets are
// then what the next ordinary Save records, over a command the user wrote. So defaults are for the
// first case only. A key that held something keeps whatever survived, even if that is nothing —
// the report says what went and what saving will do about it.
//
// This is not a guard against the user's own hand edits, which are theirs to make and theirs to
// own; it is a guard against *our* filter being wrong, so that a bug on our side ends in a visible
// empty section rather than a silent substitution.
function seedFromStorage(read, defaults, skippedForKey) {
  if (read?.length) return read;
  return skippedForKey ? [] : defaults;
}

// The generation of an edit state assembled from more than one source — what was on screen plus an
// imported file. It answers for the **oldest** thing in it: reviewing the merged state has to cover
// the older half, or importing a current file would license stale commands that came from elsewhere.
//
// Taking the minimum only means that while both sides are generations this extension understands.
// With a stored version of 2 and a file of 0 it produced 0, and the next Save wrote that 0 down —
// the newer machine's review demoted by a merge of a file we understood into settings we did not.
// The precondition is checked here rather than at the call site, because it is what makes the
// arithmetic mean anything.
function mergedSourceVersion(current, incoming) {
  if (current > SETTINGS_VERSION) throw new Error(STORED_FROM_FUTURE_MESSAGE());
  // Import already refuses a newer file outright (importedSchemaVersion); this is the second lock
  // on the same door, so the assumption cannot be quietly broken by a future caller.
  if (incoming > SETTINGS_VERSION) throw new Error(BACKUP_FROM_FUTURE_MESSAGE());
  return Math.min(current, incoming);
}

// What the version becomes on save. `reviewed` is true only after an explicit act — applying the
// migration (in whole or in part), declining it, acknowledging that there was nothing to change, or
// resetting to defaults. Everything else preserves what was read, which is what stops an ordinary
// save from silently swallowing a pending migration.
// A version from the future is never lowered. That can only reach us through the normal load path —
// another machine on the account running a newer extension — because a newer *backup* is refused at
// import (see importedSchemaVersion) rather than filled in.
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

      // Raw, not filtered: the apply-time guard compares these bytes against the live button, and a
      // cleaned copy would never match a button that still holds the entry we cleaned away.
      // A copy, not the live array: the options handlers edit claudeInputs in place on the very
      // objects handed to the planner, and a retained reference would mutate fromInputs along with
      // the user's edit — the guard would then bless overwriting their new text.
      const inputs = Array.isArray(button?.claudeInputs) ? button.claudeInputs.slice() : [];
      let current = command;
      let currentInputs = inputs;
      let source = null;
      let describe = '';
      let behaviorChange = false;
      for (const step of steps) {
        // A step may scope itself to the kinds whose generation it describes; outside that scope
        // the same bytes belong to someone else's experiment and are not this step's to rewrite.
        if (step.appliesTo && !step.appliesTo(kind)) continue;
        const verbatim = step.rewrites?.get(current);
        const promoted = verbatim === undefined ? step.promote?.(current) : verbatim;
        const commandMoved = !(promoted === undefined || promoted === null || promoted === current);
        const nextInputs = step.promoteInput
          ? currentInputs.map(v => (typeof v === 'string' ? (step.promoteInput(v) ?? v) : v))
          : currentInputs;
        const inputsMoved = nextInputs.some((v, i) => v !== currentInputs[i]);
        if (!commandMoved && !inputsMoved) continue;
        const viaPrefix = !commandMoved || verbatim === undefined;
        // The first step that matched says how this entered the chain
        source = source || (viaPrefix ? 'prefix' : 'verbatim');
        behaviorChange = behaviorChange
          || (viaPrefix ? step.prefixEffect : step.verbatimEffect) === 'behavior-change';
        describe = [describe, viaPrefix ? step.prefixDescribe : step.describe].filter(Boolean).join(' ');
        if (commandMoved) current = promoted;
        if (inputsMoved) currentInputs = nextInputs;
      }

      // A candidate is named by the button's uid, never by where it sits. The plan is built from the
      // edit state and applied to the edit state, and in between the user can type, reorder, add and
      // delete — an index stops meaning the same button the moment any of that happens. Without a
      // uid we cannot name it, so we do not offer it.
      if (typeof button.uid !== 'string' && typeof button.uid !== 'number') return;
      const where = { id: button.uid, storageKey, kind, index, label: button.label || '' };
      const inputsChanged = currentInputs !== inputs;
      if (current !== command || inputsChanged) {
        actionable.push({
          ...where,
          from: command,
          to: current,
          source,
          describe,
          ...(inputsChanged ? { fromInputs: inputs, toInputs: currentInputs } : {}),
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
//
// `applied` is how many were actually rewritten, which is not how many were checked: a candidate
// whose button was deleted, moved, or typed over since the preview was built is skipped by the
// guards below. Reporting the checkbox count instead said "2 commands updated" for one rewrite and
// one silent skip — the number has to come from the loop that does the work.
function applyMigrationPlan(stored, plan, selectedIds) {
  const selected = new Set(selectedIds);
  const next = { ...stored };
  let applied = 0;
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
    // The same guard for claude inputs, element by element: a plan that promised to rename an input
    // must find that exact input still there, or the rewrite would replace text the user typed
    // after the preview was built.
    if (item.fromInputs) {
      const live = Array.isArray(list[index].claudeInputs) ? list[index].claudeInputs : [];
      if (live.length !== item.fromInputs.length
        || live.some((v, i) => v !== item.fromInputs[i])) continue;
    }
    // Copy each touched array once; later hits on the same key edit the copy
    const buttons = list === stored[item.storageKey] ? list.slice() : list;
    buttons[index] = {
      ...buttons[index],
      command: item.to,
      ...(item.toInputs ? { claudeInputs: item.toInputs } : {}),
    };
    next[item.storageKey] = buttons;
    applied += 1;
  }
  return { settings: next, applied };
}

// Which candidates start checked. Only the ones nothing can go wrong with: a behavior change is
// something the user opts into after reading it, never something they have to notice and opt out of.
function defaultSelection(plan) {
  return plan.actionable.filter(item => item.effect === 'unconditional').map(item => item.id);
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
    descriptions: migrationDescription(plan.fromVersion),
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
  if (raw > SETTINGS_VERSION) throw new Error(BACKUP_FROM_FUTURE_MESSAGE());
  return raw;
}

// Whether a storage change that arrived from another machine should be pulled into the page.
// Unsaved edits always win: the whole point of the single write path is that nothing lands without
// a Save, and silently replacing what someone is typing would be the worst possible reading of
// "keep it in sync".
// Which of the changed keys are ours. One filter, used for three decisions — whether to adopt,
// whether to warn, and whether a change is our own write coming back — so they cannot disagree
// about what counts as a change to this page's settings.
function ownedChangedKeys(changes) {
  const ours = new Set([...SETTINGS_KEYS, VERSION_KEY]);
  return Object.keys(changes || {}).filter(key => ours.has(key));
}

// `busy` covers both kinds of unsaved work: text being edited, and a review being decided. Checking
// boxes is not "dirty" — nothing has been typed — but it is the user answering a question, and
// re-planning underneath them silently restores the choices they just made. Applying then rewrote
// the very button they had declined.
function shouldAdoptSyncedChange(busy, changes) {
  if (busy) return false;
  return ownedChangedKeys(changes).length > 0;
}

// Our own save comes back to us as a change event. It is not another device, and treating it as one
// warns about a conflict with ourselves and throws away a review in progress. The snapshot we
// recorded when writing is what tells the two apart.
function isOwnEcho(changes, loadedSnapshot) {
  const owned = ownedChangedKeys(changes);
  if (!owned.length) return false;
  return owned.every(key => sameStoredValue(changes[key]?.newValue, loadedSnapshot?.[key]));
}

// storage.sync has no compare-and-set, so two pages editing one account can only be told apart by
// looking. Before writing, the page re-reads every key it owns and compares it against what it read
// when it loaded; if anything moved, the save is refused.
//
// Refusing rather than merging is the whole point, and it replaces a design that got this wrong. An
// earlier version kept a "floor" of the highest version ever seen and wrote that alongside whatever
// content the page happened to hold — which stamped a v1 marker onto v0 commands and erased another
// device's migration without a word. The version states which generation **the content being
// written** belongs to; it cannot be defended separately from the content it describes.
// **Deliberately not the same sentence as the stale banner.** Two near-identical strings are the
// worst of both: the ownership gate only refuses exact duplicates, so a copy-paste slip can survive
// while reading to a user as the same message. They are said at two different moments and report
// different things — the banner warns that the store moved, this one reports that a save was refused.
const SAVE_CONFLICT_MESSAGE = () => tr('ext.error.saveConflict');

function sameStoredValue(a, b) {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  // Length before keys: `new Array(1)` and `[]` have the same (empty) key set, so comparing keys
  // alone calls two different arrays identical — and a save would then land on a store that had in
  // fact changed.
  if (Array.isArray(a) && a.length !== b.length) return false;
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  return keysA.every(key => Object.hasOwn(b, key) && sameStoredValue(a[key], b[key]));
}

// True when the settings moved under us since the load. Every key we own is compared, the version
// included — a version change on its own means another device reviewed the migration, and writing
// over that undoes their decision just as surely as overwriting their commands would.
function saveConflict(loadedSnapshot, liveSnapshot) {
  return [...SETTINGS_KEYS, VERSION_KEY].some(
    key => !sameStoredValue(loadedSnapshot?.[key], liveSnapshot?.[key])
  );
}

// A load landed while the save was in flight, so the form on screen is no longer the one the
// payload was built from. Writing it would store settings the user is not looking at.
const SAVE_RELOADED_MESSAGE = () => tr('ext.error.saveReloaded', tr('ext.button.save'));

// A load is out and its answer may replace the form at any moment. Starting a save into that window
// means building a payload from a form that is about to be someone else's.
const SAVE_LOADING_MESSAGE = () => tr('ext.error.saveLoading', tr('ext.button.save'));

// Nothing capped the length of a command, so one long enough pushed a key past what storage.sync
// will hold and the save died on the quota error itself. Checked per key, because that is the unit
// the limit applies to — and checking it here covers commands, scheduled inputs and the override map
// in one place rather than growing a length rule per field.
const SETTINGS_TOO_LARGE_MESSAGE = () => tr('ext.error.settingsTooLarge');

function oversizedSettingsKey(payload) {
  for (const [key, value] of Object.entries(payload || {})) {
    if (storedItemBytes(key, value) > MAX_STORED_ITEM_BYTES) return key;
  }
  return null;
}

// Whether a page-changing task — a save, an import, a load — may start.
//
// Each of the three builds something out of the form, or puts something into it, across an await.
// Any two of them overlapping means one is working from a form the other is about to replace: two
// saves each captured the same world and the later write landed with older information; a save
// started while a file was being read wrote a payload the file was about to overwrite; a load
// answering mid-import replaced the form the file was about to be applied to.
//
// One rule for all three, rather than one gate per task. The previous version enumerated the
// exclusions per task and got the enumeration wrong: imports excluded other imports and nothing
// else, so the save-during-import case simply was not covered. A task cannot start while it is
// already running either, which is why nothing here subtracts the caller from the check.
function pageIsBusy({ saving, importing, loading }) {
  return saving === true || importing === true || loading === true;
}

function shouldStartPageTask({ loaded, saving, importing, loading }) {
  return loaded === true && !pageIsBusy({ saving, importing, loading });
}

// Which task is in the way, so the refusal says something the user can act on rather than a generic
// "busy". Null when nothing is.
function pageBusyMessage({ saving, importing, loading }) {
  if (saving) return SAVE_BUSY_MESSAGE();
  if (importing) return IMPORT_BUSY_MESSAGE();
  if (loading) return SAVE_LOADING_MESSAGE();
  return null;
}

const SAVE_BUSY_MESSAGE = () => tr('ext.error.saveBusy');

// The save as a decision, kept apart from the act of writing so it can be reasoned about on its own.
// A refusal carries the message and writes nothing; there is no repair attempted behind the user's
// back, because any repair here would be a guess about which of two intentions to keep.
//
// Three questions, none of which the others can answer.
//
// `storeMovedSinceLoad` — a change event for one of our keys has arrived that this page has not
// caught up with, whether it landed just before this save or during it. It is the only check here
// that does not depend on a read, and that is why it exists: the live read can be answered from
// before a remote write committed, so "the read agrees with my capture" is not proof that nothing
// moved. An event is proof that something did.
//
// `appliedGeneration` — did a load *apply* under this save? The counter that used to be compared
// here counted load *requests*, which cannot answer that: a load requested before the save started
// and applied halfway through never moved it, and the write went out describing a form that had
// already been replaced.
//
// `capturedSnapshot` versus the live read — the original optimistic check. `capturedSnapshot` is
// what the store held when *this save* started, taken once and never re-read from the page, because
// adoption is not a user action and bumps no revision: a change adopted mid-save used to be pulled
// into `loadedSnapshot` and the comparison became S1 against S1.
//
// `stale` says whether the banner should be up afterwards. A conflict means the page is behind the
// store; a reload means it has just caught up, and warning there would be a lie.
function planSave({
  capturedSnapshot, liveSnapshot, payload,
  appliedGenerationAtStart, appliedGenerationNow, storeMovedSinceLoad, loadedVersion,
}) {
  // First, because no retry and no reload changes it: settings from a generation this extension does
  // not understand may be read, shown and exported, but never written over.
  if (loadedVersion > SETTINGS_VERSION) {
    return { refused: true, message: STORED_FROM_FUTURE_MESSAGE(), stale: false };
  }
  // Second, and for the same reason — a payload storage will not accept is not a payload. Refusing
  // here names the key and the limit; letting `set` fail produced a raw quota error and no guidance.
  const oversized = oversizedSettingsKey(payload);
  if (oversized) {
    return {
      refused: true,
      stale: false,
      // The frame is a message; what follows it is a diagnostic payload — a storage key and a
      // byte count, neither of which is a sentence
      message: `${SETTINGS_TOO_LARGE_MESSAGE()} (${oversized} > ${MAX_STORED_ITEM_BYTES} bytes)`,
    };
  }
  if (storeMovedSinceLoad) return { refused: true, message: SAVE_CONFLICT_MESSAGE(), stale: true };
  if (appliedGenerationAtStart !== appliedGenerationNow) {
    return { refused: true, message: SAVE_RELOADED_MESSAGE(), stale: false };
  }
  if (saveConflict(capturedSnapshot, liveSnapshot)) {
    return { refused: true, message: SAVE_CONFLICT_MESSAGE(), stale: true };
  }
  return { refused: false, write: payload };
}

// What to do with a change event from storage.sync, as one decision rather than a chain of early
// returns that each had to remember to raise the banner.
//
//   'ignore' — not ours, or our own write coming back: the store did not move under us.
//   'defer'  — it moved, but this page cannot act on it yet. Held, not dropped, and asked again
//              later. Before the first load there is nothing to compare it against; during a save
//              the payload was captured before it.
//   'banner' — it moved and there is unsaved work, which wins. The user has to be told.
//   'adopt'  — it moved and nothing is in the way: re-read.
//
// 'defer' before the first load is the fix for a comment that was simply wrong: dropping the event
// on the grounds that "the load in flight will pick it up" assumed the read that was already out
// would see a write that landed after it went.
// `taskInFlight` is a save or an import: either one holds the form across an await, and adopting
// underneath it replaces what that task is about to write or fill. A *load* is not one of them —
// that is adoption's own mechanism, and a newer load supersedes an older one by generation.
function classifyStorageChange({ changes, loaded, taskInFlight, busy, isOwnWrite }) {
  if (!ownedChangedKeys(changes).length) return 'ignore';
  if (isOwnWrite) return 'ignore';
  if (!loaded) return 'defer';
  if (taskInFlight) return 'defer';
  // The "may we adopt?" rule itself is unchanged and still lives in one place; this function only
  // decides which changes get as far as asking it.
  return shouldAdoptSyncedChange(busy, changes) ? 'adopt' : 'banner';
}

// Reading a file is asynchronous, and the form stays live while it happens. A file applied over
// what was typed in that window is the same defect as a stale load answer landing on top of typing,
// so it asks the same question — did anything happen since I started? — and refuses the same way.
const IMPORT_STALE_MESSAGE = () => tr('ext.error.importStale');

function planImport({
  revisionAtStart, revisionNow, generationAtStart, generationNow, settings,
}) {
  if (!nothingHappenedSince(revisionAtStart, revisionNow) || generationAtStart !== generationNow) {
    return { refused: true, message: IMPORT_STALE_MESSAGE() };
  }
  return { refused: false, apply: settings };
}

// One file at a time — the same rule the save follows, for the same reason.
//
// Two files chosen in quick succession both captured revision 0. Whichever `file.text()` resolved
// first applied and bumped the revision, and the guard above then refused the other: the file picked
// *second* lost to the one picked first, and nothing said so. Superseding instead — apply only the
// newest and drop the overtaken one — was the alternative, and it was rejected because the earlier
// import's own application moves the revision, so the newer one would need to be told which bumps to
// ignore. That is a second concurrency model living beside the save's. Refusing the second pick
// keeps one rule on this page, and unlike the old behaviour it says out loud what happened.
const IMPORT_BUSY_MESSAGE = () => tr('ext.error.importBusy');

// Everything that has not reached storage yet, in one definition.
//
// `dirty` alone was the test on the way out of the page, and it missed a review: unchecking a
// candidate types nothing, so the tab closed without a word and the decision went with it. The sync
// path asks this same question to decide whether a remote change may be adopted, and passes `saving`
// as false there on purpose — leaving mid-write loses the write, but a remote change arriving
// mid-write is deferred rather than refused, which is a different answer to a different question.
function hasUnsavedWork({ dirty, reviewTouched, saving }) {
  return dirty === true || reviewTouched === true || saving === true;
}

// Whether a settings snapshot read from storage may still be applied to the page.
//
// Between asking storage for the settings and getting them back, the user can type, toggle a
// checkbox, or start editing. Any of that makes the snapshot older than the screen, and applying it
// would silently undo what they just did. `revision` counts every such act — including checkbox
// toggles, which are not "dirty" edits but are still the user speaking about this plan.
//
// The generation covers the other half: two loads can be in flight at once — a sync event arriving
// while the first is still running — and the one that answers last is not necessarily the one that
// asked last. Only the newest request may apply its answer, or an older view of the settings lands
// on top of a newer one.
// `initial` is the first load: there is nothing on screen yet, so there is nothing a late arrival
// could overwrite and no reason to refuse it. Refusing it was worse than useless — a keystroke in a
// field that was still live bumped the revision, the answer was dropped, and nothing ever retried,
// so the page sat unloaded forever. Being overtaken by a newer request still wins.
function shouldApplyLoadedSnapshot({
  revisionAtStart, revisionNow, dirty, generation, latestGeneration, initial, reviewTouched,
}) {
  if (generation !== latestGeneration) return false;
  if (initial) return true;
  // reviewTouched is named here as well as being counted in the revision. Both halves were needed
  // once: the badge click did not bump the revision, so an answer already in flight arrived and
  // wiped the review. The click bumps it now, and this line means that cannot be undone by accident.
  return !dirty && !reviewTouched && nothingHappenedSince(revisionAtStart, revisionNow);
}

// Reads a settings object that came from outside this page — storage or an imported file — and
// keeps only what has a shape we understand, reporting how much it had to drop.
//
// Storage is exactly as untrusted as a file here. Its contents were written by another device, or
// by another version of this extension, or by hand; `{"buttons": [null]}` and
// `{"buttons": {"length": 1}}` both threw during load and left the page stuck with no settings and
// no way to retry. The two paths share this one validator so that a shape one of them survives
// cannot be a shape the other one dies on.
//
// Dropping is never silent: `skipped` counts what went, and the caller says so. Folding quietly
// back to defaults would look exactly like "you have no buttons", which is a lie about the user's
// own data.
//
// The count is kept **per key** as well as in total. A total alone hid the case that matters most
// for import: a file with one good button and one unreadable one imported the good one, the key was
// present in the result, and nothing in the report said an entry had gone.
function adoptStoredSettings(raw) {
  const settings = {};
  const skippedByKey = {};
  let skipped = 0;

  const drop = (key, count) => {
    if (!count) return;
    skippedByKey[key] = (skippedByKey[key] || 0) + count;
    skipped += count;
  };

  for (const { storageKey } of Object.values(BUTTON_KINDS)) {
    const value = raw?.[storageKey];
    if (value === undefined) continue;
    // The same validator the content script and the service worker use (defaults.js) — one shape
    // verdict for every reader
    const adopted = adoptStoredButtons(value);
    drop(storageKey, adopted.skipped);
    settings[storageKey] = adopted.buttons;
  }

  // Also shared with the service worker (defaults.js), which resolves {main} from these two keys.
  // Asked one key at a time so each answers for its own losses rather than a combined total.
  const asDefault = adoptStoredMainBranch({ defaultMain: raw?.defaultMain });
  if (asDefault.defaultMain !== undefined) settings.defaultMain = asDefault.defaultMain;
  drop('defaultMain', asDefault.skipped);

  const asOverrides = adoptStoredMainBranch({ repoMainBranch: raw?.repoMainBranch });
  if (asOverrides.overrides !== undefined) settings.repoMainBranch = asOverrides.overrides;
  drop('repoMainBranch', asOverrides.skipped);

  return { settings, skipped, skippedByKey };
}

// One sentence per key that lost something, so the report names what went and where. "Could not be
// used" rather than "unreadable" because there are now two ways to earn it — a shape we cannot read,
// and more entries than this page can hold — and both end the same way.
// The count sits behind a noun and a colon, so no language here has to make anything agree with
// it — the English needed `1 entry … was` against `N entries … were`, and a translation cannot be
// assembled out of the pieces that made those agree.
function describeSkipped(skippedByKey) {
  return Object.entries(skippedByKey)
    .map(([key, count]) => tr('ext.error.skipped', key, count));
}

// --- One signal for "the user said something" ---
// `revision` is the primary signal and everything else is derived from it. It used to be three
// half-signals — dirty, revision, reviewTouched — each maintained at its own call sites, and every
// boundary between them leaked: a save cleared reviewTouched before checking the revision, and a
// badge click bumped neither.
//
// So: every interaction goes through one function that bumps the revision (options.js `touch`), and
// every asynchronous step ends by asking this one question before it changes anything.
function nothingHappenedSince(revisionAtStart, revisionNow) {
  return revisionAtStart === revisionNow;
}

// Whether a user action may change any state at all. Before the first load there is nothing to
// change and no snapshot to compare against, so the answer is no however the action arrived —
// `inert` stops clicks, but a dispatched event or a programmatic `.click()` walks straight past it.
// Guarding the state change instead of the listeners is what makes that route irrelevant.
function shouldAcceptUserAction(loaded) {
  return loaded === true;
}

// An interaction is "may I?" and then "do it", in that order. Keeping the two apart is how they got
// swapped: [+ Add Button] pushed the button onto the edit state and called the guard afterwards, so
// the guard could only ever refuse a change that had already happened — and [+ Add Override], the
// card inputs, delete, duplicate, reorder and the review checkboxes were all built the same way.
//
// The order is not a convention to remember at fourteen call sites; it is this function, and the
// change is a closure so there is nowhere for a mutation to sit ahead of the guard. Returns whether
// the change ran, because a caller that reports "done" also has to know.
function userAction(accept, change) {
  if (!accept()) return false;
  change();
  return true;
}

// A load can fail — storage.sync rejects, and it did so silently: the page stayed unloaded and inert
// with nothing on screen and no way back. The gate stays shut (opening it would bring back writing
// an empty settings object over real ones), so the way out has to be a retry, and the message has to
// offer one.
const LOAD_FAILED_MESSAGE = () => tr('ext.error.loadFailed');
