// defaults.js is the single source of truth for button defaults, presets, and face rules
// (options.html loads it first)

// PR, issue, and repository buttons differ in both their storage key and the variables they can
// use (BUTTON_KINDS in defaults.js). Everything else about editing them is identical, so here we
// only add the DOM slot each set of cards goes into and share one renderer and one set of event
// handlers.
const SECTIONS = [
  { kind: 'pr', container: 'pr-buttons', addButton: 'pr-add', addHint: 'pr-add-hint' },
  { kind: 'issue', container: 'issue-buttons', addButton: 'issue-add', addHint: 'issue-add-hint' },
  { kind: 'repo', container: 'repo-buttons', addButton: 'repo-add', addHint: 'repo-add-hint' },
].map(dom => ({ ...BUTTON_KINDS[dom.kind], ...dom }));

// Emoji commonly used as a face — clicking one appends it to the face field (they can be combined)
const FACE_EMOJI = ['⏏️', '🤖', '🌳', '🪵', '🔍', '🧪', '📝', '🚀', '🔧', '⚡', '📋', '📂'];

// This page stores message ids in `data-i18n`, not prose, and resolves them synchronously through
// `chrome.i18n` before drawing.

// A message as **text**. Everything that lands in `textContent`, a `title`, a placeholder or
// `confirm()` comes through here, and no value it returns carries markup.
//
// The split from `tHTML` is the point, and it is the same shape as the app's shell-payload type: a
// value that will be parsed as HTML and a value that may contain something the user typed must not
// be reachable through one function. A repository name goes into a validation message; that message
// is set with `textContent`, so it can only ever be text. A test pins the halves apart — a key whose
// value contains a tag is used only through `tHTML`, and never the other way around.
function t(key, ...args) {
  return tr(key, ...args);
}

// A message as **markup**, for the two places that build HTML: the static prose in `options.html`
// and the button card template. Its arguments are ours — a constant, a preset name, another
// message — and never anything a user typed.
function tHTML(key, ...args) {
  return tr(key, ...args);
}

// The arguments the static prose takes, in one table, so that "what can reach innerHTML on this
// page" is a list to read rather than a search to run. Thunks rather than values: the labels they
// quote are themselves messages and must resolve in the same paint as the containing sentence.
//
// The quotations are message relations. Prose that names another control used to spell that control's
// label out again — and the two had already drifted apart here, with one paragraph calling the
// field `Face` and another calling it `face`. Naming the message instead of the string means a
// translator cannot make them disagree. Thunks resolve the quoted labels in the same paint as the
// sentence that contains them.
const STATIC_TEXT_ARGS = {
  'ext.section.pr.help1': () => [MAX_BUTTONS, t('ext.field.face'), t('ext.field.tooltip')],
  'ext.section.pr.help2': () => [t('ext.card.duplicate')],
  'ext.section.issue.help': () => [MAX_BUTTONS],
  'ext.section.repo.help': () => [
    MAX_BUTTONS,
    presetById(section('repo').presets, 'repo.open').name,
    t('ext.field.face'),
  ],
  'ext.section.backup.help2': () => [t('ext.button.save')],
  'ext.button.addLimit': () => [MAX_BUTTONS],
};

// Fill every node that names a message while the parser is still here.
function applyStaticText(root = document) {
  for (const node of root.querySelectorAll('[data-i18n]')) {
    const key = node.dataset.i18n;
    const args = Object.hasOwn(STATIC_TEXT_ARGS, key) ? STATIC_TEXT_ARGS[key]() : [];
    node.innerHTML = tHTML(key, ...args);
  }
}

applyDocumentLanguage();
document.title = `Terminal Checkout — ${t('ext.header.options')}`;
applyStaticText();

// Unlike the storage schema, overrides are kept as an array. Keying them by repo would mean
// deleting and re-adding the key on every keystroke in the name, and redrawing the row each time
// would throw away the input focus.
const state = {
  buttons: Object.fromEntries(SECTIONS.map(s => [s.kind, []])),
  overrides: [],
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
  // Ids of the checked candidates — they start checked, so this starts as all of them.
  selection: new Set(),
};

function section(kind) {
  return SECTIONS.find(s => s.kind === kind);
}

// The preset list is fixed per section, so build it once and clone it for each card.
//
// Chrome fixes the catalogue for this extension context, so a template built at load can be cloned
// for the page's lifetime. A Chrome-language change creates a new context on the next page load.
let presetTemplates = buildPresetTemplates();

function buildPresetTemplates() {
  return Object.fromEntries(SECTIONS.map(({ kind, presets }) => {
    const select = document.createElement('select');
    select.className = 'preset-select';
    select.add(new Option(t('ext.field.preset.placeholder'), ''));
    // The value is the preset's id and the text is its name — a name is display text and will be
    // translated, so it cannot be what the selection is read back as (defaults.js, presetOptions)
    presetOptions(presets).forEach(({ value, text }) => select.add(new Option(text, value)));
    return [kind, select];
  }));
}

// Buttons enter the edit state through `adoptButton` (anything from outside: storage, a file, a
// preset — it gets a uid we mint) or `reshapeButton` (a button already here, keeping its name).
// Both live in defaults.js, along with why they are two functions and not one.

// Until the first load answers, this page holds no settings — only the empty shell of the edit
// state. Every entry point that would write, or that would change what a later write contains, asks
// here first. The page is also inert until then (updateLoadedGate), but that is the fence; this is
// the rule, and code paths that do not come from a click still have to pass it.
const LOADING_MESSAGE = () => t('ext.status.loading');

function requireLoaded() {
  if (state.loaded) return true;
  showStatus('info', LOADING_MESSAGE());
  return false;
}

// Nothing on the page is interactive until there are settings to interact with.
//
// One switch on the root, not a list of controls. The list was wrong the moment it was written: it
// named the buttons and forgot the `default-main` field and [+ Add Override], and typing in that
// field bumped the revision — which made the first load throw away its own answer and stop, leaving
// the page unloaded with nothing to retry it. A control added later is covered here without anyone
// having to remember.
function updateLoadedGate() {
  // The app, not the whole document: the status line and [Retry] live outside it, so a load that
  // failed still has somewhere to say so and something the user can press.
  document.getElementById('app').inert = !state.loaded;
}

