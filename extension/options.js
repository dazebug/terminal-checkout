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
  // Set when a change arrives from another device while editing — the banner warns before the save
  // is attempted, but the re-read at save time is what decides
  staleSinceLoad: false,
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

// The preset list is fixed per section, so build it once and clone it for each card
const presetTemplates = Object.fromEntries(SECTIONS.map(({ kind, presets }) => {
  const select = document.createElement('select');
  select.className = 'preset-select';
  select.add(new Option('Apply preset…', ''));
  presets.forEach(p => select.add(new Option(p.name, p.name)));
  return [kind, select];
}));

// Buttons enter the edit state through `adoptButton` (anything from outside: storage, a file, a
// preset — it gets a uid we mint) or `reshapeButton` (a button already here, keeping its name).
// Both live in defaults.js, along with why they are two functions and not one.

// Until the first load answers, this page holds no settings — only the empty shell of the edit
// state. Every entry point that would write, or that would change what a later write contains, asks
// here first. The page is also inert until then (updateLoadedGate), but that is the fence; this is
// the rule, and code paths that do not come from a click still have to pass it.
const LOADING_MESSAGE = 'Still loading your settings — one moment.';

function requireLoaded() {
  if (state.loaded) return true;
  showStatus('info', LOADING_MESSAGE);
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
  showStatus('error', `${LOAD_FAILED_MESSAGE} (${error?.message || error})`);
}

