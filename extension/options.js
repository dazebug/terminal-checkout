// defaults.js is the single source of truth for button defaults, presets, and face rules
// (options.html loads it first)

/** @typedef {'pr'|'pr-list'|'issue'|'issue-list'|'repo'} OptionsButtonKind */
/** @typedef {'face'|'label'|'command'} OptionsButtonRequiredField */
/** @typedef {'incomplete'|'duplicate'} OptionsOverrideErrorCode */
/** @typedef {'claude-inputs-without-claude-command'} OptionsButtonWarningCode */

/**
 * @typedef {Object} OptionsButtonValue
 * @property {string} face
 * @property {string} label
 * @property {string} command
 * @property {ReadonlyArray<string>} claudeInputs
 */

/**
 * @typedef {Object} OptionsButtonValidation
 * @property {ReadonlyArray<OptionsButtonRequiredField>} errors Every empty required field, in face/label/command order.
 * @property {ReadonlyArray<OptionsButtonWarningCode>} warnings Diagnostics shared by Save and the snapshot.
 */

/**
 * @typedef {Object} OptionsButtonSnapshot
 * @property {string} uid Runtime-only identity minted by the edit engine.
 * @property {string} face Stored button face value.
 * @property {string} label Stored button tooltip value.
 * @property {string} command Stored command value.
 * @property {ReadonlyArray<string>} claudeInputs Stored Claude input rows in their current order.
 * @property {string|null} presetId Exact matching preset id for this kind, or null.
 * @property {boolean} customCommand Non-empty command matching no preset command for this kind.
 * @property {OptionsButtonValidation} validation Read-only button diagnostics.
 */

/**
 * @typedef {Object} OptionsOverrideSnapshot
 * @property {number} index Current edit-array index used by override actions.
 * @property {string} repo Raw editable repository text.
 * @property {string} branch Raw editable branch text.
 */

/**
 * @typedef {Object} OptionsMigrationActionableSnapshot
 * @property {string} uid Runtime button uid identifying the candidate.
 * @property {OptionsButtonKind} kind
 * @property {number} index Current button index for display only.
 * @property {string} label
 * @property {string} from
 * @property {string} to
 * @property {'verbatim'|'prefix'} source
 * @property {'unconditional'|'behavior-change'} effect
 * @property {boolean} selected
 * @property {string} describe Localized migration explanation.
 * @property {ReadonlyArray<string>=} fromInputs Present when this candidate rewrites input rows.
 * @property {ReadonlyArray<string>=} toInputs Present when this candidate rewrites input rows.
 */

/**
 * @typedef {Object} OptionsMigrationInformationalSnapshot
 * @property {string} uid Runtime button uid identifying the item.
 * @property {OptionsButtonKind} kind
 * @property {number} index Current button index for display only.
 * @property {string} label
 * @property {string} command
 * @property {string} note
 */

/**
 * @typedef {Object} OptionsMigrationSummarySnapshot
 * @property {number} actionableCount
 * @property {number} informationalCount
 * @property {number} selectedCount
 * @property {boolean} nothingToApply
 * @property {boolean} reviewOnly
 * @property {string} descriptions
 */

/**
 * @typedef {Object} OptionsEngineSnapshot
 * @property {Readonly<Record<OptionsButtonKind, ReadonlyArray<OptionsButtonSnapshot>>>} buttons Per-kind buttons in edit order, with runtime uids and stored fields.
 * @property {boolean} dirty Whether button/global settings differ from the loaded edit state.
 * @property {number} revision Monotonic edit revision.
 * @property {{buttons: ReadonlyArray<{kind: OptionsButtonKind, uid: string, errors: ReadonlyArray<OptionsButtonRequiredField>, warnings: ReadonlyArray<OptionsButtonWarningCode>}>, overrides: ReadonlyArray<{index: number, errors: ReadonlyArray<OptionsOverrideErrorCode>}>}} validation The same button and override rules Save uses.
 * @property {{defaultMain: string, repoMainBranch: ReadonlyArray<OptionsOverrideSnapshot>}} globalSettings Raw editable default main and ordered overrides.
 * @property {{status: 'unloaded'|'loading'|'loaded'|'reloading'|'error', loaded: boolean, generation: number, appliedGeneration: number, inFlight: number, errorMessage: string|null, retryAvailable: boolean}} load
 * @property {{status: 'blocked'|'clean'|'dirty'|'saving', saving: boolean, importing: boolean, dirty: boolean, reviewTouched: boolean, hasUnsavedWork: boolean, canSave: boolean, loadedVersion: number|null, versionToWrite: number|null}} save
 * @property {{staleSinceLoad: boolean, deferredChangePending: boolean, changedDuringSave: boolean}} sync
 * @property {{fromVersion: number|null, targetVersion: number, pending: boolean, reviewed: boolean, reviewTouched: boolean, panelOpen: boolean, selectedUids: ReadonlyArray<string>, summary: OptionsMigrationSummarySnapshot, actionable: ReadonlyArray<OptionsMigrationActionableSnapshot>, informational: ReadonlyArray<OptionsMigrationInformationalSnapshot>}} migration
 * @property {{type: 'idle'|'info'|'success'|'error', message: string}} status
 */

/**
 * @typedef {Object} OptionsStorageWriteSite
 * @property {'extension/options.js'} file
 * @property {'saveSettings'} functionName
 * @property {'chrome.storage.sync.set'} api
 */

/** @typedef {{type: 'save'}} OptionsSaveAction */
/** @typedef {{type: 'discard', confirmed?: true}} OptionsDiscardAction `confirmed` is true only after the view has asked before dropping unsaved work. */
/** @typedef {{type: 'retry-load'}} OptionsRetryLoadAction */
/** @typedef {{type: 'reload-latest'}} OptionsReloadLatestAction */
/** @typedef {{type: 'adopt-latest', confirmed?: true}} OptionsAdoptLatestAction `confirmed` is true only after the view has asked before dropping unsaved work. */
/** @typedef {{type: 'defer-latest'}} OptionsDeferLatestAction */
/** @typedef {{type: 'reset'}} OptionsResetAction */
/** @typedef {{type: 'export-saved'}} OptionsExportAction */
/** @typedef {{type: 'import-file', file: File}} OptionsImportAction */
/** @typedef {{type: 'migration-apply'}} OptionsMigrationApplyAction */
/** @typedef {{type: 'migration-keep'}} OptionsMigrationKeepAction */
/** @typedef {{type: 'migration-selection', uid: string, selected: boolean}} OptionsMigrationSelectionAction */
/** @typedef {{type: 'migration-panel-toggle'}} OptionsMigrationPanelToggleAction */
/** @typedef {{type: 'main-patch', value: string}} OptionsMainPatchAction */
/** @typedef {{type: 'override-add'}} OptionsOverrideAddAction */
/** @typedef {{type: 'override-patch', index: number, patch: Partial<{repo: string, branch: string}>}} OptionsOverridePatchAction */
/** @typedef {{type: 'override-remove', index: number}} OptionsOverrideRemoveAction */
/** @typedef {{type: 'button-patch', kind: OptionsButtonKind, uid: string, patch: Partial<Pick<OptionsButtonValue, 'face'|'label'|'command'>>}} OptionsButtonPatchAction */
/** @typedef {{type: 'button-add', kind: OptionsButtonKind}} OptionsButtonAddAction */
/** @typedef {{type: 'button-duplicate', kind: OptionsButtonKind, uid: string}} OptionsButtonDuplicateAction */
/** @typedef {{type: 'button-remove', kind: OptionsButtonKind, uid: string}} OptionsButtonRemoveAction */
/** @typedef {{type: 'button-move', kind: OptionsButtonKind, uid: string, beforeUid: string|null}} OptionsButtonMoveAction */
/** @typedef {{type: 'preset-add', kind: OptionsButtonKind, presetId: string, beforeUid?: string|null}} OptionsPresetAddAction */
/** @typedef {{type: 'preset-replace', kind: OptionsButtonKind, uid: string, presetId: string, confirmed?: true}} OptionsPresetReplaceAction `confirmed` is required only for a custom command. */
/** @typedef {{type: 'input-add', kind: OptionsButtonKind, buttonUid: string, value?: string}} OptionsInputAddAction */
/** @typedef {{type: 'input-patch', kind: OptionsButtonKind, buttonUid: string, inputIndex: number, value: string}} OptionsInputPatchAction */
/** @typedef {{type: 'input-remove', kind: OptionsButtonKind, buttonUid: string, inputIndex: number}} OptionsInputRemoveAction */
/** @typedef {{type: 'input-move', kind: OptionsButtonKind, buttonUid: string, fromIndex: number, beforeIndex: number}} OptionsInputMoveAction */