// A load that never answered. The gate stays shut — a Save here would write an empty settings object
// over real ones — so what is offered instead is another attempt.
function showLoadFailure(error) {
  document.getElementById('load-error').hidden = false;
  showStatus('error', `${LOAD_FAILED_MESSAGE()} (${error?.message || error})`);
}

function hideLoadFailure() {
  document.getElementById('load-error').hidden = true;
}

// Save is the one control that has to be shut while it is already running. `inert` covers "before
// the load"; this covers "while a write is in flight", and the guard in saveSettings covers the
// routes that never touch a button.
function updateSavingGate() {
  document.getElementById('save-btn').disabled = state.saving;
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
  renderStaleBanner();
}

// Warns before the save is attempted. The verdict is still the re-read in saveSettings — a change
// event can be missed, and a banner that was never shown must not mean "nothing changed".
function renderStaleBanner() {
  const banner = document.getElementById('stale-banner');
  if (banner) banner.hidden = !state.staleSinceLoad;
}

// The edit state in the shape the planner reads: what would be stored if Save were pressed now,
// with the uids still attached. The plan is always computed against this, never against what
// storage happens to hold — those two drift apart the moment anything is edited or imported.
function editStateSnapshot() {
  return Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [storageKey, state.buttons[kind]]));
}

// --- Rendering ---
// Editing text only updates the state; it never redraws. Redrawing happens only when cards or rows
// are added, removed, or reordered, and every one of those is triggered by a button click, a drag,
// or ↑↓ — so focus is never lost while typing.

function renderButtons(kind) {
  const { container: containerId, addButton, addHint } = section(kind);
  const container = document.getElementById(containerId);
  container.innerHTML = '';

  const count = state.buttons[kind].length;

  state.buttons[kind].forEach((btn, i) => {
    const card = document.createElement('div');
    card.className = 'btn-card';
    card.dataset.index = i;
    card.dataset.kind = kind;
    // Values aren't interpolated into the HTML; they are assigned as properties below (which removes the need to escape them)
    card.innerHTML = `
      <div class="btn-card-header">
        <span class="btn-number">
          ${count > 1 ? `<button class="drag-handle" aria-label="${t('ext.card.reorder.aria')}" title="${t('ext.reorder.tooltip')}">⠿</button>` : ''}
          <span class="prompt">❯</span> ${section(kind).storageKey}[${i}]
        </span>
        <span class="card-actions">
          ${count < MAX_BUTTONS ? `<button class="duplicate-btn" title="${t('ext.card.duplicate.tooltip')}">${t('ext.card.duplicate')}</button>` : ''}
          ${count > 1 ? `<button class="remove-btn">${t('ext.card.delete')}</button>` : ''}
        </span>
      </div>
      <div class="btn-row">
        <div class="field field-face">
          <label for="${kind}-${i}-face">${t('ext.field.face')}</label>
          <input id="${kind}-${i}-face" class="face-input" data-field="face" maxlength="24">
        </div>
        <div class="field field-preview">
          <label>${t('ext.field.preview')}</label>
          <span class="face-preview"></span>
        </div>
        <div class="field field-label">
          <label for="${kind}-${i}-label">${t('ext.field.tooltip')}</label>
          <input id="${kind}-${i}-label" class="label-input" data-field="label" placeholder="${t('ext.field.tooltip.placeholder')}">
        </div>
        <div class="field field-preset">
          <label for="${kind}-${i}-preset">${t('ext.field.preset')}</label>
        </div>
      </div>
      <div class="face-palette">
        <span class="palette-label">${t('ext.card.palette.label')}</span>
        ${FACE_EMOJI.map(e => `<button class="palette-btn" title="${t('ext.card.palette.tooltip', e)}">${e}</button>`).join('')}
      </div>
      <div class="field field-command">
        <label for="${kind}-${i}-command">${t('ext.field.command')}</label>
        <div class="cmd-block">
          <span class="cmd-prompt">$</span>
          <textarea id="${kind}-${i}-command" class="command-input" data-field="command" rows="2"
                    spellcheck="false" placeholder="{cd} && claude"></textarea>
        </div>
      </div>
      <div class="claude-queue">
        <div class="claude-queue-head"><span class="ret">⏎</span> ${t('ext.field.claudeInputs')}
          <span class="help-inline">${tHTML('ext.field.claudeInputs.help')}</span>
        </div>
        <div class="claude-hint" hidden>${tHTML('ext.field.claudeInputs.hint')}</div>
        <div class="claude-warn" hidden>${t('ext.field.claudeInputs.warn')}</div>
        <div class="claude-rows"></div>
        <button class="add-input-btn">${t('ext.button.addInput')}</button>
      </div>
    `;

    const select = presetTemplates[kind].cloneNode(true);
    select.id = `${kind}-${i}-preset`;
    card.querySelector('.field-preset').appendChild(select);

    card.querySelector('.face-input').value = btn.face;
    card.querySelector('.label-input').value = btn.label;
    card.querySelector('.command-input').value = btn.command;

    const rows = card.querySelector('.claude-rows');
    btn.claudeInputs.forEach((text, j) => {
      const row = document.createElement('div');
      row.className = 'claude-row';
      row.dataset.ci = j;
      // Keep this class separate from .drag-handle: the card mousedown listener matches that class
      // and would make the whole card draggable from a row's handle.
      row.innerHTML = `
        ${btn.claudeInputs.length > 1 ? `<button class="ci-drag-handle" aria-label="${t('ext.claudeInput.reorder.aria', j + 1)}" title="${t('ext.reorder.tooltip')}">⠿</button>` : ''}
        <span class="ci-marker">⏎${j + 1}</span>
        <input class="ci-input" placeholder="${t('ext.field.claudeInput.placeholder')}">
        <button class="ci-remove" title="${t('ext.button.remove')}">×</button>
      `;
      row.querySelector('.ci-input').value = text;
      rows.appendChild(row);
    });
    card.querySelector('.add-input-btn').disabled = btn.claudeInputs.length >= MAX_CLAUDE_INPUTS;

    updateFacePreview(card, btn.face);
    updateClaudeWarn(card, btn);
    container.appendChild(card);
    autosize(card.querySelector('.command-input')); // scrollHeight is only meaningful once it is attached
  });

  const atMax = count >= MAX_BUTTONS;
  document.getElementById(addButton).disabled = atMax;
  document.getElementById(addHint).hidden = !atMax;
}

