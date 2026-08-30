// Single source of truth for button defaults, presets, and page-type detection. content.js
// (rendering), background.js (execution), and options.js (editing) all have to see the same
// values, so they live here and nowhere else.
// The content script, the service worker, and the options page all load this file first.

// Every preset opens with `{cd}` — the clause that moves into the repository. Its value comes from
// the app, not from this file: with no base directory configured it is exactly `z {repo}`, and with
// one configured it falls back to `cd <base>/<repo>` and
// then to cloning. A bare `z {repo}` exits non-zero on a cold zoxide DB, which kills the whole `&&`
// chain with nothing to see anywhere (issue #30).
//
// A preset is *named* by its `id` and *shown* by its `name` and `face`. Those last two are display
// text and will be translated, so nothing may find a preset by them: the dropdown's value, and the
// default buttons' reference back to the preset they were built from, both go through the id.
// Ids are ASCII `<kind>.<what>` and never change — a translation is not a reason to touch one.
//
// An id names a preset and never a button. It is not written to storage: a saved button is a
// snapshot of the preset's fields (`toStoredButton`), and putting a persistent id into the stored
// schema would be a SETTINGS_VERSION bump, which is a different piece of work entirely.
//
// A preset. Its `id`, `command` and `face` are fixed; its `name` is resolved **when it is read**
// rather than when this file loads.
//
// `name` is an accessor over the dictionaries. A value read at load time would freeze the language
// the context started in, so presets are built here and never spread: object spread evaluates
// accessors and would store their current values.
//
// **A face is a literal, never a translated string.** `isTextFace` gives a face with letters or
// digits a different shape from an emoji-only one, so a translated face can change the shape of a
// button from one language to the next while the code that draws it is unchanged. A face that has
// to say a word says it in `name`, which is where the options page reads it.
function definePreset({ id, nameKey, face, command, claudeInputs }) {
  const preset = { id, command, face };
  if (claudeInputs) preset.claudeInputs = claudeInputs;
  Object.defineProperty(preset, 'name', { get: () => tr(nameKey), enumerable: true });
  return preset;
}

// PR pages: buttons next to the branch name. The { } is grouping, not a subshell — cd has to stick
// in the current shell, so ( ) must not be used
const PR_PRESETS = [
  // If checkout fails (branch already checked out in a worktree, etc.), move to the worktree at the conventional path
  definePreset({
    id: 'pr.checkout', nameKey: 'ext.preset.pr.checkout', face: '⏏️',
    command: '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  }),
  definePreset({
    id: 'pr.checkoutClaude', nameKey: 'ext.preset.pr.checkoutClaude', face: '🤖',
    command: '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude',
  }),
  definePreset({
    id: 'pr.worktreeClaude', nameKey: 'ext.preset.pr.worktreeClaude', face: '🌳',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude',
  }),
  definePreset({
    id: 'pr.worktree', nameKey: 'ext.preset.pr.worktree', face: '🪵',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}',
  }),
  // A leading `!` is typed into claude's shell mode, so the command really runs in that session
  definePreset({
    id: 'pr.review', nameKey: 'ext.preset.pr.review', face: '🔍',
    command: '{cd} && claude',
    claudeInputs: ['!gh pr view {number} --comments', '!gh pr diff {number}'],
  }),
];

// PR list pages: one terminal session per selected row. The app can resolve the branch from the PR
// number through `gh`, so the list has no need to invent a `{branch}` or `{base}` value.
// Every row must get its own worktree — a fan-out that checks rows out in the shared `{cd}` tree
// has the later rows switching the branch under the earlier sessions. `--detach` on both commands
// keeps the fan-out conflict-free: no local branch is created, so rows cannot collide with each
// other or with a worktree that already holds the PR's branch, and the FETCH_HEAD that
// `gh pr checkout` resolves is a per-worktree ref, so parallel rows cannot cross.
const PR_LIST_PRESETS = [
  definePreset({
    id: 'pr-list.checkoutClaude', nameKey: 'ext.preset.prList.checkoutClaude', face: '🤖',
    command: '{cd} && ([ -d ../{repo}-pr-{pr} ] || git worktree add -f --detach ../{repo}-pr-{pr}) && cd ../{repo}-pr-{pr} && gh pr checkout {pr} --detach && claude',
  }),
];

// Issue pages: buttons on the status badge row. There is no head branch, so the {branch} family and {base} are unavailable
const ISSUE_PRESETS = [
  definePreset({
    id: 'issue.read', nameKey: 'ext.preset.issue.read', face: '📋',
    command: '{cd} && claude',
    claudeInputs: [
      '!gh issue view {number}',
      '!gh issue view {number} --comments',
      // Numbers of the issues and PRs that mention this issue. The --json fields only surface the "closing PR", so use the timeline
      '!gh api repos/{owner}/{repo}/issues/{number}/timeline --jq \'[.[]|select(.event=="cross-referenced")|.source.issue.number]\'',
    ],
  }),
  definePreset({
    id: 'issue.startWork', nameKey: 'ext.preset.issue.startWork', face: '🌳',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-issue-{number} ] || git worktree add -f ../{repo}-issue-{number} -b issue-{number} origin/{main}) && cd ../{repo}-issue-{number} && claude',
    claudeInputs: ['!gh issue view {number} --comments'],
  }),
  definePreset({
    id: 'issue.open', nameKey: 'ext.preset.issue.open', face: '📂',
    command: '{cd}',
    claudeInputs: [],
  }),
];

// Issue list pages: the issue number is enough for gh to put the issue discussion in front of claude.
const ISSUE_LIST_PRESETS = [
  definePreset({
    id: 'issue-list.triageClaude', nameKey: 'ext.preset.issueList.triageClaude', face: '📋',
    command: '{cd} && claude',
    claudeInputs: ['!gh issue view {issue} --comments'],
  }),
];