/**
 * @typedef {
 *   OptionsSaveAction|OptionsDiscardAction|OptionsRetryLoadAction|OptionsReloadLatestAction|
 *   OptionsAdoptLatestAction|OptionsDeferLatestAction|OptionsResetAction|OptionsExportAction|
 *   OptionsImportAction|OptionsMigrationApplyAction|OptionsMigrationKeepAction|
 *   OptionsMigrationSelectionAction|OptionsMigrationPanelToggleAction|OptionsMainPatchAction|
 *   OptionsOverrideAddAction|OptionsOverridePatchAction|OptionsOverrideRemoveAction|
 *   OptionsButtonPatchAction|OptionsButtonAddAction|OptionsButtonDuplicateAction|OptionsButtonRemoveAction|
 *   OptionsButtonMoveAction|OptionsPresetAddAction|OptionsPresetReplaceAction|OptionsInputAddAction|
 *   OptionsInputPatchAction|OptionsInputRemoveAction|OptionsInputMoveAction
 * } OptionsEngineAction
 * @typedef {Object} OptionsDispatchResult
 * @property {boolean} ok Whether the action completed or was accepted.
 * @property {('not-loaded'|'busy'|'limit'|'not-found'|'needs-confirmation'|'invalid'|'failed')=} [reason] Failure category when `ok` is false.
 * @property {string=} [createdUid] Runtime uid created by button-add, button-duplicate, or preset-add.
 * @property {OptionsEngineSnapshot} snapshot Snapshot after the action was handled.
 *
 * @typedef {Object} OptionsEngine
 * @property {() => OptionsEngineSnapshot} getSnapshot Returns a deeply frozen copy of the current edit and page state.
 * @property {(listener: (snapshot: OptionsEngineSnapshot) => void) => () => void} subscribe Registers for state changes coalesced into one microtask; registration never invokes the listener, so mount calls getSnapshot for its first render. Returns an unsubscribe function.
 * @property {(action: OptionsEngineAction) => Promise<OptionsDispatchResult>} dispatch Applies an action to engine state. It never opens a browser dialog; a caller confirms in its own UI and resends confirmed: true.
 *
 * `preset-replace` needs confirmed: true when the current command is non-empty and does not exactly match a preset for the same kind. `discard` and `adopt-latest` need confirmed: true only when there is unsaved work. Without it the result is needs-confirmation. `reload-latest` uses the existing load path and applies only when the edit state remains unchanged. Confirmed discard/adopt re-read through that path; if the read fails, existing edits remain. `defer-latest` preserves the edit state and stale warning. `migration-selection` takes a migration candidate uid and boolean `selected`; it records review intent without marking settings dirty. `migration-panel-toggle` changes the shared migration panel visibility and records review intent. Button and input moves use the existing before-index ordering.
 */

const SECTIONS = Object.entries(BUTTON_KINDS).map(([kind, section]) => ({ kind, ...section }));

/** @type {(key: string, ...args: Array<string|number>) => string} */
const tHTML = tr;

// Engine messages are plain text. The view modules own their text and markup insertion helpers.
applyDocumentLanguage();
document.title = `Terminal Checkout — ${tr('ext.header.options')}`;

// Unlike the storage schema, overrides are kept as an array. Keying them by repo would mean
// deleting and re-adding the key on every keystroke in the name, and redrawing the row each time
// would throw away the input focus.
const state = {
  buttons: Object.fromEntries(SECTIONS.map(s => [s.kind, []])),
  overrides: [],
  defaultMain: DEFAULT_MAIN,
  dirty: false,
  // Bumped on every edit. Used after a save to tell whether the user changed anything in the meantime.
  revision: 0,
  // False until the first load answers. The page has no settings before then, so nothing may be
  // saved: an early Save used to write `buttons: []` at the current version — every command gone and
  // the migration marked as reviewed, in one click.
  loaded: false,
  // The schema generation read from storage — null while unknown, so it can never be mistaken for a
  // real one. Whether the user has since decided about it is `reviewed`, and that is the consent:
  // only it lets a save move the version forward, so an ordinary edit cannot swallow a pending
  // migration (versionToSave in migrations.js).
  loadedVersion: null,
  // Exactly what storage held when this page loaded it. A save compares against it and refuses if
  // anything moved, because storage.sync offers no compare-and-set and merging would be a guess.
  loadedSnapshot: null,
  // Counts load requests, so an answer from an overtaken one can be dropped
  loadGeneration: 0,
  // Counts the loads that actually **applied**. The request counter above cannot stand in for this:
  // a load requested before a save started and applied halfway through it never moves the request
  // counter, so the save read "nothing reloaded" while the form had already been replaced.
  appliedGeneration: 0,
  // How many load requests are outstanding. Any of them may replace the form the moment it answers,
  // so a save must not start into that window.
  loadsInFlight: 0,
  // Set when a change arrives from another device while editing — the banner warns before the save
  // is attempted, but the re-read at save time is what decides
  staleSinceLoad: false,
  // A save is in flight. It is unsaved work like any other — adopting a remote change during one
  // replaced the very snapshot the save was about to compare against, and the payload built before
  // that adoption then overwrote the remote settings with no conflict reported.
  saving: false,
  // The payload of the save in flight, so the change event our own write produces is recognized as
  // ours even before it has been recorded as the loaded snapshot.
  pendingWrite: null,
  // Set when an owned, non-echo change arrives during a save: the store has moved, so this save
  // cannot be written whatever its live read happens to say.
  changedDuringSave: false,
  // A remote change that arrived during a save, held rather than dropped — once the save settles
  // the page is clean again and the change should land.
  deferredChange: null,
  // A settings file is being read. One at a time: two in flight both captured the same revision, and
  // whichever finished reading first applied and disqualified the other, so the file chosen second
  // lost to the one chosen first with nothing said.
  importing: false,
  // Set the moment the user engages with the migration preview. Checking boxes is not a "dirty"
  // edit — nothing has been typed — but it is unsaved work all the same, and re-planning underneath
  // it silently restores the choices they just made.
  reviewTouched: false,
  reviewed: false,
  plan: null,
  migrationPanelOpen: false,
  loadErrorMessage: null,
  status: { type: 'idle', message: '' },
  // Ids of the checked candidates — they start checked, so this starts as all of them.
  selection: new Set(),
};

const optionsEngineListeners = new Set();
let optionsEngineNotificationScheduled = false;

function scheduleOptionsEngineNotify() {
  if (!optionsEngineListeners.size || optionsEngineNotificationScheduled) return;
  optionsEngineNotificationScheduled = true;
  queueMicrotask(() => {
    optionsEngineNotificationScheduled = false;
    const snapshot = getOptionsEngineSnapshot();
    for (const listener of [...optionsEngineListeners]) {
      try {
        listener(snapshot);
      } catch (error) {
        console.error('Terminal Checkout: options subscriber failed', error);
      }
    }
  });
}

function section(kind) {
  return SECTIONS.find(s => s.kind === kind);
}

// Buttons enter the edit state through `adoptButton` (anything from outside: storage, a file, a
// preset — it gets a uid we mint) or `reshapeButton` (a button already here, keeping its name).
// Both live in defaults.js, along with why they are two functions and not one.

// Until the first load answers, this page holds no settings — only the empty shell of the edit
// state. Every entry point that would write, or that would change what a later write contains, asks
// here first. The page is also inert until then (updateLoadedGate), but that is the fence; this is
// the rule, and code paths that do not come from a click still have to pass it.
const LOADING_MESSAGE = () => tr('ext.status.loading');

function requireLoaded() {
  if (state.loaded) return true;
  showStatus('info', LOADING_MESSAGE());
  return false;
}

// The replica and editor become interactive only after settings load. One switch on their shared
// root covers every control, including controls added by either view module.
function updateLoadedGate() {
  // The app, not the whole document: the status line and [Retry] live outside it, so a load that
  // failed still has somewhere to say so and something the user can press.
  document.getElementById('app').inert = !state.loaded;
}

// A load that never answered. The gate stays shut — a Save here would write an empty settings object
// over real ones — so what is offered instead is another attempt.
function showLoadFailure(error) {
  state.loadErrorMessage = `${LOAD_FAILED_MESSAGE()} (${error?.message || error})`;
  showStatus('error', state.loadErrorMessage);
  scheduleOptionsEngineNotify();
}

function hideLoadFailure() {
  state.loadErrorMessage = null;
  scheduleOptionsEngineNotify();
}

// Unsaved work that a remote change must never overwrite: text typed, and a review being decided.
// A save in flight is handled on its own axis — a change arriving then is deferred, not refused.
function editsInProgress() {
  return hasUnsavedWork({ dirty: state.dirty, reviewTouched: state.reviewTouched });
}