// Paired with the button rendering rules in content.js (they share the decision in defaults.js) —
// this reproduces exactly how the button will look.
// Repository buttons are the only filled action buttons, so their shape is the same whether the
// face is text or emoji.
function updateFacePreview(card, face) {
  const el = card.querySelector('.face-preview');
  const shown = face.trim() || '⏏️';
  const style = card.dataset.kind === 'repo' ? 'gh-btn-header'
    : isTextFace(shown) ? 'gh-btn-text' : 'gh-btn-emoji';
  el.textContent = shown;
  el.className = `face-preview ${style}`;
}

function updateClaudeWarn(card, btn) {
  const hasInputs = btn.claudeInputs.some(s => s.trim());
  card.querySelector('.claude-warn').hidden = !hasInputs || /\bclaude\b/.test(btn.command);
  // The merge rules are only worth reading once there is something to merge — showing them on
  // every empty card would put three paragraphs of prose above every button
  card.querySelector('.claude-hint').hidden = !hasInputs;
}

function renderOverrides() {
  const tbody = document.getElementById('overrides-body');
  tbody.innerHTML = '';

  state.overrides.forEach((row, i) => {
    const tr = document.createElement('tr');
    tr.dataset.index = i;
    tr.innerHTML = `
      <td><input type="text" class="override-repo" placeholder="remy-worker"></td>
      <td><input type="text" class="override-branch" placeholder="master"></td>
      <td><button class="remove-row" title="${t('ext.button.remove')}">✕</button></td>
    `;
    tr.querySelector('.override-repo').value = row.repo;
    tr.querySelector('.override-branch').value = row.branch;
    tbody.appendChild(tr);
  });

  const isEmpty = state.overrides.length === 0;
  document.querySelector('.override-table').hidden = isEmpty;
  document.getElementById('overrides-empty').hidden = !isEmpty;
}

// A clipped command can be neither edited nor reviewed, so grow the height to fit the content
function autosize(textarea) {
  textarea.style.height = 'auto';
  textarea.style.height = `${textarea.scrollHeight}px`; // cmd-block owns the border, so no adjustment is needed
}

function cardOf(el) {
  const card = el.closest('.btn-card');
  return { card, kind: card.dataset.kind, index: Number(card.dataset.index) };
}

function overrideInput(index, selector) {
  return document.querySelector(`#overrides-body tr[data-index="${index}"] ${selector}`);
}

// Grabs an element inside a card by kind and index (the counterpart of overrideInput for override
// rows). Redrawing a card drops the old nodes, so nothing is held on to — it is looked up again
// every time.
function cardElement(kind, index, selector) {
  return document.querySelector(`.btn-card[data-kind="${kind}"][data-index="${index}"] ${selector}`);
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
  if (dirty) {
    state.dirty = true;
    document.getElementById('dirty-indicator').hidden = false;
  }
  if (review) state.reviewTouched = true;
  return true;
}

// Every handler is one of these three: the guard runs, and only then does the change. Writing the
// guard and the change as separate statements is how their order got reversed — [+ Add Button]
// pushed the button and asked afterwards, and so did [+ Add Override], the card inputs, delete,
// duplicate, reorder and the review checkboxes (userAction in migrations.js).
function edit(change) {
  return userAction(() => touch({ dirty: true }), change);
}

function review(change) {
  return userAction(() => touch({ review: true }), change);
}

// Applying, declining and resetting are all decisions about the migration *and* changes that have
// to be saved, so they raise both signals.
function editAndReview(change) {
  return userAction(() => touch({ dirty: true, review: true }), change);
}

function clearDirty() {
  state.dirty = false;
  document.getElementById('dirty-indicator').hidden = true;
}


// --- Applying a preset ---
// The dropdown does not represent the current state. The card shows the state; the dropdown is
// merely an action that loads a template, so it snaps back to its placeholder as soon as one is
// picked.

function applyPreset(select) {
  const id = select.value;
  select.value = ''; // applied or cancelled, it always returns to the placeholder
  if (!id) return;

  const { kind, index } = cardOf(select);
  const preset = presetById(section(kind).presets, id);
  if (!preset) return;

  const current = state.buttons[kind][index].command.trim();
  const isCustom = current !== '' && !section(kind).presets.some(p => p.command === current);
  if (isCustom && !confirm(t('ext.confirm.presetOverwrite', index, preset.name))) {
    return;
  }

  edit(() => {
    // The card stays the same button — only its contents are replaced — so it keeps its uid
    state.buttons[kind][index] = reshapeButton({
      face: preset.face, label: preset.name, command: preset.command,
      claudeInputs: [...(preset.claudeInputs || [])],
    }, state.buttons[kind][index].uid);
    renderButtons(kind); // the number of claude input rows changes too, so redraw the whole card
  });
}

// --- Validation ---

// A complete sentence per field, not a noun phrase spliced into one. `enter ${label}.` needed
// `a face` to carry an English article, and an article is a fact about English grammar that no
// other language here inflects the same way, so never assemble a translated clause.
const REQUIRED_FIELDS = [
  { field: 'face', describe: (key, index) => t('ext.validate.face', key, index) },
  { field: 'label', describe: (key, index) => t('ext.validate.tooltip', key, index) },
  { field: 'command', describe: (key, index) => t('ext.validate.command', key, index) },
];

function validateButtons() {
  for (const { kind } of SECTIONS) {
    const name = section(kind).storageKey;
    for (let i = 0; i < state.buttons[kind].length; i++) {
      for (const { field, describe } of REQUIRED_FIELDS) {
        if (state.buttons[kind][i][field].trim()) continue;
        return {
          message: describe(name, i),
          focus: cardElement(kind, i, `[data-field="${field}"]`),
        };
      }
    }
  }
  return null;
}