function hideLoadFailure() {
  document.getElementById('load-error').hidden = true;
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
          ${count > 1 ? '<button class="drag-handle" aria-label="Reorder" title="Drag, or use the ↑↓ keys, to reorder">⠿</button>' : ''}
          <span class="prompt">❯</span> ${section(kind).storageKey}[${i}]
        </span>
        <span class="card-actions">
          ${count < MAX_BUTTONS ? '<button class="duplicate-btn" title="Duplicate this button">Duplicate</button>' : ''}
          ${count > 1 ? '<button class="remove-btn">Delete</button>' : ''}
        </span>
      </div>
      <div class="btn-row">
        <div class="field field-face">
          <label for="${kind}-${i}-face">Face</label>
          <input id="${kind}-${i}-face" class="face-input" data-field="face" maxlength="24">
        </div>
        <div class="field field-preview">
          <label>Preview</label>
          <span class="face-preview"></span>
        </div>
        <div class="field field-label">
          <label for="${kind}-${i}-label">Tooltip</label>
          <input id="${kind}-${i}-label" class="label-input" data-field="label" placeholder="Button tooltip">
        </div>
        <div class="field field-preset">
          <label for="${kind}-${i}-preset">Preset</label>
        </div>
      </div>
      <div class="face-palette">
        <span class="palette-label">Add to face:</span>
        ${FACE_EMOJI.map(e => `<button class="palette-btn" title="Add ${e} to the face">${e}</button>`).join('')}
      </div>
      <div class="field field-command">
        <label for="${kind}-${i}-command">command</label>
        <div class="cmd-block">
          <span class="cmd-prompt">$</span>
          <textarea id="${kind}-${i}-command" class="command-input" data-field="command" rows="2"
                    spellcheck="false" placeholder="{cd} && claude"></textarea>
        </div>
      </div>
      <div class="claude-queue">
        <div class="claude-queue-head"><span class="ret">⏎</span> claude inputs
          <span class="help-inline">— when the command starts claude, these are typed into that session in order</span>
        </div>
        <div class="claude-warn" hidden>⚠ The command doesn't start claude, so these inputs won't be delivered</div>
        <div class="claude-rows"></div>
        <button class="add-input-btn">+ Add Input</button>
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
      row.innerHTML = `
        <span class="ci-marker">⏎${j + 1}</span>
        <input class="ci-input" placeholder="!gh issue view {number}, or: summarize this issue">
        <button class="ci-remove" title="Remove">×</button>
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
      <td><button class="remove-row" title="Remove">✕</button></td>
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

function markDirty() {
  touch({ dirty: true });
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
  const name = select.value;
  select.value = ''; // applied or cancelled, it always returns to the placeholder
  if (!name) return;

  const { kind, index } = cardOf(select);
  const preset = section(kind).presets.find(p => p.name === name);
  if (!preset) return;

  const current = state.buttons[kind][index].command.trim();
  const isCustom = current !== '' && !section(kind).presets.some(p => p.command === current);
  if (isCustom && !confirm(`Button ${index} will be overwritten with the "${preset.name}" preset. Continue?`)) {
    return;
  }

  // The card stays the same button — only its contents are replaced — so it keeps its uid
  state.buttons[kind][index] = reshapeButton({
    face: preset.face, label: preset.name, command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  }, state.buttons[kind][index].uid);
  markDirty();
  renderButtons(kind); // the number of claude input rows changes too, so redraw the whole card
}

// --- Validation ---

const REQUIRED_FIELDS = [
  { field: 'face', label: 'a face' },
  { field: 'label', label: 'a tooltip' },
  { field: 'command', label: 'a command' },
];

function validateButtons() {
  for (const { kind } of SECTIONS) {
    const name = section(kind).storageKey;
    for (let i = 0; i < state.buttons[kind].length; i++) {
      for (const { field, label } of REQUIRED_FIELDS) {
        if (state.buttons[kind][i][field].trim()) continue;
        return {
          message: `${name}[${i}]: enter ${label}.`,
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
          message: `Override ${i + 1}: enter both a repository and a main branch.`,
          focus: overrideInput(i, repo ? '.override-branch' : '.override-repo'),
        },
      };
    }
    if (entries.has(repo)) {
      return {
        error: {
          message: `Override ${i + 1}: the repository "${repo}" appears more than once.`,
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
  let data;
  try {
    data = await chrome.storage.sync.get([...SETTINGS_KEYS, VERSION_KEY]);
  } catch (error) {
    if (generation === state.loadGeneration) showLoadFailure(error);
    return;
  }

  if (!shouldApplyLoadedSnapshot({
    revisionAtStart, revisionNow: state.revision, dirty: state.dirty,
    reviewTouched: state.reviewTouched,
    generation, latestGeneration: state.loadGeneration, initial,
  })) return;

  // Storage is as untrusted as an imported file: another device, another version of this extension,
  // or a hand edit wrote it. Anything unreadable is dropped and counted, never guessed at.
  const { settings, skipped } = adoptStoredSettings(data);

  for (const { kind, storageKey, defaults } of SECTIONS) {
    const saved = settings[storageKey];
    state.buttons[kind] = (saved?.length ? saved : defaults).map(adoptButton);
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
  hideLoadFailure();
  updateLoadedGate();
  renderStaleBanner();
  if (skipped) {
    // Said out loud. Quietly falling back to defaults would read as "you have no buttons", which is
    // a lie about the user's own data — and would hide whatever wrote the broken value.
    showStatus('error', `${skipped} stored ${skipped === 1 ? 'entry was' : 'entries were'} unreadable and skipped.`);
  }

  SECTIONS.forEach(({ kind }) => renderButtons(kind));
  renderOverrides();
  // Planned from the edit state that was just built, not from `data` — those are the same thing
  // here, and keeping one path means they cannot fall out of step later.
  setPlan(planMigration(editStateSnapshot(), state.loadedVersion));
}

async function saveSettings() {
  // Nothing may be written before the first load answers: the edit state is empty until then, and
  // writing it would delete every command and mark the migration as reviewed in the same breath.
  if (!requireLoaded()) return;

  const invalidButton = validateButtons();
  if (invalidButton) return showError(invalidButton);

  const overrides = serializeOverrides();
  if (overrides.error) return showError(overrides.error);

  // toStoredButton is what decides the stored shape — including dropping the runtime uid
  const cleaned = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind, state.buttons[kind].map(toStoredButton),
  ]));
  const defaultMain = document.getElementById('default-main').value.trim() || 'main';
  const savedRevision = state.revision;

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

  // This page may have been open a long time, and another device on the account can have saved in
  // the meantime — a migration, say. Writing our payload over that would erase their decision with
  // no trace. There is no compare-and-set in storage.sync, so we read once more, right here, and
  // refuse if anything moved.
  //
  // The window between this read and the write below cannot be closed without a transaction. What
  // lands in it is a last-write-wins overwrite, and if what it overwrites was a migration decision
  // the loss is permanent: the version we write is ours, so the notice does not come back to offer
  // it again. That is the residual, stated as it is — it is not "the notice appears once more".
  const liveSnapshot = await chrome.storage.sync.get([...SETTINGS_KEYS, VERSION_KEY]);
  const outcome = planSave({ loadedSnapshot: state.loadedSnapshot, liveSnapshot, payload });
  if (outcome.refused) {
    state.staleSinceLoad = true;
    renderStaleBanner();
    showStatus('error', outcome.message);
    return;
  }

  try {
    await chrome.storage.sync.set(outcome.write);
  } catch (error) {
    showStatus('error', `Could not save: ${error.message}`);
    return;
  }
  // Facts about storage, true whatever the user did meanwhile: it now holds exactly this payload,
  // so that is what a later save must find there, and our own change event is no longer a conflict
  // with ourselves.
  state.loadedSnapshot = payload;
  state.staleSinceLoad = false;
  renderStaleBanner();
  const version = payload[VERSION_KEY];

  // Everything below is a claim about the *user* — that they have nothing outstanding — and none of
  // it may be made if they acted while the save was in flight. Clearing `reviewTouched` above this
  // line is precisely the bug: a box toggled during the save was forgotten, the next remote change
  // was adopted, the selection snapped back to the defaults, and Apply rewrote a candidate they had
  // declined. One predicate now guards the whole settlement.
  if (!nothingHappenedSince(savedRevision, state.revision)) {
    showStatus('success', 'Settings saved. Changes made since then are not saved yet.');
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
  showStatus('success', 'Settings saved.');
}

// Saving happens through the Save button alone. This only resets the view; storage is untouched.
function resetSettings() {
  if (!requireLoaded()) return;
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
  markDirty();
  showStatus('info', 'Reset to defaults. Press Save to apply.');
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
      ${checkbox && item.effect === 'behavior-change' ? `<span class="mig-effect">behavior change</span>` : ''}
    </div>
  `;
  row.querySelector('.mig-label').textContent = item.label || '(no tooltip)';
  row.querySelector('.mig-where').textContent = where;
  if (checkbox) {
    // 'verbatim' = this was one of our old presets; 'prefix' = you had edited it, and only the
    // leading jump is being replaced. Saying which is how the user knows we noticed their edit.
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
      ? 'Nothing here can be rewritten safely, but these commands still use the old form:'
      : 'Nothing to change — your commands are already current. Press Got it to mark them as reviewed.';
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
  keep.textContent = summary.reviewOnly ? 'Got it' : 'Keep mine';
  document.getElementById('migration-hint').textContent = summary.reviewOnly
    ? 'Dismissing this marks your settings as reviewed — press Save afterwards.'
    : `${summary.selectedCount} of ${summary.actionableCount} selected. Applying fills the form; press Save to store it.`;
}

// Fills the edit state with the selected rewrites. Storage is untouched until Save, exactly like
// import — the edit state is the only thing that changes here.
function applyMigration() {
  if (!requireLoaded()) return;
  touch({ review: true });
  const migrated = applyMigrationPlan(editStateSnapshot(), state.plan, state.selection);
  const count = state.selection.size;

  for (const { kind, storageKey } of SECTIONS) {
    state.buttons[kind] = migrated[storageKey].map(button => reshapeButton(button, button.uid));
    renderButtons(kind);
  }
  markReviewed();
  markDirty();
  showStatus('info', `${count} command${count === 1 ? '' : 's'} updated in the form. Press Save to apply.`);
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
    throw new Error('This file could not be read as JSON.');
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('The top level of the settings file is not an object.');
  }

  // A file from a newer extension is refused whole, before anything is read out of it: we do not
  // know what its keys mean, and filling the form from a half-understood file invites a Save that
  // downgrades the account. This throws rather than joining `skipped` — it is not a key we ignored,
  // it is an import that must not happen.
  const version = importedSchemaVersion(data);

  // Shape checking is shared with the load path (adoptStoredSettings): a file and a stored object
  // are the same kind of stranger, and a shape one path survives must not be one the other dies on.
  // What is specific to a file is layered on top — the per-button caps, and "an empty array is not
  // a setting".
  const adopted = adoptStoredSettings(data);
  const settings = {};
  const skipped = [];

  for (const key of SECTIONS.map(s => s.storageKey)) {
    if (data[key] === undefined) continue;
    // An empty array means "no setting", not "no buttons" — the background logic doesn't fall back
    // to the defaults for an empty array, so the buttons would disappear entirely.
    const buttons = (adopted.settings[key] || []).slice(0, MAX_BUTTONS).map(button => ({
      ...button,
      claudeInputs: button.claudeInputs.slice(0, MAX_CLAUDE_INPUTS),
    }));
    if (buttons.length) settings[key] = buttons;
    else skipped.push(key);
  }

  for (const key of ['defaultMain', 'repoMainBranch']) {
    if (data[key] === undefined) continue;
    if (adopted.settings[key] !== undefined) settings[key] = adopted.settings[key];
    else skipped.push(key);
  }

  if (Object.keys(settings).length === 0) {
    throw new Error(`Nothing to import (one of ${BACKUP_KEYS.join(', ')} is required).`);
  }
  return { settings, skipped, version };
}