// Repository pages: buttons next to the repository name in the header. All three faces are emoji
// literals, and that is a row-level decision rather than three independent ones: they sit on one
// line, `isTextFace` gives a face with letters or digits a different shape from an emoji-only one,
// and one text pill among two icons makes the row ragged. A literal also keeps `isTextFace`
// answering the same way in every language, which a translated face cannot promise — the previous
// faces were message keys, so `main ⤓` stayed an icon while `Open in Terminal` became a pill.
const REPO_PRESETS = [
  definePreset({
    id: 'repo.open', nameKey: 'ext.preset.repo.open', face: '📂',
    command: '{cd}',
  }),
  definePreset({
    id: 'repo.openClaude', nameKey: 'ext.preset.repo.openClaude', face: '📂🤖',
    command: '{cd} && claude',
  }),
  definePreset({
    id: 'repo.updateMain', nameKey: 'ext.preset.repo.updateMain', face: '⤓',
    command: '{cd} && git checkout {main} && git pull --ff-only',
  }),
];

// The preset an id names, or null. A list search rather than a keyed object: an id arrives from a
// `<select>` the page filled in, and comparing against the entries is the form that cannot answer
// with something off Object.prototype (the same rule the stored-settings readers keep).
function presetById(presets, id) {
  return presets.find(preset => preset.id === id) ?? null;
}

// What the options page's dropdown is built from — the id as the value, the name as the text. The
// pairing lives here rather than in options.js because *which field identifies a preset* is a
// defaults.js decision, and because there is nowhere to assert it on the options page.
function presetOptions(presets) {
  return presets.map(preset => ({ value: preset.id, text: preset.name }));
}

// The button drawn when a section has nothing stored: the preset's fields, plus the id it came from
// so the reference survives its name being translated. `presetId` is edit-state only — every reader
// reaches a button through buttonFields, which keeps the four stored fields and drops the rest.
function defaultFromPreset(presets, id) {
  const preset = presetById(presets, id);
  // Loud at load rather than a default button with no command: a typo here ships a button that
  // reaches the app as an empty command_template and is refused with nothing to explain it.
  if (!preset) throw new Error(`No preset with id ${id}`);
  return {
    presetId: preset.id,
    // Read through to the preset, so the button drawn when nothing is stored is in the language
    // being drawn right now rather than the one this file was loaded in
    get face() { return preset.face; },
    get label() { return preset.name; },
    command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  };
}

const DEFAULT_BUTTONS = [defaultFromPreset(PR_PRESETS, 'pr.checkout')];

const DEFAULT_PR_LIST_BUTTONS = [defaultFromPreset(PR_LIST_PRESETS, 'pr-list.checkoutClaude')];

const DEFAULT_ISSUE_BUTTONS = [defaultFromPreset(ISSUE_PRESETS, 'issue.read')];

const DEFAULT_ISSUE_LIST_BUTTONS = [defaultFromPreset(ISSUE_LIST_PRESETS, 'issue-list.triageClaude')];

const DEFAULT_REPO_BUTTONS = [defaultFromPreset(REPO_PRESETS, 'repo.open')];

// Variables the app fills in on its own, usable on every page. They are deliberately kept out of
// the per-page `variables` lists below, which mean "what the extension actually sends": the app is
// the single source for these values, exactly as it is for the terminal choice, and a request that
// carries one of these names is rejected outright ("Unknown variable: {cd}") rather than merged.
// {cd} = the clause that moves into the repository — see the preset comment at the top of the file.
const APP_VARIABLES = ['cd'];

// Definitions per page type. If the storage keys were scattered across content.js (rendering),
// background.js (execution), and options.js (editing), one of them drifting out of sync would be
// enough to make saved settings silently ignored, so all three files read them from here.
// `variables` is what the extension actually passes on that page — a test pins presets and
// defaults to this list plus APP_VARIABLES (tests/buttons.test.js). Using a variable that is
// neither passed nor app-provided makes the app reject the request, so the button does nothing.
// {base} is only passed when it could be read off the PR page, so it does not always arrive.
const BUTTON_KINDS = {
  pr: {
    storageKey: 'buttons', presets: PR_PRESETS, defaults: DEFAULT_BUTTONS,
    variables: ['repo', 'owner', 'number', 'branch', 'base', 'main', 'branch_underbar'],
  },
  'pr-list': {
    storageKey: 'prListButtons', presets: PR_LIST_PRESETS, defaults: DEFAULT_PR_LIST_BUTTONS,
    variables: ['repo', 'owner', 'pr'],
  },
  issue: {
    storageKey: 'issueButtons', presets: ISSUE_PRESETS, defaults: DEFAULT_ISSUE_BUTTONS,
    variables: ['repo', 'owner', 'number', 'main'],
  },
  'issue-list': {
    storageKey: 'issueListButtons', presets: ISSUE_LIST_PRESETS, defaults: DEFAULT_ISSUE_LIST_BUTTONS,
    variables: ['repo', 'owner', 'issue'],
  },
  repo: {
    storageKey: 'repoButtons', presets: REPO_PRESETS, defaults: DEFAULT_REPO_BUTTONS,
    variables: ['repo', 'owner', 'main'],
  },
};

// A button is visible only when every placeholder in its command and every scheduled claude input
// can be supplied for its page kind. Keeping this predicate here makes the list of variables in
// BUTTON_KINDS the one authority shared by the content script and service worker; the app's own
// renderer remains the final fail-closed check when a request leaves the extension.
function buttonUsesAllowedVariables(kind, button) {
  if (typeof kind !== 'string' || !Object.hasOwn(BUTTON_KINDS, kind)) return false;
  if (!button || typeof button !== 'object' || typeof button.command !== 'string') return false;
  if (button.claudeInputs !== undefined && !Array.isArray(button.claudeInputs)) return false;

  const allowed = new Set([...BUTTON_KINDS[kind].variables, ...APP_VARIABLES]);
  for (const template of [button.command, ...(button.claudeInputs || [])]) {
    if (typeof template !== 'string') return false;
    for (const [, name] of template.matchAll(/\{(\w+)\}/g)) {
      if (!allowed.has(name)) return false;
    }
  }
  return true;
}

