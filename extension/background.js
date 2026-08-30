importScripts(
  'i18n.js',
  'defaults.js' // the single source of truth for button defaults and presets
);

const NATIVE_HOST_NAME = 'com.dazebug.terminal_checkout';

// Pull owner/repo — and the number, on PR and issue pages — out of a GitHub URL. The extension icon
// can be clicked on any tab, so the origin is compared whole rather than matched as a string
// (`example.com/github.com/foo/bar` would pass a string match), and "is this a repository page?" is
// left to the same decision content.js makes.
// One reader for the four parts a request is built from (defaults.js), shared with the content
// script and with the final gate below, so every side describes a page the same way — including
// what counts as our origin.
function parseGitHubUrl(url) {
  return pageTargetOfUrl(url);
}

// Extract the branch name and the base branch from the DOM
function getBranchAndMainFromDOM() {
  // The location is read here, in the same synchronous pass as the branch, so the two cannot come
  // from different pages: the caller compares it against the page the click came from.
  // The whole href, not just the path — a path cannot say which origin served it, and the caller's
  // check is only as good as what it is given (`pageTargetOfUrl` in defaults.js).
  const href = location.href;
  const match = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+/);
  if (!match) return null;

  // Cross-fork PRs: the head ref link can point at the fork's path, so search every tree link
  const branchLinks = document.querySelectorAll('a[href*="/tree/"]');

  let baseBranch = null;
  let headBranch = null;

  for (const link of branchLinks) {
    const rect = link.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && rect.top < 300 && rect.top > 0) {
      const href = link.getAttribute('href');
      const branchMatch = href.match(/\/tree\/(.+)$/);
      if (branchMatch) {
        const branch = decodeURIComponent(branchMatch[1]);
        if (!baseBranch) {
          baseBranch = branch; // first visible one = base ref
        }
        headBranch = branch; // last visible one = head ref
      }
    }
  }

  if (headBranch) return { branch: headBranch, detectedMain: baseBranch, href };

  // Legacy UI fallback 1: head-ref element
  const headRef = document.querySelector('.head-ref a, .head-ref span');
  if (headRef) {
    const baseRef = document.querySelector('.base-ref a, .base-ref span');
    return {
      branch: headRef.textContent.trim(),
      detectedMain: baseRef ? baseRef.textContent.trim() : null,
      href,
    };
  }

  // Legacy UI fallback 2: commit-ref
  const branchElement = document.querySelector('.commit-ref.head-ref');
  if (branchElement) {
    const baseElement = document.querySelector('.commit-ref.base-ref');
    return {
      branch: branchElement.textContent.trim(),
      detectedMain: baseElement ? baseElement.textContent.trim() : null,
      href,
    };
  }

  return null;
}

// Read the default branch out of the repository info GitHub embeds in the page. This is the
// repository's own default, not the branch being viewed, so it comes out right on `/tree/maint`
// too, and on a fork whose default branch differs from upstream's (measured).
//
// The code view and issue detail pages carry this info, but the issue list, pulls, and Actions tabs
// do not (measured), so in those cases fetch the repository home and read it from there. That fetch
// has to happen right here — on the page: called from the service worker it would go out from the
// extension origin, and the same URL comes back without this info (measured: on the issue list a
// master repository came out as main).
//
// chrome.scripting injects this function on its own, so it cannot reference outer constants or helpers.
async function getDefaultBranchFromPage(owner, repo) {
  const pattern = /"defaultBranch"\s*:\s*"([^"]+)"/;
  // Read alongside the answer, every time. Capturing the location once at the top was exactly
  // backwards: if the page moved while the fetch below was in flight, the answer came back stamped
  // with the page we had left, and the caller's check agreed with it and let the command through.
  // The location has to describe the page that exists when the answer does — and it is the whole
  // href, because a path cannot say which origin served it.
  for (const script of document.querySelectorAll('script[type="application/json"]')) {
    const match = script.textContent.match(pattern);
    if (match) return { branch: match[1], href: location.href }; // synchronous: same page
  }
  try {
    const html = await (await fetch(`/${owner}/${repo}`)).text();
    return { branch: html.match(pattern)?.[1] || null, href: location.href };
  } catch {
    return { branch: null, href: location.href };
  }
}