// Turn the overrides we keep as an array back into the storage schema (an object)
function serializeOverrides() {
  const entries = new Map();

  for (let i = 0; i < state.overrides.length; i++) {
    const repo = state.overrides[i].repo.trim();
    const branch = state.overrides[i].branch.trim();

    if (!repo && !branch) continue; // a row that was added but never filled in is dropped silently

    if (!repo || !branch) {
      return {
        error: {
          message: t('ext.validate.override.incomplete', i + 1),
          focus: overrideInput(i, repo ? '.override-branch' : '.override-repo'),
        },
      };
    }
    if (entries.has(repo)) {
      return {
        error: {
          message: t('ext.validate.override.duplicate', i + 1, repo),
          focus: overrideInput(i, '.override-repo'),
        },
      };
    }
    entries.set(repo, branch);
  }

  return { value: Object.fromEntries(entries) };
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
  try {
    data = await chrome.storage.sync.get([...SETTINGS_KEYS, VERSION_KEY]);
  } catch (error) {
    if (generation === state.loadGeneration) showLoadFailure(error);
    // The change that asked for this re-read is not adopted, and `staleSinceLoad` was never cleared,
    // so the banner it raised is still up — which is the whole point of not clearing it early.
    return;
  } finally {
    state.loadsInFlight -= 1;
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
    return;
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
  document.getElementById('default-main').value = settings.defaultMain || 'main';

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
  renderStaleBanner();
  const dropped = describeSkipped(skippedByKey);
  if (dropped.length) {
    // Said out loud, named per key, and with the consequence attached. The section above is now
    // empty rather than quietly full of presets, so the user can see that something is missing —
    // and this says what pressing Save would do to it, and how to keep a copy first.
    showStatus('error', `${dropped.join('; ')}. ${SKIP_CONSEQUENCE()}`);
  }

  SECTIONS.forEach(({ kind }) => renderButtons(kind));
  renderOverrides();
  // Planned from the edit state that was just built, not from `data` — those are the same thing
  // here, and keeping one path means they cannot fall out of step later.
  setPlan(planMigration(editStateSnapshot(), state.loadedVersion));

  // A change that arrived before this page had settings was held rather than dropped, because the
  // read that was already outstanding may have been answered from before that write landed. Now
  // there is something to compare against, so ask again — which re-reads, this time knowing the
  // store moved.
  adoptDeferredChange();
}

async function saveSettings() {
  // Nothing may be written before the first load answers: the edit state is empty until then, and
  // writing it would delete every command and mark the migration as reviewed in the same breath.
  if (!requireLoaded()) return;
  // One page-changing task at a time. Two saves would each capture the same world, each find it
  // unchanged, and the later write would land carrying what was true before the earlier one; a save
  // started while a load is outstanding builds its payload from a form that answer is about to
  // replace.
  if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) {
    showStatus('info', pageBusyMessage(pageTasks()));
    return;
  }

  const invalidButton = validateButtons();
  if (invalidButton) return showError(invalidButton);

  const overrides = serializeOverrides();
  if (overrides.error) return showError(overrides.error);

  // toStoredButton is what decides the stored shape — including dropping the runtime uid
  const cleaned = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind, state.buttons[kind].map(toStoredButton),
  ]));
  const defaultMain = document.getElementById('default-main').value.trim() || 'main';

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
  updateSavingGate();
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
      showStatus('error', t('ext.status.saveFailed', error.message));
      return;
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
      return;
    }

    try {
      // From here until settleSave records it as the loaded snapshot, this is what our own change
      // event will look like — the event can arrive before `set` has even resolved.
      state.pendingWrite = payload;
      await chrome.storage.sync.set(outcome.write);
    } catch (error) {
      showStatus('error', t('ext.status.saveFailed', error.message));
      return;
    }
    settleSave({ payload, cleaned, defaultMain, overrides, savedRevision });
  } finally {
    state.saving = false;
    state.pendingWrite = null;
    updateSavingGate();
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
  renderStaleBanner();
  const version = payload[VERSION_KEY];

  // Everything below is a claim about the *user* — that they have nothing outstanding — and none of
  // it may be made if they acted while the save was in flight. Clearing `reviewTouched` above this
  // line is precisely the bug: a box toggled during the save was forgotten, the next remote change
  // was adopted, the selection snapped back to the defaults, and Apply rewrote a candidate they had
  // declined. One predicate now guards the whole settlement.
  if (!nothingHappenedSince(savedRevision, state.revision)) {
    showStatus('success', t('ext.status.savedWithPendingEdits'));
    return;
  }
  state.reviewTouched = false;

  // Bring the view in line with what was saved (empty rows cleared, whitespace trimmed). The uids
  // are carried over: these are the same buttons, only tidied, and a candidate the user is looking
  // at must keep its name across a save.
  document.getElementById('default-main').value = defaultMain;
  for (const { kind } of SECTIONS) {
    state.buttons[kind] = cleaned[kind].map(
      (button, index) => reshapeButton(button, state.buttons[kind][index].uid)
    );
    renderButtons(kind);
  }
  state.overrides = Object.entries(overrides.value).map(([repo, branch]) => ({ repo, branch }));
  renderOverrides();

  // What was just written is now what is stored, so the notice reflects that — and because the
  // version rode along, the other machines on this account drop their notice as the change syncs.
  state.loadedVersion = version;
  state.reviewed = false;
  setPlan(planMigration(editStateSnapshot(), version));

  clearDirty();
  showStatus('success', t('ext.status.saved'));
}

// Saving happens through the Save button alone. This only resets the view; storage is untouched.
function resetSettings() {
  if (!requireLoaded()) return;
  editAndReview(() => {
    for (const { kind, defaults } of SECTIONS) {
      state.buttons[kind] = defaults.map(adoptButton);
      renderButtons(kind);
    }
    state.overrides = [];
    document.getElementById('default-main').value = 'main';

    renderOverrides();
    // Reset replaces every command with the current preset, so the settings are the current
    // generation by construction — taking that as a decision keeps the notice from lingering over
    // settings that have nothing stale left in them.
    markReviewed();
    showStatus('info', t('ext.status.reset', t('ext.button.save')));
  });
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
  renderMigration();
}

// The user has decided about this generation — by applying some or none of it, by declining, or by
// resetting. That decision is what lets the next save move the version.
function markReviewed() {
  state.reviewed = true;
  state.plan = null;
  state.selection = new Set();
  renderMigration();
}

