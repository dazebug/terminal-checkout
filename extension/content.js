// Repository header button style — the same look as GitHub's green action button
const REPO_BUTTON_STYLE = `
  background-color: #238636;
  color: white;
  border: none;
  border-radius: 6px;
  padding: 3px 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  margin-left: 8px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
`;

// The custom command button in the repository header. Unlike the icon buttons on PR and issue
// pages this is drawn as a filled button — next to the breadcrumb an icon alone doesn't stand out.
// The progress indicator follows the face too: swapping a text face for a single ⏳ would shrink
// the button sharply and make the header jump.
function createRepoButton(buttonConfig, index) {
  const face = buttonFace(buttonConfig);
  // Read now, for this drawing of the button, so the phases and face come from the same catalogue.
  // Chrome fixes that catalogue for this extension context; a page reload creates the next one.
  const phases = isTextFace(face)
    ? { busy: tr('ext.button.phase.busy'), done: tr('ext.button.phase.done'), error: tr('ext.button.phase.error') }
    : { busy: '⏳', done: '✅', error: '❌' };

  const button = document.createElement('button');
  button.textContent = face;
  button.title = buttonConfig.label;
  button.style.cssText = REPO_BUTTON_STYLE;
  button.className = 'terminal-open-btn';
  button.dataset.btnIndex = index;

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = '#2ea043';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = '#238636';
  });

  return splitButton(button, buttonConfig, index, {
    action: 'execute_repo_command', kind: 'repo', face, phases, delays: { done: 2000, error: 2000 }, look: 'filled',
  });
}

// Send a single button's message (`buildButtonMessage`, defaults.js). sendMessage does not reject when
// the background returns {success:false}, so without inspecting the response a rejected command would
// still show up as success on the button.
//
// The index says which button; the fingerprint says what that button was going to run when it was
// drawn; the target says which page it was clicked on. The service worker reads storage again for
// the command and the page again for the branch, and refuses if either disagrees — so what runs is
// what was on screen, for the page it was on screen for.
//
// What the fingerprint deliberately leaves out is the face and the tooltip: they are display text
// and will be translated, so adjacent contexts that rendered through different catalogue
// generations would otherwise refuse a command neither of them changed (defaults.js).
//
// Both are comparison keys, never sources. The command still comes from storage, and the repository,
// number and branch still come from the tab and its DOM; these two only decide whether to refuse.
// Sending them as sources would let a message name its own repository. The one value a click adds is
// a note typed into a claude button's popover, and it can only become that run's last claude input:
// the worker judges it again and puts it after the stored inputs.
async function sendButtonMessage(message) {
  const response = await chrome.runtime.sendMessage(message);
  if (!response?.success) throw new Error(response?.error || 'unknown error');
}

// Send a list batch (`buildListBatchMessage`, defaults.js), whose selection is a comparison snapshot.
// The worker reads the current document again and builds every item from that read; this side never
// turns the snapshot's repo or number into a command source. A normal app-level failure is returned as
// structured data so the result view can show its overall and per-item verdicts without confusing it
// with transport failure.
async function sendListBatchMessage(message) {
  const outcome = interpretListBatchResponse(await chrome.runtime.sendMessage(message));
  if (!outcome.transportSuccess) throw new Error(outcome.error);
  if (outcome.appSuccess === null) throw new Error(outcome.error);
  return outcome;
}

// Button configs per page type (BUTTON_KINDS in defaults.js is the single source of truth for the
// storage keys).
//
// Returns null when storage could not be read at all. Drawing the defaults there looked harmless
// and was not: the service worker does its own read when the button is clicked, so a page showing
// our presets would have run whatever the user actually had saved. Nothing is drawn instead, and the
// one-second poll retries — a read that fails now usually succeeds a moment later, and until it does
// the honest answer is that we do not know what this user's buttons are.
//
// A read that *succeeds* still falls back to the defaults for a value it cannot use (readStoredButtons):
// there both sides read the same storage and reach the same verdict, so what is drawn is what runs.
async function loadButtonConfigs(kind) {
  const { storageKey, defaults } = BUTTON_KINDS[kind];
  try {
    const data = await chrome.storage.sync.get([storageKey]);
    // Stored buttons are validated here too, not only on the options page: an entry another device
    // wrote as null would otherwise throw while drawing and take the whole button row with it
    return readStoredButtons(data[storageKey], defaults);
  } catch (error) {
    // **Latent, not diagnostic.** "Could not read your
    // buttons, will retry" is addressed to a *user*: it says what failed, whose it was, and what
    // happens next. It reaches only the console today, which is why it stays English, but the
    // boundary that decides that is **who a sentence is addressed to**, not where it is written.
    // "Everything in `console.*` is a diagnostic" was the broad version, and this is where it leaked.
    console.warn('Terminal Checkout: could not read your buttons, will retry —', error);
    return null;
  }
}

// GitHub list rows have changed their module class names over time. These are structural anchors:
// semantic rows first, the stable Primer Box-row token second, and no hashed class name.
const LIST_ROW_SELECTOR = '[role="row"], [role="listitem"], li, div[class~="Box-row"]';
const OWNED_LIST_CHECKBOX_CLASS = 'terminal-list-checkbox';
const LIST_ROW_ANCHOR_PATTERN = /^\/([^/]+)\/([^/]+)\/(pull|issues)\/(\d+)\/?$/;
const LIST_BUTTON_CLASS = 'terminal-list-btn';
const LIST_BUTTON_ROW_CLASS = 'terminal-list-btn-row';
const LIST_RESULT_BADGE_CLASS = 'terminal-list-result-badge';
const LIST_BUTTON_STYLE = `
  background: transparent;
  border: 1px solid rgba(87, 171, 90, 0.45);
  cursor: pointer;
  padding: 3px 8px;
  margin-left: 6px;
  display: inline-flex;
  align-items: center;
  border-radius: 2em;
  color: #57ab5a;
  font: 600 11px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
`;
const nativeListCheckboxVisibility = new WeakMap();
let listSelectionState = null;
let listDocumentGeneration = 0;

function listRowElementFor(anchor) {
  return anchor.closest(LIST_ROW_SELECTOR);
}

function checkboxAttributeText(control) {
  return [
    control.getAttribute('aria-label'),
    control.getAttribute('name'),
    control.getAttribute('id'),
    control.getAttribute('data-testid'),
    control.getAttribute('title'),
  ].filter(Boolean).join(' ').toLowerCase();
}

function isSelectAllCheckbox(control) {
  if (control.matches('[data-check-all], [data-select-all]')) return true;
  return /\b(?:select|check)\s+all\b|\ball\s+(?:issues|pull requests|items)\b/.test(checkboxAttributeText(control));
}

function nativeCheckboxesIn(row) {
  return [...row.querySelectorAll('input[type="checkbox"], [role="checkbox"]')]
    .filter(control => !control.classList.contains(OWNED_LIST_CHECKBOX_CLASS))
    .filter(control => !isSelectAllCheckbox(control));
}

function ownedCheckboxIn(row) {
  return row.querySelector(`.${OWNED_LIST_CHECKBOX_CLASS}`);
}