// Unsaved work that leaving the page would lose — the same definition, plus the write still in
// flight. Asking `dirty` alone here let a decided review go with the tab: unchecking a candidate
// types nothing, so the browser said nothing on the way out.
function wouldLoseWork() {
  return hasUnsavedWork({
    dirty: state.dirty, reviewTouched: state.reviewTouched, saving: state.saving,
  });
}

// Our own write, whether or not it has been recorded as the loaded snapshot yet — the change event
// for a save can arrive before `set` has even resolved.
// Before the first load there is no write of ours to compare against, and "nothing versus nothing"
// must not read as a match: a remote key *removal* would otherwise look exactly like our own echo.
function isOurOwnWrite(changes) {
  if (state.loadedSnapshot && isOwnEcho(changes, state.loadedSnapshot)) return true;
  return !!state.pendingWrite && isOwnEcho(changes, state.pendingWrite);
}

// A remote change that could not be acted on when it arrived — the first load had not answered yet,
// or a save was in flight — was held rather than dropped. Once that moment has passed, the same
// question is asked again through the same classifier.
//
// Every branch here ends somewhere visible: adopted, still held, or on the banner. A change we
// decide not to adopt is still a change, and dropping it silently is how the warning disappeared
// while the page was in fact still behind the store.
// What is holding the form right now, in the shape every gate asks for. A load counts here too:
// its answer replaces the form, so a save or an import started into that window builds from
// something that is about to be gone.
function pageTasks() {
  return { saving: state.saving, importing: state.importing, loading: state.loadsInFlight > 0 };
}

function adoptDeferredChange() {
  const changes = state.deferredChange;
  if (!changes) return;
  const outcome = classifyStorageChange({
    changes, loaded: state.loaded, taskInFlight: state.saving || state.importing,
    busy: editsInProgress(), isOwnWrite: false,
  });
  if (outcome === 'defer') return; // still not a moment to act; it stays held
  state.deferredChange = null;
  if (outcome === 'ignore') return;
  markStale(); // true until a load actually lands, which is what clears it
  if (outcome === 'adopt') loadSettings();
}

// The one way "this page is behind the store" gets recorded. Every branch that learns it and cannot
// act on it ends here, so there is no route where the fact is known and nothing shows it.
function markStale() {
  state.staleSinceLoad = true;
  scheduleOptionsEngineNotify();
}

// The edit state in the shape the planner reads: what would be stored if Save were pressed now,
// with the uids still attached. The plan is always computed against this, never against what
// storage happens to hold — those two drift apart the moment anything is edited or imported.
function editStateSnapshot() {
  return Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [storageKey, state.buttons[kind]]));
}

// --- Unsaved-change indicator ---

// The one place a user action becomes state. Everything the user can do — typing, checking a box,
// opening the review, pressing a panel button — comes through here, and nothing else assigns
// `revision`, `dirty` or `reviewTouched`.
//
// One funnel, for two reasons. Before the load there is nothing to change, and refusing here covers
// every route in: `inert` stops clicks, but a dispatched event or a programmatic `.click()` walks
// straight past it, and guarding listeners one at a time means the listener added next year is the
// one that was forgotten. After the load, `revision` is the primary signal — the three half-signals
// it replaces were each maintained at their own call sites, and every boundary between them leaked
// (a save cleared `reviewTouched` before checking the revision; the badge click bumped neither).
function touch({ dirty = false, review = false } = {}) {
  if (!shouldAcceptUserAction(state.loaded)) return false;
  state.revision++;
  if (dirty) state.dirty = true;
  if (review) state.reviewTouched = true;
  return true;
}

// The guard and edit run together so a rejected action cannot partially change engine state.
function edit(change) {
  const accepted = userAction(() => touch({ dirty: true }), change);
  if (accepted) scheduleOptionsEngineNotify();
  return accepted;
}

function review(change) {
  const accepted = userAction(() => touch({ review: true }), change);
  if (accepted) scheduleOptionsEngineNotify();
  return accepted;
}

// Applying, declining and resetting are all decisions about the migration *and* changes that have
// to be saved, so they raise both signals.
function editAndReview(change) {
  const accepted = userAction(() => touch({ dirty: true, review: true }), change);
  if (accepted) scheduleOptionsEngineNotify();
  return accepted;
}

function preparedEdit(apply, createdUid, changed = true) {
  return { ok: true, apply, changed, ...(createdUid ? { createdUid } : {}) };
}

function rejectedEdit(reason) {
  return { ok: false, reason };
}

function prepareButtonPatch(kind, uid, patch) {
  const buttonSection = section(kind);
  const index = buttonIndexForUid(kind, uid);
  if (!buttonSection || index < 0) return rejectedEdit('not-found');
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return rejectedEdit('invalid');
  const fields = ['face', 'label', 'command'];
  const entries = Object.keys(patch).map(field => [field, patch[field]]);
  if (entries.length === 0) return preparedEdit(() => {}, undefined, false);
  if (entries.some(([field, value]) => !fields.includes(field) || typeof value !== 'string')) {
    return rejectedEdit('invalid');
  }
  return preparedEdit(() => {
    for (const [field, value] of entries) state.buttons[kind][index][field] = value;
  });
}

function prepareButtonAdd(kind) {
  const buttonSection = section(kind);
  if (!buttonSection) return rejectedEdit('invalid');
  if (state.buttons[kind].length >= MAX_BUTTONS) return rejectedEdit('limit');
  const next = appendButton(state.buttons[kind], buttonSection);
  const createdUid = next[next.length - 1].uid;
  return preparedEdit(() => { state.buttons[kind] = next; }, createdUid);
}

function prepareButtonDuplicate(kind, uid) {
  const index = buttonIndexForUid(kind, uid);
  if (index < 0) return rejectedEdit('not-found');
  if (state.buttons[kind].length >= MAX_BUTTONS) return rejectedEdit('limit');
  const next = duplicateButton(state.buttons[kind], index);
  const createdUid = next[index + 1].uid = nextButtonUid();
  return preparedEdit(() => { state.buttons[kind] = next; }, createdUid);
}

function prepareButtonRemove(kind, uid) {
  const index = buttonIndexForUid(kind, uid);
  if (index < 0) return rejectedEdit('not-found');
  if (state.buttons[kind].length <= 1) return rejectedEdit('limit');
  return preparedEdit(() => { state.buttons[kind].splice(index, 1); });
}

function prepareButtonMove(kind, uid, beforeUid) {
  const buttons = state.buttons[kind];
  const from = buttonIndexForUid(kind, uid);
  if (!section(kind) || from < 0) return rejectedEdit('not-found');
  if (beforeUid !== null && typeof beforeUid !== 'string') return rejectedEdit('invalid');
  const insertBefore = beforeUid === null ? buttons.length : buttonIndexForUid(kind, beforeUid);
  if (insertBefore < 0) return rejectedEdit('not-found');
  if (insertBefore === from || insertBefore === from + 1) return preparedEdit(() => {}, undefined, false);
  const next = moveItem(buttons, from, insertBefore);
  return preparedEdit(() => { state.buttons[kind] = next; });
}

function preparePresetReplace(kind, uid, presetId, confirmed = false) {
  const buttonSection = section(kind);
  const index = buttonIndexForUid(kind, uid);
  if (!buttonSection || index < 0) return rejectedEdit('not-found');
  if (typeof presetId !== 'string') return rejectedEdit('invalid');
  const preset = presetById(buttonSection.presets, presetId);
  if (!preset) return rejectedEdit('not-found');
  const current = state.buttons[kind][index];
  if (classifyPresetCommand(current.command, buttonSection.presets).customCommand && confirmed !== true) {
    return rejectedEdit('needs-confirmation');
  }
  const nextButton = reshapeButton({
    face: preset.face,
    label: preset.name,
    command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  }, current.uid);
  return preparedEdit(() => { state.buttons[kind][index] = nextButton; });
}

function preparePresetAdd(kind, presetId, beforeUid) {
  const buttonSection = section(kind);
  if (!buttonSection) return rejectedEdit('invalid');
  const preset = presetById(buttonSection.presets, presetId);
  if (!preset) return rejectedEdit('not-found');
  if (state.buttons[kind].length >= MAX_BUTTONS) return rejectedEdit('limit');
  const next = appendButton(state.buttons[kind], buttonSection);
  const added = next[next.length - 1];
  next[next.length - 1] = reshapeButton({
    face: preset.face,
    label: preset.name,
    command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  }, added.uid);
  if (beforeUid !== undefined) {
    if (beforeUid !== null && (typeof beforeUid !== 'string' || buttonIndexForUid(kind, beforeUid) < 0)) {
      return rejectedEdit('not-found');
    }
    const beforeIndex = beforeUid === null ? next.length - 1 : buttonIndexForUid(kind, beforeUid);
    const moved = moveItem(next, next.length - 1, beforeIndex);
    return preparedEdit(() => { state.buttons[kind] = moved; }, added.uid);
  }
  return preparedEdit(() => { state.buttons[kind] = next; }, added.uid);
}