// --- Settings schema version ---
// Saved commands are snapshots of the presets at save time, so improving a preset never reaches
// anyone who already pressed Save. The stored version says which generation of the presets a
// settings object has been **reviewed against** — not "was rewritten to". Applying a migration,
// applying part of one, declining it, and resetting to defaults are all reviews; ordinary edits are
// not, and must never move it (see migrations.js).
// This constant is the single source of truth for the current generation, and a test pins the
// registry in `extension/migrations.js` to carry one entry per step up to it.
const SETTINGS_VERSION = 2;

// The version rides alongside the settings in storage.sync, and therefore in the export/import
// JSON, so reviewing once clears the notice on every machine on the account.
const VERSION_KEY = 'version';

// Every key the settings live under, minus the version. options.js derives BACKUP_KEYS from this,
// and "is anything stored at all" — fresh install versus legacy v0 — is decided by it.
const SETTINGS_KEYS = [
  ...Object.values(BUTTON_KINDS).map(kind => kind.storageKey),
  'defaultMain',
  'repoMainBranch',
];

// GitHub path → page type. content.js (button insertion) and background.js (extension icon
// routing) must reach the same verdict — an icon click never goes through the content script, so
// if the two diverge a path like `/settings/profile` reads as a repository and `z profile` runs in
// the terminal.
// Reserved paths that can never appear in the owner position are filtered out. If GitHub adds a
// reserved word that isn't listed here, the worst case is the same misreading as before, so only
// the common ones are covered.
const RESERVED_OWNERS = new Set([
  'settings', 'notifications', 'explore', 'marketplace', 'sponsors', 'topics', 'collections',
  'events', 'codespaces', 'organizations', 'orgs', 'account', 'apps', 'users', 'dashboard',
  'new', 'login', 'logout', 'join', 'pricing', 'features', 'about', 'search', 'stars',
  'issues', 'pulls', 'discussions', 'sitemap', 'security', 'trending', 'enterprises',
]);

// Sub-tabs treated as repository pages — issue and PR detail pages are already filtered out above
const REPO_TABS = 'tree|blob|issues|actions|settings|releases|tags|wiki|security|pulse|graphs|network|projects|commits|branches|pulls|discussions|compare';

function pageTypeOf(pathname) {
  const [, owner, repo] = pathname.split('/');
  if (!owner || !repo || RESERVED_OWNERS.has(owner)) return null;
  // These are exact repository list pages. Keep the slash optional, but do not let a nested path
  // such as `/pulls/extra` borrow the list kind.
  if (/^\/[^/]+\/[^/]+\/pulls\/?$/.test(pathname)) return 'pr-list';
  if (/^\/[^/]+\/[^/]+\/issues\/?$/.test(pathname)) return 'issue-list';
  if (/\/issues\/\d+/.test(pathname)) return 'issue';
  if (/\/pull\/\d+/.test(pathname)) return 'pr';
  if (/^\/[^/]+\/[^/]+\/?$/.test(pathname)) return 'repo';
  return new RegExp(`^/[^/]+/[^/]+/(${REPO_TABS})`).test(pathname) ? 'repo' : null;
}

const DEFAULT_MAIN = 'main';
const MAX_BUTTONS = 3;
const MAX_CLAUDE_INPUTS = 5;
const MAX_BATCH_ITEMS = 8;
const LIST_BATCH_ACTION = 'execute_list_batch';
const LIST_BATCH_RESULT_KEY_PROTOCOL = 1;

// The button's display text. `face` is the current key; `emoji` is kept for values saved by older versions.
function buttonFace(config) {
  return (config.face ?? config.emoji ?? '').trim() || '⏏️';
}

// Draw as a text pill when letters or digits are mixed in, as an icon when it is emoji only.
// content.js (rendering on GitHub) and options.js (preview) share this decision.
function isTextFace(face) {
  return /[\p{L}\p{N}]/u.test(face);
}

// --- Who pressed it, and what page they were on ---

// A command runs because a person clicked something they could see. `dispatchEvent(new
// MouseEvent('click'))` from any script running on the GitHub page — an XSS, another extension —
// reached the same handler and ran the stored command with nobody touching the mouse. `isTrusted` is
// the browser's own word for "a user did this", and it is the only thing that can answer it.
function isUserGesture(event) {
  return event?.isTrusted === true;
}

// Binds a click handler with that guard ahead of it, once, instead of at each call site. The same
// lesson as `userAction` on the options page: an order kept by convention at two call sites is an
// order that gets reversed at the third.
function onUserClick(element, run) {
  element.addEventListener('click', (event) => {
    if (!isUserGesture(event)) {
      console.warn('Terminal Checkout: ignoring a click that did not come from the user.');
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    run(event);
  });
}

// Everything a request is built from that comes out of the URL, read off one pathname in one go.
// The page the user clicked on is a fact with four parts, and taking them from two different reads
// is how a request went out carrying one PR's number and another PR's branch.
function pageTargetOf(pathname) {
  const kind = pageTypeOf(pathname);
  if (!kind) return null;
  const [, owner, repo] = pathname.split('/');
  return { kind, owner, repo, number: pathname.match(/\/(?:pull|issues)\/(\d+)/)?.[1] || null };
}

// Whether two reads landed on the same page. `null` never matches, including against itself: an
// absent target is not agreement, it is the absence of an answer.
function sameTarget(a, b) {
  if (!a || !b) return false;
  return a.kind === b.kind && a.owner === b.owner && a.repo === b.repo && a.number === b.number;
}

// The same four parts from a full URL. A tab reports a URL rather than a pathname, and a page on
// some other **origin** is not a page of ours however its path happens to be shaped.
//
// The origin is compared whole, and that is the point. Naming its parts one at a time is how they
// were closed one at a time: the host was checked and the scheme was not, so `http://github.com/…`
// passed; then both were checked and the port was not, so `https://github.com:8443/…` passed. An
// origin has exactly three parts and `URL.origin` is all three — there is no fourth to forget next
// time. `:443` is normalized away by the parser, so writing out the default port still matches.
//
// What passing wrongly costs: the manifest only injects the content script over https, but the icon
// path never goes through the content script — `activeTab` grants executeScript on whatever tab was
// clicked, and a match pattern with no port matches every port. So a look-alike origin could still
// be read for the branch and the default branch. Its response is not a GitHub document, it is
// whatever was on the wire, and those reads decide what the command runs *against*. The command
// itself still comes from storage; its target would not have.
const GITHUB_ORIGIN = 'https://github.com';

function pageTargetOfUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null; // tabs we have no host permission for hand us nothing
  }
  if (parsed.origin !== GITHUB_ORIGIN) return null;
  return pageTargetOf(parsed.pathname);
}