function listRowBelongsToTarget(href, expectedTarget) {
  if (!expectedTarget || typeof expectedTarget.owner !== 'string' || typeof expectedTarget.repo !== 'string') {
    return false;
  }
  let parsed;
  try {
    parsed = new URL(href, GITHUB_ORIGIN);
  } catch {
    return false;
  }
  if (parsed.origin !== GITHUB_ORIGIN) return false;
  const match = parsed.pathname.match(LIST_ROW_ANCHOR_PATTERN);
  return !!match && match[1] === expectedTarget.owner && match[2] === expectedTarget.repo;
}

// DOM reading is deliberately separate from parseListRowAnchor and the selection contracts in
// defaults.js. The pure functions stay testable without pretending a jsdom fixture proves which
// GitHub surface is live today.
function readListRows(root = document, expectedKind, expectedTarget = pageTargetOfUrl(location.href)) {
  const anchors = [];
  if (root.matches?.('a[href]')) anchors.push(root);
  if (root.querySelectorAll) anchors.push(...root.querySelectorAll('a[href]'));

  const rowsByKey = new Map();
  for (const anchor of anchors) {
    const href = anchor.getAttribute('href') ?? anchor.href;
    if (!listRowBelongsToTarget(href, expectedTarget)) continue;
    const parsed = parseListRowAnchor(href, anchor.textContent, expectedTarget);
    if (!parsed || (expectedKind && parsed.kind !== expectedKind)) continue;

    const element = listRowElementFor(anchor);
    if (!element) continue;
    const nativeCheckboxes = nativeCheckboxesIn(element);
    const candidate = {
      ...parsed,
      element,
      anchor,
      nativeCheckboxes,
      native: nativeCheckboxes.length > 0,
      ownedCheckbox: ownedCheckboxIn(element),
    };
    const current = rowsByKey.get(parsed.key);
    // A row can expose the same canonical link more than once. Prefer the occurrence that gives us
    // native coverage, then the one with the more useful title, while retaining one row per key.
    if (!current || (candidate.native && !current.native) || candidate.title.length > current.title.length) {
      rowsByKey.set(parsed.key, candidate);
    }
  }
  return [...rowsByKey.values()];
}

function readCheckboxChecked(control) {
  if (!control) return false;
  if ('checked' in control) return control.checked === true;
  return control.getAttribute('aria-checked') === 'true';
}

function setCheckboxChecked(control, checked) {
  if (!control) return;
  if ('checked' in control) {
    control.checked = checked;
  } else {
    control.setAttribute('aria-checked', String(checked));
  }
}

function listCheckboxForRow(row, mode) {
  if (mode === 'native') return row.nativeCheckboxes?.[0] || null;
  return row.ownedCheckbox || ownedCheckboxIn(row.element);
}

function rowsWithListChecks(rows, mode) {
  return rows.map(row => ({ ...row, checked: readCheckboxChecked(listCheckboxForRow(row, mode)) }));
}

function readListSelection(root = document, expectedKind) {
  const target = pageTargetOfUrl(location.href);
  const rows = readListRows(root, expectedKind, target);
  const mode = listCheckboxMode(rows);
  const selected = selectedListRows(rowsWithListChecks(rows, mode));
  return { rows, mode, selected, status: listSelectionStatus(selected) };
}

function readSelectedListRows(root = document, expectedKind) {
  return readListSelection(root, expectedKind).selected;
}

function rememberNativeListCheckbox(control) {
  if (!nativeListCheckboxVisibility.has(control)) {
    nativeListCheckboxVisibility.set(control, {
      hidden: control.hidden,
      ariaHidden: control.getAttribute('aria-hidden'),
    });
  }
  return nativeListCheckboxVisibility.get(control);
}

function setNativeListCheckboxVisible(control, visible) {
  if (!control) return;
  const original = rememberNativeListCheckbox(control);
  if (visible) {
    control.hidden = original.hidden;
    if (original.ariaHidden === null) control.removeAttribute('aria-hidden');
    else control.setAttribute('aria-hidden', original.ariaHidden);
  } else {
    control.hidden = true;
    control.setAttribute('aria-hidden', 'true');
  }
}

function restoreNativeListCheckboxes(rows) {
  for (const row of rows || []) {
    for (const control of row.nativeCheckboxes || []) setNativeListCheckboxVisible(control, true);
  }
}

function removeOwnedListCheckboxes(root = document) {
  const checkboxes = [];
  if (root.matches?.(`.${OWNED_LIST_CHECKBOX_CLASS}`)) checkboxes.push(root);
  if (root.querySelectorAll) checkboxes.push(...root.querySelectorAll(`.${OWNED_LIST_CHECKBOX_CLASS}`));
  for (const checkbox of checkboxes) checkbox.remove();
}

function sameListRows(previousRows, currentRows) {
  if (!Array.isArray(previousRows) || previousRows.length !== currentRows.length) return false;
  const previousByKey = new Map(previousRows.map(row => [row.key, row.element]));
  return currentRows.every(row => previousByKey.get(row.key) === row.element);
}

function createOwnedListCheckbox(row, checked) {
  const checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  checkbox.className = OWNED_LIST_CHECKBOX_CLASS;
  checkbox.checked = checked;
  checkbox.dataset.listRowKey = row.key;
  checkbox.title = row.title || row.number;
  checkbox.setAttribute('aria-label', row.title || row.number);
  checkbox.style.cssText = 'margin: 0 8px 0 0; vertical-align: middle;';
  checkbox.addEventListener('click', event => event.stopPropagation());

  const before = row.anchor === row.element.firstElementChild ? row.anchor : row.element.firstElementChild;
  row.element.insertBefore(checkbox, before || null);
  return checkbox;
}

function syncListSelectionControls(kind, rows, mode) {
  const previous = listSelectionState;
  const sameRows = previous?.kind === kind && sameListRows(previous.rows, rows);
  const canCarry = previous?.kind === kind && sameRows;
  const selectedKeys = canCarry
    ? attachedCheckedListRowKeys(previous.rows.map(row => ({
      ...row,
      selectionControl: listCheckboxForRow(row, previous.mode),
    })))
    : [];

  // A stable DOM and stable mode need no work on the one-second poll; in particular, don't replace
  // a focused native checkbox while the user is selecting rows.
  if (sameRows && canCarry && previous.mode === mode) {
    listSelectionState = { kind, mode, rows };
    return;
  }

  restoreNativeListCheckboxes(previous?.rows);
  restoreNativeListCheckboxes(rows);
  removeOwnedListCheckboxes();

  if (mode === 'owned') {
    for (const row of rows) {
      for (const control of row.nativeCheckboxes) setNativeListCheckboxVisible(control, false);
    }
    const carriedRows = carryListRowChecks(rows, selectedKeys);
    for (const row of carriedRows) {
      const current = rows.find(candidate => candidate.key === row.key);
      current.ownedCheckbox = createOwnedListCheckbox(current, row.checked);
    }
  } else if (mode === 'native' && canCarry && previous.mode !== 'native') {
    for (const row of carryListRowChecks(rows, selectedKeys)) {
      setCheckboxChecked(listCheckboxForRow(row, mode), row.checked);
    }
  }

  listSelectionState = { kind, mode, rows };
}