async function exportSettings() {
  const data = await chrome.storage.sync.get(BACKUP_KEYS);
  // Export the saved values, not the unsaved edits on screen
  const saved = Object.fromEntries(BACKUP_KEYS.filter(k => data[k] !== undefined).map(k => [k, data[k]]));
  if (Object.keys(saved).length === 0) {
    showStatus('error', 'No settings have been saved yet. Save first, then export.');
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

  if (state.dirty) showStatus('info', 'Unsaved changes were not included in the export.');
}

// Saving happens through the Save button alone — this too only fills in the view and leaves storage untouched.
function applyImportedSettings(settings) {
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
  markDirty();
}

async function importSettings(file) {
  // An import that landed before the load answered would be merged into an empty edit state and
  // then compared against a snapshot we do not have yet
  if (!requireLoaded()) return;
  if (file.size > MAX_IMPORT_BYTES) {
    showStatus('error', 'The settings file is too large (256KB max).');
    return;
  }

  let imported;
  try {
    imported = parseImportedSettings(await file.text());
  } catch (error) {
    showStatus('error', `Could not import: ${error.message}`);
    return;
  }

  applyImportedSettings(imported.settings);

  // The edit state is now part file, part whatever was already on screen — a file carrying only
  // `defaultMain` leaves every button section untouched. So the generation to answer for is the
  // *older* of the two, and the plan covers the merged whole rather than the file's keys.
  state.loadedVersion = mergedSourceVersion(state.loadedVersion, imported.version);
  state.reviewed = false;
  setPlan(planMigration(editStateSnapshot(), state.loadedVersion));

  const dropped = imported.skipped.length ? ` (skipped: ${imported.skipped.join(', ')})` : '';
  showStatus('info', `Settings imported. Press Save to apply.${dropped}`);
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
    state.buttons[kind][index].claudeInputs[row] = e.target.value;
    updateClaudeWarn(card, state.buttons[kind][index]);
    markDirty();
    return;
  }

  const field = e.target.dataset.field;
  if (!field) return;
  state.buttons[kind][index][field] = e.target.value;
  if (field === 'face') updateFacePreview(card, e.target.value);
  if (field === 'command') {
    autosize(e.target);
    updateClaudeWarn(card, state.buttons[kind][index]);
  }
  markDirty();
}