// A list row's identity comes from GitHub's canonical detail link, never from its position in the
// document. The same shape works for a repository's own links and links to a fork: the owner and
// repository in the href identify the checkout target that `gh` will resolve. When a page target is
// supplied, the row must belong to that exact repository before it can enter the selection set.
function parseListRowAnchor(href, text, expected) {
  if (typeof href !== 'string') return null;

  let parsed;
  try {
    parsed = new URL(href, GITHUB_ORIGIN);
  } catch {
    return null;
  }
  if (parsed.origin !== GITHUB_ORIGIN) return null;

  const match = parsed.pathname.match(/^\/([^/]+)\/([^/]+)\/(pull|issues)\/(\d+)\/?$/);
  if (!match) return null;

  const [, owner, repo, pathKind, number] = match;
  if (expected !== undefined &&
      (typeof expected?.owner !== 'string' || typeof expected?.repo !== 'string' ||
       owner !== expected.owner || repo !== expected.repo)) {
    return null;
  }
  const kind = pathKind === 'pull' ? 'pr' : 'issue';
  const rowTitle = typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '';
  return {
    key: `${owner}/${repo}/${kind}/${number}`,
    owner,
    repo,
    kind,
    number,
    title: rowTitle,
  };
}

// A native checkbox is usable only when every eligible row has one. Mixing GitHub's controls with
// ours would make one visible selection have two different sources of truth, so an empty list is
// no mode and any incomplete coverage selects the all-owned mode.
function listCheckboxMode(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return null;
  return rows.every(row => row?.native === true) ? 'native' : 'owned';
}

function checkedListRowKeys(rows) {
  const keys = [];
  const seen = new Set();
  for (const row of rows || []) {
    if (row?.checked !== true || typeof row.key !== 'string' || seen.has(row.key)) continue;
    seen.add(row.key);
    keys.push(row.key);
  }
  return keys;
}

// Copying checked state by key is the only state transfer permitted when the control source changes.
// It also makes a redraw independent of whatever order GitHub happened to render the rows in.
function carryListRowChecks(rows, selectedKeys) {
  const selected = new Set(selectedKeys || []);
  return (rows || []).map(row => ({ ...row, checked: selected.has(row.key) }));
}

// Control selection is caller-decided: this helper only checks whether the caller-provided control is
// still attached to the row and actually checked.
function attachedCheckedListRowKeys(rows) {
  const keys = [];
  const seen = new Set();
  for (const row of rows || []) {
    if (typeof row.key !== 'string' || seen.has(row.key)) continue;

    const control = row.selectionControl;
    if (!control || typeof control !== 'object') continue;
    if (!row.element?.contains?.(control)) continue;
    if (!isCheckboxChecked(control)) continue;

    seen.add(row.key);
    keys.push(row.key);
  }
  return keys;
}

function isCheckboxChecked(control) {
  if (!control) return false;
  if ('checked' in control) return control.checked === true;
  return control.getAttribute?.('aria-checked') === 'true';
}

function selectedListRows(rows) {
  const selected = [];
  const seen = new Set();
  for (const row of rows || []) {
    if (row?.checked !== true || typeof row.key !== 'string' || seen.has(row.key)) continue;
    seen.add(row.key);
    selected.push({ key: row.key, title: typeof row.title === 'string' ? row.title : '' });
  }
  return selected;
}

function listSelectionStatus(selected, limit = MAX_BATCH_ITEMS) {
  const count = Array.isArray(selected) ? selected.length : 0;
  if (count === 0) return { count, valid: false, error: 'empty' };
  if (count > limit) return { count, valid: false, error: 'too-many' };
  return { count, valid: true, error: null };
}

// A list click carries a snapshot only so the worker can tell whether the document changed while
// the message was in flight. It is never a source for the request, so the boundary checks its shape
// before the worker performs the live DOM read.
function validateListBatchSelection(selection) {
  if (!Array.isArray(selection)) return { valid: false, error: 'not-array' };
  if (selection.length === 0) return { valid: false, error: 'empty' };
  if (selection.length > MAX_BATCH_ITEMS) return { valid: false, error: 'too-many' };

  const seen = new Set();
  for (const row of selection) {
    if (!row || typeof row !== 'object' || Array.isArray(row) ||
        typeof row.key !== 'string' || !row.key || typeof row.title !== 'string' ||
        seen.has(row.key)) {
      return { valid: false, error: 'invalid-row' };
    }
    seen.add(row.key);
  }
  return { valid: true, error: null };
}

// The worker re-reads keys from the current document. Parsing the key is separate from parsing the
// anchor so the item builder can use the document's order without trusting the snapshot's values.
function parseListRowKey(key) {
  if (typeof key !== 'string') return null;
  const match = key.match(/^([^/]+)\/([^/]+)\/(pr|issue)\/(\d+)$/);
  if (!match) return null;
  const [, owner, repo, kind, number] = match;
  return { owner, repo, kind, number };
}