// null when it can't be read — the caller falls back to the override or the global default
async function detectDefaultBranch(tab, owner, repo, clicked) {
  let read;
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: getDefaultBranchFromPage,
      args: [owner, repo],
    });
    read = results[0]?.result;
  } catch (error) {
    console.error('Could not detect default branch:', error);
    return null;
  }
  // Outside the catch: a page that moved is a refusal, not a detection failure to shrug off
  assertSamePage(clicked, read?.href);
  return read?.branch || null;
}

// Resolving the main branch: storage override → detected from the page → global default
async function resolveMainBranch(repo, detectedMain) {
  const data = await chrome.storage.sync.get(['repoMainBranch', 'defaultMain']);
  // Storage is not our data here either. The same validator the options page uses (defaults.js)
  // decides what counts as a branch: `{widget: 42}` used to send `main=42` to the app, and a stored
  // string "abc" answered `Object.hasOwn("abc", "0")` — making "a" the branch of a repository
  // called `0`. One shape verdict for every reader.
  const { defaultMain, overrides } = readStoredMainBranch(data);

  // 1. Per-repository override. `repo` comes out of the page URL, so it reaches this lookup as an
  // arbitrary string — and a plain object answers `overrides['constructor']` with an inherited
  // member, which would then be passed on as if it were a branch name. Only an own property counts.
  if (overrides && Object.hasOwn(overrides, repo) && overrides[repo]) return overrides[repo];

  // 2. Value read off the page — the base ref on a PR, the repository's default branch on
  //    repository and issue pages
  if (detectedMain) return detectedMain;

  // 3. Global default
  return defaultMain || DEFAULT_MAIN;
}

async function loadButtons(kind) {
  const { storageKey, defaults } = BUTTON_KINDS[kind];
  const data = await chrome.storage.sync.get([storageKey]);
  // Same validation as the content script and the options page — a stored entry that is not a
  // button would otherwise throw here, and the click would fail with nothing explaining why
  return readStoredButtons(data[storageKey], defaults);
}

// The page a request is built for has to be the page the click came from — at the moment the tab is
// asked, and again at the moment its DOM is read.
//
// Those two used to be different instants. The PR number was parsed from `sender.tab.url` when the
// message arrived, while the branch was read out of the DOM some milliseconds later; a navigation in
// between produced a request carrying one PR's number and another PR's branch. The button
// fingerprint cannot catch that — a button is drawn for a section, not for a page — so the page is
// its own check.
//
// `clicked` is a comparison key and never a source: every value still comes from the tab and its
// DOM, so a message can cause a refusal but cannot name its own repository. The extension-icon path
// sends no *fingerprint* — nothing was drawn for it to disagree with — but it does send a target,
// read from the tab when the icon was pressed, so it takes this same gate.
//
// Like `BUTTON_CHANGED_ERROR`, this is **not drawn anywhere**: the content script throws it and its
// click handler turns it into `❌` plus a `console.error`. English, therefore — and on the
// same trigger, since displaying it would mean sending an id from this worker, which has no render
// locale, rather than a sentence.
const PAGE_CHANGED_ERROR = 'The page changed while this was running — reload and try again.';
const LIST_SELECTION_CHANGED_ERROR =
  'The selected list rows changed while this was running — reload and try again.';

// Internal coherence: the values a single read produced describe one page. This is what the final
// gate below cannot answer — that the number and the branch belong together — so the two are not
// alternatives.
function assertSamePage(clicked, href) {
  if (!sameTarget(clicked, pageTargetOfUrl(href))) throw new Error(PAGE_CHANGED_ERROR);
}

// Read the page's own idea of where it is. `chrome.scripting` injects this on its own, so it cannot
// reference anything outside itself.
function readCurrentHref() {
  return location.href;
}

// The final gate. Asked once, immediately before the command leaves, so every await behind it is
// covered together and there is no next await to forget.
//
// It asks the *document*, not `chrome.tabs.get`. A `Tab`'s url is documented as the last **committed**
// URL, and GitHub navigates with `pushState`, which commits nothing — Chrome exposes those separately
// as `webNavigation.onHistoryStateUpdated`. So a tab record can honestly report the page we left, and
// a gate built on it would agree with the click and let the command through. `location` inside the
// page is the page's own answer and cannot lag behind itself. (This is the mechanism the DOM reads
// already use, so it brings no new permission.)
//
// A failure to inject is a refusal, not a shrug: the usual reason is that the page is no longer there.
//
// The caller must send with no await in between, or this becomes another check with a gap after it.
async function assertRequestIsCoherent(tab, { clicked, source }) {
  let current;
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: readCurrentHref,
    });
    current = pageTargetOfUrl(results[0]?.result ?? '');
  } catch {
    throw new Error(PAGE_CHANGED_ERROR); // the tab is gone, or we can no longer reach it
  }
  if (!requestIsCoherent({ clicked, source, current })) throw new Error(PAGE_CHANGED_ERROR);
}