function onCardClick(e) {
  if (e.target.classList.contains('remove-btn')) {
    const { kind, index } = cardOf(e.target);
    state.buttons[kind].splice(index, 1);
    markDirty();
    renderButtons(kind);
    return;
  }

  if (e.target.classList.contains('duplicate-btn')) {
    const { kind, index } = cardOf(e.target);
    if (state.buttons[kind].length >= MAX_BUTTONS) return;
    state.buttons[kind] = duplicateButton(state.buttons[kind], index);
    // duplicateButton spreads the original, uid included — two buttons answering to the same name
    // would make a candidate ambiguous, so the copy gets its own
    state.buttons[kind][index + 1].uid = nextButtonUid();
    markDirty();
    renderButtons(kind);
    // The tooltip is disambiguated by its number, but the face is identical to the original — put the cursor in the copy's face field
    cardElement(kind, index + 1, '.face-input').focus();
    return;
  }

  if (e.target.classList.contains('palette-btn')) {
    const { card, kind, index } = cardOf(e.target);
    const input = card.querySelector('.face-input');
    state.buttons[kind][index].face += e.target.textContent;
    input.value = state.buttons[kind][index].face;
    updateFacePreview(card, input.value);
    markDirty();
    return;
  }

  if (e.target.classList.contains('add-input-btn')) {
    const { kind, index } = cardOf(e.target);
    const inputs = state.buttons[kind][index].claudeInputs;
    if (inputs.length >= MAX_CLAUDE_INPUTS) return;
    inputs.push('');
    markDirty();
    renderButtons(kind);
    cardElement(kind, index, `.claude-row[data-ci="${inputs.length - 1}"] .ci-input`).focus();
    return;
  }

  if (e.target.classList.contains('ci-remove')) {
    const { kind, index } = cardOf(e.target);
    const row = Number(e.target.closest('.claude-row').dataset.ci);
    state.buttons[kind][index].claudeInputs.splice(row, 1);
    markDirty();
    renderButtons(kind);
  }
}