function prepareInputAdd(kind, buttonUid, value = '') {
  const index = buttonIndexForUid(kind, buttonUid);
  if (index < 0) return rejectedEdit('not-found');
  const button = state.buttons[kind][index];
  if (button.claudeInputs.length >= MAX_CLAUDE_INPUTS) return rejectedEdit('limit');
  if (typeof value !== 'string') return rejectedEdit('invalid');
  return preparedEdit(() => { button.claudeInputs.push(value); });
}

function prepareInputPatch(kind, buttonUid, inputIndex, value) {
  const index = buttonIndexForUid(kind, buttonUid);
  if (index < 0) return rejectedEdit('not-found');
  const inputs = state.buttons[kind][index].claudeInputs;
  if (!Number.isInteger(inputIndex) || inputIndex < 0 || inputIndex >= inputs.length) return rejectedEdit('not-found');
  if (typeof value !== 'string') return rejectedEdit('invalid');
  return preparedEdit(() => { inputs[inputIndex] = value; });
}

function prepareInputRemove(kind, buttonUid, inputIndex) {
  const index = buttonIndexForUid(kind, buttonUid);
  if (index < 0) return rejectedEdit('not-found');
  const inputs = state.buttons[kind][index].claudeInputs;
  if (!Number.isInteger(inputIndex) || inputIndex < 0 || inputIndex >= inputs.length) return rejectedEdit('not-found');
  return preparedEdit(() => { inputs.splice(inputIndex, 1); });
}

function prepareInputMove(kind, buttonUid, fromIndex, beforeIndex) {
  const index = buttonIndexForUid(kind, buttonUid);
  if (index < 0) return rejectedEdit('not-found');
  const inputs = state.buttons[kind][index].claudeInputs;
  if (!Number.isInteger(fromIndex) || fromIndex < 0 || fromIndex >= inputs.length
    || !Number.isInteger(beforeIndex) || beforeIndex < 0 || beforeIndex > inputs.length) {
    return rejectedEdit('invalid');
  }
  if (beforeIndex === fromIndex || beforeIndex === fromIndex + 1) return preparedEdit(() => {}, undefined, false);
  const next = moveItem(inputs, fromIndex, beforeIndex);
  return preparedEdit(() => { state.buttons[kind][index].claudeInputs = next; });
}

function prepareMainPatch(value) {
  if (typeof value !== 'string') return rejectedEdit('invalid');
  return preparedEdit(() => { state.defaultMain = value; });
}

function prepareOverrideAdd() {
  return preparedEdit(() => { state.overrides.push({ repo: '', branch: '' }); });
}

function prepareOverridePatch(index, patch) {
  if (!Number.isInteger(index) || index < 0 || index >= state.overrides.length
    || !patch || typeof patch !== 'object' || Array.isArray(patch)) return rejectedEdit('not-found');
  const entries = Object.keys(patch).map(field => [field, patch[field]]);
  if (entries.length === 0) return preparedEdit(() => {}, undefined, false);
  if (entries.some(([field, value]) => !['repo', 'branch'].includes(field) || typeof value !== 'string')) {
    return rejectedEdit('invalid');
  }
  return preparedEdit(() => {
    for (const [field, value] of entries) state.overrides[index][field] = value;
  });
}

function prepareOverrideRemove(index) {
  if (!Number.isInteger(index) || index < 0 || index >= state.overrides.length) return rejectedEdit('not-found');
  return preparedEdit(() => { state.overrides.splice(index, 1); });
}

function prepareReset() {
  const buttons = Object.fromEntries(SECTIONS.map(({ kind, defaults }) => [kind, defaults.map(adoptButton)]));
  return preparedEdit(() => {
    state.buttons = buttons;
    state.overrides = [];
    state.defaultMain = DEFAULT_MAIN;
    recordMigrationReviewed();
  });
}

function prepareMigrationApply() {
  if (!state.plan) return rejectedEdit('not-found');
  const { settings: migrated, applied } = applyMigrationPlan(editStateSnapshot(), state.plan, state.selection);
  const declined = state.selection.size - applied;
  const buttons = Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [
    kind,
    migrated[storageKey].map(button => reshapeButton(button, button.uid)),
  ]));
  return {
    ...preparedEdit(() => {
      state.buttons = buttons;
      recordMigrationReviewed();
    }),
    applied,
    declined,
  };
}

function prepareMigrationKeep() {
  return preparedEdit(recordMigrationReviewed);
}

function clearDirty() {
  state.dirty = false;
}

// --- Validation ---

// A complete sentence per field, not a noun phrase spliced into one. `enter ${label}.` needed
// `a face` to carry an English article, and an article is a fact about English grammar that no
// other language here inflects the same way, so never assemble a translated clause.
const REQUIRED_FIELDS = [
  { field: 'face', describe: (key, index) => tr('ext.validate.face', key, index) },
  { field: 'label', describe: (key, index) => tr('ext.validate.tooltip', key, index) },
  { field: 'command', describe: (key, index) => tr('ext.validate.command', key, index) },
];

function validateEditState() {
  const buttons = SECTIONS.flatMap(({ kind }) => state.buttons[kind].map(button => ({
    kind,
    uid: button.uid,
    ...validateButtonValue(button),
  })));
  const overrides = validateOverrideRows(state.overrides);
  return { buttons, overrides: overrides.rows, overrideValue: overrides.value };
}

function validateButtons(validation = validateEditState()) {
  const diagnostic = validation.buttons.find(button => button.errors.length > 0);
  if (!diagnostic) return null;
  const index = buttonIndexForUid(diagnostic.kind, diagnostic.uid);
  const field = diagnostic.errors[0];
  return {
    message: REQUIRED_FIELDS.find(item => item.field === field)
      .describe(section(diagnostic.kind).storageKey, index),
  };
}

// Turn the shared override diagnostics back into the storage schema (an object).
function serializeOverrides(validation = validateEditState()) {
  const diagnostic = validation.overrides.find(row => row.errors.length > 0);
  if (!diagnostic) return { value: validation.overrideValue };

  const row = state.overrides[diagnostic.index];
  const code = diagnostic.errors[0];
  const repo = row.repo.trim();
  return {
    error: {
      message: code === 'duplicate'
        ? tr('ext.validate.override.duplicate', diagnostic.index + 1, repo)
        : tr('ext.validate.override.incomplete', diagnostic.index + 1),
    },
  };
}

// --- Load / save ---

// The terminal choice is owned solely by the Terminal Checkout app (its settings window)
async function loadSettings() {
  // The user can act while storage is being read, and a second load can start before the first
  // answers. Remember both where the page was and which request this is, so an answer that has been
  // overtaken is dropped instead of landing on top of newer settings.
  const revisionAtStart = state.revision;
  const generation = ++state.loadGeneration;
  // Before the first answer there is nothing on screen to protect, so this one is applied whatever
  // the user did meanwhile — dropping it left the page unloaded with nothing to retry it.
  const initial = !state.loaded;

  // storage.sync can reject. It used to do so silently: the page stayed unloaded and inert with
  // nothing on screen and no way back. The gate stays shut — opening it would let a Save write an
  // empty settings object over real ones — so the way out is a retry the user can actually reach.
  //
  // While this is outstanding the form may be replaced at any moment, so a save must not start.
  // Counted rather than flagged, because two loads can overlap and the first to answer must not
  // declare the window closed for the second.
  let data;
  state.loadsInFlight += 1;
  scheduleOptionsEngineNotify();
  try {
    data = await chrome.storage.sync.get([...SETTINGS_KEYS, VERSION_KEY]);
  } catch (error) {
    if (generation === state.loadGeneration) showLoadFailure(error);
    // The change that asked for this re-read is not adopted, and `staleSinceLoad` was never cleared,
    // so the banner it raised is still up — which is the whole point of not clearing it early.
    return false;
  } finally {
    state.loadsInFlight -= 1;
    scheduleOptionsEngineNotify();
  }

  if (!shouldApplyLoadedSnapshot({
    revisionAtStart, revisionNow: state.revision, dirty: state.dirty,
    reviewTouched: state.reviewTouched,
    generation, latestGeneration: state.loadGeneration, initial,
  })) {
    // Not applying is not the same as not having read. This answer is evidence about the store, and
    // if it differs from what the page holds, the page is behind — say so rather than discarding
    // both the snapshot and the fact that it existed. Only once there is a snapshot to compare
    // against: before that, "everything differs from nothing" would be a banner about nothing.
    if (state.loaded && saveConflict(state.loadedSnapshot, data)) markStale();
    return false;
  }

  // Storage is as untrusted as an imported file: another device, another version of this extension,
  // or a hand edit wrote it. Anything unreadable is dropped and counted, never guessed at.
  const { settings, skippedByKey } = adoptStoredSettings(data);

  for (const { kind, storageKey, defaults } of SECTIONS) {
    // Presets only where the key said nothing at all. A key that held something we could not use is
    // answered with whatever survived — even if that is nothing — because what lands here is what
    // the next Save records, and filling it from our presets makes that Save a rewrite.
    state.buttons[kind] = seedFromStorage(settings[storageKey], defaults, skippedByKey[storageKey])
      .map(adoptButton);
  }
  state.overrides = Object.entries(settings.repoMainBranch || {}).map(([repo, branch]) => ({ repo, branch }));
  state.defaultMain = settings.defaultMain || DEFAULT_MAIN;

  state.loadedVersion = storedSchemaVersion(data);
  // Exactly what was read — the raw object, not the cleaned one, because that is what a later save
  // has to find unchanged in storage
  state.loadedSnapshot = data;
  state.staleSinceLoad = false;
  state.reviewTouched = false;
  state.reviewed = false;
  state.loaded = true;
  // The form has been replaced. This is what a save in flight compares against — counting requests
  // instead of applications is what let a load applied mid-save go unnoticed.
  state.appliedGeneration += 1;
  hideLoadFailure();
  updateLoadedGate();
  const dropped = describeSkipped(skippedByKey);
  if (dropped.length) {
    // Said out loud, named per key, and with the consequence attached. The section above is now
    // empty rather than quietly full of presets, so the user can see that something is missing —
    // and this says what pressing Save would do to it, and how to keep a copy first.
    showStatus('error', `${dropped.join('; ')}. ${SKIP_CONSEQUENCE()}`);
  }

  // Planned from the edit state that was just built, not from `data` — those are the same thing
  // here, and keeping one path means they cannot fall out of step later.
  setPlan(planMigration(editStateSnapshot(), state.loadedVersion));

  // A change that arrived before this page had settings was held rather than dropped, because the
  // read that was already outstanding may have been answered from before that write landed. Now
  // there is something to compare against, so ask again — which re-reads, this time knowing the
  // store moved.
  adoptDeferredChange();
  scheduleOptionsEngineNotify();
  return true;
}