// The worker's second read must be self-contained: chrome.scripting serializes only this function
// into the tab, not defaults.js or any helper from this worker. It mirrors the content selector and
// the all-or-none control rule, then returns only the current selected keys/titles and href.
function readListSelectionFromPage(expected) {
  const rowSelector = '[role="row"], [role="listitem"], li, div[class~="Box-row"]';
  const ownedClass = 'terminal-list-checkbox';
  const origin = 'https://github.com';

  function parseAnchor(href, text) {
    if (typeof href !== 'string') return null;
    let parsed;
    try {
      parsed = new URL(href, origin);
    } catch {
      return null;
    }
    if (parsed.origin !== origin) return null;
    const match = parsed.pathname.match(/^\/([^/]+)\/([^/]+)\/(pull|issues)\/(\d+)\/?$/);
    if (!match) return null;
    const [, owner, repo, pathKind, number] = match;
    const kind = pathKind === 'pull' ? 'pr' : 'issue';
    if (!expected || expected.kind !== kind || owner !== expected.owner || repo !== expected.repo) return null;
    return {
      key: `${owner}/${repo}/${kind}/${number}`,
      kind,
      number,
      title: typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '',
    };
  }

  function checkboxText(control) {
    return [
      control.getAttribute('aria-label'),
      control.getAttribute('name'),
      control.getAttribute('id'),
      control.getAttribute('data-testid'),
      control.getAttribute('title'),
    ].filter(Boolean).join(' ').toLowerCase();
  }

  function isSelectAll(control) {
    if (control.matches('[data-check-all], [data-select-all]')) return true;
    return /\b(?:select|check)\s+all\b|\ball\s+(?:issues|pull requests|items)\b/.test(checkboxText(control));
  }

  function nativeCheckboxes(row) {
    return [...row.querySelectorAll('input[type="checkbox"], [role="checkbox"]')]
      .filter(control => !control.classList.contains(ownedClass))
      .filter(control => !isSelectAll(control));
  }

  function readChecked(control) {
    if (!control) return false;
    if ('checked' in control) return control.checked === true;
    return control.getAttribute('aria-checked') === 'true';
  }

  const rowsByKey = new Map();
  for (const anchor of document.querySelectorAll('a[href]')) {
    const parsed = parseAnchor(anchor.getAttribute('href') ?? anchor.href, anchor.textContent);
    if (!parsed) continue;
    const element = anchor.closest(rowSelector);
    if (!element) continue;
    const native = nativeCheckboxes(element);
    const candidate = { ...parsed, element, native, owned: element.querySelector(`.${ownedClass}`) };
    const current = rowsByKey.get(parsed.key);
    if (!current || (native.length > 0 && current.native.length === 0) ||
        parsed.title.length > current.title.length) {
      rowsByKey.set(parsed.key, candidate);
    }
  }

  const rows = [...rowsByKey.values()];
  // In owned mode the native controls remain in the DOM but are hidden, so their presence alone is
  // not enough to select them. The owned controls are the mode marker content.js installs for every
  // row during a partial-coverage transition.
  const nativeMode = rows.length > 0 && rows.every(row => row.native.length > 0 && !row.owned);
  const selected = [];
  for (const row of rows) {
    const control = nativeMode ? row.native[0] : row.owned;
    if (readChecked(control)) selected.push({ key: row.key, title: row.title });
  }
  return { href: location.href, selected };
}

// The button a click meant, or a refusal.
//
// This is a *second* read: the page did its own when it drew the button, and the settings can have
// moved in between — another device saved, someone reordered the list — or the page may be showing
// something its own read never returned. Running whatever now sits at that index would run a command
// the user never saw, so a click brings a fingerprint of what it was going to run and it has to
// match. The index says which button, the fingerprint says what it runs, and the pair is the
// identity this check is made of (defaults.js).
//
// The command still comes from here, from storage, never from the message: the fingerprint can only
// cause a refusal, not introduce a command of its own.
async function clickedButton(kind, index, shown) {
  const button = (await loadButtons(kind))[index];
  if (!button) throw new Error(`Button index ${index} not found`);
  if (!clickMatchesWhatWasShown(button, shown)) throw new Error(BUTTON_CHANGED_ERROR);
  return button;
}

