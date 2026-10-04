/**
 * @typedef {Object} ExampleContext
 * @property {'octo-demo'} owner
 * @property {'sample-repo'} repo
 * @property {{number: 42, branch: 'example/options', base: 'main', title: 'Add button presets'}} pullRequest
 * @property {{number: 17, title: 'Example tracking issue'}} issue
 * @property {'/work/sample-repo'} repoPath
 *
 * @typedef {
 *   'code'|'issues'|'pullRequests'|'actions'|'projects'|'wiki'|'security'|'insights'|'settings'|'search'|
 *   'edit'|'open'|'closed'|'conversation'|'commits'|'checks'|'filesChanged'|'reviewers'|'assignees'|
 *   'labels'|'label'|'milestone'|'milestones'|'development'|'noReviews'|'noneYet'|'newIssue'|
 *   'newPullRequest'|'filters'|'author'|'reviews'|'sort'|'watch'|'fork'|'star'|'public'|'noConflicts'|
 *   'mergingAutomatically'|'pullRequest'|'allIssues'|'openedBy'|'wantsToMergeInto'|'from'|'comments'|
 *   'about'|'readme'|'activity'|'branches'|'updated'|'timeline'
 * } GitHubUICopyKey
 * @typedef {Readonly<Record<GitHubUICopyKey, string>>} GitHubUICopy
 * @typedef {{kind: OptionsButtonKind, uid: string, anchor: HTMLElement, restoreFocusTo: HTMLElement}} ReplicaEditorOpenOptions
 * @typedef {{mount: (root: HTMLElement, engine: OptionsEngine, editor: OptionsEditor) => void,
 *   focusButton: (kind: OptionsButtonKind, uid: string) => boolean,
 *   openDrawer: () => void, closeDrawer: () => void, isDrawerOpen: () => boolean,
 *   getExampleContext: () => Readonly<ExampleContext>}} OptionsReplica
 */

(() => {
/** @type {Readonly<ExampleContext>} */
const EXAMPLE_CONTEXT = Object.freeze({
  owner: 'octo-demo',
  repo: 'sample-repo',
  pullRequest: Object.freeze({
    number: 42,
    branch: 'example/options',
    base: 'main',
    title: 'Add button presets',
  }),
  issue: Object.freeze({ number: 17, title: 'Example tracking issue' }),
  repoPath: '/work/sample-repo',
});

/** @type {GitHubUICopy} */
const GITHUB_UI_COPY = Object.freeze({
  code: 'Code',
  issues: 'Issues',
  pullRequests: 'Pull requests',
  actions: 'Actions',
  projects: 'Projects',
  wiki: 'Wiki',
  security: 'Security',
  insights: 'Insights',
  settings: 'Settings',
  search: 'Type / to search',
  edit: 'Edit',
  open: 'Open',
  closed: 'Closed',
  conversation: 'Conversation',
  commits: 'Commits',
  checks: 'Checks',
  filesChanged: 'Files changed',
  reviewers: 'Reviewers',
  assignees: 'Assignees',
  labels: 'Labels',
  label: 'Label',
  milestone: 'Milestone',
  milestones: 'Milestones',
  development: 'Development',
  noReviews: 'No reviews',
  noneYet: 'None yet',
  newIssue: 'New issue',
  newPullRequest: 'New pull request',
  filters: 'Filters',
  author: 'Author',
  reviews: 'Reviews',
  sort: 'Sort',
  watch: 'Watch',
  fork: 'Fork',
  star: 'Star',
  public: 'Public',
  noConflicts: 'No conflicts with base branch',
  mergingAutomatically: 'Merging can be performed automatically.',
  pullRequest: 'pull request',
  allIssues: 'All issues',
  openedBy: 'opened by',
  wantsToMergeInto: 'wants to merge into',
  from: 'from',
  comments: 'Comments',
  about: 'About',
  readme: 'README',
  activity: 'Activity',
  branches: 'Branches',
  updated: 'Updated',
  timeline: 'Timeline',
});

const REPLICA_MESSAGE_READERS = Object.freeze({
  label: () => tr('ext.d.replica.label'),
  exampleBanner: () => tr('ext.d.replica.exampleBanner'),
  description: () => tr('ext.d.replica.description'),
  mode: () => tr('ext.d.replica.mode'),
  'page.pr': () => tr('ext.d.replica.page.pr'),
  'page.prList': () => tr('ext.d.replica.page.prList'),
  'page.issue': () => tr('ext.d.replica.page.issue'),
  'page.issueList': () => tr('ext.d.replica.page.issueList'),
  'page.repo': () => tr('ext.d.replica.page.repo'),
  iconAction: () => tr('ext.d.replica.iconAction'),
  iconEmpty: () => tr('ext.d.replica.iconEmpty'),
  'placeholders.show': () => tr('ext.d.replica.placeholders.show'),
  'placeholders.hide': () => tr('ext.d.replica.placeholders.hide'),
  'drawer.open': () => tr('ext.d.replica.drawer.open'),
  'drawer.close': () => tr('ext.d.replica.drawer.close'),
  'place.pr': () => tr('ext.d.replica.place.pr'),
  'place.prList': () => tr('ext.d.replica.place.prList'),
  'place.issue': () => tr('ext.d.replica.place.issue'),
  'place.issueList': () => tr('ext.d.replica.place.issueList'),
  'place.repo': () => tr('ext.d.replica.place.repo'),
  'slot.empty': () => tr('ext.d.replica.slot.empty'),
  'slot.add': () => tr('ext.d.replica.slot.add'),
  'move.left': () => tr('ext.d.replica.move.left'),
  'move.right': () => tr('ext.d.replica.move.right'),
  'move.instructions': () => tr('ext.d.replica.move.instructions'),
  'drawer.empty': () => tr('ext.d.replica.drawer.empty'),
  'action.failed': () => tr('ext.d.replica.action.failed'),
});
const REPLICA_MESSAGE_KEYS = Object.freeze(
  Object.keys(REPLICA_MESSAGE_READERS).map(suffix => `ext.d.replica.${suffix}`),
);

const REPLICA_KIND_ORDER = Object.freeze(Object.keys(BUTTON_KINDS));

/** @param {string} kind */
function replicaRoute(kind) {
  switch (kind) {
    case 'pr': return `/pull/${EXAMPLE_CONTEXT.pullRequest.number}`;
    case 'pr-list': return '/pulls';
    case 'issue': return `/issues/${EXAMPLE_CONTEXT.issue.number}`;
    case 'issue-list': return '/issues';
    case 'repo': return '/';
    default: return null;
  }
}

/** Return route data projected from the live default kind registry. */
function replicaKinds() {
  return REPLICA_KIND_ORDER.map(kind => ({
    kind,
    storageKey: BUTTON_KINDS[kind].storageKey,
    route: replicaRoute(kind),
    presetCount: BUTTON_KINDS[kind].presets.length,
  }));
}

/** Match the shape selected by content.js for this button kind. */
function replicaButtonLook(kind, button) {
  if (!Object.hasOwn(BUTTON_KINDS, kind)) return null;
  if (kind === 'repo') return 'filled';
  if (kind === 'pr-list' || kind === 'issue-list') return 'list-pill';
  return isTextFace(buttonFace(button || {})) ? 'text' : 'emoji';
}

/** Whether content.js draws the split-note caret beside this button. */
function replicaButtonHasCaret(button) {
  return buttonTakesClaudeNote(button);
}

/** List pages omit buttons with variables that content.js cannot supply. */
function replicaButtonsForSlot(kind, buttons) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || !Array.isArray(buttons)) return [];
  if (kind === 'pr-list' || kind === 'issue-list') {
    return buttons.filter(button => buttonUsesAllowedVariables(kind, button));
  }
  return buttons.slice();
}