async function saveSettings() {
  // Nothing may be written before the first load answers: the edit state is empty until then, and
  // writing it would delete every command and mark the migration as reviewed in the same breath.
  if (!requireLoaded()) return false;
  // One page-changing task at a time. Two saves would each capture the same world, each find it
  // unchanged, and the later write would land carrying what was true before the earlier one; a save
  // started while a load is outstanding builds its payload from a form that answer is about to
  // replace.
  if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) {
    showStatus('info', pageBusyMessage(pageTasks()));
    return false;
  }

  const validation = validateEditState();
  const invalidButton = validateButtons(validation);
  if (invalidButton) {
    showError(invalidButton.message);
    return false;
  }

  const overrides = serializeOverrides(validation);
  if (overrides.error) {
    showError(overrides.error.message);
    return false;
  }

  // toStoredButton is what decides the stored shape — including dropping the runtime uid
  const cleaned = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind, state.buttons[kind].map(toStoredButton),
  ]));
  const defaultMain = state.defaultMain.trim() || DEFAULT_MAIN;

  // The world this save starts in, captured once. Everything below settles against these values and
  // never against `state`, which moves underneath: adoption of a remote change is not a user action
  // and bumps no revision, so it used to replace `state.loadedSnapshot` mid-save and the comparison
  // became "the remote settings against the remote settings" — no conflict, and this payload went
  // over the top of them.
  const savedRevision = state.revision;
  const appliedGenerationAtStart = state.appliedGeneration;
  const capturedSnapshot = state.loadedSnapshot;
  // A change event that arrived *before* this save is exactly as disqualifying as one that arrives
  // during it: either way the store moved and this page has not caught up, so the payload describes
  // the world before it. Latching it at the start is what makes the refusal independent of what the
  // live read happens to return.
  const staleAtStart = state.staleSinceLoad;

  // The version moves only when the user decided something (applied, declined, acknowledged, or
  // reset). Stamping the current version on every save would clear the notice for someone who only
  // renamed a tooltip, and their stale commands would never be offered again. It describes the
  // generation of *this content* and nothing else.
  const payload = {
    ...Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [storageKey, cleaned[kind]])),
    defaultMain,
    repoMainBranch: overrides.value,
    [VERSION_KEY]: versionToSave({ loadedVersion: state.loadedVersion, reviewed: state.reviewed }),
  };

  state.saving = true;
  state.changedDuringSave = false;
  scheduleOptionsEngineNotify();
  try {
    // This page may have been open a long time, and another device on the account can have saved in
    // the meantime — a migration, say. Writing our payload over that would erase their decision with
    // no trace. There is no compare-and-set in storage.sync, so we read once more, right here, and
    // refuse if anything moved.
    //
    // The window between this read and the write below cannot be closed without a transaction. What
    // lands in it is a last-write-wins overwrite, and if what it overwrites was a migration decision
    // the loss is permanent: the version we write is ours, so the notice does not come back to offer
    // it again. That is the residual, stated as it is — it is not "the notice appears once more".
    let liveSnapshot;
    try {
      liveSnapshot = await chrome.storage.sync.get([...SETTINGS_KEYS, VERSION_KEY]);
    } catch (error) {
      // The read that decides whether writing is safe failed, so writing is not safe. It used to
      // reject unhandled: no status, no refusal, and the save simply evaporated.
      showStatus('error', tr('ext.status.saveFailed', error.message));
      return false;
    }
    const outcome = planSave({
      capturedSnapshot,
      liveSnapshot,
      payload,
      appliedGenerationAtStart,
      appliedGenerationNow: state.appliedGeneration,
      // Before or during — either way an owned change arrived that this page has not adopted. A
      // change event is a stronger fact than the live read, which can be answered from before the
      // remote write committed.
      storeMovedSinceLoad: staleAtStart || state.changedDuringSave,
      // Settings from a generation we do not understand are readable and exportable, never
      // writable. The storage-version contract should keep this unreachable; it is insurance if it
      // does not.
      loadedVersion: state.loadedVersion,
    });
    if (outcome.refused) {
      // Only a conflict means the page is behind the store. After a reload it has just caught up,
      // and a banner there would be telling the user about a gap that no longer exists.
      if (outcome.stale) markStale();
      showStatus('error', outcome.message);
      return false;
    }

    try {
      // From here until settleSave records it as the loaded snapshot, this is what our own change
      // event will look like — the event can arrive before `set` has even resolved.
      state.pendingWrite = payload;
      await chrome.storage.sync.set(outcome.write);
    } catch (error) {
      showStatus('error', tr('ext.status.saveFailed', error.message));
      return false;
    }
    settleSave({ payload, cleaned, defaultMain, overrides, savedRevision });
    return true;
  } finally {
    state.saving = false;
    state.pendingWrite = null;
    scheduleOptionsEngineNotify();
    // A remote change that arrived during the save was held rather than acted on. Now that the save
    // has settled, ask the ordinary question again.
    adoptDeferredChange();
  }
}

// Everything that follows a successful write, kept out of saveSettings so the try/finally around the
// asynchronous part stays readable.
function settleSave({ payload, cleaned, defaultMain, overrides, savedRevision }) {
  // Facts about storage, true whatever the user did meanwhile: it now holds exactly this payload,
  // so that is what a later save must find there, and our own change event is no longer a conflict
  // with ourselves.
  state.loadedSnapshot = payload;
  // …but only if nothing arrived while we were writing. A remote change that landed after the
  // pre-write read is still unadopted, so clearing the banner here would erase a warning that is
  // still true — and if the user had also been typing, the held change was then dropped as well and
  // nothing at all showed it.
  if (!state.changedDuringSave) state.staleSinceLoad = false;
  const version = payload[VERSION_KEY];

  // Everything below is a claim about the *user* — that they have nothing outstanding — and none of
  // it may be made if they acted while the save was in flight. Clearing `reviewTouched` above this
  // line is precisely the bug: a box toggled during the save was forgotten, the next remote change
  // was adopted, the selection snapped back to the defaults, and Apply rewrote a candidate they had
  // declined. One predicate now guards the whole settlement.
  if (!nothingHappenedSince(savedRevision, state.revision)) {
    showStatus('success', tr('ext.status.savedWithPendingEdits'));
    return;
  }
  state.reviewTouched = false;

  // Bring the view in line with what was saved (empty rows cleared, whitespace trimmed). The uids
  // are carried over: these are the same buttons, only tidied, and a candidate the user is looking
  // at must keep its name across a save.
  state.defaultMain = defaultMain;
  for (const { kind } of SECTIONS) {
    state.buttons[kind] = cleaned[kind].map(
      (button, index) => reshapeButton(button, state.buttons[kind][index].uid)
    );
  }
  state.overrides = Object.entries(overrides.value).map(([repo, branch]) => ({ repo, branch }));

  // What was just written is now what is stored, so the notice reflects that — and because the
  // version rode along, the other machines on this account drop their notice as the change syncs.
  state.loadedVersion = version;
  state.reviewed = false;
  setPlan(planMigration(editStateSnapshot(), version));

  clearDirty();
  showStatus('success', tr('ext.status.saved'));
}

