// Single source of truth for button defaults, presets, and page-type detection. content.js
// (rendering), background.js (execution), and options.js (editing) all have to see the same
// values, so they live here and nowhere else.
// The content script, the service worker, and the options page all load this file first.

// Every preset opens with `{cd}` — the clause that moves into the repository. Its value comes from
// the app, not from this file: with no base directory configured it is exactly `z {repo}` (what
// these presets used to spell out), and with one configured it falls back to `cd <base>/<repo>` and
// then to cloning. A bare `z {repo}` exits non-zero on a cold zoxide DB, which kills the whole `&&`
// chain with nothing to see anywhere (issue #30).
//
// PR pages: buttons next to the branch name. The { } is grouping, not a subshell — cd has to stick
// in the current shell, so ( ) must not be used
const PR_PRESETS = [
  {
    name: 'Checkout Branch', face: '⏏️',
    // If checkout fails (branch already checked out in a worktree, etc.), move to the worktree at the conventional path
    command: '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  },
  {
    name: 'Checkout + Claude', face: '🤖',
    command: '{cd} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude',
  },
  {
    name: 'Worktree + Claude', face: '🌳',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude',
  },
  {
    name: 'Worktree', face: '🪵',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}',
  },
  {
    name: 'Review PR (claude)', face: '🔍',
    command: '{cd} && claude',
    // A leading `!` in claude hands the line to the shell — gh output piles straight into claude's context
    claudeInputs: ['!gh pr view {number} --comments', '!gh pr diff {number}'],
  },
];

// Issue pages: buttons on the status badge row. There is no head branch, so the {branch} family and {base} are unavailable
const ISSUE_PRESETS = [
  {
    name: 'Read Issue (claude)', face: '📋',
    command: '{cd} && claude',
    claudeInputs: [
      '!gh issue view {number}',
      '!gh issue view {number} --comments',
      // Numbers of the issues and PRs that mention this issue. The --json fields only surface the "closing PR", so use the timeline
      '!gh api repos/{owner}/{repo}/issues/{number}/timeline --jq \'[.[]|select(.event=="cross-referenced")|.source.issue.number]\'',
    ],
  },
  {
    name: 'Start Work on Issue', face: '🌳',
    command: '{cd} && git fetch origin && ([ -d ../{repo}-issue-{number} ] || git worktree add -f ../{repo}-issue-{number} -b issue-{number} origin/{main}) && cd ../{repo}-issue-{number} && claude',
    claudeInputs: ['!gh issue view {number} --comments'],
  },
  {
    name: 'Open Issue', face: '📂',
    command: '{cd}',
    claudeInputs: [],
  },
];

// Repository pages: buttons next to the repository name in the header. Unlike PR and issue buttons
// these look like GitHub's green action button, so a name reads more naturally than a short emoji
// as the face
const REPO_PRESETS = [
  {
    name: 'Open in Terminal', face: 'Open in Terminal',
    command: '{cd}',
  },
  {
    name: 'Open + Claude', face: 'Open + Claude',
    command: '{cd} && claude',
  },
  {
    name: 'Update main', face: 'main ⤓',
    command: '{cd} && git checkout {main} && git pull --ff-only',
  },
];

const DEFAULT_BUTTONS = [
  { face: PR_PRESETS[0].face, label: PR_PRESETS[0].name, command: PR_PRESETS[0].command, claudeInputs: [] },
];

const DEFAULT_ISSUE_BUTTONS = [
  {
    face: ISSUE_PRESETS[0].face, label: ISSUE_PRESETS[0].name,
    command: ISSUE_PRESETS[0].command, claudeInputs: [...ISSUE_PRESETS[0].claudeInputs],
  },
];

const DEFAULT_REPO_BUTTONS = [
  { face: REPO_PRESETS[0].face, label: REPO_PRESETS[0].name, command: REPO_PRESETS[0].command, claudeInputs: [] },
];

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
  issue: {
    storageKey: 'issueButtons', presets: ISSUE_PRESETS, defaults: DEFAULT_ISSUE_BUTTONS,
    variables: ['repo', 'owner', 'number', 'main'],
  },
  repo: {
    storageKey: 'repoButtons', presets: REPO_PRESETS, defaults: DEFAULT_REPO_BUTTONS,
    variables: ['repo', 'owner', 'main'],
  },
};

// --- Settings schema version ---
// Saved commands are snapshots of the presets at save time, so improving a preset never reaches
// anyone who already pressed Save. The stored version says which generation of the presets a
// settings object has been **reviewed against** — not "was rewritten to". Applying a migration,
// applying part of one, declining it, and resetting to defaults are all reviews; ordinary edits are
// not, and must never move it (see migrations.js).
// This constant is the single source of truth for the current generation, and a test pins the
// registry in `extension/migrations.js` to carry one entry per step up to it.
const SETTINGS_VERSION = 1;

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
  if (/\/issues\/\d+/.test(pathname)) return 'issue';
  if (/\/pull\/\d+/.test(pathname)) return 'pr';
  if (/^\/[^/]+\/[^/]+\/?$/.test(pathname)) return 'repo';
  return new RegExp(`^/[^/]+/[^/]+/(${REPO_TABS})`).test(pathname) ? 'repo' : null;
}

const DEFAULT_MAIN = 'main';
const MAX_BUTTONS = 3;
const MAX_CLAUDE_INPUTS = 5;

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
// generation puts around the same content (decision 9 clause 2 — if that clause packs a generation
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
// So a click carries a fingerprint of the button as it was drawn, and the service worker runs it
// only if what it now reads is that same button. The fingerprint is a comparison key and nothing
// more: the command still comes from storage and never from the message, so a message can only ever
// cause a refusal, never introduce a command of its own. That is the same shape as the app owning
// the terminal choice — the side that executes keeps the single source of truth.
//
// Both sides reach a button through adoptStoredButtons, so both fingerprint the same normalized
// shape, and buttonFields writes its keys in a fixed order, which makes the JSON stable.
function buttonFingerprint(button) {
  return JSON.stringify(buttonFields(button));
}

// What a mismatch reports. It reaches the user on the button itself, through the {success:false}
// response the content script already inspects, so it has to say what to do next.
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
    claudeInputs: (button.claudeInputs || []).map(input => String(input).trim()).filter(Boolean),
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
// then a change, and that order is what a test has to be able to reach: [+ Add Button] used to push
// the button onto the edit state and ask afterwards whether it was allowed to.
function appendButton(buttons, { presets, defaults }) {
  if (buttons.length >= MAX_BUTTONS) return buttons;
  const used = new Set(buttons.map(button => button.face));
  const face = presets.map(preset => preset.face).find(f => !used.has(f)) || defaults[0].face;
  return [...buttons, adoptButton({ face, label: 'New Button', command: '' })];
}

// A new array with button `from` moved "before" card `insertBefore`, indexed against the original.
// The item is removed before it is spliced back in, so moving it later pulls the destination one
// slot closer — miss that adjustment and everything lands one slot off.
function moveButton(buttons, from, insertBefore) {
  const next = buttons.slice();
  const [moved] = next.splice(from, 1);
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