/** Match background.js icon routing; list pages use the repository action. */
function iconRunKind(kind) {
  if (kind === 'pr-list' || kind === 'issue-list') return 'repo';
  return Object.hasOwn(BUTTON_KINDS, kind) ? kind : null;
}

/** The extension icon runs the first configured button for its routed kind. */
function iconButtonForPage(kind, snapshot) {
  const runKind = iconRunKind(kind);
  return runKind ? (snapshot?.buttons?.[runKind]?.[0] || null) : null;
}

/** Build the beforeUid action used by the left and right arrow alternatives to dragging. */
function buttonMoveAction(kind, buttons, uid, direction) {
  if (direction !== -1 && direction !== 1) return null;
  const visible = replicaButtonsForSlot(kind, buttons);
  const index = visible.findIndex(button => button.uid === uid);
  if (index < 0) return null;
  if (direction < 0) {
    const previous = visible[index - 1];
    return previous ? { type: 'button-move', kind, uid, beforeUid: previous.uid } : null;
  }
  const afterNext = visible[index + 2];
  if (index + 1 >= visible.length) return null;
  return { type: 'button-move', kind, uid, beforeUid: afterNext?.uid ?? null };
}

/** Build a beforeUid action for a drop on a same-kind button. */
function dropMoveAction(kind, buttons, uid, targetUid, after) {
  if (!Array.isArray(buttons) || uid === targetUid) return null;
  const sourceIndex = buttons.findIndex(button => button.uid === uid);
  const targetIndex = buttons.findIndex(button => button.uid === targetUid);
  if (sourceIndex < 0 || targetIndex < 0) return null;
  const beforeUid = after ? (buttons[targetIndex + 1]?.uid ?? null) : targetUid;
  return { type: 'button-move', kind, uid, beforeUid };
}

const model = Object.freeze({
  replicaKinds,
  replicaButtonLook,
  replicaButtonHasCaret,
  replicaButtonsForSlot,
  iconRunKind,
  iconButtonForPage,
  buttonMoveAction,
  dropMoveAction,
});

let mounted = null;
let dragUid = null;

/** @param {string} suffix */
function replicaText(suffix) {
  const readMessage = REPLICA_MESSAGE_READERS[suffix];
  return readMessage ? readMessage() : '';
}