// --- The update notice ---
// The stored settings can predate the current presets. What we may rewrite (an old preset matched
// verbatim, or a customized command whose first clause was exactly the old jump) is offered per
// item; anything else is only pointed at. Applying fills the edit state — the write still goes
// through Save, like import.

function setPlan(plan) {
  state.plan = plan;
  // Only the candidates nothing can go wrong with start checked. A behavior change is opted into
  // after reading it, never opted out of after missing it (defaultSelection in migrations.js).
  state.selection = new Set(defaultSelection(plan));
  scheduleOptionsEngineNotify();
}

function prepareMigrationSelection(uid, selected) {
  if (!state.plan || typeof uid !== 'string' || typeof selected !== 'boolean'
    || !state.plan.actionable.some(item => item.id === uid)) return rejectedEdit('not-found');
  if (state.selection.has(uid) === selected) return preparedEdit(() => {}, undefined, false);
  return preparedEdit(() => {
    if (selected) state.selection.add(uid);
    else state.selection.delete(uid);
    state.migrationPanelOpen = true;
  });
}

function prepareMigrationPanelToggle() {
  if (!state.plan || state.loadedVersion >= state.plan.targetVersion) return rejectedEdit('not-found');
  return preparedEdit(() => {
    state.migrationPanelOpen = !state.migrationPanelOpen;
  });
}

// The user has decided about this generation — by applying some or none of it, by declining, or by
// resetting. That decision is what lets the next save move the version.
function recordMigrationReviewed() {
  state.reviewed = true;
  state.plan = null;
  state.migrationPanelOpen = false;
  state.selection = new Set();
  scheduleOptionsEngineNotify();
}

function completeMigrationApply(operation) {
  // Two complete messages, not one message with a clause bolted on. The English needed
  // `command`/`commands` and `was`/`were` to agree with two different counts, and a translation
  // cannot be assembled out of the pieces that made those agree.
  showStatus('info', operation.declined > 0
    ? tr('ext.migration.appliedWithDeclined', operation.applied, operation.declined, tr('ext.button.save'))
    : tr('ext.migration.applied', operation.applied, tr('ext.button.save')));
}

function completeMigrationKeep() {
  showStatus('info', tr('ext.migration.markedReviewed', tr('ext.button.save')));
}

// --- Export / import ---
// The extension ID is pinned by the manifest key, so storage.sync already carries settings between
// Chrome profiles on the same Google account — this path is for moving them without an account, or
// for a file backup against a reinstall.

// The version rides along, so a backup records which generation of the presets it was written
// against and an old one still gets offered the migration when it comes back in.
const BACKUP_KEYS = [...SETTINGS_KEYS, VERSION_KEY];
const MAX_IMPORT_BYTES = 256 * 1024;

// Validate file text into a fragment of the storage schema. It touches neither the DOM nor the
// chrome APIs, so it can be tested standalone.
// Throws for an unusable file, and returns the keys it recognized but discarded as `skipped`.
function parseImportedSettings(raw) {
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error(tr('ext.import.notJSON'));
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(tr('ext.import.notObject'));
  }

  // A file from a newer extension is refused whole, before anything is read out of it: we do not
  // know what its keys mean, and filling the form from a half-understood file invites a Save that
  // downgrades the account. This throws rather than joining `skipped` — it is not a key we ignored,
  // it is an import that must not happen.
  const version = importedSchemaVersion(data);

  // Shape checking — and the limits — are shared with the load path (adoptStoredSettings): a file
  // and a stored object are the same kind of stranger, and a shape one path survives must not be one
  // the other dies on. The limits used to be applied only here, as a silent `slice`, so the same
  // over-limit array was cut short through import and kept whole through storage; and the entry this
  // trimmed away vanished with nothing said. All that is left specific to a file is "an empty array
  // is not a setting".
  const adopted = adoptStoredSettings(data);
  const settings = {};
  const skipped = [];
  // What was dropped from *inside* a key the file did carry. A file with one good button and one
  // unusable one used to import the good one in silence: the key was present in the result, so it
  // never reached the "skipped keys" list below and nothing said an entry had gone.
  const unreadable = describeSkipped(adopted.skippedByKey);

  for (const key of SECTIONS.map(s => s.storageKey)) {
    if (data[key] === undefined) continue;
    // An empty array means "no setting", not "no buttons" — the background logic doesn't fall back
    // to the defaults for an empty array, so the buttons would disappear entirely.
    const buttons = adopted.settings[key] || [];
    if (buttons.length) settings[key] = buttons;
    else skipped.push(key);
  }

  for (const key of ['defaultMain', 'repoMainBranch']) {
    if (data[key] === undefined) continue;
    if (adopted.settings[key] !== undefined) settings[key] = adopted.settings[key];
    else skipped.push(key);
  }

  if (Object.keys(settings).length === 0) {
    throw new Error(tr('ext.import.nothingToImport', BACKUP_KEYS.join(', ')));
  }
  return { settings, skipped, unreadable, version };
}