function removeListBatchResultBadges(identity) {
  for (const badge of document.querySelectorAll(`.${LIST_RESULT_BADGE_CLASS}`)) {
    if (identity === undefined || badge.dataset.listResultIdentity === identity) badge.remove();
  }
}

function clearListBatchResult(identity) {
  removeListBatchResultBadges(identity);
}

function invalidateListBatchResults() {
  clearListBatchResult();
  listDocumentGeneration += 1;
}

function resetListSelectionState() {
  restoreNativeListCheckboxes(listSelectionState?.rows);
  removeOwnedListCheckboxes();
  invalidateListBatchResults();
  listSelectionState = null;
}

function tryInsertListSelection(kind) {
  const expectedKind = kind === 'pr-list' ? 'pr' : 'issue';
  const target = pageTargetOfUrl(location.href);
  const rows = readListRows(document, expectedKind, target);
  if (rows.length === 0) {
    resetListSelectionState();
    document.querySelectorAll(`.${LIST_BUTTON_CLASS}, .${LIST_BUTTON_ROW_CLASS}`).forEach(node => node.remove());
    return false;
  }

  if (listSelectionState &&
      (listSelectionState.kind !== kind || !sameListRows(listSelectionState.rows, rows))) {
    invalidateListBatchResults();
  }
  syncListSelectionControls(kind, rows, listCheckboxMode(rows));
  return true;
}

// The list header is not a stable class name: GitHub rebuilds those module classes. Find a control
// row by its layout and its position before the first canonical list row instead. This also keeps a
// button from landing in a row when the page happens to contain nested forms or navigation lists.
function listToolbarLooksLike(element) {
  if (!element || !element.querySelector) return false;
  const display = getComputedStyle(element).display;
  if (!['block', 'flex', 'grid', 'inline-block', 'inline-flex'].includes(display)) return false;
  return !!element.querySelector('button, input, select, [role="button"], [role="combobox"]');
}

function documentElementBefore(left, right) {
  return !!left && !!right && left !== right &&
    !!(left.compareDocumentPosition(right) & Node.DOCUMENT_POSITION_FOLLOWING);
}

function listToolbarAnchor(rows) {
  const firstRow = rows[0]?.element;
  if (!firstRow) return null;

  let child = firstRow;
  for (let depth = 0; depth < 8 && child.parentElement; depth += 1) {
    const parent = child.parentElement;
    const siblings = [...parent.children];
    const childIndex = siblings.indexOf(child);
    const previous = siblings.slice(0, childIndex).reverse().find(listToolbarLooksLike);
    if (previous) return previous;

    const toolbar = parent.matches?.('[role="toolbar"]') ? parent : parent.querySelector?.('[role="toolbar"]');
    if (toolbar && documentElementBefore(toolbar, firstRow) && listToolbarLooksLike(toolbar)) return toolbar;
    child = parent;
  }

  let preceding = null;
  for (const candidate of document.querySelectorAll('[role="toolbar"], form, nav')) {
    if (documentElementBefore(candidate, firstRow) && listToolbarLooksLike(candidate)) preceding = candidate;
  }
  return preceding;
}

// Where the list buttons mount — two GitHub list generations, two chosen spots. The new issue-list
// UI has a visible page-title h1 row ("All issues") with empty space beside the title, so the
// buttons go inline right after that h1. The legacy PR-list UI has no visible h1 (only a
// screen-reader one, which offsetWidth filters out) — there the buttons get a dedicated full-width
// row right above the filter/search block. Hashed module class names cannot be selectors, so both
// anchors are structural.
function listButtonMount(rows) {
  const firstRow = rows[0]?.element;
  if (!firstRow) return null;

  let heading = null;
  for (const h1 of document.querySelectorAll('h1')) {
    if (h1.offsetWidth > 1 && h1.offsetHeight > 1 && documentElementBefore(h1, firstRow)) heading = h1;
  }
  if (heading?.parentElement) {
    return { parent: heading.parentElement, before: heading.nextSibling, inline: true };
  }

  const toolbar = listToolbarAnchor(rows);
  if (toolbar?.parentElement) {
    return { parent: toolbar.parentElement, before: toolbar, inline: false };
  }
  return null;
}

function listBatchBadgeLabel(result) {
  return result.success
    ? tr('ext.list.batch.result.success')
    : tr('ext.list.batch.result.failure', result.error || tr('ext.list.batch.result.unknown'));
}

function createListBatchResultBadge(view, result) {
  const badge = document.createElement('span');
  badge.className = LIST_RESULT_BADGE_CLASS;
  badge.dataset.listResultIdentity = view.buttonIdentity;
  badge.dataset.listRowKey = result.key;
  badge.textContent = result.success ? '✓' : '✕';
  badge.title = listBatchBadgeLabel(result);
  badge.setAttribute('aria-label', listBatchBadgeLabel(result));
  badge.style.cssText = result.success
    ? 'display: inline-block; margin-left: 6px; color: #1a7f37; font-weight: 600;'
    : 'display: inline-block; margin-left: 6px; color: #cf222e; font-weight: 600;';
  return badge;
}

function renderListBatchResultView(view, kind, generation) {
  if (generation !== listDocumentGeneration) return;
  const target = pageTargetOfUrl(location.href);
  if (target?.kind !== kind) return;

  clearListBatchResult(view.buttonIdentity);
  if (view.badges.length === 0) return;

  const expectedKind = kind === 'pr-list' ? 'pr' : 'issue';
  const rows = readListRows(document, expectedKind, target);
  const rowsByKey = new Map(rows.map(row => [row.key, row]));
  for (const result of view.badges) {
    const row = rowsByKey.get(result.key);
    if (!row) continue;
    row.anchor.insertAdjacentElement('afterend', createListBatchResultBadge(view, result));
  }
}

// A body click on a selection the batch cannot take shows the error marker (its run's phase) with the
// reason as the tooltip, until the marker clears and the label comes back
function showListBatchSelectionError(button, notice) {
  if (notice?.messageKey === 'ext.list.batch.selection.empty') {
    button.title = tr('ext.list.batch.selection.empty');
  } else if (notice?.messageKey === 'ext.list.batch.selection.tooMany') {
    button.title = tr('ext.list.batch.selection.tooMany', notice.args[0], notice.args[1]);
  }
}

// The same reason, on the popover's line, where the note stays as typed
function listSelectionNoticeText(notice) {
  if (notice.messageKey === 'ext.list.batch.selection.tooMany') {
    return tr('ext.list.batch.selection.tooMany', notice.args[0], notice.args[1]);
  }
  return tr('ext.list.batch.selection.empty');
}

// A list batch button is a split button like the header's (`splitButton` below): one run function, one
// lock, one popover. What is its own is what it sends — a batch for the rows selected when its run
// starts — and how its answer is shown, as badges on those rows.
function createListBatchButton(buttonConfig, index, kind) {
  const face = buttonFace(buttonConfig);
  const button = document.createElement('button');
  button.type = 'button';
  button.className = LIST_BUTTON_CLASS;
  button.textContent = face;
  button.title = buttonConfig.label;
  button.dataset.btnIndex = index;
  button.dataset.listKind = kind;
  button.style.cssText = LIST_BUTTON_STYLE;

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = 'rgba(87, 171, 90, 0.1)';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = 'transparent';
  });

  return splitButton(button, buttonConfig, index, {
    action: LIST_BATCH_ACTION, kind, face, phases: { busy: '⏳', done: '✅', error: '❌' },
    delays: { done: 2000, error: 2000 }, look: 'pill',
    restoreTitle: () => { button.title = buttonConfig.label; },
  });
}