/** Escape values from settings before placing them in the replica markup. */
function replicaEscape(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

/** @param {GitHubUICopyKey} key */
function gh(key) {
  return replicaEscape(GITHUB_UI_COPY[key]);
}

/** @param {string} kind */
function pageName(kind) {
  return replicaText(`page.${kind === 'pr-list' ? 'prList' : kind === 'issue-list' ? 'issueList' : kind}`);
}

/** @param {string} kind */
function placeName(kind) {
  return replicaText(`place.${kind === 'pr-list' ? 'prList' : kind === 'issue-list' ? 'issueList' : kind}`);
}

/** @param {string} kind */
function routeAddress(kind) {
  return `github.com/${EXAMPLE_CONTEXT.owner}/${EXAMPLE_CONTEXT.repo}${replicaRoute(kind)}`;
}

/** @param {string} kind */
function routeSection(kind) {
  if (kind === 'pr' || kind === 'pr-list') return 'pullRequests';
  if (kind === 'issue' || kind === 'issue-list') return 'issues';
  return 'code';
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot */
function iconKindAndButton(kind, snapshot) {
  const runKind = iconRunKind(kind);
  return runKind ? { kind: runKind, button: iconButtonForPage(kind, snapshot) } : null;
}

/** @param {string} kind @param {OptionsButtonSnapshot|null} button */
function renderDecorativeButton(kind, button) {
  if (!button) return `<span class="replica-icon-empty">${replicaEscape(replicaText('iconEmpty'))}</span>`;
  const face = buttonFace(button);
  const look = replicaButtonLook(kind, button);
  const caret = replicaButtonHasCaret(button) ? '<span class="gh-button-caret" aria-hidden="true"><svg viewBox="0 0 16 16"><path d="M3.5 5.75 8 10.25l4.5-4.5"/></svg></span>' : '';
  return `<span class="gh-button gh-button-${look}${caret ? ' has-split-caret' : ''}" aria-hidden="true"><span>${replicaEscape(face)}</span>${caret}</span>`;
}

/** @param {string} kind @param {OptionsButtonSnapshot} button @param {boolean} loaded */
function renderEditButton(kind, button, loaded) {
  const face = buttonFace(button);
  const label = typeof button.label === 'string' && button.label ? button.label : face;
  const shape = replicaButtonLook(kind, button);
  const hasCaret = replicaButtonHasCaret(button);
  const caret = hasCaret ? '<span class="gh-button-caret" aria-hidden="true"><svg viewBox="0 0 16 16"><path d="M3.5 5.75 8 10.25l4.5-4.5"/></svg></span>' : '';
  return `<button type="button" class="gh-button gh-button-${shape}${hasCaret ? ' has-split-caret' : ''} replica-edit-button" data-replica-button="true" data-kind="${replicaEscape(kind)}" data-uid="${replicaEscape(button.uid)}" data-focus-key="button:${replicaEscape(kind)}:${replicaEscape(button.uid)}" aria-describedby="replica-reorder-instructions" aria-keyshortcuts="ArrowLeft ArrowRight" draggable="${loaded}"${loaded ? '' : ' disabled'}><span class="replica-sr-only">${replicaEscape(label)}</span><span class="replica-button-face" aria-hidden="true">${replicaEscape(face)}</span>${caret}</button>`;
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot @param {boolean} showPlaceholders */
function renderSlot(kind, snapshot, showPlaceholders) {
  const all = snapshot.buttons?.[kind] || [];
  const visible = replicaButtonsForSlot(kind, all);
  const location = placeName(kind);
  const canAdd = all.length < MAX_BUTTONS;
  const controls = visible.map(button => renderEditButton(kind, button, Boolean(snapshot.load?.loaded))).join('');
  const emptySlotHint = showPlaceholders && visible.length === 0
    ? `<span class="replica-slot-empty">${replicaEscape(replicaText('slot.empty'))}</span>`
    : '';
  return `<div class="replica-slot${showPlaceholders ? ' is-marked' : ' is-quiet'}${visible.length ? ' has-buttons' : ' is-empty'}" role="group" aria-labelledby="replica-slot-label-${replicaEscape(kind)}" data-drop-kind="${replicaEscape(kind)}" data-focus-key="slot:${replicaEscape(kind)}" tabindex="-1"><span id="replica-slot-label-${replicaEscape(kind)}" class="replica-slot-label${showPlaceholders ? '' : ' is-visually-hidden'}">${replicaEscape(location)}</span><span class="replica-slot-buttons">${controls}${emptySlotHint}</span><button type="button" class="replica-slot-add" data-action="slot-add" data-slot-kind="${replicaEscape(kind)}" data-focus-key="slot-add:${replicaEscape(kind)}" aria-controls="replica-drawer" aria-labelledby="replica-slot-label-${replicaEscape(kind)} replica-slot-add-name-${replicaEscape(kind)}" aria-expanded="${mounted.drawerOpen}"${canAdd && snapshot.load?.loaded ? '' : ' disabled'}><span class="replica-sr-only" id="replica-slot-add-name-${replicaEscape(kind)}">${replicaEscape(replicaText('slot.add'))}</span><span aria-hidden="true">+</span></button><span class="replica-slot-count">${visible.length}/${MAX_BUTTONS}</span></div>`;
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot */
function renderFilmstripCard(kind, snapshot) {
  const buttons = snapshot.buttons?.[kind] || [];
  const previewButton = replicaButtonsForSlot(kind, buttons)[0] || null;
  const preview = previewButton
    ? renderDecorativeButton(kind, previewButton)
    : `<span class="replica-filmstrip-empty" aria-hidden="true">+</span>`;
  return `<button type="button" class="replica-page-card" data-page-kind="${replicaEscape(kind)}" data-focus-key="page:${replicaEscape(kind)}" aria-current="${mounted.pageKind === kind ? 'page' : 'false'}"><span class="replica-page-card-name">${replicaEscape(pageName(kind))}</span><span class="replica-page-card-preview">${preview}</span><span class="replica-page-card-location">${replicaEscape(placeName(kind))}</span></button>`;
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot @param {boolean} showPlaceholders */
function renderGitHubPage(kind, snapshot, showPlaceholders) {
  const context = EXAMPLE_CONTEXT;
  const repoSlot = renderSlot('repo', snapshot, showPlaceholders);
  const navKeys = ['code', 'issues', 'pullRequests', 'actions', 'projects', 'wiki', 'security', 'insights', 'settings'];
  const nav = navKeys.map(key => `<span class="gh-nav-item${key === routeSection(kind) ? ' is-current' : ''}"${key === routeSection(kind) ? ' aria-current="page"' : ''}>${gh(key)}</span>`).join('');
  const tabs = ['conversation', 'commits', 'checks', 'filesChanged'].map((key, index) => `<span class="gh-content-tab${index === 0 ? ' is-current' : ''}">${gh(key)}</span>`).join('');
  let body;

  if (kind === 'pr') {
    const branchSlot = renderSlot('pr', snapshot, showPlaceholders);
    body = `<header class="gh-detail-heading"><h1>${replicaEscape(context.pullRequest.title)} <span class="gh-number">#${context.pullRequest.number}</span></h1><div class="gh-status-line"><span class="gh-state gh-state-open">${gh('open')}</span><span>${replicaEscape(context.owner)} ${gh('openedBy')} ${replicaEscape(context.owner)}</span></div><div class="gh-branch-line"><span class="gh-branch-relation">${gh('wantsToMergeInto')}</span><span class="gh-branch">${replicaEscape(context.pullRequest.base)}</span><span class="gh-branch-relation">${gh('from')}</span><span class="gh-branch">${replicaEscape(context.pullRequest.branch)}</span>${branchSlot}</div></header><nav class="gh-content-tabs">${tabs}</nav><div class="gh-pr-grid"><article class="gh-conversation-card"><div class="gh-card-heading"><span class="gh-avatar">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span><b>${replicaEscape(context.owner)}</b><span>${gh('openedBy')} ${replicaEscape(context.owner)}</span><button type="button" class="gh-muted-button">${gh('edit')}</button></div><div class="gh-card-body"><p>${replicaEscape(context.pullRequest.title)}</p><div class="gh-merge-summary"><span class="gh-state gh-state-open">${gh('open')}</span><span>${gh('noConflicts')}</span></div><span>${gh('mergingAutomatically')}</span></div><div class="gh-card-footer"><span>${gh('comments')}</span><span>${gh('reviews')}</span></div></article><aside class="gh-sidebar"><h2>${gh('reviewers')}</h2><p>${gh('noReviews')}</p><h2>${gh('assignees')}</h2><p>${gh('noneYet')}</p><h2>${gh('labels')}</h2><p>${gh('noneYet')}</p><h2>${gh('milestone')}</h2><p>${gh('noneYet')}</p><h2>${gh('development')}</h2><p>${gh('noneYet')}</p></aside></div>`;
  } else if (kind === 'pr-list') {
    const listSlot = renderSlot('pr-list', snapshot, showPlaceholders);
    body = `<header class="gh-list-heading"><h1>${gh('pullRequests')}</h1><button type="button" class="gh-green-button">${gh('newPullRequest')}</button></header><div class="gh-list-tools">${listSlot}<div class="gh-filter-row"><span>${gh('filters')}</span><span>${gh('author')}</span><span>${gh('labels')}</span><span class="gh-spacer"></span><span>${gh('sort')}: ${gh('updated')}</span></div></div><div class="gh-list"><div class="gh-list-row"><span class="gh-open-dot">●</span><b>${replicaEscape(context.pullRequest.title)}</b><span class="gh-row-meta">#${context.pullRequest.number}</span></div><div class="gh-list-row"><span class="gh-open-dot">●</span><span>${gh('noneYet')}</span><span class="gh-row-meta">${gh('author')}</span></div></div>`;
  } else if (kind === 'issue') {
    const issueSlot = renderSlot('issue', snapshot, showPlaceholders);
    body = `<header class="gh-detail-heading"><h1>${replicaEscape(context.issue.title)} <span class="gh-number">#${context.issue.number}</span></h1><div class="gh-status-line gh-issue-status"><span class="gh-state gh-state-open">${gh('open')}</span><span>${replicaEscape(context.owner)} ${gh('openedBy')} ${replicaEscape(context.owner)}</span>${issueSlot}</div></header><nav class="gh-content-tabs">${['conversation', 'commits', 'checks'].map((key, index) => `<span class="gh-content-tab${index === 0 ? ' is-current' : ''}">${gh(key)}</span>`).join('')}</nav><div class="gh-pr-grid"><article class="gh-conversation-card"><div class="gh-card-heading"><span class="gh-avatar">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span><b>${replicaEscape(context.owner)}</b><span>${gh('openedBy')} ${replicaEscape(context.owner)}</span><button type="button" class="gh-muted-button">${gh('edit')}</button></div><div class="gh-card-body"><p>${replicaEscape(context.issue.title)}</p><span>${gh('comments')}</span></div><div class="gh-card-footer"><span>${gh('timeline')}</span><span>${gh('updated')}</span></div></article><aside class="gh-sidebar"><h2>${gh('assignees')}</h2><p>${gh('noneYet')}</p><h2>${gh('labels')}</h2><p>${gh('noneYet')}</p><h2>${gh('milestone')}</h2><p>${gh('noneYet')}</p><h2>${gh('development')}</h2><p>${gh('noneYet')}</p></aside></div>`;
  } else if (kind === 'issue-list') {
    const listSlot = renderSlot('issue-list', snapshot, showPlaceholders);
    body = `<header class="gh-list-heading gh-issue-list-heading"><h1>${gh('allIssues')}</h1>${listSlot}<button type="button" class="gh-green-button">${gh('newIssue')}</button></header><div class="gh-list-tools"><div class="gh-filter-row"><span>${gh('filters')}</span><span>${gh('author')}</span><span>${gh('labels')}</span><span class="gh-spacer"></span><span>${gh('sort')}: ${gh('updated')}</span></div></div><div class="gh-list"><div class="gh-list-row"><span class="gh-open-dot">●</span><b>${replicaEscape(context.issue.title)}</b><span class="gh-row-meta">#${context.issue.number}</span></div><div class="gh-list-row"><span class="gh-open-dot">●</span><span>${gh('noneYet')}</span><span class="gh-row-meta">${gh('author')}</span></div></div>`;
  } else {
    body = `<header class="gh-repo-overview"><div><span class="gh-public-badge">${gh('public')}</span><h1>${replicaEscape(context.repo)}</h1><p>${gh('about')}</p></div><div class="gh-repo-actions"><button type="button">${gh('watch')}</button><button type="button">${gh('fork')}</button><button type="button">${gh('star')}</button></div></header><div class="gh-repo-grid"><section class="gh-readme"><h2>${gh('readme')}</h2><p>${replicaEscape(context.repo)}</p><span>${gh('activity')}</span></section><aside class="gh-sidebar"><h2>${gh('branches')}</h2><p>${replicaEscape(context.pullRequest.base)}</p><h2>${gh('issues')}</h2><p>${replicaEscape(context.issue.title)}</p><h2>${gh('pullRequests')}</h2><p>${replicaEscape(context.pullRequest.title)}</p></aside></div>`;
  }

  return `
    <div class="gh-page" data-rendered-kind="${replicaEscape(kind)}">
      <div class="gh-global-bar">
        <span class="gh-octicon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 .8a11.2 11.2 0 0 0-3.54 21.83c.56.1.76-.24.76-.54v-2.1c-3.1.67-3.76-1.31-3.76-1.31-.51-1.29-1.24-1.63-1.24-1.63-1.02-.7.08-.69.08-.69 1.12.08 1.71 1.15 1.71 1.15 1 1.71 2.61 1.22 3.25.93.1-.72.39-1.22.71-1.5-2.48-.28-5.09-1.24-5.09-5.52 0-1.22.44-2.21 1.15-2.99-.12-.28-.5-1.42.11-2.95 0 0 .94-.3 3.08 1.14a10.7 10.7 0 0 1 5.6 0c2.14-1.45 3.08-1.14 3.08-1.14.61 1.53.23 2.67.11 2.95.72.78 1.15 1.77 1.15 2.99 0 4.29-2.61 5.23-5.1 5.51.4.35.76 1.02.76 2.06v3.05c0 .3.2.65.77.54A11.2 11.2 0 0 0 12 .8Z"/></svg></span>
        <span class="gh-search">${gh('search')}</span>
        <span class="gh-top-actions">${gh('pullRequests')} <span class="gh-avatar">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span></span>
      </div>
      <div class="gh-repo-header">
        <div class="gh-repo-crumb"><span class="gh-owner">${replicaEscape(context.owner)}</span><span aria-hidden="true">/</span><b>${replicaEscape(context.repo)}</b><span class="gh-public-badge">${gh('public')}</span></div>
        ${repoSlot}
      </div>
      <nav class="gh-repo-nav">${nav}</nav>
      <main class="gh-main">${body}</main>
    </div>`;
}

/** @param {boolean} open */
function setDrawerVisible(open) {
  if (!mounted) return;
  mounted.drawerOpen = open;
  const drawer = mounted.root.querySelector('.replica-drawer');
  const toggle = mounted.root.querySelector('.replica-drawer-toggle');
  if (drawer) {
    drawer.hidden = !open;
    drawer.setAttribute('aria-hidden', String(!open));
  }
  if (toggle) {
    toggle.setAttribute('aria-expanded', String(open));
    toggle.textContent = replicaText(open ? 'drawer.close' : 'drawer.open');
  }
  mounted.root.querySelectorAll('[data-action="slot-add"]').forEach(button => {
    button.setAttribute('aria-expanded', String(open));
  });
}

/** Redraw from the engine snapshot. Replacing the view deliberately ends any native drag. */
function renderReplica() {
  if (!mounted) return;
  const { root, engine } = mounted;
  const active = root.ownerDocument.activeElement;
  const focusKey = active && root.contains(active) ? active.dataset?.focusKey : null;
  dragUid = null;
  mounted.snapshot = engine.getSnapshot();
  const snapshot = mounted.snapshot;
  const kind = mounted.pageKind;
  const icon = iconKindAndButton(kind, snapshot);
  const filmstrip = REPLICA_KIND_ORDER.map(pageKind => renderFilmstripCard(pageKind, snapshot)).join('');
  const drawerOpen = mounted.drawerOpen;
  const iconPreview = icon ? renderDecorativeButton(icon.kind, icon.button) : renderDecorativeButton('repo', null);
  root.innerHTML = `
    <section class="options-replica">
      <h2 class="replica-sr-only">${replicaEscape(replicaText('label'))}</h2>
      <p class="replica-example-banner">${replicaEscape(replicaText('exampleBanner'))}</p>
      <div class="replica-workspace">
        <section class="replica-browser">
          <h2 class="replica-sr-only">${replicaEscape(replicaText('label'))}</h2>
          <div class="replica-browser-chrome">
            <span class="replica-browser-lights" aria-hidden="true"><i></i><i></i><i></i></span>
            <span class="replica-browser-address">${replicaEscape(routeAddress(kind))}</span>
          </div>
          <div class="replica-editbar">
            <div class="replica-editbar-copy">
              <strong>${replicaEscape(replicaText('mode'))}</strong>
              <span>${replicaEscape(replicaText('description'))}</span>
            </div>
            <div class="replica-editbar-controls">
              <div class="replica-icon-preview"><span class="replica-icon-label">${replicaEscape(replicaText('iconAction'))}</span>${iconPreview}</div>
              <button type="button" class="replica-control" data-action="placeholders-toggle" data-focus-key="placeholders-toggle" aria-pressed="${mounted.showPlaceholders}"${snapshot.load?.loaded ? '' : ' disabled'}>${replicaEscape(replicaText(mounted.showPlaceholders ? 'placeholders.hide' : 'placeholders.show'))}</button>
              <button type="button" class="replica-control replica-drawer-toggle" data-action="drawer-toggle" data-focus-key="drawer-toggle" aria-controls="replica-drawer" aria-expanded="${drawerOpen}"${snapshot.load?.loaded ? '' : ' disabled'}>${replicaEscape(replicaText(drawerOpen ? 'drawer.close' : 'drawer.open'))}</button>
            </div>
          </div>
          <p class="replica-reorder-instructions" id="replica-reorder-instructions">${replicaEscape(replicaText('move.instructions'))}</p>
          <div class="replica-page-frame">${renderGitHubPage(kind, snapshot, mounted.showPlaceholders)}</div>
          <aside id="replica-drawer" class="replica-drawer" aria-hidden="${!drawerOpen}"${drawerOpen ? '' : ' hidden'}>
            <div class="replica-drawer-heading">
              <h2>${replicaEscape(replicaText('drawer.open'))}</h2>
              <button type="button" class="replica-drawer-close" data-action="drawer-close" data-focus-key="drawer-close"><span class="replica-sr-only">${replicaEscape(replicaText('drawer.close'))}</span><span aria-hidden="true">×</span></button>
            </div>
          <p>${replicaEscape(replicaText('drawer.empty'))}</p>
          </aside>
          <p class="replica-action-status" role="status" aria-live="polite">${replicaEscape(mounted.status || '')}</p>
        </section>
        <nav class="replica-filmstrip"><h2 class="replica-sr-only">${replicaEscape(replicaText('label'))}</h2>${filmstrip}</nav>
      </div>
    </section>`;
  root.querySelector('.replica-drawer')?.setAttribute('data-drawer-kind', mounted.drawerKind);
  if (focusKey) {
    const replacement = [...root.querySelectorAll('[data-focus-key]')].find(node => node.dataset.focusKey === focusKey);
    replacement?.focus();
  }
}

/** @param {OptionsEngineAction} action @param {string|null} focusKey */
async function sendReplicaAction(action, focusKey = null) {
  if (!mounted) return null;
  try {
    const result = await mounted.engine.dispatch(action);
    mounted.snapshot = result?.snapshot || mounted.engine.getSnapshot();
    mounted.status = result?.ok === false ? replicaText('action.failed') : '';
    renderReplica();
    if (focusKey) {
      const target = [...mounted.root.querySelectorAll('[data-focus-key]')].find(node => node.dataset.focusKey === focusKey);
      target?.focus();
    }
    return result;
  } catch {
    mounted.snapshot = mounted.engine.getSnapshot();
    mounted.status = replicaText('action.failed');
    renderReplica();
    return null;
  }
}

/** @param {HTMLElement} button */
function openButtonEditor(button) {
  if (!mounted || !button) return;
  const { kind, uid } = button.dataset;
  if (mounted.drawerOpen) setDrawerVisible(false);
  if (typeof mounted.editor?.open === 'function') {
    /** @type {ReplicaEditorOpenOptions} */
    const options = { kind, uid, anchor: button, restoreFocusTo: button };
    mounted.editor.open(options);
  }
}

/** @param {Event} event */
function handleReplicaClick(event) {
  const target = event.target instanceof Element ? event.target : null;
  const editButton = target?.closest('[data-replica-button]');
  if (editButton) {
    event.preventDefault();
    if (mounted.suppressClickUid === editButton.dataset.uid) {
      mounted.suppressClickUid = null;
      return;
    }
    openButtonEditor(editButton);
    return;
  }
  const pageCard = target?.closest('[data-page-kind]');
  if (pageCard) {
    event.preventDefault();
    mounted.pageKind = pageCard.dataset.pageKind;
    if (mounted.drawerOpen) mounted.drawerKind = mounted.pageKind;
    renderReplica();
    const selected = [...mounted.root.querySelectorAll('[data-focus-key]')]
      .find(node => node.dataset.focusKey === `page:${mounted.pageKind}`);
    selected?.focus();
    return;
  }
  const action = target?.closest('[data-action]')?.dataset.action;
  if (action === 'placeholders-toggle') {
    event.preventDefault();
    mounted.showPlaceholders = !mounted.showPlaceholders;
    renderReplica();
    mounted.root.querySelector('[data-focus-key="placeholders-toggle"]')?.focus();
  } else if (action === 'drawer-toggle') {
    event.preventDefault();
    if (mounted.drawerOpen) closeDrawerInternal(true);
    else openDrawerInternal(true, mounted.pageKind);
  } else if (action === 'slot-add') {
    event.preventDefault();
    openDrawerInternal(true, target.closest('[data-slot-kind]')?.dataset.slotKind || mounted.pageKind);
  } else if (action === 'drawer-close') {
    event.preventDefault();
    closeDrawerInternal(true);
  }
}

/** @param {KeyboardEvent} event */
function handleReplicaKeydown(event) {
  const target = event.target instanceof Element ? event.target.closest('[data-replica-button]') : null;
  if (!target || (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight')) return;
  event.preventDefault();
  const kind = target.dataset.kind;
  const uid = target.dataset.uid;
  const action = buttonMoveAction(kind, mounted.snapshot.buttons?.[kind] || [], uid, event.key === 'ArrowLeft' ? -1 : 1);
  if (action) sendReplicaAction(action, `button:${kind}:${uid}`);
}

/** @param {DragEvent} event */
function handleReplicaDragStart(event) {
  const target = event.target instanceof Element ? event.target.closest('[data-replica-button]') : null;
  if (!target || !mounted.snapshot.load?.loaded) return;
  dragUid = { kind: target.dataset.kind, uid: target.dataset.uid };
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', target.dataset.uid);
  }
  target.classList.add('is-dragging');
}

/** @param {DragEvent} event */
function handleReplicaDragOver(event) {
  if (!dragUid) return;
  const target = event.target instanceof Element ? event.target.closest('[data-replica-button], [data-drop-kind]') : null;
  if (!target || (target.dataset.kind || target.dataset.dropKind) !== dragUid.kind) return;
  event.preventDefault();
  event.dataTransfer && (event.dataTransfer.dropEffect = 'move');
  mounted.root.querySelectorAll('.is-drop-target').forEach(node => node.classList.remove('is-drop-target'));
  target.classList.add('is-drop-target');
}

/** @param {DragEvent} event */
function handleReplicaDrop(event) {
  if (!dragUid) return;
  const source = dragUid;
  const target = event.target instanceof Element ? event.target.closest('[data-replica-button], [data-drop-kind]') : null;
  if (!target || (target.dataset.kind || target.dataset.dropKind) !== source.kind) return;
  event.preventDefault();
  dragUid = null;
  let action;
  if (target.hasAttribute('data-replica-button')) {
    const rectangle = target.getBoundingClientRect();
    const after = event.clientX > rectangle.left + rectangle.width / 2;
    action = dropMoveAction(source.kind, mounted.snapshot.buttons?.[source.kind] || [], source.uid, target.dataset.uid, after);
  } else {
    const buttons = mounted.snapshot.buttons?.[source.kind] || [];
    if (buttons.some(button => button.uid === source.uid)) {
      action = { type: 'button-move', kind: source.kind, uid: source.uid, beforeUid: null };
    }
  }
  mounted.root.querySelectorAll('.is-drop-target, .is-dragging').forEach(node => node.classList.remove('is-drop-target', 'is-dragging'));
  if (action) {
    mounted.suppressClickUid = source.uid;
    sendReplicaAction(action, `button:${source.kind}:${source.uid}`);
  }
}

function handleReplicaDragEnd() {
  if (!mounted) return;
  dragUid = null;
  mounted.root.querySelectorAll('.is-drop-target, .is-dragging').forEach(node => node.classList.remove('is-drop-target', 'is-dragging'));
}

/** @param {boolean} focusClose @param {string} kind */
function openDrawerInternal(focusClose, kind = mounted?.pageKind) {
  if (!mounted) return;
  if (typeof mounted.editor?.close === 'function') mounted.editor.close();
  mounted.drawerKind = Object.hasOwn(BUTTON_KINDS, kind) ? kind : mounted.pageKind;
  setDrawerVisible(true);
  if (focusClose) mounted.root.querySelector('[data-focus-key="drawer-close"]')?.focus();
}

/** @param {boolean} restoreFocus */
function closeDrawerInternal(restoreFocus) {
  if (!mounted) return;
  setDrawerVisible(false);
  if (restoreFocus) mounted.root.querySelector('[data-focus-key="drawer-toggle"]')?.focus();
}

/** @param {HTMLElement} root @param {OptionsEngine} engine @param {OptionsEditor} editor */
function mountReplica(root, engine, editor) {
  if (!root || !engine) return;
  if (mounted?.unsubscribe) mounted.unsubscribe();
  if (mounted?.root && mounted.root !== root) {
    mounted.root.onclick = null;
    mounted.root.onkeydown = null;
    mounted.root.ondragstart = null;
    mounted.root.ondragover = null;
    mounted.root.ondrop = null;
    mounted.root.ondragend = null;
  }
  mounted = {
    root,
    engine,
    editor,
    pageKind: REPLICA_KIND_ORDER[0],
    drawerKind: REPLICA_KIND_ORDER[0],
    showPlaceholders: true,
    drawerOpen: false,
    status: '',
    suppressClickUid: null,
    snapshot: engine.getSnapshot(),
    unsubscribe: null,
  };
  dragUid = null;
  root.onclick = handleReplicaClick;
  root.onkeydown = handleReplicaKeydown;
  root.ondragstart = handleReplicaDragStart;
  root.ondragover = handleReplicaDragOver;
  root.ondrop = handleReplicaDrop;
  root.ondragend = handleReplicaDragEnd;
  renderReplica();
  mounted.unsubscribe = engine.subscribe(() => {
    if (!mounted) return;
    mounted.snapshot = engine.getSnapshot();
    renderReplica();
  });
}

/** Focus the requested live button, or its insertion place when it is absent. */
function focusReplicaButton(kind, uid) {
  if (!mounted || !Object.hasOwn(BUTTON_KINDS, kind)) return false;
  if (kind !== 'repo' && mounted.pageKind !== kind) {
    mounted.pageKind = kind;
    renderReplica();
  }
  const button = [...mounted.root.querySelectorAll('[data-replica-button]')]
    .find(node => node.dataset.kind === kind && node.dataset.uid === uid);
  if (button) {
    button.focus();
    return true;
  }
  const add = [...mounted.root.querySelectorAll('.replica-slot-add')]
    .find(node => node.dataset.slotKind === kind);
  const slot = [...mounted.root.querySelectorAll('[data-drop-kind]')]
    .find(node => node.dataset.dropKind === kind);
  (add && !add.disabled ? add : slot)?.focus();
  return Boolean(add || slot);
}

/** Open the empty drawer surface, keeping it separate from the preset implementation. */
function openReplicaDrawer() {
  openDrawerInternal(true);
}

/** Close the drawer and return focus to its toolbar control. */
function closeReplicaDrawer() {
  closeDrawerInternal(true);
}

/** @returns {boolean} */
function isReplicaDrawerOpen() {
  return Boolean(mounted?.drawerOpen);
}

/** @type {OptionsReplica} */
window.optionsReplica = Object.freeze({
  /** @param {HTMLElement} root @param {OptionsEngine} engine @param {OptionsEditor} editor */
  mount: mountReplica,
  /** @param {OptionsButtonKind} kind @param {string} uid */
  focusButton: focusReplicaButton,
  openDrawer: openReplicaDrawer,
  closeDrawer: closeReplicaDrawer,
  isDrawerOpen: isReplicaDrawerOpen,
  /** @returns {Readonly<ExampleContext>} */
  getExampleContext() { return EXAMPLE_CONTEXT; },
  EXAMPLE_CONTEXT,
  GITHUB_UI_COPY,
  messageKeys: REPLICA_MESSAGE_KEYS,
  model,
});
})();