async function exportSettings() {
  let data;
  try {
    data = await chrome.storage.sync.get(BACKUP_KEYS);
  } catch (error) {
    // An unhandled rejection here produced a button that did nothing and said nothing — and this is
    // the path a user takes precisely when they are trying not to lose their settings.
    showStatus('error', tr('ext.status.exportFailed', error.message));
    return false;
  }
  // Export the saved values, not the unsaved edits on screen
  const saved = Object.fromEntries(BACKUP_KEYS.filter(k => data[k] !== undefined).map(k => [k, data[k]]));
  if (Object.keys(saved).length === 0) {
    showStatus('error', tr('ext.export.nothingSaved'));
    return false;
  }

  const now = new Date();
  const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
  const url = URL.createObjectURL(new Blob([JSON.stringify(saved, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = `terminal-checkout-settings-${stamp}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000); // revoking immediately can cancel the download

  if (state.dirty) showStatus('info', tr('ext.export.excludedUnsaved'));
  return true;
}

// Saving happens through the Save button alone — this too only fills in the view and leaves storage
// untouched. The guard runs before any of it, like every other edit.
function applyImportedSettings(settings, mergedVersion) {
  return edit(() => {
    for (const { kind, storageKey } of SECTIONS) {
      if (settings[storageKey]) state.buttons[kind] = settings[storageKey].map(adoptButton);
    }
    if (settings.defaultMain !== undefined) {
      state.defaultMain = settings.defaultMain.trim() || DEFAULT_MAIN;
    }
    if (settings.repoMainBranch) {
      state.overrides = Object.entries(settings.repoMainBranch).map(([repo, branch]) => ({ repo, branch }));
    }

    // The edit state is now part file, part whatever was already on screen — a file carrying only
    // `defaultMain` leaves every button section untouched. So the generation to answer for is the
    // *older* of the two, and the plan covers the merged whole rather than the file's keys.
    state.loadedVersion = mergedVersion;
    state.reviewed = false;
    setPlan(planMigration(editStateSnapshot(), state.loadedVersion));
  });
}

async function importSettings(file) {
  // An import that landed before the load answered would be merged into an empty edit state and
  // then compared against a snapshot we do not have yet
  if (!requireLoaded()) return false;
  // One file at a time. Two in flight both captured the same revision, and whichever finished
  // reading first applied and disqualified the other — so the file chosen *second* lost, silently.
  if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) {
    showStatus('error', pageBusyMessage(pageTasks()));
    return false;
  }
  if (file.size > MAX_IMPORT_BYTES) {
    showStatus('error', tr('ext.import.fileTooLarge'));
    return false;
  }

  // The world this import starts in. Reading the file is asynchronous and the form stays live
  // throughout, so a file applied afterwards can land on top of what was typed meanwhile — the same
  // defect as a stale load answer overwriting an edit, and it gets the same predicate.
  const revisionAtStart = state.revision;
  const generationAtStart = state.loadGeneration;

  state.importing = true;
  scheduleOptionsEngineNotify();
  try {
    let imported;
    let mergedVersion;
    try {
      imported = parseImportedSettings(await file.text());
      // Refused here rather than merged: with stored settings from the future, taking the minimum
      // hands an old generation to content a newer extension wrote, and the next Save records it.
      mergedVersion = mergedSourceVersion(state.loadedVersion, imported.version);
    } catch (error) {
      showStatus('error', tr('ext.status.importFailed', error.message));
      return false;
    }

    const outcome = planImport({
      revisionAtStart,
      revisionNow: state.revision,
      generationAtStart,
      generationNow: state.loadGeneration,
      settings: imported.settings,
    });
    if (outcome.refused) {
      showStatus('error', outcome.message);
      return false;
    }

    // Refused only if the page stopped being loaded under us; nothing was filled in, so nothing is
    // reported as imported either.
    if (!applyImportedSettings(outcome.apply, mergedVersion)) return false;

    const notes = [...imported.unreadable];
    if (imported.skipped.length) notes.push(tr('ext.import.skippedNote', imported.skipped.join(', ')));
    // The notes are a list of complete diagnostic sentences, not a clause of this one, which is why
    // they may ride in a placeholder where the declined count above may not: what varies here is how
    // many sentences follow, never the grammar of this one.
    showStatus('info', notes.length
      ? tr('ext.status.importedWithNotes', tr('ext.button.save'), notes.join('; '))
      : tr('ext.status.imported', tr('ext.button.save')));
    return true;
  } finally {
    state.importing = false;
    scheduleOptionsEngineNotify();
    // Same settlement as the save: a change held while this ran gets asked again now
    adoptDeferredChange();
  }
}

let statusTimer = null;

function showStatus(type, message) {
  state.status = { type, message };
  clearTimeout(statusTimer);
  scheduleOptionsEngineNotify();
  statusTimer = setTimeout(() => {
    state.status = { type: 'idle', message: '' };
    scheduleOptionsEngineNotify();
  }, 4000);
}

function showError(message) {
  showStatus('error', message);
}

// A save on another machine on this account arrives here as a storage change. Adopting it is what
// makes the notice disappear everywhere once anyone has dealt with it — but never at the cost of
// what someone is typing right now.
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName !== 'sync') return;

  // One decision instead of a chain of early returns, because each of those returns had to remember
  // to raise the banner and one of them did not: a change arriving before the first load was dropped
  // on the theory that the read already in flight would see it, which it need not.
  const outcome = classifyStorageChange({
    changes,
    loaded: state.loaded,
    // A save or an import holds the form across an await; adopting underneath either replaces what
    // it is about to write or fill
    taskInFlight: state.saving || state.importing,
    // Unsaved work — text typed, or a review being decided — wins over a remote change
    busy: editsInProgress(),
    // Our own save arrives here as a change event too. Treating it as another device would warn
    // about a conflict with ourselves and throw away a review in progress.
    isOwnWrite: isOurOwnWrite(changes),
  });
  if (outcome === 'ignore') return;

  // From here the store has moved under us, and that fact is recorded before anything else is
  // decided — the save is the authority, but the warning belongs on screen sooner.
  markStale();
  // A save in flight captured the store as it was before this change; it cannot be written now,
  // whatever its own live read comes back with.
  if (state.saving) state.changedDuringSave = true;

  if (outcome === 'defer') {
    // Held, not dropped. Merged rather than replaced: two changes arriving before we can act are
    // two keys that moved, and the adoption that follows has to cover both.
    state.deferredChange = { ...state.deferredChange, ...changes };
    return;
  }
  if (outcome === 'banner') return; // the mark above is the whole action
  // loadSettings checks again, after its await, whether the page moved on in the meantime
  loadSettings();
});

// The manifest uses options_page (a full tab), so the leave-site warning dialog actually appears.
// Switching to options_ui (embedded) makes the browser suppress it.
window.addEventListener('beforeunload', (e) => {
  if (!wouldLoseWork()) return;
  e.preventDefault();
  e.returnValue = '';
});

// A load that failed is the only thing the user can act on while unloaded, and retry starts a fresh
// attempt — a new generation, so an earlier answer that turns up late cannot win.
async function retrySettingsLoad() {
  hideLoadFailure();
  showStatus('info', LOADING_MESSAGE());
  return loadSettings();
}

function freezeSnapshot(value) {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) freezeSnapshot(child);
  return Object.freeze(value);
}

function optionsStatusSnapshot() {
  return { ...state.status };
}

/** @returns {OptionsEngineSnapshot} */
function getOptionsEngineSnapshot() {
  const editValidation = validateEditState();
  const validationByButton = new Map(editValidation.buttons.map(item => [item.uid, item]));
  const buttons = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind,
    state.buttons[kind].map(button => ({
      uid: button.uid,
      face: button.face,
      label: button.label,
      command: button.command,
      claudeInputs: [...button.claudeInputs],
      ...classifyPresetCommand(button.command, section(kind).presets),
      validation: {
        errors: [...validationByButton.get(button.uid).errors],
        warnings: [...validationByButton.get(button.uid).warnings],
      },
    })),
  ]));
  const buttonDiagnostics = SECTIONS.flatMap(({ kind }) => buttons[kind].map(button => ({
    kind,
    uid: button.uid,
    errors: [...button.validation.errors],
    warnings: [...button.validation.warnings],
  })));
  const loadError = state.loadErrorMessage !== null;
  const loadStatus = state.loaded
    ? (state.loadsInFlight ? 'reloading' : 'loaded')
    : state.loadsInFlight
      ? 'loading'
      : loadError ? 'error' : 'unloaded';
  const validation = { buttons: buttonDiagnostics, overrides: editValidation.overrides };
  const targetVersion = state.plan?.targetVersion ?? SETTINGS_VERSION;
  const planSummary = state.plan
    ? migrationSummary(state.plan, state.selection)
    : {
      actionableCount: 0,
      informationalCount: 0,
      selectedCount: 0,
      nothingToApply: true,
      reviewOnly: false,
      descriptions: '',
    };
  const migration = {
    fromVersion: state.plan?.fromVersion ?? state.loadedVersion,
    targetVersion,
    pending: state.plan !== null && state.loadedVersion !== null && state.loadedVersion < targetVersion,
    reviewed: state.reviewed,
    reviewTouched: state.reviewTouched,
    panelOpen: state.migrationPanelOpen,
    selectedUids: [...state.selection].filter(uid => typeof uid === 'string'),
    summary: planSummary,
    actionable: (state.plan?.actionable || []).map(item => ({
      uid: item.id,
      kind: item.kind,
      index: item.index,
      label: item.label,
      from: item.from,
      to: item.to,
      source: item.source,
      effect: item.effect,
      selected: state.selection.has(item.id),
      describe: item.describe,
      ...(Object.hasOwn(item, 'fromInputs') ? { fromInputs: [...item.fromInputs], toInputs: [...item.toInputs] } : {}),
    })),
    informational: (state.plan?.informational || []).map(item => ({
      uid: item.id,
      kind: item.kind,
      index: item.index,
      label: item.label,
      command: item.command,
      note: item.note || '',
    })),
  };
  const saveBlocked = !shouldStartPageTask({ loaded: state.loaded, ...pageTasks() });
  const saveStatus = state.saving ? 'saving'
    : saveBlocked ? 'blocked'
      : (state.dirty || state.reviewTouched) ? 'dirty' : 'clean';
  const status = optionsStatusSnapshot();
  return freezeSnapshot({
    buttons,
    dirty: state.dirty,
    revision: state.revision,
    validation,
    globalSettings: {
      defaultMain: state.defaultMain,
      repoMainBranch: state.overrides.map((row, index) => ({ index, repo: row.repo, branch: row.branch })),
    },
    load: {
      status: loadStatus,
      loaded: state.loaded,
      generation: state.loadGeneration,
      appliedGeneration: state.appliedGeneration,
      inFlight: state.loadsInFlight,
      errorMessage: state.loadErrorMessage,
      retryAvailable: !state.loaded && loadError,
    },
    save: {
      status: saveStatus,
      saving: state.saving,
      importing: state.importing,
      dirty: state.dirty,
      reviewTouched: state.reviewTouched,
      hasUnsavedWork: editsInProgress(),
      canSave: !saveBlocked && !state.saving,
      loadedVersion: state.loadedVersion,
      versionToWrite: state.loaded ? versionToSave({ loadedVersion: state.loadedVersion, reviewed: state.reviewed }) : null,
    },
    sync: {
      staleSinceLoad: state.staleSinceLoad,
      deferredChangePending: state.deferredChange !== null,
      changedDuringSave: state.changedDuringSave,
    },
    migration,
    status,
  });
}

/** @param {(snapshot: OptionsEngineSnapshot) => void} listener @returns {() => void} */
function subscribeOptionsEngine(listener) {
  if (typeof listener !== 'function') throw new TypeError('optionsEngine.subscribe expects a function');
  optionsEngineListeners.add(listener);
  return () => optionsEngineListeners.delete(listener);
}

function buttonIndexForUid(kind, uid) {
  const buttonSection = section(kind);
  if (!buttonSection || typeof uid !== 'string') return -1;
  return state.buttons[buttonSection.kind].findIndex(button => button.uid === uid);
}

function runPreparedEdit(operation, { review: isReview = false } = {}) {
  if (!operation.ok) return operation;
  if (operation.changed === false) return { ok: true };
  const accepted = (isReview ? editAndReview : edit)(operation.apply);
  if (!accepted) return rejectedEdit(state.loaded ? 'busy' : 'not-loaded');
  return { ok: true, ...(operation.createdUid ? { createdUid: operation.createdUid } : {}) };
}

function runPreparedReview(operation) {
  if (!operation.ok) return operation;
  if (operation.changed === false) return { ok: true };
  if (!review(operation.apply)) return rejectedEdit(state.loaded ? 'busy' : 'not-loaded');
  return { ok: true };
}

async function discardOptionsEdits(confirmed) {
  if (!state.loaded) return rejectedEdit('not-loaded');
  if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) {
    showStatus('info', pageBusyMessage(pageTasks()));
    return rejectedEdit('busy');
  }
  const hadUnsavedWork = editsInProgress();
  if (hadUnsavedWork && confirmed !== true) return rejectedEdit('needs-confirmation');

  const revisionAtStart = state.revision;
  const appliedGenerationAtStart = state.appliedGeneration;
  const previousDirty = state.dirty;
  const previousReviewTouched = state.reviewTouched;
  if (hadUnsavedWork) {
    clearDirty();
    state.reviewTouched = false;
    scheduleOptionsEngineNotify();
  }
  await loadSettings();
  const applied = state.appliedGeneration !== appliedGenerationAtStart;
  if (!applied && state.revision === revisionAtStart && hadUnsavedWork) {
    state.dirty = previousDirty;
    state.reviewTouched = previousReviewTouched;
    scheduleOptionsEngineNotify();
  }
  return applied ? { ok: true } : rejectedEdit('failed');
}

function dispatchResult(outcome) {
  return {
    ok: outcome.ok,
    ...(outcome.reason ? { reason: outcome.reason } : {}),
    ...(outcome.createdUid ? { createdUid: outcome.createdUid } : {}),
    snapshot: getOptionsEngineSnapshot(),
  };
}

/** @param {OptionsEngineAction} action @returns {Promise<OptionsDispatchResult>} */
async function dispatchOptionsEngineAction(action) {
  if (!action || typeof action !== 'object' || typeof action.type !== 'string') {
    return dispatchResult(rejectedEdit('invalid'));
  }
  const type = action.type;
  const editsSettings = new Set([
    'discard', 'adopt-latest', 'reset', 'migration-apply', 'migration-keep', 'main-patch',
    'migration-selection', 'migration-panel-toggle',
    'override-add', 'override-patch', 'override-remove', 'button-patch', 'button-add',
    'button-duplicate', 'button-remove', 'button-move', 'preset-add', 'preset-replace',
    'input-add', 'input-patch', 'input-remove', 'input-move',
  ]);
  if (editsSettings.has(type) && !state.loaded) {
    requireLoaded();
    return dispatchResult(rejectedEdit('not-loaded'));
  }

  try {
    let outcome;
    switch (type) {
      case 'save': {
        if (!state.loaded) outcome = rejectedEdit('not-loaded');
        else if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) outcome = rejectedEdit('busy');
        else {
          const validation = validateEditState();
          if (validation.buttons.some(button => button.errors.length)
            || validation.overrides.some(row => row.errors.length)) {
            await saveSettings();
            outcome = rejectedEdit('invalid');
          }
          else outcome = await saveSettings() ? { ok: true } : rejectedEdit('failed');
        }
        break;
      }
      case 'discard':
      case 'adopt-latest':
        outcome = await discardOptionsEdits(action.confirmed);
        break;
      case 'retry-load': {
        const appliedBefore = state.appliedGeneration;
        await retrySettingsLoad();
        outcome = state.appliedGeneration !== appliedBefore ? { ok: true } : rejectedEdit('failed');
        break;
      }
      case 'reload-latest': {
        if (!state.loaded) outcome = rejectedEdit('not-loaded');
        else if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) outcome = rejectedEdit('busy');
        else {
          const appliedBefore = state.appliedGeneration;
          await loadSettings();
          outcome = state.appliedGeneration !== appliedBefore ? { ok: true } : rejectedEdit('failed');
        }
        break;
      }
      case 'defer-latest':
        outcome = { ok: true };
        break;
      case 'reset':
        outcome = runPreparedEdit(prepareReset(), { review: true });
        if (outcome.ok) showStatus('info', tr('ext.status.reset', tr('ext.button.save')));
        break;
      case 'export-saved':
        outcome = await exportSettings() ? { ok: true } : rejectedEdit('failed');
        break;
      case 'import-file':
        if (typeof File === 'undefined' || !(action.file instanceof File)) outcome = rejectedEdit('invalid');
        else if (!state.loaded) outcome = rejectedEdit('not-loaded');
        else if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) outcome = rejectedEdit('busy');
        else outcome = await importSettings(action.file) ? { ok: true } : rejectedEdit('failed');
        break;
      case 'migration-apply':
        {
          const operation = prepareMigrationApply();
          outcome = runPreparedEdit(operation, { review: true });
          if (outcome.ok) completeMigrationApply(operation);
        }
        break;
      case 'migration-keep':
        outcome = runPreparedEdit(prepareMigrationKeep(), { review: true });
        if (outcome.ok) completeMigrationKeep();
        break;
      case 'migration-selection':
        outcome = runPreparedReview(prepareMigrationSelection(action.uid, action.selected));
        break;
      case 'migration-panel-toggle':
        outcome = runPreparedReview(prepareMigrationPanelToggle());
        break;
      case 'main-patch':
        outcome = runPreparedEdit(prepareMainPatch(action.value));
        break;
      case 'override-add':
        outcome = runPreparedEdit(prepareOverrideAdd());
        break;
      case 'override-patch':
        outcome = runPreparedEdit(prepareOverridePatch(action.index, action.patch));
        break;
      case 'override-remove':
        outcome = runPreparedEdit(prepareOverrideRemove(action.index));
        break;
      case 'button-patch':
        outcome = runPreparedEdit(prepareButtonPatch(action.kind, action.uid, action.patch));
        break;
      case 'button-add':
        outcome = runPreparedEdit(prepareButtonAdd(action.kind));
        break;
      case 'button-duplicate':
        outcome = runPreparedEdit(prepareButtonDuplicate(action.kind, action.uid));
        break;
      case 'button-remove':
        outcome = runPreparedEdit(prepareButtonRemove(action.kind, action.uid));
        break;
      case 'button-move':
        outcome = runPreparedEdit(prepareButtonMove(action.kind, action.uid, action.beforeUid));
        break;
      case 'preset-add':
        outcome = runPreparedEdit(preparePresetAdd(action.kind, action.presetId, action.beforeUid));
        break;
      case 'preset-replace':
        outcome = runPreparedEdit(preparePresetReplace(action.kind, action.uid, action.presetId, action.confirmed));
        break;
      case 'input-add':
        outcome = runPreparedEdit(prepareInputAdd(action.kind, action.buttonUid, action.value));
        break;
      case 'input-patch':
        outcome = runPreparedEdit(prepareInputPatch(action.kind, action.buttonUid, action.inputIndex, action.value));
        break;
      case 'input-remove':
        outcome = runPreparedEdit(prepareInputRemove(action.kind, action.buttonUid, action.inputIndex));
        break;
      case 'input-move':
        outcome = runPreparedEdit(prepareInputMove(action.kind, action.buttonUid, action.fromIndex, action.beforeIndex));
        break;
      default:
        outcome = rejectedEdit('invalid');
    }
    return dispatchResult(outcome);
  } catch (error) {
    console.error('Terminal Checkout: options action failed', error);
    return dispatchResult(rejectedEdit('failed'));
  }
}

/** @type {OptionsEngine} */
window.optionsEngine = Object.freeze({
  getSnapshot: getOptionsEngineSnapshot,
  subscribe: subscribeOptionsEngine,
  dispatch: dispatchOptionsEngineAction,
});

window.optionsShell.mount(
  document.getElementById('options-shell-root'),
  window.optionsEngine,
  document.getElementById('options-shell-settings-root'),
);
window.optionsReplica.mount(
  document.getElementById('options-replica-root'),
  window.optionsEngine,
  window.optionsEditor,
);
window.optionsEditor.mount(document.getElementById('options-editor-root'), window.optionsEngine);

// Nothing on this page may act on settings until there are settings. The gate goes up before the
// first load is even asked for, so the window where the controls are live but the state is empty
// does not exist.
updateLoadedGate();
loadSettings();