async function tryInsertListButtons(kind, generation) {
  if (document.querySelector(`.${LIST_BUTTON_CLASS}`)) return true;

  const target = pageTargetOfUrl(location.href);
  const expectedKind = kind === 'pr-list' ? 'pr' : 'issue';
  const rows = readListRows(document, expectedKind, target);
  const mount = listButtonMount(rows);
  if (!mount) return false;

  const buttons = await loadButtonConfigs(kind);
  if (!buttons) return false;
  // The rows and the mount above were read from a page that may be gone by now
  if (pageChangedSince(generation)) return false;

  if (document.querySelector(`.${LIST_BUTTON_CLASS}`)) return true;

  const visible = buttons
    .map((config, index) => ({ config, index }))
    .filter(({ config }) => buttonUsesAllowedVariables(kind, config));
  if (visible.length === 0) return true;

  const host = document.createElement(mount.inline ? 'span' : 'div');
  host.className = LIST_BUTTON_ROW_CLASS;
  host.style.display = mount.inline ? 'inline-flex' : 'flex';
  host.style.alignItems = 'center';
  host.style.gap = '8px';
  if (mount.inline) {
    host.style.marginLeft = '12px';
    host.style.verticalAlign = 'middle';
  } else {
    host.style.margin = '0 0 8px';
  }
  visible.forEach(({ config, index }) => host.appendChild(createListBatchButton(config, index, kind)));
  mount.parent.insertBefore(host, mount.before);
  return true;
}

// Create the custom command button next to the PR branch or the issue badge (emoji icon or text pill)
function createCommandIconButton(buttonConfig, index, { action, kind, className }) {
  const face = buttonFace(buttonConfig);
  const button = document.createElement('button');
  button.className = className;
  button.title = buttonConfig.label;
  // flex-shrink:0 — when space runs short, what should give is the branch name (GitHub ellipsizes
  // it), not the button. Without this the text pill is squeezed first and you can no longer read
  // which button it is
  button.style.cssText = isTextFace(face) ? `
    background: transparent;
    border: 1px solid rgba(87, 171, 90, 0.45);
    cursor: pointer;
    padding: 2px 8px;
    margin-left: 4px;
    display: inline-block;
    flex-shrink: 0;
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    vertical-align: middle;
    border-radius: 2em;
    color: #57ab5a;
    font: 600 11px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
  ` : `
    background: transparent;
    border: none;
    cursor: pointer;
    padding: 4px;
    margin-left: 4px;
    display: inline-flex;
    flex-shrink: 0;
    align-items: center;
    border-radius: 4px;
    color: #57ab5a;
    font-size: 14px;
  `;
  button.textContent = face;
  button.dataset.btnIndex = index;

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = 'rgba(87, 171, 90, 0.1)';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = 'transparent';
  });

  return splitButton(button, buttonConfig, index, {
    action, kind, face, phases: { busy: '⏳', done: '✅', error: '❌' }, delays: { done: 1500, error: 2000 },
    look: isTextFace(face) ? 'pill' : 'icon',
  });
}

// --- Split buttons: one run per button, and the note a claude button can carry ---
//
// A header button or a list batch button is its body and, when it starts claude with room for one more
// input (`buttonTakesClaudeNote`, defaults.js), a caret beside it that opens a one-line note for claude
// — one split button, kept on one line. Every run goes through `runSplitButton`: the body's click, and
// the popover's send button and Enter. The run is held by the button's identity (defaults.js), not by
// the node that was pressed, so the same button drawn again while its request is in flight comes back
// busy, and no other button or page is held.
//
// The popover lives in <body>, not in the header: the PR header's rows clip (layout.js). It is placed
// absolutely rather than as an HTML `popover` in the top layer, which needs Chrome 114 while the
// manifest sets no minimum version. There is no shadow root: a key event from inside one reaches the
// page retargeted to its host, which is no longer an editable field to GitHub's shortcut handling,
// while our own input stays the target of its events — and the popover stops key events besides.
// Styles are CSSOM, like every other node this script draws, with GitHub's colour variables and a
// fallback for each, so the popover follows the light and dark themes.
const SPLIT_BUTTON_CLASS = 'terminal-split-btn';
const NOTE_CARET_CLASS = 'terminal-note-caret';
const NOTE_POPOVER_CLASS = 'terminal-note-popover';
const SVG_NS = 'http://www.w3.org/2000/svg';

const SPLIT_BUTTON_STYLE = `
  display: inline-flex;
  align-items: stretch;
  flex-shrink: 0;
  vertical-align: middle;
`;
// The body's corners where it meets its caret, per look
const SPLIT_BODY_RADIUS = { filled: '6px 0 0 6px', pill: '2em 0 0 2em', icon: '4px 0 0 4px' };
// The caret carries on its body's look: a green piece joined to the filled repository button, the
// rest of a text pill's outline, or a narrow transparent piece past an icon behind a thin divider
const NOTE_CARET_STYLE = {
  filled: `
    background-color: #238636;
    color: white;
    border: none;
    border-left: 1px solid rgba(255, 255, 255, 0.35);
    border-radius: 0 6px 6px 0;
    padding: 0 5px;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
  `,
  pill: `
    background: transparent;
    color: #57ab5a;
    border: 1px solid rgba(87, 171, 90, 0.45);
    border-left: none;
    border-radius: 0 2em 2em 0;
    padding: 0 6px 0 4px;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
  `,
  icon: `
    background: transparent;
    color: #57ab5a;
    border: none;
    border-left: 1px solid rgba(87, 171, 90, 0.35);
    border-radius: 0 4px 4px 0;
    padding: 0 3px;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
  `,
};
const NOTE_POPOVER_STYLE = `
  position: absolute;
  left: 0;
  top: 0;
  z-index: 2147483647;
  box-sizing: border-box;
  width: 320px;
  max-width: calc(100vw - 16px);
  overflow: auto;
  padding: 8px;
  border: 1px solid var(--borderColor-default, #d0d7de);
  border-radius: 6px;
  background: var(--overlay-bgColor, var(--bgColor-default, #ffffff));
  color: var(--fgColor-default, #1f2328);
  box-shadow: var(--shadow-floating-large, 0 8px 24px rgba(140, 149, 159, 0.2));
  font: 12px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
  text-align: left;
  visibility: hidden;
`;
const NOTE_INPUT_STYLE = `
  flex: 1 1 auto;
  min-width: 0;
  box-sizing: border-box;
  margin: 0;
  padding: 4px 8px;
  font: inherit;
  color: inherit;
  background: var(--bgColor-default, #ffffff);
  border: 1px solid var(--borderColor-default, #d0d7de);
  border-radius: 6px;
`;
const NOTE_SEND_STYLE = `
  flex: 0 0 auto;
  margin: 0;
  padding: 4px 10px;
  font: inherit;
  font-weight: 600;
  color: var(--button-primary-fgColor-rest, #ffffff);
  background: var(--button-primary-bgColor-rest, #1f883d);
  border: 1px solid var(--button-primary-borderColor-rest, rgba(31, 35, 40, 0.15));
  border-radius: 6px;
  cursor: pointer;
`;
const NOTE_STATUS_STYLE = `
  display: none;
  margin: 6px 0 0;
  overflow-wrap: anywhere;
`;
const NOTE_QUIET_COLOR = 'var(--fgColor-muted, #59636e)';
const NOTE_PROBLEM_COLOR = 'var(--fgColor-danger, #d1242f)';