function migrationItemRow(item, { checkbox }) {
  const row = document.createElement('div');
  row.className = 'mig-item';
  row.dataset.id = item.id;
  const where = `${section(item.kind).storageKey}[${item.index}]`;
  row.innerHTML = `
    <div class="mig-head">
      ${checkbox ? `<input type="checkbox" class="mig-check" checked>` : ''}
      <span class="mig-label"></span>
      <span class="mig-where"></span>
      ${checkbox ? `<span class="mig-source"></span>` : ''}
      ${checkbox && item.effect === 'behavior-change' ? `<span class="mig-effect">${t('ext.migration.effect.behaviorChange')}</span>` : ''}
    </div>
  `;
  row.querySelector('.mig-label').textContent = item.label || t('ext.migration.noTooltip');
  row.querySelector('.mig-where').textContent = where;
  if (checkbox) {
    // 'verbatim' = this was one of our old presets; 'prefix' = you had edited it, and only the
    // leading jump is being replaced. Saying which is how the user knows we noticed their edit.
    //
    // **A visible machine identifier**, and filed as one rather than left in the gap between "shown"
    // and "translated". It is drawn on screen, next to the `- old` / `+ new` diff, and it is *not*
    // translated: it is a discriminator of the same kind as the command text beside it, and
    // rendering it in five languages would mean inventing UX copy the product has no basis for. The
    // residual is stated rather than implied — a Korean screen shows an English discriminator — and
    // what it is not is invisible.
    row.querySelector('.mig-source').textContent = item.source;
  }

  const detail = document.createElement('div');
  if (checkbox) {
    detail.className = 'mig-diff';
    const from = document.createElement('div');
    from.className = 'mig-from';
    from.textContent = `- ${item.from}`;
    const to = document.createElement('div');
    to.className = 'mig-to';
    to.textContent = `+ ${item.to}`;
    detail.append(from, to);
  } else {
    detail.className = 'mig-note';
    detail.textContent = item.note;
  }
  row.appendChild(detail);

  // A behavior change has to say what changes, next to the item it changes — a paragraph at the top
  // of the panel is not what someone reads while deciding about one particular button.
  if (checkbox && item.effect === 'behavior-change' && item.describe) {
    const why = document.createElement('div');
    why.className = 'mig-why';
    why.textContent = item.describe;
    row.appendChild(why);
  }
  return row;
}

function renderMigration() {
  const badge = document.getElementById('migration-badge');
  const panel = document.getElementById('migration-section');
  const plan = state.plan;
  const pending = !!plan && state.loadedVersion < plan.targetVersion;

  badge.hidden = !pending;
  if (!pending) {
    panel.hidden = true;
    return;
  }

  const summary = migrationSummary(plan, state.selection);
  // Every step being applied gets its say, not only the newest one — a settings object can be
  // several generations behind, and the user is consenting to all of them at once.
  let intro = migrationDescription(plan.fromVersion);
  if (summary.reviewOnly) {
    intro = summary.informationalCount
      ? t('ext.migration.intro.nothingSafe')
      : t('ext.migration.intro.nothingToDo', t('ext.migration.gotIt'));
  }
  document.getElementById('migration-describe').textContent = intro;

  const actionable = document.getElementById('migration-actionable');
  const informational = document.getElementById('migration-informational');
  actionable.innerHTML = '';
  informational.innerHTML = '';
  for (const item of plan.actionable) {
    const row = migrationItemRow(item, { checkbox: true });
    row.querySelector('.mig-check').checked = state.selection.has(item.id);
    actionable.appendChild(row);
  }
  for (const item of plan.informational) {
    informational.appendChild(migrationItemRow(item, { checkbox: false }));
  }

  const apply = document.getElementById('migration-apply');
  apply.hidden = summary.reviewOnly;
  apply.disabled = summary.nothingToApply;
  const keep = document.getElementById('migration-keep');
  keep.textContent = summary.reviewOnly ? t('ext.migration.gotIt') : t('ext.migration.keep');
  document.getElementById('migration-hint').textContent = summary.reviewOnly
    ? t('ext.migration.hint.reviewOnly', t('ext.button.save'))
    : t('ext.migration.hint.selected', summary.selectedCount, summary.actionableCount, t('ext.button.save'));
}