// Hand one command to the app and interpret only the command outcome. Locale metadata may still be
// present while an old app overlaps, but this extension neither records nor forwards it: Chrome
// owns the extension language.
async function sendToNativeHost(message) {
  let response;
  try {
    response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch (error) {
    console.log('Native host error:', error);
    throw error;
  }
  console.log('Native host response:', response);
  const verdict = nativeOutcome(response);
  if (verdict.failed) throw new Error(verdict.error);
  return verdict.response;
}

// Unlike the single-command path, an app-level `{success:false, items:[...]}` is a normal batch
// response. Only a missing or malformed native envelope is a transport failure at this boundary.
function batchNativeOutcome(response) {
  if (!response || typeof response !== 'object' || Array.isArray(response) ||
      typeof response.success !== 'boolean') {
    return { failed: true, error: 'native host returned no result' };
  }
  return { failed: false, response };
}

async function sendBatchToNativeHost(message) {
  let response;
  try {
    response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch (error) {
    console.log('Native host error:', error);
    throw error;
  }
  console.log('Native host response:', response);
  const verdict = batchNativeOutcome(response);
  if (verdict.failed) throw new Error(verdict.error);
  return verdict.response;
}

// Run a single button — variable substitution and claude input delivery are the app's job, so we
// only send the raw material
async function runButton(button, variables, page) {
  // The one place every command passes through, and therefore the only place this check has to be.
  // Everything from here to the send is synchronous **on purpose**: an await in between would make
  // this one more check with a gap behind it, which is the shape of every defect this loop has been
  // closing. sendToNativeHost hands the message to Chrome as its own first statement.
  //
  // That closes the window **inside this script** and nothing more. Handing the message to Chrome is
  // not the command running: it crosses a native-messaging IPC, and the page can move between the
  // hand-off and the moment the app acts on it. So the check and the execution are **not atomic** —
  // this is the same TOCTOU residual as the get↔set window on the options page, accepted for the
  // same reason: closing it would need a compare-and-set the boundary does not offer. The app cannot
  // supply one either; it has no view of the browser's pages to re-check against.
  await assertRequestIsCoherent(page.tab, page);
  // What this click executes, normalized once, in defaults.js — the same call the fingerprint is
  // taken of. Trimming the claude inputs and dropping the empty ones used to happen here, so two
  // buttons that produced the identical message could still fail the fingerprint check.
  const { command, claudeInputs } = executionPayload(button);
  const message = { command_template: command, variables };
  // Inputs to type, in order, into the claude session the command starts (the app delivers them
  // once it has confirmed claude is up)
  if (claudeInputs.length) message.claude_inputs = claudeInputs;
  await sendToNativeHost(message);
}

// Run a custom command (PR page)
async function executeCommand(tab, buttonIndex, shown, clicked) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'pr') throw new Error('Not a GitHub PR page');

  const button = await clickedButton('pr', buttonIndex, shown);

  // Extract the branch and the base branch from the DOM
  const results = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: getBranchAndMainFromDOM
  });

  const domResult = results[0]?.result;
  if (!domResult?.branch) throw new Error('Could not extract branch name');
  // The authoritative check: the branch below and the number above have to describe one page, and
  // this is the page the branch was actually read from, origin included
  assertSamePage(clicked, domResult.href);

  const main = await resolveMainBranch(target.repo, domResult.detectedMain);

  // Which terminal to run in is decided by the Terminal Checkout app's settings
  console.log(`Executing command: repo=${target.repo}, branch=${domResult.branch}, main=${main}`);
  const variables = {
    repo: target.repo,
    owner: target.owner,
    number: target.number,
    branch: domResult.branch,
    main,
    branch_underbar: domResult.branch.replace(/\//g, '_'),
  };
  // {base}: the branch this PR will be merged into. Unlike {main}, which goes through the override
  // and the global default, only the value read off the page is used — if it couldn't be read we
  // don't pass it at all, so the app rejects it as not provided (silently substituting another
  // branch would mean merging or rebasing onto the wrong one)
  if (domResult.detectedMain) variables.base = domResult.detectedMain;
  // `target` is where these variables were read from — the third axis of the gate
  await runButton(button, variables, { tab, clicked, source: target });
}