function buildListBatchItems(target, selected) {
  const kind = target?.kind === 'pr-list' ? 'pr' : target?.kind === 'issue-list' ? 'issue' : null;
  if (!kind || typeof target.repo !== 'string' || !validateListBatchSelection(selected).valid) return null;

  const items = [];
  for (const row of selected) {
    const parsed = parseListRowKey(row.key);
    if (!parsed || parsed.kind !== kind || parsed.owner !== target.owner || parsed.repo !== target.repo) {
      return null;
    }
    items.push({ variables: { repo: target.repo, owner: target.owner, [kind]: parsed.number } });
  }
  return items;
}

// The batch protocol's command lives at the top level. A single-command request uses
// `command_template`; putting that key into a batch would make the app reject the otherwise-valid
// items envelope before it could report per-item results.
function buildListBatchRequest(button, items) {
  const { command, claudeInputs } = executionPayload(button);
  const request = { command, items };
  if (claudeInputs.length) request.claude_inputs = claudeInputs;
  return request;
}

// Titles are display data and can change without changing the identity of a selected row. The
// worker therefore compares exact key sets, not array order or the snapshot's title strings.
function sameListSelectionKeys(expected, actual) {
  if (!Array.isArray(expected) || !Array.isArray(actual)) return false;
  const expectedKeys = expected.map(row => row?.key);
  const actualKeys = actual.map(row => row?.key);
  if (expectedKeys.some(key => typeof key !== 'string') || actualKeys.some(key => typeof key !== 'string')) {
    return false;
  }
  const expectedSet = new Set(expectedKeys);
  const actualSet = new Set(actualKeys);
  return expectedSet.size === expectedKeys.length &&
    actualSet.size === actualKeys.length &&
    expectedSet.size === actualSet.size &&
    [...expectedSet].every(key => actualSet.has(key));
}

function buildListBatchMessage(buttonIndex, shown, target, selected) {
  return {
    action: LIST_BATCH_ACTION,
    buttonIndex,
    shown,
    resultKeyProtocol: LIST_BATCH_RESULT_KEY_PROTOCOL,
    target,
    selected,
  };
}

function validateListBatchResultKeyProtocol(message) {
  return message?.resultKeyProtocol === LIST_BATCH_RESULT_KEY_PROTOCOL;
}

// `success` exists at two boundaries: the worker's outer response says whether transport and
// validation reached the app, while `batch.success` is the app's overall command verdict. An app
// validation failure is normal data and must retain its ordered item failures for the result UI.
function interpretListBatchResponse(response) {
  if (!response || typeof response !== 'object' || Array.isArray(response) || response.success !== true) {
    return {
      transportSuccess: false,
      appSuccess: null,
      error: (response && typeof response.error === 'string' && response.error)
        || 'native host returned no result',
      items: [],
    };
  }

  const batch = response.batch;
  if (!batch || typeof batch !== 'object' || Array.isArray(batch) ||
      typeof batch.success !== 'boolean' || !Array.isArray(batch.items)) {
    return {
      transportSuccess: true,
      appSuccess: null,
      error: 'native host returned no result',
      items: [],
    };
  }

  return {
    transportSuccess: true,
    appSuccess: batch.success,
    error: typeof batch.error === 'string' ? batch.error : null,
    items: batch.items,
    itemKeys: Array.isArray(response.itemKeys) ? response.itemKeys : [],
  };
}

// Local selection failures are shown through the button's existing error marker and a temporary
// tooltip. Keeping the result as a message id here lets the content script resolve it in the
// catalogue that is actually painting this page.
function listBatchSelectionNotice(status) {
  if (status?.error === 'empty') {
    return { messageKey: 'ext.list.batch.selection.empty', args: [] };
  }
  if (status?.error === 'too-many') {
    return { messageKey: 'ext.list.batch.selection.tooMany', args: [status.count, MAX_BATCH_ITEMS] };
  }
  return null;
}

// A result belongs to the button that produced it, not merely to the row it happens to decorate.
// The identity stays in the pure view so a second list button cannot replace the first one's badges.
function listBatchButtonIdentity(kind, index) {
  return `${kind}:${index}`;
}

// App item results are ordered like the selected snapshot. If that shape is absent or malformed,
// the safe display is the overall phase only; inventing a row verdict from a shorter response would
// make an incomplete native response look authoritative.
function listBatchResultView(buttonIdentity, selected, outcome) {
  const rows = Array.isArray(selected) ? selected : [];
  const items = Array.isArray(outcome?.items) ? outcome.items : [];
  const itemKeys = Array.isArray(outcome?.itemKeys) ? outcome.itemKeys : rows.map(row => row.key);
  const complete = rows.length > 0 && items.length === itemKeys.length &&
    rows.every(row => row && typeof row.key === 'string') &&
    itemKeys.every(key => typeof key === 'string') &&
    items.every(item => item && typeof item === 'object' && !Array.isArray(item) &&
      typeof item.success === 'boolean' &&
      (item.error === undefined || typeof item.error === 'string'));
  return {
    buttonIdentity,
    phase: outcome?.appSuccess === true ? 'done' : 'error',
    badges: complete ? items.map((item, index) => ({
      key: itemKeys[index],
      success: item.success,
      error: typeof item.error === 'string' ? item.error : null,
    })) : [],
  };
}

// The last question asked before a command runs. Three answers, from three different moments, and
// all three have to name the same page:
//
//   `clicked` — where the user was when they pressed the button (the content script read it then)
//   `source`  — where the values in this request were read from: the tab as the message was
//               dispatched, which is what the repository, owner and number come out of
//   `current` — where the page is *right now*, read immediately before the command leaves
//
// Between a click and the send there are several awaits — the buttons come from storage, a script is
// injected to read the DOM, the main-branch overrides are read — and the page can move during any of
// them. Putting a check after each one is how the next one gets forgotten, and it was, four times
// over. `current` is asked once, where it covers all of them together.
//
// `source` is the axis that was missing, and it is the one that needs no await at all: it is fixed
// the moment the message arrives. Without it a tab that went 1 → 2 → 1 produced a request holding
// page 2's number and page 1's branch, while `clicked` and `current` both agreed on page 1.
//
// Fails closed on every kind of "cannot tell" — nothing clicked, nothing read back, a tab that no
// longer exists. Not knowing where a command would land is not a reason to send it.
function requestIsCoherent({ clicked, source, current }) {
  return sameTarget(clicked, source) && sameTarget(clicked, current);
}