const splitButtonRuns = createSplitButtonRuns();
// Every drawing of a split button, so a run can repaint the ones on screen; detached ones are dropped
// as they are met
const drawnSplitButtons = new Set();
// What a closed or failed popover leaves typed, by the identity of the page it was opened for, for the
// next time it opens
const noteDrafts = new Map();
let notePopover = null;

// A header or list button around its body. Returns the node to insert: the body, or the split button.
//
// A drawing holds no identity of its own. It names its kind, index and fingerprint, and the page is
// supplied when it matters (`drawingIdentityOn`, defaults.js): a run holds the page its message goes
// to, and a drawing is painted, and its caret and send button obey, the run of the page on screen now.
// GitHub can move to another page without anything removing the buttons drawn for the last one, and a
// button that held the page it was drawn on while sending the page on screen let a rebuilt button send
// the same request again (measured). A list button also names the badges its results draw
// (`resultIdentity`) and how its tooltip comes back after a refused selection (`restoreTitle`).
function splitButton(body, config, index, { action, kind, face, phases, delays, look, restoreTitle }) {
  const list = action === LIST_BATCH_ACTION;
  const view = {
    action, kind, index, shown: buttonFingerprint(config), body, face, phases, delays, caret: null,
    list, resultIdentity: list ? listBatchButtonIdentity(kind, index) : null, restoreTitle,
  };
  // onUserClick refuses anything the browser did not mark as a real click, before the body runs. The
  // page is read when the body is pressed, not when it was drawn: the page moves under a button. From
  // the full href rather than the pathname, so it goes through the same origin check the service worker
  // uses — one validator, one answer to "is this a page of ours".
  onUserClick(body, () => runSplitButton(view, { target: pageTargetOfUrl(location.href) }));
  drawnSplitButtons.add(view);
  if (!buttonTakesClaudeNote(config)) {
    paintSplitButton(view);
    return body;
  }
  view.caret = createNoteCaret(view, look);
  const split = document.createElement('span');
  split.className = SPLIT_BUTTON_CLASS;
  split.style.cssText = SPLIT_BUTTON_STYLE;
  // The gap in front belongs to the pair now, and the corners where the two meet are squared
  split.style.marginLeft = body.style.marginLeft;
  body.style.marginLeft = '0';
  body.style.borderRadius = SPLIT_BODY_RADIUS[look];
  split.append(body, view.caret);
  paintSplitButton(view);
  return split;
}

// A drawing shows the run of the page on screen, whichever node it is and whichever page it was drawn
// for. The body stays off through the outcome marker as it always has; the caret is off only while the
// request is in flight.
function paintSplitButton(view) {
  const phase = splitButtonRuns.phaseOf(drawingIdentityOn(view, pageTargetOfUrl(location.href)));
  view.body.textContent = phase ? view.phases[phase] : view.face;
  view.body.disabled = phase !== null;
  if (view.caret) {
    view.caret.disabled = phase === 'busy';
    view.caret.style.opacity = phase === 'busy' ? '0.5' : '';
  }
}

// Every drawing on screen, and the open popover's send button, take up whatever the runs hold now
function repaintSplitButtons() {
  for (const view of drawnSplitButtons) {
    if (!view.body.isConnected) drawnSplitButtons.delete(view);
    else paintSplitButton(view);
  }
  if (notePopover) syncNoteSend(notePopover);
}

// Every split button run starts here — the body's click with the page read when it was pressed, a note
// with the page its popover opened on — and it is held before the first await, under the identity of
// the page it sends for, so the body, the caret, the send button and Enter all stop at that run.
//
// A list run is for the rows selected when it starts: they are read here, once, before the run is held,
// and never again once it waits — the worker reads the page again for itself and refuses a selection
// that no longer matches. A selection the batch cannot take (none, or more than the cap) sends nothing:
// in the popover it becomes the popover's line with the note left as typed; on the body it is the error
// marker, with the reason as the tooltip.
async function runSplitButton(view, { target, note, popover, typed }) {
  const selected = view.list ? readSelectedListRows(document, view.kind === 'pr-list' ? 'pr' : 'issue') : undefined;
  const notice = view.list ? listBatchSelectionNotice(listSelectionStatus(selected)) : null;
  if (notice && popover) {
    showNoteStatus(popover, listSelectionNoticeText(notice), true);
    return;
  }
  const run = splitButtonRun(view, target, note, selected);
  const token = splitButtonRuns.start(run.identity);
  if (token === null) return;
  if (view.list) clearListBatchResult(view.resultIdentity);
  let phase = 'done';
  if (notice) {
    showListBatchSelectionError(view.body, notice);
    phase = 'error';
  } else {
    if (popover) startNoteSend(popover);
    repaintSplitButtons();
    const generation = listDocumentGeneration;
    try {
      if (view.list) {
        const outcome = await sendListBatchMessage(run.message);
        const result = listBatchResultView(view.resultIdentity, selected, outcome);
        renderListBatchResultView(result, view.kind, generation);
        phase = result.phase;
      } else {
        await sendButtonMessage(run.message);
      }
    } catch (failure) {
      console.error('command error:', failure);
      phase = 'error';
    }
  }
  splitButtonRuns.finish(run.identity, token, phase);
  repaintSplitButtons();
  if (popover) settleNoteSend(popover, phase, typed);
  setTimeout(() => {
    if (!splitButtonRuns.clear(run.identity, token)) return;
    view.restoreTitle?.();
    repaintSplitButtons();
  }, view.delays[phase]);
}

function createNoteCaret(view, look) {
  const caret = document.createElement('button');
  caret.type = 'button';
  caret.className = NOTE_CARET_CLASS;
  caret.title = tr('ext.claudeNote.caret');
  caret.setAttribute('aria-label', tr('ext.claudeNote.caret'));
  caret.setAttribute('aria-haspopup', 'dialog');
  caret.setAttribute('aria-expanded', 'false');
  caret.style.cssText = NOTE_CARET_STYLE[look];
  caret.appendChild(noteCaretIcon());
  const rest = look === 'filled' ? '#238636' : 'transparent';
  const hover = look === 'filled' ? '#2ea043' : 'rgba(87, 171, 90, 0.1)';
  caret.addEventListener('mouseenter', () => { caret.style.backgroundColor = hover; });
  caret.addEventListener('mouseleave', () => { caret.style.backgroundColor = rest; });
  onUserClick(caret, () => toggleNotePopover(view));
  return caret;
}

// ▾ in the caret's own colour: a triangle of our own, filled with currentColor
function noteCaretIcon() {
  const icon = document.createElementNS(SVG_NS, 'svg');
  icon.setAttribute('viewBox', '0 0 16 16');
  icon.setAttribute('width', '10');
  icon.setAttribute('height', '10');
  icon.setAttribute('aria-hidden', 'true');
  icon.setAttribute('focusable', 'false');
  icon.style.cssText = 'display: block; fill: currentColor;';
  const path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('d', 'M3 6h10l-5 5z');
  icon.appendChild(path);
  return icon;
}