// --- Reordering (drag, ↑↓) ---
// The button order is the order they appear in on a GitHub page, and it decides which button (the
// first) the extension icon runs.

// The card being dragged. The sections share handlers, so this also carries which section the drag
// started in (so a drop over another section is not accepted).
let drag = null;

function clearDropMarks(container) {
  container.querySelectorAll('.drop-before, .drop-after')
    .forEach(el => el.classList.remove('drop-before', 'drop-after'));
}

// Which half of the hovered card the pointer is over decides "before which card" it goes (past the end, that's the count).
function dropIndex(container, y) {
  const cards = [...container.querySelectorAll('.btn-card')];
  const hit = cards.findIndex(card => {
    const rect = card.getBoundingClientRect();
    return y < rect.top + rect.height / 2;
  });
  return hit === -1 ? cards.length : hit;
}

function markDropTarget(container, index) {
  clearDropMarks(container);
  const cards = container.querySelectorAll('.btn-card');
  if (index < cards.length) cards[index].classList.add('drop-before');
  else cards[cards.length - 1].classList.add('drop-after');
}

function endDrag(container) {
  container.querySelectorAll('.btn-card').forEach(card => {
    card.draggable = false;
    card.classList.remove('dragging');
  });
  clearDropMarks(container);
  drag = null;
}