// Whether a value is a page target we can compare against, as opposed to something we would compare
// against and always agree with. Every click from a page sends one; a message without one cannot be
// checked at all, which is not the same as passing the check.
function isPageTarget(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  if (typeof value.kind !== 'string') return false;
  if (typeof value.owner !== 'string' || typeof value.repo !== 'string') return false;
  return value.number === null || typeof value.number === 'string';
}

// --- What storage will accept ---
// storage.sync measures an item as its key length plus the JSON of its value and refuses anything
// over 8,192 bytes. Nothing capped the length of a command, so a 9,000-character one made `buttons`
// 9,159 bytes: the save failed with the raw quota error and nothing had warned or prevented it.
const SYNC_QUOTA_BYTES_PER_ITEM = 8192;

// The budget a single settings key may occupy, a quarter under the hard limit. The spare quarter is
// not decoration: a measured real profile (the presets plus two overrides) is 1,978 bytes across all
// keys, so this refuses nothing anyone has, while leaving room for whatever framing a future
// generation puts around the same content (if that clause packs a generation
// and its seed snapshot into one item, this budget has to be revisited with it).
const MAX_STORED_ITEM_BYTES = 6144;

// Bytes, not characters. A face is often an emoji: one JS character, four UTF-8 bytes, and counting
// characters would let a payload past the limit it is being measured against.
function storedItemBytes(key, value) {
  return key.length + new TextEncoder().encode(JSON.stringify(value ?? null)).length;
}

// --- Button identity in the edit state ---
// While buttons are being edited they need names: they get typed over, reordered and duplicated, and
// an index stops meaning the same button the moment any of that happens. That name is a `uid` this
// page mints, and it is **ours**. A uid arriving in stored data or an imported file is that data's
// word for something, not ours — adopting one has already cost us: a stored `"uid": 0` became a plan
// id of the number 0 while the DOM carried the string "0", so unchecking that item did nothing and
// it was migrated anyway.
//
// The two directions are separate functions on purpose. One funnel doing both is how that hole
// reopens.
let uidSequence = 0;
function nextButtonUid() {
  return `b${++uidSequence}`;
}

// The fields of a button, with no identity attached.
function buttonFields(button) {
  return {
    face: button.face ?? button.emoji ?? '', // emoji: compatibility with values saved before face existed
    label: button.label || '',
    command: button.command || '',
    claudeInputs: Array.isArray(button.claudeInputs) ? button.claudeInputs.map(String) : [],
  };
}

// Data from outside — storage, an imported file, a preset. Whatever it claims its uid is, it does
// not get one: we mint ours.
function adoptButton(button) {
  return { ...buttonFields(button), uid: nextButtonUid() };
}

// A button already in the edit state being reshaped — tidied on save, rewritten by a migration. Same
// button, so it keeps its name: renaming it underneath a preview the user is reading would detach
// their choices from the items they made them about.
function reshapeButton(button, uid) {
  return { ...buttonFields(button), uid };
}

// Reads a stored button array, keeping only the entries whose shape we understand and saying how
// many it had to drop.
//
// Storage is not our data: another device wrote it, or another version of this extension, or a hand
// edit. `[null]` and `{"length": 1}` both arrive here and both used to throw — the options page hung
// with no settings and nothing to retry it. **Every** reader goes through this, the content script
// and the service worker included, which is why it lives in defaults.js: those two deliberately do
// not load migrations.js, and surviving a stored value must not depend on which files you loaded.
//
// The limits belong here for the same reason the shape rules do. They used to be applied on the
// import path alone, so a stored fourth button reached the app while the same file arriving through
// import lost it without a word — two readers, two verdicts. And a limit applied quietly inside a
// reader is the same defect as inventing a default: the next Save records the trimmed list. Over the
// limit is therefore not "trim to fit" but "cannot be used", counted and reported like any other skip.
function adoptStoredButtons(value) {
  if (value === undefined) return { buttons: [], skipped: 0 }; // nothing stored is not a problem
  if (!Array.isArray(value)) return { buttons: [], skipped: 1 };

  const buttons = [];
  let skipped = 0;
  for (const entry of value) {
    // A button is an object. null, a string, a number, an array — none of those can be read as one,
    // and guessing at them is how a typo in someone's backup becomes a command.
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) { skipped += 1; continue; }
    if (!readableButtonFields(entry)) { skipped += 1; continue; }
    // Cutting the surplus inputs off an otherwise fine button would keep the button and lose the
    // inputs — the very silent loss the field rules above exist to prevent.
    if ((entry.claudeInputs?.length ?? 0) > MAX_CLAUDE_INPUTS) { skipped += 1; continue; }
    if (buttons.length >= MAX_BUTTONS) { skipped += 1; continue; }
    buttons.push(buttonFields(entry));
  }
  return { buttons, skipped };
}

// Whether every field of an entry has the shape its readers assume.
//
// Checking that the entry is an object only moves the crash inwards: `command: 42` still reaches
// `.trim()`, and `claudeInputs: "hello"` was quietly turned into `[]` — the user's scheduled inputs
// gone at the next Save with nothing said. A field that is present has to be right; a field that is
// absent is fine, because that is what buttons saved by older versions look like.
//
// One bad field condemns the whole entry rather than the field. A button whose inputs we cannot read
// is not a button we understand, and keeping a quietly repaired version of it is exactly how those
// inputs were lost.
function readableButtonFields(entry) {
  const isText = value => value === undefined || typeof value === 'string';
  if (!isText(entry.face) || !isText(entry.emoji)) return false;
  if (!isText(entry.label) || !isText(entry.command)) return false;
  if (entry.claudeInputs === undefined) return true;
  if (!Array.isArray(entry.claudeInputs)) return false;
  // Every index has to exist and hold a string. `every` alone is no use — it does not visit a hole,
  // so `new Array(1)` answered "all strings" and the missing slot came back out of buttonFields as
  // the literal "undefined". Counting own keys instead was no better: one stray property
  // (`arr.note = 'x'`) makes the count match the length again by coincidence and the hole passes.
  // Asking each index whether it is actually there is the only form that answers the question.
  for (let i = 0; i < entry.claudeInputs.length; i++) {
    if (!Object.hasOwn(entry.claudeInputs, i)) return false;
    if (typeof entry.claudeInputs[i] !== 'string') return false;
  }
  return true;
}