function toggleNotePopover(view) {
  if (splitButtonRuns.phaseOf(drawingIdentityOn(view, pageTargetOfUrl(location.href))) === 'busy') return;
  const reopening = notePopover?.caret === view.caret;
  closeNotePopover();
  if (!reopening) openNotePopover(view);
}

// The note for one button. The page it is for is read as it opens: the note goes with the page the
// person was looking at when they started writing it, and a page that moves on in the meantime is
// refused by the worker rather than sent to. Its draft is kept under that page's identity.
function openNotePopover(view) {
  const target = pageTargetOfUrl(location.href);
  const identity = drawingIdentityOn(view, target);
  const root = document.createElement('div');
  root.className = NOTE_POPOVER_CLASS;
  root.setAttribute('role', 'dialog');
  root.setAttribute('aria-label', tr('ext.claudeNote.caret'));
  root.style.cssText = NOTE_POPOVER_STYLE;
  const input = document.createElement('input');
  input.type = 'text';
  input.autocomplete = 'off';
  input.placeholder = tr('ext.claudeNote.placeholder');
  input.setAttribute('aria-label', tr('ext.claudeNote.input'));
  input.style.cssText = NOTE_INPUT_STYLE;
  input.value = noteDrafts.get(identity) ?? '';
  const send = document.createElement('button');
  send.type = 'button';
  send.textContent = tr('ext.claudeNote.send');
  send.style.cssText = NOTE_SEND_STYLE;
  const status = document.createElement('div');
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  status.style.cssText = NOTE_STATUS_STYLE;
  const row = document.createElement('div');
  row.style.cssText = 'display: flex; align-items: center; gap: 6px;';
  row.append(input, send);
  root.append(row, status);

  const popover = { view, caret: view.caret, target, identity, root, input, send, status, sending: false };
  // GitHub's shortcuts listen on the document; nothing typed in here is theirs
  for (const type of ['keydown', 'keyup', 'keypress']) root.addEventListener(type, event => event.stopPropagation());
  root.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || event.isComposing) return;
    event.preventDefault();
    closeNotePopover();
  });
  // Enter sends only when a person pressed it, and never while it is ending an IME composition
  input.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter' || event.isComposing) return;
    event.preventDefault();
    if (isUserGesture(event)) submitNote(popover);
  });
  // Text a paste or a drop brings is judged as it arrives, from the original the event carries, before
  // the input changes it
  input.addEventListener('paste', event => refuseControlCharacterInsert(popover, event, event.clipboardData?.getData('text/plain')));
  input.addEventListener('drop', event => refuseControlCharacterInsert(popover, event, event.dataTransfer?.getData('text/plain')));
  input.addEventListener('input', () => {
    showNoteStatus(popover, '', false);
    syncNoteSend(popover);
  });
  onUserClick(send, () => submitNote(popover));
  popover.onPointerDown = (event) => {
    if (!root.contains(event.target) && !popover.caret.contains(event.target)) closeNotePopover();
  };
  popover.onResize = () => placeNotePopover(popover);
  // Anything that changes the popover's size — a status line shown or hidden, the send button's ⏳ —
  // places it again, rather than each such place remembering to
  popover.onSizeChange = new ResizeObserver(() => placeNotePopover(popover));
  document.addEventListener('pointerdown', popover.onPointerDown, true);
  window.addEventListener('resize', popover.onResize);

  document.body.appendChild(root);
  popover.onSizeChange.observe(root);
  notePopover = popover;
  view.caret.setAttribute('aria-expanded', 'true');
  syncNoteSend(popover);
  placeNotePopover(popover);
  input.focus();
}

// Placed from the measured size and capped at the viewport's height (layout.js), so the input and the
// send button stay reachable, scrolling inside the popover when the viewport is shorter than it
function placeNotePopover(popover) {
  const box = popover.root.getBoundingClientRect();
  const { left, top, maxHeight } = notePopoverPosition({
    anchor: (popover.caret.parentElement ?? popover.caret).getBoundingClientRect(),
    size: { width: box.width, height: box.height },
    viewport: { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight },
    scroll: { x: window.scrollX, y: window.scrollY },
  });
  popover.root.style.maxHeight = `${maxHeight}px`;
  popover.root.style.left = `${left}px`;
  popover.root.style.top = `${top}px`;
  popover.root.style.visibility = 'visible';
}

// A paste or a drop brings text in before a verdict can see the value, and a single-line input changes
// the line breaks in it — to spaces, or to nothing. The events carry the original: the clipboard's plain
// text on `paste`, the drag's on `drop`. That original is judged by the verdict's own control-character
// rule; text it refuses is not let in and the refusal is shown, and anything else is left to the
// browser. Measured with synthetic events: a paste of `one` CRLF `two` came back `defaultPrevented`
// with the refusal on the status line, and a single-line paste was not prevented — a synthetic paste
// inserts no text, so what the browser then puts in was not observed. A script can insert text without
// either event: `execCommand('insertText')` with `x` LF `y` left `x y` in the input and ran no
// `beforeinput` listener (measured, in a background tab). That is script territory, like any other
// write to the page's DOM: the note is judged again when it is sent, and by the worker after that.
function refuseControlCharacterInsert(popover, event, original) {
  if (typeof original !== 'string' || !claudeNoteHasControlCharacter(original)) return;
  event.preventDefault();
  showNoteStatus(popover, noteRefusalText(claudeNoteRefusalNotice('control-character')), true);
}

// A note is read here, once, and judged by the one verdict (defaults.js) before anything is sent: a
// refusal is shown in this page's language and nothing leaves. What goes out is the verdict's note.
function submitNote(popover) {
  const typed = popover.input.value;
  const verdict = claudeNoteVerdict(typed);
  if (!verdict.valid) {
    showNoteStatus(popover, noteRefusalText(claudeNoteRefusalNotice(verdict.error)), true);
    return;
  }
  runSplitButton(popover.view, { target: popover.target, note: verdict.note, popover, typed });
}

// A refused note's message in this page's language, by the message ids `claudeNoteRefusalNotice`
// (defaults.js) names. Each lookup is written out, so the catalogue audit sees every message drawn
// here; an id without one reads as the failure that names no cause.
const NOTE_REFUSAL_TEXT = {
  'ext.claudeNote.refused.notString': () => tr('ext.claudeNote.refused.notString'),
  'ext.claudeNote.refused.empty': () => tr('ext.claudeNote.refused.empty'),
  'ext.claudeNote.refused.unpairedSurrogate': () => tr('ext.claudeNote.refused.unpairedSurrogate'),
  'ext.claudeNote.refused.controlCharacter': () => tr('ext.claudeNote.refused.controlCharacter'),
  'ext.claudeNote.refused.leadingCharacter': () => tr('ext.claudeNote.refused.leadingCharacter'),
  'ext.claudeNote.refused.braces': () => tr('ext.claudeNote.refused.braces'),
  'ext.claudeNote.refused.tooLong': limit => tr('ext.claudeNote.refused.tooLong', limit),
};

