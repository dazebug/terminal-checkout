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

  // onUserClick refuses anything the browser did not mark as a real click, before the body runs
  onUserClick(button, async () => {
    button.textContent = phases.busy;
    button.disabled = true;

    try {
      await runButtonCommand('execute_repo_command', index, buttonConfig);
      button.textContent = phases.done;
      setTimeout(() => {
        button.textContent = face;
        button.disabled = false;
      }, 2000);
    } catch (error) {
      console.error('repo command error:', error);
      button.textContent = phases.error;
      setTimeout(() => {
        button.textContent = face;
        button.disabled = false;
      }, 2000);
    }
  });

  return button;
}

// Run a single button. sendMessage does not reject when the background returns {success:false}, so
// without inspecting the response a rejected command would still show up as success on the button.
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
// Sending them as sources would let a message name its own repository.
async function runButtonCommand(action, index, config) {
  const response = await chrome.runtime.sendMessage({
    action,
    buttonIndex: index,
    shown: buttonFingerprint(config),
    // Read now, not when the button was drawn: the button is drawn once and the page moves under it.
    // From the full href rather than the pathname, so this goes through the same origin check the
    // service worker uses — one validator, one answer to "is this a page of ours".
    target: pageTargetOfUrl(location.href),
  });
  if (!response?.success) throw new Error(response?.error || 'unknown error');
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
const nativeListCheckboxVisibility = new WeakMap();
let listSelectionState = null;

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

// DOM reading is deliberately separate from parseListRowAnchor and the selection contracts in
// defaults.js. The pure functions stay testable without pretending a jsdom fixture proves which
// GitHub surface is live today.
function readListRows(root = document, expectedKind) {
  const anchors = [];
  if (root.matches?.('a[href]')) anchors.push(root);
  if (root.querySelectorAll) anchors.push(...root.querySelectorAll('a[href]'));

  const rowsByKey = new Map();
  for (const anchor of anchors) {
    const parsed = parseListRowAnchor(anchor.getAttribute('href') ?? anchor.href, anchor.textContent);
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
  const rows = readListRows(root, expectedKind);
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

function listControlsAttached(rows, mode) {
  return rows.every(row => {
    const controls = mode === 'native' ? row.nativeCheckboxes : [row.ownedCheckbox || ownedCheckboxIn(row.element)];
    return controls.length > 0 && controls.every(control => control && row.element.contains(control));
  });
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
  const canCarry = sameRows && listControlsAttached(previous.rows, previous.mode);
  const selectedKeys = canCarry
    ? checkedListRowKeys(rowsWithListChecks(previous.rows, previous.mode))
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

function resetListSelectionState() {
  restoreNativeListCheckboxes(listSelectionState?.rows);
  removeOwnedListCheckboxes();
  listSelectionState = null;
}

function tryInsertListSelection(kind) {
  const expectedKind = kind === 'pr-list' ? 'pr' : 'issue';
  const rows = readListRows(document, expectedKind);
  if (rows.length === 0) {
    resetListSelectionState();
    return false;
  }

  syncListSelectionControls(kind, rows, listCheckboxMode(rows));
  return true;
}

// Create the custom command button next to the PR branch or the issue badge (emoji icon or text pill)
function createCommandIconButton(buttonConfig, index, { action, className }) {
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

  onUserClick(button, async () => {
    const originalText = button.textContent;
    button.textContent = '⏳';
    button.disabled = true;

    try {
      await runButtonCommand(action, index, buttonConfig);
      button.textContent = '✅';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 1500);
    } catch (error) {
      console.error('command error:', error);
      button.textContent = '❌';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 2000);
    }
  });

  return button;
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
async function tryInsertPRButtons() {
  // Skip if the buttons are already there
  if (document.querySelector('.terminal-cmd-btn')) {
    return true;
  }

  // New GitHub UI: find the PR's source branch link
  const match = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+/);
  if (!match) return false;

  // Cross-fork PRs: the head ref link can point at the fork's path, so search every tree link
  const branchLinks = document.querySelectorAll('a[href*="/tree/"]');

  // Find the branch link that is visible on screen
  let headBranchLink = null;
  for (const link of branchLinks) {
    const rect = link.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && rect.top < 300 && rect.top > 0) {
      headBranchLink = link;
    }
  }

  if (!headBranchLink) return false;

  const buttons = await loadButtonConfigs('pr');
  if (!buttons) return false; // read failed; the poll retries rather than drawing something that would refuse

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
      action: 'execute_command', className: 'terminal-cmd-btn',
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
async function tryInsertIssueButtons() {
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  const row = issueBadgeRow();
  if (!row) return false;

  const buttons = await loadButtonConfigs('issue');
  if (!buttons) return false;

  // While awaiting, another trigger (the poll, the MutationObserver, a turbo event) may have
  // inserted them first
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  buttons.forEach((config, index) => {
    row.appendChild(createCommandIconButton(config, index, {
      action: 'execute_issue_command', className: 'terminal-issue-btn',
    }));
  });

  return true;
}

// Add the buttons to the repository header (returns true on success)
async function tryInsertRepoButtons() {
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  const header = document.querySelector('header[role="banner"]');
  // Private repository: the breadcrumb item with the lock icon / public: after the repository name link
  let anchor = header?.querySelector('svg.octicon-lock');
  if (!anchor) {
    const pathMatch = location.pathname.match(/^\/([^/]+\/[^/]+)/);
    if (!pathMatch) return false;
    anchor = header?.querySelector(`a[href="/${pathMatch[1]}"]`);
  }
  if (!anchor) return false;

  const buttons = await loadButtonConfigs('repo');
  if (!buttons) return false;

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
async function tryInsertButton() {
  const target = pageTargetOfUrl(location.href);
  if (!target) return false;

  let result = false;

  // Repository, PR, and issue pages all get the repository buttons in the header
  result = await tryInsertRepoButtons() || result;

  // PR and issue pages also get their own custom command buttons (configured separately)
  if (target.kind === 'pr') {
    result = await tryInsertPRButtons() || result;
  } else if (target.kind === 'issue') {
    result = await tryInsertIssueButtons() || result;
  } else if (target.kind === 'pr-list' || target.kind === 'issue-list') {
    result = tryInsertListSelection(target.kind) || result;
  }

  return result;
}

// Wrap the History API to detect URL changes
let lastUrl = location.href;
let lastTarget = pageTargetOfUrl(location.href);

// Our buttons belong to the page they were drawn on. GitHub navigates without a reload, and the
// insert functions bail out as soon as they see a button already there — so buttons drawn for PR #1
// could survive onto PR #2, where their position and the header around them mean something else.
// Removing them makes the next insert redraw for the page that is actually showing.
function removeInsertedButtons() {
  document.querySelectorAll('.terminal-cmd-btn, .terminal-issue-btn, .terminal-open-btn')
    .forEach(button => button.remove());
  resetListSelectionState();
}

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

// Detect History API events
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
        // Insert the buttons if the added node is, or contains, a relevant element
        if (node.classList?.contains('gh-header-actions') ||
            node.classList?.contains('AppHeader-context-full') ||
            node.querySelector?.('.gh-header-actions') ||
            node.querySelector?.('.AppHeader-context-full') ||
            (listKind && readListRows(node, listKind).length > 0)) {
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