// Run a custom command (issue page). An issue has no head branch, so the {branch} family of
// variables isn't passed — if a template uses one, the app rejects it with
// "Variable {branch} not provided"
async function executeIssueCommand(tab, buttonIndex, shown, clicked) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'issue') throw new Error('Not a GitHub issue page');

  const button = await clickedButton('issue', buttonIndex, shown);

  // detectDefaultBranch checks the page it read from against the click as well — the default branch
  // it finds is embedded in whatever page is showing, which need not be this repository's
  const detected = await detectDefaultBranch(tab, target.owner, target.repo, clicked);
  const main = await resolveMainBranch(target.repo, detected);
  console.log(`Executing issue command: repo=${target.repo}, number=${target.number}, main=${main}`);
  await runButton(button, {
    repo: target.repo,
    owner: target.owner,
    number: target.number,
    main,
  }, { tab, clicked, source: target });
}

// Run a custom command (repository page). Unlike PRs and issues there is neither a branch nor a
// number, so only {repo}, {owner}, and {main} are passed
async function executeRepoCommand(tab, buttonIndex, shown, clicked) {
  // Repository buttons are also attached to the header of PR and issue pages, so don't check kind
  const target = parseGitHubUrl(tab.url);
  if (!target) throw new Error('Not a GitHub repo page');

  const button = await clickedButton('repo', buttonIndex, shown);

  const detected = await detectDefaultBranch(tab, target.owner, target.repo, clicked);
  const main = await resolveMainBranch(target.repo, detected);
  console.log(`Executing repo command: repo=${target.repo}, main=${main}`);
  await runButton(button, { repo: target.repo, owner: target.owner, main }, { tab, clicked, source: target });
}

const LIST_BATCH_SELECTION_ERRORS = {
  'not-array': 'List selection is not an array.',
  empty: 'List selection is empty.',
  'too-many': `List selection exceeds the ${MAX_BATCH_ITEMS}-item limit.`,
  'invalid-row': 'List selection contains an invalid row.',
};
const LIST_BUTTON_VARIABLE_ERROR = 'List button uses a variable unavailable on this page.';

function listBatchSelectionError(verdict) {
  return LIST_BATCH_SELECTION_ERRORS[verdict.error] || 'List selection is invalid.';
}

async function executeListBatch(tab, buttonIndex, shown, clicked, selected) {
  const target = parseGitHubUrl(tab?.url);
  if (target?.kind !== 'pr-list' && target?.kind !== 'issue-list') {
    throw new Error('Not a GitHub list page');
  }

  const snapshotVerdict = validateListBatchSelection(selected);
  if (!snapshotVerdict.valid) throw new Error(listBatchSelectionError(snapshotVerdict));

  const button = await clickedButton(target.kind, buttonIndex, shown);
  if (!buttonUsesAllowedVariables(target.kind, button)) {
    throw new Error(LIST_BUTTON_VARIABLE_ERROR);
  }

  const expectedKind = target.kind === 'pr-list' ? 'pr' : 'issue';
  let current;
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: readListSelectionFromPage,
      args: [{ kind: expectedKind, owner: target.owner, repo: target.repo }],
    });
    current = results[0]?.result;
  } catch {
    throw new Error(PAGE_CHANGED_ERROR);
  }

  assertSamePage(clicked, current?.href);
  const itemKeys = (current?.selected || []).map(row => row?.key).filter(key => typeof key === 'string');
  const currentVerdict = validateListBatchSelection(current?.selected);
  if (!currentVerdict.valid || !sameListSelectionKeys(selected, current.selected)) {
    throw new Error(LIST_SELECTION_CHANGED_ERROR);
  }

  const items = buildListBatchItems(target, current.selected);
  if (!items) throw new Error(LIST_SELECTION_CHANGED_ERROR);
  const message = buildListBatchRequest(button, items);

  // The final page check is deliberately the last await before the native hand-off.
  await assertRequestIsCoherent(tab, { clicked, source: target });
  const batch = await sendBatchToNativeHost(message);
  return { batch, itemKeys };
}

// Check whether this page really rendered as a repository. Only pages GitHub drew as a repository
// have the repository name link in the header (a lock icon if it is private); 404s and non-
// repository paths don't (measured). The path pattern and the reserved word list alone can't tell
// apart a repository that doesn't exist or a GitHub path that doesn't exist yet.
// chrome.scripting injects this function on its own, so it cannot reference outer constants or helpers.
function isRepoPageFromDOM(owner, repo) {
  const header = document.querySelector('header[role="banner"]');
  if (!header) return false;
  return !!(header.querySelector(`a[href="/${owner}/${repo}"]`) || header.querySelector('svg.octicon-lock'));
}