function noteRefusalText(notice) {
  const text = notice && Object.hasOwn(NOTE_REFUSAL_TEXT, notice.messageKey) ? NOTE_REFUSAL_TEXT[notice.messageKey] : null;
  return text ? text(...notice.args) : tr('ext.claudeNote.failed');
}

function showNoteStatus(popover, message, problem) {
  popover.status.textContent = message;
  popover.status.style.display = message ? 'block' : 'none';
  popover.status.style.color = problem ? NOTE_PROBLEM_COLOR : NOTE_QUIET_COLOR;
}

// The send button is off while the box is empty, while this button has a run in flight, and while
// this popover's own note is on its way
function syncNoteSend(popover) {
  const off = popover.sending || popover.input.value === ''
    || splitButtonRuns.phaseOf(drawingIdentityOn(popover.view, pageTargetOfUrl(location.href))) === 'busy';
  popover.send.disabled = off;
  popover.send.style.opacity = off ? '0.5' : '1';
  popover.send.style.cursor = off ? 'default' : 'pointer';
}

function startNoteSend(popover) {
  popover.sending = true;
  popover.input.readOnly = true;
  popover.send.textContent = '⏳';
  showNoteStatus(popover, '', false);
  syncNoteSend(popover);
}

// What a note's answer does to its popover. Success closes it and forgets the draft. Failure keeps the
// typed note — in the popover when it is still the open one, and for the next opening either way —
// under a line that names no cause: the worker's reason is an English sentence composed where no page
// language exists, and it goes to the console only. A popover closed in the meantime, or another one
// open now, is left alone.
function settleNoteSend(popover, phase, typed) {
  popover.sending = false;
  if (phase === 'done') {
    if (notePopover === popover) closeNotePopover();
    noteDrafts.delete(popover.identity);
    return;
  }
  noteDrafts.set(popover.identity, typed);
  if (notePopover !== popover) return;
  popover.input.readOnly = false;
  popover.send.textContent = tr('ext.claudeNote.send');
  showNoteStatus(popover, tr('ext.claudeNote.failed'), true);
  syncNoteSend(popover);
}

function closeNotePopover({ restoreFocus = true } = {}) {
  const popover = notePopover;
  if (!popover) return;
  notePopover = null;
  if (popover.input.value) noteDrafts.set(popover.identity, popover.input.value);
  else noteDrafts.delete(popover.identity);
  popover.onSizeChange.disconnect();
  popover.root.remove();
  document.removeEventListener('pointerdown', popover.onPointerDown, true);
  window.removeEventListener('resize', popover.onResize);
  popover.caret.setAttribute('aria-expanded', 'false');
  if (restoreFocus && popover.caret.isConnected && !popover.caret.disabled) popover.caret.focus();
}

// Drawings GitHub took away with a rebuilt header, or that a page change removed, are dropped — and a
// popover whose caret went with them has nothing to hang from or return focus to. Safe at the start
// of an insert pass: every insert creates and inserts its buttons in one synchronous stretch, so no
// drawing is ever waiting, created but not yet inserted, across an await.
function forgetDetachedSplitButtons() {
  for (const view of drawnSplitButtons) {
    if (!view.body.isConnected) drawnSplitButtons.delete(view);
  }
  if (notePopover && !notePopover.caret.isConnected) closeNotePopover({ restoreFocus: false });
}

// Inside a breadcrumb item of the new GitHub header (an li with display:block), leaving the button
// to the inline flow drops it about 12px below the baseline. Making the item a flex container puts
// it on the same line (cross-axis centered) as the repository name and the dropdown. Moving it
// outside the item (as a sibling of the ol) makes a new breadcrumb "/" separator appear in front of
// the button, so keeping it inside is the right call.
function attachToRepoCrumb(anchor, buttons) {
  const crumb = anchor.closest('li');
  if (crumb) {
    crumb.style.display = 'flex';
    crumb.style.alignItems = 'center';
    buttons.forEach(button => crumb.appendChild(button));
    return;
  }
  // Legacy UI: a header that isn't a breadcrumb. afterend inserts immediately after, so the button
  // just inserted has to become the next anchor for them to line up in the configured order
  let after = anchor;
  for (const button of buttons) {
    after.insertAdjacentElement('afterend', button);
    after = button;
  }
}

// Add the custom command buttons to the PR header (returns true on success)
async function tryInsertPRButtons(generation) {
  // Skip if the buttons are already there
  if (document.querySelector('.terminal-cmd-btn')) {
    return true;
  }

  const match = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+/);
  if (!match) return false;

  // The header's branch links, base first and head second (`PR_BRANCH_LINK_SELECTOR`, defaults.js)
  const [, headBranchLink] = [...document.querySelectorAll(PR_BRANCH_LINK_SELECTOR)].filter(link => {
    const rect = link.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  });
  if (!headBranchLink) return false;

  const buttons = await loadButtonConfigs('pr');
  if (!buttons) return false; // read failed; the poll retries rather than drawing something that would refuse
  // The branch link above was read from a page that may be gone by now
  if (pageChangedSince(generation)) return false;

  // While awaiting above, another trigger (the 1-second poll, the MutationObserver, a turbo event)
  // may have inserted them first — without re-checking, the buttons show up twice
  if (document.querySelector('.terminal-cmd-btn')) {
    return true;
  }

  // Insert outside the head-ref span (so the buttons don't land inside the branch badge)
  const headRefSpan = headBranchLink.closest('.head-ref');
  // The wrapper span around clipboard-copy (the next sibling of head-ref)
  const copyWrapper = headRefSpan?.nextElementSibling;
  const hasCopy = copyWrapper?.querySelector('clipboard-copy');
  const insertAfter = (hasCopy ? copyWrapper : null) || headRefSpan || headBranchLink;

  // Insert the buttons in reverse order (insertAdjacentElement afterend inserts immediately after)
  for (let i = buttons.length - 1; i >= 0; i--) {
    const iconButton = createCommandIconButton(buttons[i], i, {
      action: 'execute_command', kind: 'pr', className: 'terminal-cmd-btn',
    });
    insertAfter.insertAdjacentElement('afterend', iconButton);
  }

  unclipButtonRow(insertAfter.parentElement, el => getComputedStyle(el).overflowX);

  return true;
}

// The status badge row in the issue header (Open, linked PRs, labels). Putting the buttons inside
// the title (h1) pushes them onto the next line depending on the title's length, but this row is a
// flex container, so they sit reliably on the same line as the badges.
function issueBadgeRow() {
  const state = document.querySelector('[data-testid="header-state"]');
  if (!state) return null;
  // Module CSS class names carry a build hash and change, so find the row by layout (flex) instead
  let element = state.parentElement;
  for (let depth = 0; depth < 4 && element; depth++) {
    if (getComputedStyle(element).display === 'flex') return element;
    element = element.parentElement;
  }
  return state.parentElement;
}

// Add the issue-specific buttons to the issue header (returns true on success)
async function tryInsertIssueButtons(generation) {
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  const row = issueBadgeRow();
  if (!row) return false;

  const buttons = await loadButtonConfigs('issue');
  if (!buttons) return false;
  // The badge row above was read from a page that may be gone by now
  if (pageChangedSince(generation)) return false;

  // While awaiting, another trigger (the poll, the MutationObserver, a turbo event) may have
  // inserted them first
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  buttons.forEach((config, index) => {
    row.appendChild(createCommandIconButton(config, index, {
      action: 'execute_issue_command', kind: 'issue', className: 'terminal-issue-btn',
    }));
  });

  return true;
}

