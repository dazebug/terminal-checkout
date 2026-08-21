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

function normalizeButton(btn) {
  return {
    face: btn.face ?? btn.emoji ?? '', // emoji: compatibility with values saved before face existed
    label: btn.label || '',
    command: btn.command || '',
    claudeInputs: Array.isArray(btn.claudeInputs) ? btn.claudeInputs.map(String) : [],
  };
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
                    spellcheck="false" placeholder="z {repo} && claude"></textarea>
        </div>
      </div>
      <div class="claude-queue">
        <div class="claude-queue-head"><span class="ret">⏎</span> claude inputs
          <span class="help-inline">— delivered in order; <code>!</code> lines run in claude's shell mode</span>
        </div>
        <div class="claude-hint" hidden><code>!</code> lines are typed into claude's shell mode so they really run as commands — consecutive ones go in as a single line joined with <code>;</code>, each behind a banner. On Warp that typing needs the Accessibility permission. A single plain-text input, with nothing else in the list, skips typing entirely and becomes claude's opening message — that additionally needs the command to end in a bare <code>claude</code>.</div>
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

function markDirty() {
  state.dirty = true;
  state.revision++;
  document.getElementById('dirty-indicator').hidden = false;
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

  state.buttons[kind][index] = normalizeButton({
    face: preset.face, label: preset.name, command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  });
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
  const keys = SECTIONS.map(s => s.storageKey).concat(['defaultMain', 'repoMainBranch']);
  const data = await chrome.storage.sync.get(keys);

  for (const { kind, storageKey, defaults } of SECTIONS) {
    const saved = data[storageKey];
    state.buttons[kind] = (saved?.length ? saved : defaults).map(normalizeButton);
  }
  state.overrides = Object.entries(data.repoMainBranch || {}).map(([repo, branch]) => ({ repo, branch }));
  document.getElementById('default-main').value = data.defaultMain || 'main';

  SECTIONS.forEach(({ kind }) => renderButtons(kind));
  renderOverrides();
}

async function saveSettings() {
  const invalidButton = validateButtons();
  if (invalidButton) return showError(invalidButton);

  const overrides = serializeOverrides();
  if (overrides.error) return showError(overrides.error);

  const cleaned = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind,
    state.buttons[kind].map(b => ({
      face: b.face.trim(),
      label: b.label.trim(),
      command: b.command,
      claudeInputs: b.claudeInputs.map(s => s.trim()).filter(Boolean), // empty rows are dropped silently
    })),
  ]));
  const defaultMain = document.getElementById('default-main').value.trim() || 'main';
  const savedRevision = state.revision;

  try {
    await chrome.storage.sync.set({
      ...Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [storageKey, cleaned[kind]])),
      defaultMain,
      repoMainBranch: overrides.value,
    });
  } catch (error) {
    showStatus('error', `Could not save: ${error.message}`);
    return;
  }

  // The form stays live while the save is in flight. If the user edited more in the meantime,
  // resetting the view to the snapshot we just saved would wipe that input, so leave the view
  // alone and keep the dirty flag set.
  if (state.revision !== savedRevision) {
    showStatus('success', 'Settings saved. Changes made since then are not saved yet.');
    return;
  }

  // Bring the view in line with what was saved (empty rows cleared, whitespace trimmed)
  document.getElementById('default-main').value = defaultMain;
  for (const { kind } of SECTIONS) {
    state.buttons[kind] = cleaned[kind].map(normalizeButton);
    renderButtons(kind);
  }
  state.overrides = Object.entries(overrides.value).map(([repo, branch]) => ({ repo, branch }));
  renderOverrides();

  clearDirty();
  showStatus('success', 'Settings saved.');
}

// Saving happens through the Save button alone. This only resets the view; storage is untouched.
function resetSettings() {
  for (const { kind, defaults } of SECTIONS) {
    state.buttons[kind] = defaults.map(normalizeButton);
    renderButtons(kind);
  }
  state.overrides = [];
  document.getElementById('default-main').value = 'main';

  renderOverrides();
  markDirty();
  showStatus('info', 'Reset to defaults. Press Save to apply.');
}

// --- Export / import ---
// The extension ID is pinned by the manifest key, so storage.sync already carries settings between
// Chrome profiles on the same Google account — this path is for moving them without an account, or
// for a file backup against a reinstall.

const BACKUP_KEYS = [...SECTIONS.map(s => s.storageKey), 'defaultMain', 'repoMainBranch'];
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

  // Values from a file can't be trusted to have the right type. Non-string fields are dropped to
  // an empty value so the required-field check catches them on save (left as they are, saving
  // would blow up in .trim()).
  const text = v => (typeof v === 'string' ? v : '');
  const settings = {};
  const skipped = [];

  for (const key of SECTIONS.map(s => s.storageKey)) {
    if (data[key] === undefined) continue;
    // An empty array means "no setting", not "no buttons" — the background logic doesn't fall back
    // to the defaults for an empty array, so the buttons would disappear entirely.
    const buttons = (Array.isArray(data[key]) ? data[key] : [])
      .filter(b => b && typeof b === 'object' && !Array.isArray(b))
      .slice(0, MAX_BUTTONS)
      .map(b => {
        const btn = normalizeButton(b);
        return {
          face: text(btn.face),
          label: text(btn.label),
          command: text(btn.command),
          claudeInputs: btn.claudeInputs.slice(0, MAX_CLAUDE_INPUTS),
        };
      });
    if (buttons.length) settings[key] = buttons;
    else skipped.push(key);
  }

  if (data.defaultMain !== undefined) {
    if (typeof data.defaultMain === 'string') settings.defaultMain = data.defaultMain;
    else skipped.push('defaultMain');
  }

  if (data.repoMainBranch !== undefined) {
    const map = data.repoMainBranch;
    if (map && typeof map === 'object' && !Array.isArray(map)) {
      // An empty object is a valid setting meaning "no overrides", so take it as is
      settings.repoMainBranch = Object.fromEntries(
        Object.entries(map).filter(([, branch]) => typeof branch === 'string')
      );
    } else {
      skipped.push('repoMainBranch');
    }
  }

  if (Object.keys(settings).length === 0) {
    throw new Error(`Nothing to import (one of ${BACKUP_KEYS.join(', ')} is required).`);
  }
  return { settings, skipped };
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
    if (settings[storageKey]) state.buttons[kind] = settings[storageKey].map(normalizeButton);
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

    state.buttons[kind].push(normalizeButton({ face, label: 'New Button', command: '' }));
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

// Initial load
loadSettings();