// --- What was drawn versus what will run ---
// A click reaches the service worker as an index, and the service worker reads storage again to find
// out what that index means. Between those two reads the settings can have moved — another device
// saved, someone reordered — or the page may be showing something its own read never returned. The
// command that then runs is one the user never saw.
//
// So a click carries a fingerprint of what it was going to run, and the service worker runs it only
// if what it now reads runs the same thing. The fingerprint is a comparison key and nothing more:
// the command still comes from storage and never from the message, so a message can only ever cause
// a refusal, never introduce a command of its own. That is the same shape as the app owning the
// terminal choice — the side that executes keeps the single source of truth.
//
// Everything a click will hand the app, normalized exactly as the send normalizes it: the inputs are
// trimmed for ordinary spaces only and the empty ones dropped, which is what runButton did on its
// way out. It builds its message from this now, so the two cannot disagree — a normalization the
// fingerprint performs and the send does not is two buttons that are different to us and byte-
// identical to the app.
//
// Key order is fixed by this literal, which is what makes the JSON of it a stable comparison key.
// `String.prototype.trim()` also removes TAB, CR and LF, so it once made ["\t"] disappear at save
// time and changed ["\t!echo x"] before it could reach the app. Those control bytes must reach the
// app and be rejected there as `{success:false}`. `face` and `label` still use `trim()` below because
// they are display text, not typed bytes.
function normalizeClaudeInputs(inputs) {
  return (inputs || []).map(input => String(input).replace(/^ +| +$/g, '')).filter(Boolean);
}

function executionPayload(button) {
  return {
    command: button.command || '',
    claudeInputs: normalizeClaudeInputs(button.claudeInputs),
  };
}

// The question the fingerprint answers is "is this still the button that was drawn" — where a
// *button* is the command and the inputs it carries, and not its face or its tooltip. Which button
// was clicked is answered by its index within its section, and the pair of the two is what names it:
// `(kind, index, executionFingerprint)`.
//
// **It is not the identity of the request**, and the earlier wording here — "execution identity",
// "the same thing executed" — claimed that it was. The message also carries `variables`, which this
// does not cover and must not: they are read from the live DOM at click time, not frozen when the
// button was drawn, so a PR whose branch moved between the two runs the command against the branch
// it has *now*, which is the behaviour anyone pressing "check out this PR" is asking for. Whether
// the page is still the page is a different question with a different answer — `requestIsCoherent`,
// which compares identity (`kind/owner/repo/number`) and deliberately not content, because content
// changing underneath a page is expected and is not a reason to refuse.
//
// `face` and `label` were part of this and had to come out. They are display text: they never leave
// the browser (runButton sends the command template, the page's variables and the claude inputs —
// never the face or the tooltip), and they will be translated. Two extension contexts can resolve
// different languages for a whole request — Chrome contexts can outlive an extension-folder swap,
// and adjacent generations can therefore render the same button through different catalogues — and
// with a display string in the key, that difference refused a command that had not changed by a
// character.
//
// So this is the identity of **what the button will run**. It is not a security identity and not a
// UX one: two buttons with the same command and the same inputs are one button to this check. That
// is deliberate — the request and the run are identical, so there is no wrong command it could pick
// — and it is the residual to revisit if buttons ever need telling apart individually, which would
// mean a persistent id in the stored schema and therefore a SETTINGS_VERSION bump.
function buttonFingerprint(button) {
  return JSON.stringify(executionPayload(button));
}

// Whether a click may run: what storage holds now has to run what the page drew.
//
// The comparison lives here, next to the fingerprint it compares, rather than inline at the one
// call site — the two are one decision, and a caller holding half of it is a caller that can be
// given the other half wrong. `shown` is absent only on the extension-icon path, which draws
// nothing: there is no rendered button for it to disagree with.
function clickMatchesWhatWasShown(button, shown) {
  return shown === undefined || buttonFingerprint(button) === shown;
}

// What a mismatch reports, and where it goes.
//
// The content script inspects the `{success:false}` response and throws, but both click handlers
// catch that throw, put a phase marker on the button (`Error!` / `❌`) and send the message to
// `console.error`.
// **No error text is drawn on a GitHub page at all** — the only strings a button ever shows are its
// face, its tooltip and those phase markers.
//
// So this string is a diagnostic today, and it stays English — but it is not an ordinary
// one, because it is written as an instruction to a user and it will become locale-dependent the
// moment anything displays it. What that would take is not a translation: the message is composed in
// the **service worker**, which draws nothing and has no render locale, so displaying it properly
// means sending a message *id* to the content script and letting the side that knows the language
// render it. That is a protocol change, and it is the trigger to revisit this.
const BUTTON_CHANGED_ERROR =
  'This button no longer matches your saved settings — reload the page and try again.';