// Add the buttons to the repository header (returns true on success)
async function tryInsertRepoButtons(target, generation) {
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  // Private repository: the breadcrumb item with the lock icon / public: the repository name link
  const { banner, crumb } = repoCrumbSelectors(target.owner, target.repo);
  const header = document.querySelector(banner);
  const anchor = header && crumb.map(selector => header.querySelector(selector)).find(Boolean);
  if (!anchor) return false;

  const buttons = await loadButtonConfigs('repo');
  if (!buttons) return false;
  // The crumb above was read from a page that may be gone by now
  if (pageChangedSince(generation)) return false;

  // While awaiting above, another trigger (the 1-second poll, the MutationObserver, a turbo event)
  // may have inserted them first — without re-checking, the buttons show up twice
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  attachToRepoCrumb(anchor, buttons.map((config, index) => createRepoButton(config, index)));
  return true;
}

// Insert the buttons according to the page type.
//
// The same reading the click and the service worker use, so a page we would refuse to run anything
// on is a page we do not draw a button on either — a button that can only fail is worse than none.
//
// Every pass first asks whether the page moved (`onUrlChange`, a no-op when it has not). The history
// wrappers below see only moves made from this script's side; GitHub's own navigation goes past them,
// and a move made through a `pushState` they did not wrap left the previous PR's buttons, and an open
// popover, on the next PR (measured). The poll, the observer and GitHub's navigation events all run this
// pass, so such a move reaches the one place that clears the old page within a second.
//
// The pass then holds the generation of the page it started on, and after every await it asks again
// (`pageChangedSince`) before it reads or draws anything more: what it read before the await belongs to
// that page. A pass that waited through a move and drew when it resumed put the old page's buttons on
// the new one, and the pass started on the new page found buttons there and drew nothing — reproduced by
// running this script in a DOM harness with the storage read held; the window is one storage read wide.
async function tryInsertButton() {
  onUrlChange();
  const generation = pageGeneration;
  forgetDetachedSplitButtons();
  const target = pageTargetOfUrl(location.href);
  if (!target) return false;

  let result = false;

  // Repository, PR, and issue pages all get the repository buttons in the header
  result = await tryInsertRepoButtons(target, generation) || result;
  // `target` was read before that await, and chooses what is drawn next
  if (pageChangedSince(generation)) return result;

  // PR and issue pages also get their own custom command buttons (configured separately)
  if (target.kind === 'pr') {
    result = await tryInsertPRButtons(generation) || result;
  } else if (target.kind === 'issue') {
    result = await tryInsertIssueButtons(generation) || result;
  } else if (target.kind === 'pr-list' || target.kind === 'issue-list') {
    result = tryInsertListSelection(target.kind) || result;
    result = await tryInsertListButtons(target.kind, generation) || result;
  }

  return result;
}

// The page the buttons on screen were drawn for, as `onUrlChange` last saw it
let lastUrl = location.href;
let lastTarget = pageTargetOfUrl(location.href);
// Moved on by every removal, so an insert pass can tell that the page it started on is gone. Not
// `listDocumentGeneration`: that one also moves when a list's rows change under the same page, which
// must not cancel a pass whose buttons are still right there.
let pageGeneration = 0;

// Our buttons belong to the page they were drawn on. GitHub navigates without a reload, and the
// insert functions bail out as soon as they see a button already there — so buttons drawn for PR #1
// could survive onto PR #2, where their position and the header around them mean something else.
// Removing them makes the next insert redraw for the page that is actually showing. A note popover
// belongs to its button's page too, and goes with it; its draft stays, under the page it was opened for.
// The page generation moves on first, so a pass that read the old page and is still waiting draws
// nothing when it resumes.
function removeInsertedButtons() {
  pageGeneration += 1;
  closeNotePopover({ restoreFocus: false });
  document.querySelectorAll(`.terminal-cmd-btn, .terminal-issue-btn, .terminal-open-btn, .${SPLIT_BUTTON_CLASS}, .terminal-list-btn, .terminal-list-btn-row`)
    .forEach(node => node.remove());
  resetListSelectionState();
}

// Reached from the history wrappers and `popstate`, and from every insert pass for the moves those miss.
// A no-op while the URL has not moved, so being asked often costs nothing.
function onUrlChange() {
  if (location.href === lastUrl) return;
  lastUrl = location.href;
  const target = pageTargetOfUrl(location.href);
  // Only when the *target* changed. Reclassification makes moving between the two lists change the
  // target and redraw the buttons; query-only pagination or filtering within one list keeps it stable.
  if (!sameTarget(target, lastTarget)) removeInsertedButtons();
  lastTarget = target;
  // On a URL change, wait a moment before trying to insert the buttons
  setTimeout(tryInsertButton, 300);
}

// Whether the page an insert pass started on is gone — asked after each of the pass's awaits, before it
// reads or draws anything more. It asks `onUrlChange` first, so a move nothing has reported yet counts as
// well. Only a new target moves the generation: a query change within one list keeps the buttons, and a
// pass drawing them there is still right.
function pageChangedSince(generation) {
  onUrlChange();
  return generation !== pageGeneration;
}

// History API wrappers. They wrap this script's view of `history` only — GitHub's own navigation
// happens in the page's world and does not pass through them; the insert passes catch those moves.
const originalPushState = history.pushState;
history.pushState = function(...args) {
  originalPushState.apply(this, args);
  onUrlChange();
};

const originalReplaceState = history.replaceState;
history.replaceState = function(...args) {
  originalReplaceState.apply(this, args);
  onUrlChange();
};

window.addEventListener('popstate', onUrlChange);

// MutationObserver: detect when the header area or a list row is added
const observer = new MutationObserver((mutations) => {
  const target = pageTargetOfUrl(location.href);
  const listKind = target?.kind === 'pr-list' ? 'pr' : target?.kind === 'issue-list' ? 'issue' : null;
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        // Insert the buttons if the added node is, or contains, a relevant element. GitHub can replace
        // its whole banner after the page loads (seen once, 8s in), taking the repository buttons with it.
        if (node.classList?.contains('gh-header-actions') ||
            node.classList?.contains('AppHeader-context-full') ||
            node.querySelector?.('.gh-header-actions') ||
            node.querySelector?.('.AppHeader-context-full') ||
            node.matches?.(GITHUB_BANNER_SELECTOR) ||
            node.querySelector?.(GITHUB_BANNER_SELECTOR) ||
            (listKind && readListRows(node, listKind, target).length > 0)) {
          tryInsertButton();
          return;
        }
      }
    }
  }
});

observer.observe(document.body, {
  childList: true,
  subtree: true
});

// Periodic polling (backup) - check every second
setInterval(tryInsertButton, 1000);

// GitHub navigation events
document.addEventListener('turbo:load', tryInsertButton);
document.addEventListener('turbo:render', tryInsertButton);
document.addEventListener('pjax:end', tryInsertButton);

// Initial run
tryInsertButton();
