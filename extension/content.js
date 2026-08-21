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
  const phases = isTextFace(face)
    ? { busy: 'Opening...', done: 'Done!', error: 'Error!' }
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

  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();

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
// The index says which button; the fingerprint says which button it *was* when it was drawn. The
// service worker reads storage again for the command, and refuses if the two disagree — so what
// runs is always what was on screen (buttonFingerprint in defaults.js).
async function runButtonCommand(action, index, config) {
  const response = await chrome.runtime.sendMessage({
    action, buttonIndex: index, shown: buttonFingerprint(config),
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
    console.warn('Terminal Checkout: could not read your buttons, will retry —', error);
    return null;
  }
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

  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();

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

// Insert the buttons according to the page type
async function tryInsertButton() {
  const pageType = pageTypeOf(location.pathname);
  if (!pageType) return false;

  let result = false;

  // Repository, PR, and issue pages all get the repository buttons in the header
  result = await tryInsertRepoButtons() || result;

  // PR and issue pages also get their own custom command buttons (configured separately)
  if (pageType === 'pr') {
    result = await tryInsertPRButtons() || result;
  } else if (pageType === 'issue') {
    result = await tryInsertIssueButtons() || result;
  }

  return result;
}

// Wrap the History API to detect URL changes
let lastUrl = location.href;

function onUrlChange() {
  if (location.href !== lastUrl) {
    lastUrl = location.href;
    // On a URL change, wait a moment before trying to insert the buttons
    setTimeout(tryInsertButton, 300);
  }
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

// MutationObserver: detect when the header area is added
const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        // Insert the buttons if the added node is, or contains, a relevant element
        if (node.classList?.contains('gh-header-actions') ||
            node.classList?.contains('AppHeader-context-full') ||
            node.querySelector?.('.gh-header-actions') ||
            node.querySelector?.('.AppHeader-context-full')) {
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