// A button click doesn't need this check — the content script only attaches buttons once it has
// found the same evidence, so the click itself means this is a repository page. The path that does
// need it is the extension icon click, which never goes through the content script
async function isRepoPage(tab, owner, repo) {
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: isRepoPageFromDOM,
      args: [owner, repo],
    });
    return results[0]?.result === true;
  } catch (error) {
    console.error('Could not verify repository page:', error);
    return false;
  }
}

// Page type → run function. The extension icon click and messages from content.js share one table
const RUN_BY_KIND = { pr: executeCommand, issue: executeIssueCommand, repo: executeRepoCommand };
const ACTION_KIND = { execute_command: 'pr', execute_issue_command: 'issue', execute_repo_command: 'repo' };

// List pages have no DOM selection in the icon path. Preserve the old repository-button behavior
// by routing those kinds to the existing repo runner; list batch actions start only in content.js.
function iconRunKind(kind) {
  return kind === 'pr-list' || kind === 'issue-list' ? 'repo' : kind;
}

// Extension icon click handler → run the first button for this page (repository buttons when it is
// neither a PR nor an issue)
chrome.action.onClicked.addListener(async (tab) => {
  const target = parseGitHubUrl(tab.url);
  if (!target || !await isRepoPage(tab, target.owner, target.repo)) {
    console.log('Not a GitHub repository page');
    return;
  }
  try {
    // No fingerprint: nothing was drawn for this click, so there is no rendered button that could
    // disagree with what is stored. "The first button for this page" is the whole of the request.
    //
    // The page, though, still has to hold still. `target` was read from the tab when the icon was
    // pressed, so it is the same kind of comparison key a page click sends — and it makes the icon
    // take the same final gate. It is not a source: every value still comes from the tab and its
    // DOM. (Whether the icon ought to run the button the user can *see* is a separate question,
    // still open — this is only about the tab moving underneath the one it does run.)
    await RUN_BY_KIND[iconRunKind(target.kind)](tab, 0, undefined, target);
  } catch (error) {
    console.error('Error executing command:', error); // an icon click has no button to show the failure on
  }
});

// Receive messages from content.js
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // A message is an arbitrary value — `null` reaches here, and reading `.action` off it throws
  // before any check below can run. Establish that there is a string to look up, then look it up as
  // an own property: an inherited member ("constructor", "toString") would otherwise pass the
  // truthiness check and fail as "not a function" one line later.
  if (typeof message?.action !== 'string') return;

  if (message.action === LIST_BATCH_ACTION) {
    if (!Number.isInteger(message.buttonIndex)) {
      sendResponse({ success: false, error: 'Invalid list batch button index.' });
      return;
    }
    if (typeof message.shown !== 'string') {
      sendResponse({ success: false, error: 'Invalid list batch button fingerprint.' });
      return;
    }
    if (!isPageTarget(message.target)) {
      sendResponse({ success: false, error: 'Invalid list batch page target.' });
      return;
    }
    const snapshotVerdict = validateListBatchSelection(message.selected);
    if (!snapshotVerdict.valid) {
      sendResponse({ success: false, error: listBatchSelectionError(snapshotVerdict) });
      return;
    }

    executeListBatch(sender.tab, message.buttonIndex, message.shown, message.target, message.selected)
      .then(({ batch, itemKeys }) => sendResponse({ success: true, batch, itemKeys }))
      .catch((error) => {
        sendResponse({ success: false, error: error.message });
      });
    return true;
  }

  const kind = Object.hasOwn(ACTION_KIND, message.action) ? ACTION_KIND[message.action] : null;
  if (!kind) return;
  // The index picks a button out of an array; anything that is not one is not a request we can serve
  if (!Number.isInteger(message.buttonIndex)) return;
  // A click from a page always says which button it drew. Only the extension-icon path may omit it,
  // and that one never comes through here.
  if (typeof message.shown !== 'string') return;
  // And which page it was clicked on. A message without one cannot be checked against anything —
  // which is not the same as passing the check, and used to be treated as if it were.
  if (!isPageTarget(message.target)) return;

  RUN_BY_KIND[kind](sender.tab, message.buttonIndex, message.shown, message.target).then(() => {
    sendResponse({ success: true });
  }).catch((error) => {
    sendResponse({ success: false, error: error.message });
  });
  return true; // return true to respond asynchronously
});