// --- The main-branch settings, validated once for every reader ---
// The override lookup is keyed by a repository name taken straight out of a page URL, and whatever
// comes back is handed to the app as a branch name. Only the options page checked the shape, so the
// service worker sent `main=42` from a stored `{widget: 42}`, and a stored string "abc" answered
// `Object.hasOwn("abc", "0")` — making "a" the main branch of a repository called `0`. The same
// verdict now serves the options page (load and import) and the service worker.
function adoptStoredMainBranch(raw) {
  let skipped = 0;

  let defaultMain;
  if (raw?.defaultMain !== undefined) {
    if (typeof raw.defaultMain === 'string') defaultMain = raw.defaultMain;
    else skipped += 1;
  }

  let overrides;
  const map = raw?.repoMainBranch;
  if (map !== undefined) {
    if (map && typeof map === 'object' && !Array.isArray(map)) {
      const entries = Object.entries(map).filter(([, branch]) => typeof branch === 'string');
      skipped += Object.keys(map).length - entries.length;
      overrides = Object.fromEntries(entries);
    } else {
      // `Object.entries('abc')` would otherwise have produced overrides named 0, 1 and 2
      skipped += 1;
    }
  }

  return { defaultMain, overrides, skipped };
}

// What the service worker reads through: same verdict, plus a line in the console where there is no
// status line to put it in (the counterpart of readStoredButtons).
// **Latent, like the button warning below it** (see `content.js` for where that boundary was drawn
// wrongly first): both of these are addressed to a user — they name what was lost and where to go
// and repair it — and they reach only the console today. English for that reason, not because
// `console.*` is diagnostic by definition. Their English plural branches would have to be rewritten
// along with them, which is part of the cost of ever displaying them.
function readStoredMainBranch(raw) {
  const adopted = adoptStoredMainBranch(raw);
  if (adopted.skipped) {
    console.warn(
      `Terminal Checkout: ${adopted.skipped} stored main-branch `
        + `${adopted.skipped === 1 ? 'value was' : 'values were'} unreadable and skipped — `
        + 'open the options page to repair.'
    );
  }
  return adopted;
}

// What the content script and the service worker read through: validate, say out loud what was
// dropped, and fall back to the defaults only when nothing usable is left. The warning goes to the
// console because that is where those two report anything at all (README troubleshooting says so);
// the options page has a status line and says it there instead.
//
// These two keep the fallback that the options page deliberately gives up. The options page must not
// invent buttons, because whatever it shows is what the next Save records — inventing there rewrites
// storage. Neither of these can write anything, so nothing is at stake in showing a default: what is
// at stake is the opposite, a GitHub page with no button at all, which tells the user nothing is
// wrong while their settings are unreadable. The face and tooltip drawn are the ones that will run,
// so the page stays honest about what clicking it does.
function readStoredButtons(value, defaults) {
  const { buttons, skipped } = adoptStoredButtons(value);
  if (skipped) {
    console.warn(
      `Terminal Checkout: ${skipped} stored button${skipped === 1 ? ' was' : 's were'} `
        + 'unusable and skipped — open the options page to repair.'
    );
  }
  return buttons.length ? buttons : defaults;
}

// The exact shape a button takes in storage, and the only place that shape is decided. The runtime
// uid is dropped here rather than at each call site — leaked into storage it would ride storage.sync
// to other machines and into export files, where it would collide with the uids minted there.
function toStoredButton(button) {
  return {
    face: (button.face ?? '').trim(),
    label: (button.label ?? '').trim(),
    command: button.command ?? '',
    claudeInputs: normalizeClaudeInputs(button.claudeInputs),
  };
}

// --- Button list editing ---
// Only the options page uses these, but they are pure functions that know nothing about the DOM or
// the chrome APIs, so they live here (tests/buttons.test.js).

// A new array with one more button on the end, taking the first preset face this section is not
// already using so two buttons never look the same. At the cap it hands the same array back — the
// caller has nothing to change and must not report an edit.
//
// It is a function rather than the body of the click handler because the handler is a guard and
// then a change; the guard must run before the edit state changes.
function appendButton(buttons, { presets, defaults }) {
  if (buttons.length >= MAX_BUTTONS) return buttons;
  const used = new Set(buttons.map(button => button.face));
  const face = presets.map(preset => preset.face).find(f => !used.has(f)) || defaults[0].face;
  // The label is resolved now and **stored as text**, so it is a snapshot of the language the
  // button was created in — the same class as a saved command being a snapshot of the preset it came
  // from. Making it follow the language later would mean a persistent id in the stored schema, and
  // that is a SETTINGS_VERSION bump this release does not make.
  return [...buttons, adoptButton({ face, label: tr('ext.button.newButton'), command: '' })];
}

// A new array with item `from` moved "before" position `insertBefore`, indexed against the original.
// The item is removed before it is spliced back in, so moving it later pulls the destination one
// slot closer — miss that adjustment and everything lands one slot off.
function moveItem(items, from, insertBefore) {
  if (!Number.isInteger(from) || from < 0 || from >= items.length) return items;
  const next = items.slice();
  const [moved] = next.splice(from, 1);
  // `insertBefore` needs no equivalent guard: splice clamps an out-of-range destination to append.
  next.splice(insertBefore > from ? insertBefore - 1 : insertBefore, 0, moved);
  return next;
}

// Tooltip for a copy: "Review" → "Review (1)". Any number already attached is stripped and the
// smallest unused number is picked — duplicating the original twice, or duplicating a copy, never
// produces the same name twice.
// The face is left alone: mixing a digit into an emoji face makes isTextFace call it a text pill,
// which changes the shape of the button on GitHub entirely.
function copyLabel(label, existingLabels) {
  const base = label.replace(/\s*\(\d+\)$/, '').trim(); // trim before appending (a whitespace-only tooltip gets just the number)
  const used = new Set(existingLabels);
  const numbered = n => (base ? `${base} (${n})` : `(${n})`);
  let n = 1;
  while (used.has(numbered(n))) n++;
  return numbered(n);
}

// A new array with a copy of button `index` spliced in right after it. Copying the object alone
// would leave claudeInputs pointing at the original array, so editing one side's inputs would
// change the other.
function duplicateButton(buttons, index) {
  const source = buttons[index];
  const next = buttons.slice();
  next.splice(index + 1, 0, {
    ...source,
    label: copyLabel(source.label, buttons.map(b => b.label)),
    claudeInputs: [...(source.claudeInputs || [])],
  });
  return next;
}