// Fills the edit state with the selected rewrites. Storage is untouched until Save, exactly like
// import — the edit state is the only thing that changes here.
function applyMigration() {
  if (!requireLoaded()) return;
  editAndReview(() => {
    // `applied` is what was actually rewritten, not what was checked: a candidate whose button was
    // deleted, moved, or typed over while the preview was open is skipped, and counting checkboxes
    // reported those skips as successes.
    const { settings: migrated, applied } = applyMigrationPlan(
      editStateSnapshot(), state.plan, state.selection
    );
    const declined = state.selection.size - applied;

    for (const { kind, storageKey } of SECTIONS) {
      state.buttons[kind] = migrated[storageKey].map(button => reshapeButton(button, button.uid));
      renderButtons(kind);
    }
    markReviewed();
    // Two complete messages, not one message with a clause bolted on. The English needed
    // `command`/`commands` and `was`/`were` to agree with two different counts, and a translation
    // cannot be assembled out of the pieces that made those agree — so the count moved
    // behind a noun and a colon, where no language here inflects anything, and the two states each
    // became a message of their own.
    showStatus('info', declined > 0
      ? t('ext.migration.appliedWithDeclined', applied, declined, t('ext.button.save'))
      : t('ext.migration.applied', applied, t('ext.button.save')));
  });
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
    throw new Error(t('ext.import.notJSON'));
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(t('ext.import.notObject'));
  }

  // A file from a newer extension is refused whole, before anything is read out of it: we do not
  // know what its keys mean, and filling the form from a half-understood file invites a Save that
  // downgrades the account. This throws rather than joining `skipped` — it is not a key we ignored,
  // it is an import that must not happen.
  const version = importedSchemaVersion(data);

  // Shape checking — and the limits — are shared with the load path (adoptStoredSettings): a file
  // and a stored object are the same kind of stranger, and a shape one path survives must not be one
  // the other dies on. The limits used to be applied only here, as a silent `slice`, so the same
  // four-button array was three buttons through import and four through storage; and the entry this
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
    throw new Error(t('ext.import.nothingToImport', BACKUP_KEYS.join(', ')));
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
    showStatus('error', t('ext.status.exportFailed', error.message));
    return;
  }
  // Export the saved values, not the unsaved edits on screen
  const saved = Object.fromEntries(BACKUP_KEYS.filter(k => data[k] !== undefined).map(k => [k, data[k]]));
  if (Object.keys(saved).length === 0) {
    showStatus('error', t('ext.export.nothingSaved'));
    return;
  }

  const now = new Date();
  const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
  const url = URL.createObjectURL(new Blob([JSON.stringify(saved, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = `terminal-checkout-settings-${stamp}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000); // revoking immediately can cancel the download

  if (state.dirty) showStatus('info', t('ext.export.excludedUnsaved'));
}

// Saving happens through the Save button alone — this too only fills in the view and leaves storage
// untouched. The guard runs before any of it, like every other edit.
function applyImportedSettings(settings, mergedVersion) {
  return edit(() => {
    for (const { kind, storageKey } of SECTIONS) {
      if (settings[storageKey]) state.buttons[kind] = settings[storageKey].map(adoptButton);
    }
    if (settings.defaultMain !== undefined) {
      document.getElementById('default-main').value = settings.defaultMain.trim() || 'main';
    }
    if (settings.repoMainBranch) {
      state.overrides = Object.entries(settings.repoMainBranch).map(([repo, branch]) => ({ repo, branch }));
    }

    SECTIONS.forEach(({ kind }) => renderButtons(kind));
    renderOverrides();

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
  if (!requireLoaded()) return;
  // One file at a time. Two in flight both captured the same revision, and whichever finished
  // reading first applied and disqualified the other — so the file chosen *second* lost, silently.
  if (!shouldStartPageTask({ loaded: state.loaded, ...pageTasks() })) {
    showStatus('error', pageBusyMessage(pageTasks()));
    return;
  }
  if (file.size > MAX_IMPORT_BYTES) {
    showStatus('error', t('ext.import.fileTooLarge'));
    return;
  }

  // The world this import starts in. Reading the file is asynchronous and the form stays live
  // throughout, so a file applied afterwards can land on top of what was typed meanwhile — the same
  // defect as a stale load answer overwriting an edit, and it gets the same predicate.
  const revisionAtStart = state.revision;
  const generationAtStart = state.loadGeneration;

  state.importing = true;
  try {
    let imported;
    let mergedVersion;
    try {
      imported = parseImportedSettings(await file.text());
      // Refused here rather than merged: with stored settings from the future, taking the minimum
      // hands an old generation to content a newer extension wrote, and the next Save records it.
      mergedVersion = mergedSourceVersion(state.loadedVersion, imported.version);
    } catch (error) {
      showStatus('error', t('ext.status.importFailed', error.message));
      return;
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
      return;
    }

    // Refused only if the page stopped being loaded under us; nothing was filled in, so nothing is
    // reported as imported either.
    if (!applyImportedSettings(outcome.apply, mergedVersion)) return;

    const notes = [...imported.unreadable];
    if (imported.skipped.length) notes.push(t('ext.import.skippedNote', imported.skipped.join(', ')));
    // The notes are a list of complete diagnostic sentences, not a clause of this one, which is why
    // they may ride in a placeholder where the declined count above may not: what varies here is how
    // many sentences follow, never the grammar of this one.
    showStatus('info', notes.length
      ? t('ext.status.importedWithNotes', t('ext.button.save'), notes.join('; '))
      : t('ext.status.imported', t('ext.button.save')));
  } finally {
    state.importing = false;
    // Same settlement as the save: a change held while this ran gets asked again now
    adoptDeferredChange();
  }
}

let statusTimer = null;

function showStatus(type, message) {
  const el = document.getElementById('status');
  el.className = `status ${type}`;
  el.textContent = message;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { el.className = 'status'; }, 4000);
}

function showError({ message, focus }) {
  showStatus('error', message);
  focus?.focus();
}

// --- Events ---
// The sections share one card structure, so they share the handlers too. The card's data-kind says
// which section it belongs to.

function onCardInput(e) {
  const { card, kind, index } = cardOf(e.target);

  if (e.target.classList.contains('ci-input')) {
    const row = Number(e.target.closest('.claude-row').dataset.ci);
    edit(() => {
      state.buttons[kind][index].claudeInputs[row] = e.target.value;
      updateClaudeWarn(card, state.buttons[kind][index]);
    });
    return;
  }

  const field = e.target.dataset.field;
  if (!field) return;
  edit(() => {
    state.buttons[kind][index][field] = e.target.value;
    if (field === 'face') updateFacePreview(card, e.target.value);
    if (field === 'command') {
      autosize(e.target);
      updateClaudeWarn(card, state.buttons[kind][index]);
    }
  });
}

function onCardClick(e) {
  if (e.target.classList.contains('remove-btn')) {
    const { kind, index } = cardOf(e.target);
    edit(() => {
      state.buttons[kind].splice(index, 1);
      renderButtons(kind);
    });
    return;
  }

  if (e.target.classList.contains('duplicate-btn')) {
    const { kind, index } = cardOf(e.target);
    if (state.buttons[kind].length >= MAX_BUTTONS) return;
    edit(() => {
      state.buttons[kind] = duplicateButton(state.buttons[kind], index);
      // duplicateButton spreads the original, uid included — two buttons answering to the same name
      // would make a candidate ambiguous, so the copy gets its own
      state.buttons[kind][index + 1].uid = nextButtonUid();
      renderButtons(kind);
      // The tooltip is disambiguated by its number, but the face is identical to the original — put the cursor in the copy's face field
      cardElement(kind, index + 1, '.face-input').focus();
    });
    return;
  }

  if (e.target.classList.contains('palette-btn')) {
    const { card, kind, index } = cardOf(e.target);
    edit(() => {
      const input = card.querySelector('.face-input');
      state.buttons[kind][index].face += e.target.textContent;
      input.value = state.buttons[kind][index].face;
      updateFacePreview(card, input.value);
    });
    return;
  }

  if (e.target.classList.contains('add-input-btn')) {
    const { kind, index } = cardOf(e.target);
    if (state.buttons[kind][index].claudeInputs.length >= MAX_CLAUDE_INPUTS) return;
    edit(() => {
      const inputs = state.buttons[kind][index].claudeInputs;
      inputs.push('');
      renderButtons(kind);
      cardElement(kind, index, `.claude-row[data-ci="${inputs.length - 1}"] .ci-input`).focus();
    });
    return;
  }

  if (e.target.classList.contains('ci-remove')) {
    const { kind, index } = cardOf(e.target);
    const row = Number(e.target.closest('.claude-row').dataset.ci);
    edit(() => {
      state.buttons[kind][index].claudeInputs.splice(row, 1);
      renderButtons(kind);
    });
  }
}

// --- Reordering (drag, ↑↓) ---
// The button order is the order they appear in on a GitHub page, and it decides which button (the
// first) the extension icon runs.
// A row's order decides what claude is told: inputs are typed in list order, and a run of consecutive
// `!` bodies is merged onto one shell line joined with `;`, so moving a row can change which commands share shell state and whether the run merges at all.

// The item being dragged. The sections share handlers, so this also carries which section the drag
// started in (so a drop over another section is not accepted).
let drag = null;

function clearDropMarks(container, itemSelector) {
  container.querySelectorAll(itemSelector)
    .forEach(el => el.classList.remove('drop-before', 'drop-after'));
}

// Which half of the hovered item the pointer is over decides "before which item" it goes (past the end, that's the count).
function dropIndex(container, itemSelector, y) {
  const items = [...container.querySelectorAll(itemSelector)];
  const hit = items.findIndex(item => {
    const rect = item.getBoundingClientRect();
    return y < rect.top + rect.height / 2;
  });
  return hit === -1 ? items.length : hit;
}

function markDropTarget(container, itemSelector, index) {
  clearDropMarks(container, itemSelector);
  const items = container.querySelectorAll(itemSelector);
  if (index < items.length) items[index].classList.add('drop-before');
  else if (items.length) items[items.length - 1].classList.add('drop-after');
}

function claudeDropZone(kind, target) {
  if (drag?.type !== 'claude') return null;
  const rows = target.closest?.('.claude-rows');
  const card = rows?.closest('.btn-card');
  if (drag.kind !== kind
    || card?.dataset.kind !== kind
    || Number(card.dataset.index) !== drag.cardIndex) return null;
  return rows;
}

function endDrag(container) {
  container.querySelectorAll('.btn-card').forEach(card => {
    card.draggable = false;
    card.classList.remove('dragging');
  });
  container.querySelectorAll('.claude-row').forEach(row => {
    row.draggable = false;
    row.classList.remove('dragging');
  });
  clearDropMarks(container, '.btn-card');
  clearDropMarks(container, '.claude-row');
  drag = null;
}

// Returns the index after the move (so keyboard reordering can keep focus on the handle)
function reorderButtons(kind, from, insertBefore) {
  if (insertBefore === from || insertBefore === from + 1) return from; // dropped where it already was
  const moved = edit(() => {
    state.buttons[kind] = moveItem(state.buttons[kind], from, insertBefore);
    renderButtons(kind);
  });
  if (!moved) return from; // refused: nothing moved, so the handle stays where it was
  return insertBefore > from ? insertBefore - 1 : insertBefore;
}

// The row path has a nested state path and a different focus target, so it stays a sibling rather
// than becoming a flag-heavy version of reorderButtons.
function reorderClaudeInputs(kind, cardIndex, from, insertBefore) {
  if (insertBefore === from || insertBefore === from + 1) return from; // dropped where it already was
  const moved = edit(() => {
    const button = state.buttons[kind][cardIndex];
    button.claudeInputs = moveItem(button.claudeInputs, from, insertBefore);
    renderButtons(kind);
  });
  if (!moved) return from; // refused: nothing moved, so the handle stays where it was
  return insertBefore > from ? insertBefore - 1 : insertBefore;
}

for (const { kind, container, addButton } of SECTIONS) {
  const element = document.getElementById(container);
  element.addEventListener('input', onCardInput);
  element.addEventListener('click', onCardClick);
  element.addEventListener('change', (e) => {
    if (e.target.classList.contains('preset-select')) applyPreset(e.target);
  });

  // A drag may only start from the handle — the card is made draggable only while the handle is
  // held down. Leaving draggable on the card permanently would turn a press-and-pull anywhere in
  // the card into a drag, which collides with selecting text by dragging inside an input (the
  // collision itself hasn't been confirmed — Chrome may well give the input priority. Either way,
  // the handle approach prevents dragging a card by accident).
  element.addEventListener('mousedown', (e) => {
    if (e.target.classList.contains('ci-drag-handle')) {
      const row = e.target.closest('.claude-row');
      if (!row) return;
      row.draggable = true;
      // Releasing without dragging never fires dragend, so undo it here
      document.addEventListener('mouseup', () => { row.draggable = false; }, { once: true });
      return;
    }
    if (!e.target.classList.contains('drag-handle')) return;
    const card = e.target.closest('.btn-card');
    card.draggable = true;
    // Releasing without dragging never fires dragend, so undo it here
    document.addEventListener('mouseup', () => { card.draggable = false; }, { once: true });
  });

  element.addEventListener('dragstart', (e) => {
    const row = e.target.closest?.('.claude-row');
    if (row?.draggable) {
      const card = row.closest('.btn-card');
      if (!card) return;
      drag = {
        type: 'claude',
        kind,
        cardIndex: Number(card.dataset.index),
        from: Number(row.dataset.ci),
      };
      row.classList.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
      return;
    }
    const card = e.target.closest?.('.btn-card');
    if (!card?.draggable) return; // leave the native drag for selecting text inside an input alone
    // Remember the card to move here — nothing is put into dataTransfer. It is data we never read,
    // and carrying it as text/plain would let it be pasted outside (another input, another app),
    // while Chrome carries the drag through fine with an empty data store (measured — dragover and
    // dropEffect behave normally)
    drag = { type: 'button', kind, from: Number(card.dataset.index) };
    card.classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
  });

  element.addEventListener('dragover', (e) => {
    if (drag?.type === 'claude') {
      const rows = claudeDropZone(kind, e.target);
      const origin = document.getElementById(section(drag.kind).container);
      if (!rows) {
        clearDropMarks(origin, '.claude-row');
        return;
      }
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      markDropTarget(rows, '.claude-row', dropIndex(rows, '.claude-row', e.clientY));
      return;
    }
    if (drag?.type !== 'button' || drag.kind !== kind) return; // don't accept a drag that came from another section
    e.preventDefault(); // the default is "can't drop", so preventing it is what opens the drop
    e.dataTransfer.dropEffect = 'move';
    markDropTarget(element, '.btn-card', dropIndex(element, '.btn-card', e.clientY));
  });

  element.addEventListener('dragleave', (e) => {
    if (!element.contains(e.relatedTarget)) {
      clearDropMarks(element, '.btn-card');
      clearDropMarks(element, '.claude-row');
    }
  });

  element.addEventListener('drop', (e) => {
    if (drag?.type === 'claude') {
      const rows = claudeDropZone(kind, e.target);
      const origin = document.getElementById(section(drag.kind).container);
      if (!rows) {
        clearDropMarks(origin, '.claude-row');
        return;
      }
      e.preventDefault();
      const { cardIndex, from } = drag;
      const to = dropIndex(rows, '.claude-row', e.clientY);
      endDrag(element);
      reorderClaudeInputs(kind, cardIndex, from, to);
      return;
    }
    if (drag?.type !== 'button' || drag.kind !== kind) return;
    e.preventDefault();
    const { from } = drag;
    const to = dropIndex(element, '.btn-card', e.clientY);
    // Finish the cleanup here — the redraw that follows immediately removes the original card from
    // the document, so don't rely on the dragend that would reach that node (if dragend does
    // arrive, it just runs the same cleanup once more)
    endDrag(element);
    reorderButtons(kind, from, to);
  });

  element.addEventListener('dragend', () => endDrag(element)); // cancelled, or dropped outside

  element.addEventListener('keydown', (e) => {
    if (!e.target.classList.contains('drag-handle') && !e.target.classList.contains('ci-drag-handle')) return;
    const step = e.key === 'ArrowUp' ? -1 : e.key === 'ArrowDown' ? 1 : 0;
    if (!step) return;
    e.preventDefault(); // block the arrow keys' default behavior (scrolling)

    if (e.target.classList.contains('ci-drag-handle')) {
      const { index } = cardOf(e.target);
      const row = Number(e.target.closest('.claude-row').dataset.ci);
      const inputs = state.buttons[kind][index].claudeInputs;
      const to = row + step;
      if (to < 0 || to >= inputs.length) return;
      const moved = reorderClaudeInputs(kind, index, row, step < 0 ? to : to + 1);
      cardElement(kind, index, `.claude-row[data-ci="${moved}"] .ci-drag-handle`).focus();
      return;
    }

    const { index } = cardOf(e.target);
    const to = index + step;
    if (to < 0 || to >= state.buttons[kind].length) return;
    // reorderButtons takes "before which card" — moving down, that is the slot after the destination card
    const moved = reorderButtons(kind, index, step < 0 ? to : to + 1);
    cardElement(kind, moved, '.drag-handle').focus();
  });

  document.getElementById(addButton).addEventListener('click', () => {
    if (state.buttons[kind].length >= MAX_BUTTONS) return;
    edit(() => {
      state.buttons[kind] = appendButton(state.buttons[kind], section(kind));
      renderButtons(kind);
      cardElement(kind, state.buttons[kind].length - 1, '.command-input').focus();
    });
  });
}

const overridesBody = document.getElementById('overrides-body');

overridesBody.addEventListener('input', (e) => {
  const tr = e.target.closest('tr[data-index]');
  if (!tr) return;
  const isRepo = e.target.classList.contains('override-repo');
  const isBranch = e.target.classList.contains('override-branch');
  if (!isRepo && !isBranch) return;
  edit(() => {
    const row = state.overrides[Number(tr.dataset.index)];
    // Don't trim while typing (whitespace is cleaned up all at once on save)
    if (isRepo) row.repo = e.target.value;
    else row.branch = e.target.value;
  });
});

overridesBody.addEventListener('click', (e) => {
  if (!e.target.classList.contains('remove-row')) return;
  const index = Number(e.target.closest('tr').dataset.index);
  edit(() => {
    state.overrides.splice(index, 1);
    renderOverrides();
  });
});

document.getElementById('add-override').addEventListener('click', () => {
  edit(() => {
    state.overrides.push({ repo: '', branch: '' });
    renderOverrides();
    overrideInput(state.overrides.length - 1, '.override-repo').focus();
  });
});

// The field itself is what a save reads, so there is nothing in the edit state to change here — the
// guard is still the first thing that runs, and before the first load it refuses.
document.getElementById('default-main').addEventListener('input', () => touch({ dirty: true }));

document.getElementById('save-btn').addEventListener('click', saveSettings);
document.getElementById('reset-btn').addEventListener('click', resetSettings);

// --- Update notice ---

document.getElementById('migration-badge').addEventListener('click', () => {
  // Opening the review is the start of deciding about it
  review(() => {
    const panel = document.getElementById('migration-section');
    panel.hidden = !panel.hidden;
    if (!panel.hidden) panel.scrollIntoView({ block: 'nearest' });
  });
});

document.getElementById('migration-actionable').addEventListener('change', (e) => {
  if (!e.target.classList.contains('mig-check')) return;
  const { id } = e.target.closest('.mig-item').dataset;
  const { checked } = e.target;
  // Choosing which candidates to accept is not a "dirty" edit — nothing to save yet — but it is the
  // user speaking about this plan, so a snapshot that arrives from sync afterwards must not silently
  // reset their choices back to the defaults.
  review(() => {
    if (checked) state.selection.add(id);
    else state.selection.delete(id);
    renderMigration();
    // Re-opening after a redraw would be surprising: the panel was open, keep it open
    document.getElementById('migration-section').hidden = false;
  });
});

document.getElementById('migration-apply').addEventListener('click', applyMigration);

// Declining is a decision too, and it is the only thing that stops the notice coming back forever
// for someone who means to keep their commands. It changes no command — only the version, and only
// once the user presses Save.
document.getElementById('migration-keep').addEventListener('click', () => {
  if (!requireLoaded()) return;
  editAndReview(() => {
    markReviewed();
    showStatus('info', t('ext.migration.markedReviewed', t('ext.button.save')));
  });
});

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

const importInput = document.getElementById('import-file');

document.getElementById('export-btn').addEventListener('click', exportSettings);
document.getElementById('import-btn').addEventListener('click', () => importInput.click());

importInput.addEventListener('change', () => {
  const file = importInput.files[0];
  importInput.value = ''; // without clearing it, picking the same file again fires no change event
  if (file) importSettings(file);
});

// The manifest uses options_page (a full tab), so the leave-site warning dialog actually appears.
// Switching to options_ui (embedded) makes the browser suppress it.
window.addEventListener('beforeunload', (e) => {
  if (!wouldLoseWork()) return;
  e.preventDefault();
  e.returnValue = '';
});

// A load that failed is the only thing the user can act on while unloaded, and pressing it starts a
// fresh attempt — a new generation, so an earlier answer that turns up late cannot win.
document.getElementById('retry-btn').addEventListener('click', () => {
  hideLoadFailure();
  showStatus('info', LOADING_MESSAGE());
  loadSettings();
});

// Nothing on this page may act on settings until there are settings. The gate goes up before the
// first load is even asked for, so the window where the controls are live but the state is empty
// does not exist.
updateLoadedGate();
renderStaleBanner();
loadSettings();