// Returns the index after the move (so keyboard reordering can keep focus on the handle)
function reorderButtons(kind, from, insertBefore) {
  if (insertBefore === from || insertBefore === from + 1) return from; // dropped where it already was
  state.buttons[kind] = moveButton(state.buttons[kind], from, insertBefore);
  markDirty();
  renderButtons(kind);
  return insertBefore > from ? insertBefore - 1 : insertBefore;
}

for (const { kind, container, addButton, defaults } of SECTIONS) {
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
    if (!e.target.classList.contains('drag-handle')) return;
    const card = e.target.closest('.btn-card');
    card.draggable = true;
    // Releasing without dragging never fires dragend, so undo it here
    document.addEventListener('mouseup', () => { card.draggable = false; }, { once: true });
  });

  element.addEventListener('dragstart', (e) => {
    const card = e.target.closest?.('.btn-card');
    if (!card?.draggable) return; // leave the native drag for selecting text inside an input alone
    // Remember the card to move here — nothing is put into dataTransfer. It is data we never read,
    // and carrying it as text/plain would let it be pasted outside (another input, another app),
    // while Chrome carries the drag through fine with an empty data store (measured — dragover and
    // dropEffect behave normally)
    drag = { kind, from: Number(card.dataset.index) };
    card.classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
  });

  element.addEventListener('dragover', (e) => {
    if (drag?.kind !== kind) return; // don't accept a drag that came from another section
    e.preventDefault(); // the default is "can't drop", so preventing it is what opens the drop
    e.dataTransfer.dropEffect = 'move';
    markDropTarget(element, dropIndex(element, e.clientY));
  });

  element.addEventListener('dragleave', (e) => {
    if (!element.contains(e.relatedTarget)) clearDropMarks(element);
  });

  element.addEventListener('drop', (e) => {
    if (drag?.kind !== kind) return;
    e.preventDefault();
    const { from } = drag;
    const to = dropIndex(element, e.clientY);
    // Finish the cleanup here — the redraw that follows immediately removes the original card from
    // the document, so don't rely on the dragend that would reach that node (if dragend does
    // arrive, it just runs the same cleanup once more)
    endDrag(element);
    reorderButtons(kind, from, to);
  });

  element.addEventListener('dragend', () => endDrag(element)); // cancelled, or dropped outside

  element.addEventListener('keydown', (e) => {
    if (!e.target.classList.contains('drag-handle')) return;
    const step = e.key === 'ArrowUp' ? -1 : e.key === 'ArrowDown' ? 1 : 0;
    if (!step) return;
    e.preventDefault(); // block the arrow keys' default behavior (scrolling)
    const { index } = cardOf(e.target);
    const to = index + step;
    if (to < 0 || to >= state.buttons[kind].length) return;
    // reorderButtons takes "before which card" — moving down, that is the slot after the destination card
    const moved = reorderButtons(kind, index, step < 0 ? to : to + 1);
    cardElement(kind, moved, '.drag-handle').focus();
  });

  document.getElementById(addButton).addEventListener('click', () => {
    if (state.buttons[kind].length >= MAX_BUTTONS) return;

    const used = new Set(state.buttons[kind].map(b => b.face));
    const presets = section(kind).presets;
    const face = presets.map(p => p.face).find(f => !used.has(f)) || defaults[0].face;

    state.buttons[kind].push(adoptButton({ face, label: 'New Button', command: '' }));
    markDirty();
    renderButtons(kind);
    cardElement(kind, state.buttons[kind].length - 1, '.command-input').focus();
  });
}

const overridesBody = document.getElementById('overrides-body');

overridesBody.addEventListener('input', (e) => {
  const tr = e.target.closest('tr[data-index]');
  if (!tr) return;
  const row = state.overrides[Number(tr.dataset.index)];
  // Don't trim while typing (whitespace is cleaned up all at once on save)
  if (e.target.classList.contains('override-repo')) row.repo = e.target.value;
  else if (e.target.classList.contains('override-branch')) row.branch = e.target.value;
  else return;
  markDirty();
});

overridesBody.addEventListener('click', (e) => {
  if (!e.target.classList.contains('remove-row')) return;
  state.overrides.splice(Number(e.target.closest('tr').dataset.index), 1);
  markDirty();
  renderOverrides();
});

document.getElementById('add-override').addEventListener('click', () => {
  state.overrides.push({ repo: '', branch: '' });
  markDirty();
  renderOverrides();
  overrideInput(state.overrides.length - 1, '.override-repo').focus();
});

document.getElementById('default-main').addEventListener('input', markDirty);

document.getElementById('save-btn').addEventListener('click', saveSettings);
document.getElementById('reset-btn').addEventListener('click', resetSettings);

// --- Update notice ---

document.getElementById('migration-badge').addEventListener('click', () => {
  touch({ review: true }); // opening the review is the start of deciding about it
  const panel = document.getElementById('migration-section');
  panel.hidden = !panel.hidden;
  if (!panel.hidden) panel.scrollIntoView({ block: 'nearest' });
});

document.getElementById('migration-actionable').addEventListener('change', (e) => {
  if (!e.target.classList.contains('mig-check')) return;
  const { id } = e.target.closest('.mig-item').dataset;
  if (e.target.checked) state.selection.add(id);
  else state.selection.delete(id);
  // Choosing which candidates to accept is not a "dirty" edit — nothing to save yet — but it is the
  // user speaking about this plan, so a snapshot that arrives from sync afterwards must not silently
  // reset their choices back to the defaults.
  touch({ review: true });
  renderMigration();
  // Re-opening after a redraw would be surprising: the panel was open, keep it open
  document.getElementById('migration-section').hidden = false;
});

document.getElementById('migration-apply').addEventListener('click', applyMigration);

// Declining is a decision too, and it is the only thing that stops the notice coming back forever
// for someone who means to keep their commands. It changes no command — only the version, and only
// once the user presses Save.
document.getElementById('migration-keep').addEventListener('click', () => {
  if (!requireLoaded()) return;
  touch({ review: true });
  markReviewed();
  markDirty();
  showStatus('info', 'Marked as reviewed. Press Save to keep your commands as they are.');
});

// A save on another machine on this account arrives here as a storage change. Adopting it is what
// makes the notice disappear everywhere once anyone has dealt with it — but never at the cost of
// what someone is typing right now.
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName !== 'sync') return;
  if (!state.loaded) return; // nothing to compare against yet; the load in flight will pick it up
  if (!ownedChangedKeys(changes).length) return; // someone else's key; not our business to warn about
  // Our own save arrives here as a change event too. Treating it as another device would warn about
  // a conflict with ourselves and throw away a review in progress.
  if (isOwnEcho(changes, state.loadedSnapshot)) return;

  // Mark first, adopt second. A change we are not going to adopt right now — because there is
  // unsaved work — still means the settings moved, and the save must warn rather than march on. The
  // check at save time is the authority; this only gets the warning on screen sooner.
  state.staleSinceLoad = true;
  renderStaleBanner();
  // A review being decided counts as unsaved work, exactly like text being typed
  if (!shouldAdoptSyncedChange(state.dirty || state.reviewTouched, changes)) return;
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
  if (!state.dirty) return;
  e.preventDefault();
  e.returnValue = '';
});

// A load that failed is the only thing the user can act on while unloaded, and pressing it starts a
// fresh attempt — a new generation, so an earlier answer that turns up late cannot win.
document.getElementById('retry-btn').addEventListener('click', () => {
  hideLoadFailure();
  showStatus('info', LOADING_MESSAGE);
  loadSettings();
});

// Nothing on this page may act on settings until there are settings. The gate goes up before the
// first load is even asked for, so the window where the controls are live but the state is empty
// does not exist.
updateLoadedGate();
renderStaleBanner();
loadSettings();
