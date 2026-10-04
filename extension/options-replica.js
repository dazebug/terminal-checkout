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
  'drawer.title': () => tr('ext.d.replica.drawer.title'),
  'drawer.instructions': () => tr('ext.d.replica.drawer.instructions'),
  'drawer.inUse': () => tr('ext.d.replica.drawer.inUse'),
  'drawer.add': () => tr('ext.d.replica.drawer.add'),
  'drawer.replace': () => tr('ext.d.replica.drawer.replace'),
  'drawer.chooseTarget': () => tr('ext.d.replica.drawer.chooseTarget'),
  'drawer.noReplaceTargets': () => tr('ext.d.replica.drawer.noReplaceTargets'),
  'drawer.confirmReplace': (label, presetName) => tr('ext.d.replica.drawer.confirmReplace', label, presetName),
  'drawer.confirm': () => tr('ext.d.replica.drawer.confirm'),
  'drawer.cancel': () => tr('ext.d.replica.drawer.cancel'),
  'drawer.limit': () => tr('ext.d.replica.drawer.limit'),
  'drawer.actionFailed': () => tr('ext.d.replica.drawer.actionFailed'),
  'place.pr': () => tr('ext.d.replica.place.pr'),
  'place.prList': () => tr('ext.d.replica.place.prList'),
  'place.issue': () => tr('ext.d.replica.place.issue'),
  'place.issueList': () => tr('ext.d.replica.place.issueList'),
  'place.repo': () => tr('ext.d.replica.place.repo'),
  'slot.empty': () => tr('ext.d.replica.slot.empty'),
  'slot.add': () => tr('ext.d.replica.slot.add'),
  'slot.hiddenOnGitHub': () => tr('ext.d.replica.slot.hiddenOnGitHub'),
  'slot.hiddenReason': variables => tr('ext.d.replica.slot.hiddenReason', variables),
  'slot.hiddenReasonGeneric': () => tr('ext.d.replica.slot.hiddenReasonGeneric'),
  'move.left': () => tr('ext.d.replica.move.left'),
  'move.right': () => tr('ext.d.replica.move.right'),
  'move.instructions': () => tr('ext.d.replica.move.instructions'),
  'drawer.empty': () => tr('ext.d.replica.drawer.empty'),
  'action.failed': () => tr('ext.d.replica.action.failed'),
  'presetDescription.prCheckout': () => tr('ext.d.replica.presetDescription.prCheckout'),
  'presetDescription.prCheckoutClaude': () => tr('ext.d.replica.presetDescription.prCheckoutClaude'),
  'presetDescription.prWorktreeClaude': () => tr('ext.d.replica.presetDescription.prWorktreeClaude'),
  'presetDescription.prWorktree': () => tr('ext.d.replica.presetDescription.prWorktree'),
  'presetDescription.prReview': () => tr('ext.d.replica.presetDescription.prReview'),
  'presetDescription.prListCheckoutClaude': () => tr('ext.d.replica.presetDescription.prListCheckoutClaude'),
  'presetDescription.issueRead': () => tr('ext.d.replica.presetDescription.issueRead'),
  'presetDescription.issueStartWork': () => tr('ext.d.replica.presetDescription.issueStartWork'),
  'presetDescription.open': () => tr('ext.d.replica.presetDescription.open'),
  'presetDescription.issueListTriageClaude': () => tr('ext.d.replica.presetDescription.issueListTriageClaude'),
  'presetDescription.repoOpenClaude': () => tr('ext.d.replica.presetDescription.repoOpenClaude'),
  'presetDescription.repoUpdateMain': () => tr('ext.d.replica.presetDescription.repoUpdateMain'),
});
const REPLICA_MESSAGE_KEYS = Object.freeze(
  Object.keys(REPLICA_MESSAGE_READERS).map(suffix => `ext.d.replica.${suffix}`),
);

const REPLICA_KIND_ORDER = Object.freeze(Object.keys(BUTTON_KINDS));
// issue.open and repo.open run the same command, so they share one sentence rather than two copies.
const PRESET_DESCRIPTION_SUFFIX_BY_ID = Object.freeze({
  'pr.checkout': 'presetDescription.prCheckout',
  'pr.checkoutClaude': 'presetDescription.prCheckoutClaude',
  'pr.worktreeClaude': 'presetDescription.prWorktreeClaude',
  'pr.worktree': 'presetDescription.prWorktree',
  'pr.review': 'presetDescription.prReview',
  'pr-list.checkoutClaude': 'presetDescription.prListCheckoutClaude',
  'issue.read': 'presetDescription.issueRead',
  'issue.startWork': 'presetDescription.issueStartWork',
  'issue.open': 'presetDescription.open',
  'issue-list.triageClaude': 'presetDescription.issueListTriageClaude',
  'repo.open': 'presetDescription.open',
  'repo.openClaude': 'presetDescription.repoOpenClaude',
  'repo.updateMain': 'presetDescription.repoUpdateMain',
});

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
  if (typeof button?.hasCaret === 'boolean') return button.hasCaret;
  return buttonTakesClaudeNote(button);
}

/** Keep every configured button available as an edit entry point in the replica. */
function replicaButtonsForSlot(kind, buttons) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || !Array.isArray(buttons)) return [];
  return buttons.slice();
}

/** Identify variables rejected by the page-availability predicate, for an explanation. */
function replicaUnavailablePageVariables(kind, button) {
  if (!button || typeof button.command !== 'string') return [];
  const templates = [button.command, ...(Array.isArray(button.claudeInputs) ? button.claudeInputs : [])];
  const names = new Set();
  for (const template of templates) {
    if (typeof template !== 'string') continue;
    for (const [, name] of template.matchAll(/\{(\w+)\}/g)) names.add(name);
  }
  return [...names].filter(name => !buttonUsesAllowedVariables(kind, {
    command: `{${name}}`,
    claudeInputs: [],
  }));
}

/** Mirror content.js list visibility while keeping hidden actions editable here. */
function replicaButtonPageStatus(kind, button) {
  const isListPage = kind === 'pr-list' || kind === 'issue-list';
  const hiddenOnGitHub = isListPage && !buttonUsesAllowedVariables(kind, button);
  return {
    hiddenOnGitHub,
    unavailableVariables: hiddenOnGitHub ? replicaUnavailablePageVariables(kind, button) : [],
  };
}

/** Return only the buttons GitHub would draw, for scenery that previews an actual page action. */
function replicaButtonsShownOnGitHub(kind, buttons) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || !Array.isArray(buttons)) return [];
  if (kind !== 'pr-list' && kind !== 'issue-list') return buttons.slice();
  return buttons.filter(button => buttonUsesAllowedVariables(kind, button));
}

/** Return true only when the engine identifies a button with this exact kind's preset id. */
function presetInUse(kind, presetId, snapshot) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || typeof presetId !== 'string') return false;
  const buttons = snapshot?.buttons?.[kind];
  return Array.isArray(buttons) && buttons.some(button => button.presetId === presetId);
}

/** Return whether a new preset can be added without relying on a stale view count. */
function presetAddAvailability(kind, snapshot) {
  if (!Object.hasOwn(BUTTON_KINDS, kind)) return 'invalid';
  if (snapshot?.load?.loaded !== true) return 'not-loaded';
  const buttons = snapshot.buttons?.[kind];
  if (!Array.isArray(buttons)) return 'invalid';
  return buttons.length >= MAX_BUTTONS ? 'limit' : 'available';
}

/** The page, card, and slot that show where a preset of this kind will appear. */
function presetHighlightTarget(kind) {
  return Object.hasOwn(BUTTON_KINDS, kind)
    ? { pageKind: kind, pageCardKind: kind, slotKind: kind }
    : null;
}

/** Pick the visible button before the drop point, or append when the point follows them all. */
function presetInsertionBeforeUid(kind, buttons, positions, clientX, clientY = undefined) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || !Array.isArray(buttons) || !Array.isArray(positions)) return null;
  const visible = replicaButtonsForSlot(kind, buttons);
  const hasRows = Number.isFinite(clientY) && visible.every(button => {
    const position = positions.find(item => item.uid === button.uid);
    return position && Number.isFinite(position.left) && Number.isFinite(position.width)
      && Number.isFinite(position.top) && Number.isFinite(position.height);
  });
  if (hasRows) {
    for (const button of visible) {
      const position = positions.find(item => item.uid === button.uid);
      if (clientY < position.top) return button.uid;
      if (clientY <= position.top + position.height
        && clientX < position.left + position.width / 2) return button.uid;
    }
    return null;
  }
  for (const button of visible) {
    const position = positions.find(item => item.uid === button.uid);
    if (position && Number.isFinite(position.left) && Number.isFinite(position.width)
      && clientX < position.left + position.width / 2) return button.uid;
  }
  return null;
}

/** Build the engine action for adding one live preset at a runtime-uid insertion point. */
function presetAddAction(kind, presetId, beforeUid = null) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || !presetById(BUTTON_KINDS[kind].presets, presetId)) return null;
  if (beforeUid !== null && typeof beforeUid !== 'string') return null;
  if (beforeUid !== null && !beforeUid) return null;
  return { type: 'preset-add', kind, presetId, beforeUid };
}

/** Build an unconfirmed preset replacement; the drawer retries only after the engine asks. */
function presetReplaceAction(kind, uid, presetId, confirmed = false) {
  if (!Object.hasOwn(BUTTON_KINDS, kind) || typeof uid !== 'string' || !uid
    || !presetById(BUTTON_KINDS[kind].presets, presetId)) return null;
  const action = { type: 'preset-replace', kind, uid, presetId };
  if (confirmed === true) action.confirmed = true;
  return action;
}

/** Project the live defaults into grouped cards without including mockup data or command copies. */
function presetGroups(snapshot) {
  return REPLICA_KIND_ORDER.map(kind => {
    const buttons = Array.isArray(snapshot?.buttons?.[kind]) ? snapshot.buttons[kind] : [];
    return {
      kind,
      label: pageName(kind),
      placement: placeName(kind),
      buttonCount: buttons.length,
      availability: presetAddAvailability(kind, snapshot),
      cards: BUTTON_KINDS[kind].presets.map(preset => ({
        kind,
        presetId: preset.id,
        face: preset.face,
        name: preset.name,
        look: replicaButtonLook(kind, preset),
        hasCaret: replicaButtonHasCaret(preset),
        description: presetDescription(preset.id),
        inUse: presetInUse(kind, preset.id, snapshot),
      })),
    };
  });
}

/** Resolve the one-line catalog description keyed by the stable preset id. */
function presetDescription(presetId) {
  const suffix = PRESET_DESCRIPTION_SUFFIX_BY_ID[presetId];
  return suffix ? replicaText(suffix) : '';
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

/** Distinguish the trusted pointer click from an independent or keyboard activation after a drag. */
function shouldSuppressReplicaDragClick(pendingUid, clickedUid, event) {
  return Boolean(pendingUid && pendingUid === clickedUid && event?.isTrusted === true && event.detail > 0);
}

/** Classify a document click from the path captured for that event, even if a redraw detached its target. */
function isOutsideDrawerEventPath(path) {
  if (!Array.isArray(path)) return true;
  return !path.some(entry => entry?.dataset?.replicaDrawerSurface === 'true'
    || entry?.dataset?.action === 'drawer-toggle'
    || entry?.dataset?.action === 'slot-add');
}

/** An inert option surface must not react to an event dispatched on or inside it. */
function isReplicaEventBlocked(path, surfaceIsInert = false) {
  return Boolean(surfaceIsInert || (Array.isArray(path) && path.some(entry => entry?.inert === true
    || entry?.hasAttribute?.('inert') === true
    || Boolean(entry?.closest?.('[inert]')))));
}

const model = Object.freeze({
  replicaKinds,
  replicaButtonLook,
  replicaButtonHasCaret,
  replicaButtonsForSlot,
  replicaButtonPageStatus,
  replicaButtonsShownOnGitHub,
  presetInUse,
  presetAddAvailability,
  presetHighlightTarget,
  presetInsertionBeforeUid,
  presetAddAction,
  presetReplaceAction,
  presetGroups,
  presetDescription,
  iconRunKind,
  iconButtonForPage,
  buttonMoveAction,
  dropMoveAction,
  shouldSuppressReplicaDragClick,
  isOutsideDrawerEventPath,
  isReplicaEventBlocked,
});

let mounted = null;
let dragUid = null;
let dragPreset = null;

/** Ignore interactions when this view or the event target is under an inert ancestor. */
function replicaInteractionIsBlocked(event) {
  if (!mounted) return true;
  const root = mounted.root;
  const surfaceIsInert = Boolean(root?.inert || root?.closest?.('[inert]'));
  const path = typeof event?.composedPath === 'function'
    ? event.composedPath()
    : event?.target ? [event.target] : [];
  return model.isReplicaEventBlocked(path, surfaceIsInert);
}

/** @param {string} suffix */
function replicaText(suffix, ...args) {
  const readMessage = REPLICA_MESSAGE_READERS[suffix];
  return readMessage ? readMessage(...args) : '';
}

/** Escape values from settings before placing them in the replica markup. */
function replicaEscape(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

/** @param {GitHubUICopyKey} key */
function gh(key) {
  return `<span class="gh-copy" lang="en">${replicaEscape(GITHUB_UI_COPY[key])}</span>`;
}

/** Mark fixed English example values without assigning a language to edited button text. */
function ghScenery(value) {
  return `<span class="gh-example-text" lang="en">${replicaEscape(value)}</span>`;
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

/** @param {string} kind @param {OptionsButtonSnapshot} button @param {boolean} loaded @param {string} describedBy */
function renderEditButton(kind, button, loaded, describedBy = '') {
  const face = buttonFace(button);
  const label = typeof button.label === 'string' && button.label ? button.label : face;
  const shape = replicaButtonLook(kind, button);
  const hasCaret = replicaButtonHasCaret(button);
  const caret = hasCaret ? '<span class="gh-button-caret" aria-hidden="true"><svg viewBox="0 0 16 16"><path d="M3.5 5.75 8 10.25l4.5-4.5"/></svg></span>' : '';
  const describedByIds = ['replica-reorder-instructions', describedBy].filter(Boolean).join(' ');
  return `<button type="button" class="gh-button gh-button-${shape}${hasCaret ? ' has-split-caret' : ''} replica-edit-button" data-replica-button="true" data-kind="${replicaEscape(kind)}" data-uid="${replicaEscape(button.uid)}" data-focus-key="button:${replicaEscape(kind)}:${replicaEscape(button.uid)}" aria-describedby="${replicaEscape(describedByIds)}" aria-keyshortcuts="ArrowLeft ArrowRight" draggable="${loaded}"${loaded ? '' : ' disabled'}><span class="replica-sr-only">${replicaEscape(label)}</span><span class="replica-button-face" aria-hidden="true">${replicaEscape(face)}</span>${caret}</button>`;
}

/** Keep an unexecutable GitHub-list button editable and explain why beside its face. */
function renderReplicaEditEntry(kind, button, loaded) {
  const pageStatus = replicaButtonPageStatus(kind, button);
  if (!pageStatus.hiddenOnGitHub) return renderEditButton(kind, button, loaded);
  const noteId = `replica-hidden-${kind}-${button.uid}`;
  const reason = pageStatus.unavailableVariables.length
    ? replicaText('slot.hiddenReason', pageStatus.unavailableVariables.join(', '))
    : replicaText('slot.hiddenReasonGeneric');
  return `<span class="replica-edit-entry is-hidden-on-github">${renderEditButton(kind, button, loaded, noteId)}<span class="replica-button-hidden-note" id="${replicaEscape(noteId)}" role="note"><span class="replica-button-hidden-label">${replicaEscape(replicaText('slot.hiddenOnGitHub'))}</span><span>${replicaEscape(reason)}</span></span></span>`;
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot @param {boolean} showPlaceholders */
function renderSlot(kind, snapshot, showPlaceholders) {
  const all = snapshot.buttons?.[kind] || [];
  const buttons = replicaButtonsForSlot(kind, all);
  const location = placeName(kind);
  const canAdd = all.length < MAX_BUTTONS;
  const controls = buttons.map(button => renderReplicaEditEntry(kind, button, Boolean(snapshot.load?.loaded))).join('');
  const emptySlotHint = showPlaceholders && all.length === 0
    ? `<span class="replica-slot-empty">${replicaEscape(replicaText('slot.empty'))}</span>`
    : '';
  const presetTarget = mounted.previewPreset?.kind === kind;
  return `<div class="replica-slot${showPlaceholders ? ' is-marked' : ' is-quiet'}${all.length ? ' has-buttons' : ' is-empty'}${presetTarget ? ' is-preset-target' : ''}" role="group" aria-labelledby="replica-slot-label-${replicaEscape(kind)}" data-drop-kind="${replicaEscape(kind)}" data-focus-key="slot:${replicaEscape(kind)}" tabindex="-1"><span id="replica-slot-label-${replicaEscape(kind)}" class="replica-slot-label${showPlaceholders ? '' : ' is-visually-hidden'}">${replicaEscape(location)}</span><span class="replica-slot-buttons">${controls}${emptySlotHint}</span><button type="button" class="replica-slot-add" data-action="slot-add" data-slot-kind="${replicaEscape(kind)}" data-focus-key="slot-add:${replicaEscape(kind)}" aria-controls="replica-drawer" aria-labelledby="replica-slot-label-${replicaEscape(kind)} replica-slot-add-name-${replicaEscape(kind)}" aria-expanded="${mounted.drawerOpen}"${canAdd && snapshot.load?.loaded ? '' : ' disabled'}><span class="replica-sr-only" id="replica-slot-add-name-${replicaEscape(kind)}">${replicaEscape(replicaText('slot.add'))}</span><span aria-hidden="true">+</span></button><span class="replica-slot-count">${all.length}/${MAX_BUTTONS}</span></div>`;
}

/** @param {string} kind @param {OptionsEngineSnapshot} snapshot */
function renderFilmstripCard(kind, snapshot) {
  const buttons = snapshot.buttons?.[kind] || [];
  const previewButton = replicaButtonsShownOnGitHub(kind, buttons)[0] || null;
  const preview = previewButton
    ? renderDecorativeButton(kind, previewButton)
    : `<span class="replica-filmstrip-empty" aria-hidden="true">+</span>`;
  const presetTarget = mounted.previewPreset?.kind === kind;
  return `<button type="button" class="replica-page-card${presetTarget ? ' is-preset-target' : ''}" data-page-kind="${replicaEscape(kind)}" data-focus-key="page:${replicaEscape(kind)}" aria-current="${mounted.pageKind === kind ? 'page' : 'false'}"><span class="replica-page-card-name">${replicaEscape(pageName(kind))}</span><span class="replica-page-card-preview">${preview}</span><span class="replica-page-card-location">${replicaEscape(placeName(kind))}</span></button>`;
}

/** @param {ReplicaPresetGroup} group @param {ReplicaPresetCard} card @param {OptionsEngineSnapshot} snapshot */
function renderPresetCard(group, card, snapshot) {
  const kind = group.kind;
  const presetId = card.presetId;
  const focusPrefix = `preset:${kind}:${presetId}`;
  const limitId = `replica-drawer-limit-${kind}`;
  const canAdd = group.availability === 'available';
  const canReplace = snapshot.load?.loaded === true;
  const isPickerOpen = mounted.replacePicker?.kind === kind && mounted.replacePicker?.presetId === presetId;
  const isPreview = mounted.previewPreset?.kind === kind && mounted.previewPreset?.presetId === presetId;
  const useStatus = card.inUse
    ? `<span class="replica-preset-use">${replicaEscape(replicaText('drawer.inUse'))}</span>`
    : '';
  const replaceTargets = isPickerOpen
    ? renderPresetReplaceTargets(kind, presetId, snapshot, focusPrefix)
    : '';
  return `<article class="replica-preset-card${isPreview ? ' is-preview' : ''}" role="group" aria-labelledby="${focusPrefix}-name" tabindex="0" draggable="${snapshot.load?.loaded === true}" data-preset-kind="${replicaEscape(kind)}" data-preset-id="${replicaEscape(presetId)}" data-focus-key="${focusPrefix}-card">
    <div class="replica-preset-card-main">
      <span class="replica-preset-face">${renderDecorativeButton(kind, card)}</span>
      <div class="replica-preset-copy">
        <h4 id="${focusPrefix}-name">${replicaEscape(card.name)}</h4>
        <p>${replicaEscape(card.description)}</p>
        ${useStatus}
      </div>
    </div>
    <div class="replica-preset-actions">
      <button type="button" class="replica-preset-action" data-action="preset-add" data-preset-kind="${replicaEscape(kind)}" data-preset-id="${replicaEscape(presetId)}" data-focus-key="${focusPrefix}-add"${canAdd ? '' : ' disabled'}${group.availability === 'limit' ? ` aria-describedby="${limitId}"` : ''}>${replicaEscape(replicaText('drawer.add'))}</button>
      <button type="button" class="replica-preset-action replica-preset-replace-toggle" data-action="preset-replace-picker" data-preset-kind="${replicaEscape(kind)}" data-preset-id="${replicaEscape(presetId)}" data-focus-key="${focusPrefix}-replace" aria-expanded="${isPickerOpen}"${isPickerOpen ? ` aria-controls="${focusPrefix}-targets"` : ''}${canReplace ? '' : ' disabled'}>${replicaEscape(replicaText('drawer.replace'))}</button>
    </div>
    ${replaceTargets}
  </article>`;
}

/** @param {string} kind @param {string} presetId @param {OptionsEngineSnapshot} snapshot @param {string} focusPrefix */
function renderPresetReplaceTargets(kind, presetId, snapshot, focusPrefix) {
  const buttons = snapshot.buttons?.[kind] || [];
  if (buttons.length === 0) {
    return `<div class="replica-preset-replace-targets" id="${focusPrefix}-targets"><p>${replicaEscape(replicaText('drawer.noReplaceTargets'))}</p></div>`;
  }
  const targets = buttons.map((button, index) => {
    const label = typeof button.label === 'string' && button.label ? button.label : buttonFace(button);
    return `<button type="button" class="replica-preset-target-button" data-action="preset-replace-target" data-preset-kind="${replicaEscape(kind)}" data-preset-id="${replicaEscape(presetId)}" data-target-uid="${replicaEscape(button.uid)}" data-focus-key="${focusPrefix}-target-${replicaEscape(button.uid)}"><span class="replica-preset-target-number">${index + 1}</span><span>${replicaEscape(label)}</span></button>`;
  }).join('');
  return `<div class="replica-preset-replace-targets" id="${focusPrefix}-targets"><p>${replicaEscape(replicaText('drawer.chooseTarget'))}</p><div>${targets}</div></div>`;
}

/** @param {OptionsEngineSnapshot} snapshot */
function renderPresetDrawer(snapshot) {
  const groups = presetGroups(snapshot);
  const pending = mounted.pendingReplace;
  const pendingButton = pending
    ? (snapshot.buttons?.[pending.kind] || []).find(button => button.uid === pending.uid)
    : null;
  const pendingPreset = pending ? presetById(BUTTON_KINDS[pending.kind]?.presets || [], pending.presetId) : null;
  const confirmation = pending && pendingButton && pendingPreset
    ? `<div class="replica-preset-confirmation" role="alert" aria-labelledby="replica-preset-confirmation-copy">
        <p id="replica-preset-confirmation-copy">${replicaEscape(replicaText('drawer.confirmReplace', pendingButton.label || buttonFace(pendingButton), pendingPreset.name))}</p>
        <div><button type="button" class="replica-preset-action" data-action="preset-replace-cancel" data-focus-key="preset-replace-cancel">${replicaEscape(replicaText('drawer.cancel'))}</button><button type="button" class="replica-preset-action is-primary" data-action="preset-replace-confirm" data-focus-key="preset-replace-confirm">${replicaEscape(replicaText('drawer.confirm'))}</button></div>
      </div>`
    : '';
  return `<p class="replica-drawer-instructions">${replicaEscape(replicaText('drawer.instructions'))}</p><div class="replica-preset-groups">${groups.map(group => {
    const limitId = `replica-drawer-limit-${group.kind}`;
    return `<section class="replica-preset-group" aria-labelledby="replica-preset-group-${group.kind}">
      <header class="replica-preset-group-heading"><div><h3 id="replica-preset-group-${group.kind}">${replicaEscape(group.label)}</h3><p>${replicaEscape(group.placement)}</p></div><span class="replica-preset-count">${group.buttonCount}/${MAX_BUTTONS}</span></header>
      ${group.availability === 'limit' ? `<p class="replica-preset-limit" id="${limitId}">${replicaEscape(replicaText('drawer.limit'))}</p>` : ''}
      <div class="replica-preset-cards">${group.cards.map(card => renderPresetCard(group, card, snapshot)).join('')}</div>
    </section>`;
  }).join('')}${confirmation}</div>`;
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
    body = `<header class="gh-detail-heading"><h1>${ghScenery(context.pullRequest.title)} <span class="gh-number">#${context.pullRequest.number}</span></h1><div class="gh-status-line"><span class="gh-state gh-state-open">${gh('open')}</span><span>${ghScenery(context.owner)} ${gh('openedBy')} ${ghScenery(context.owner)}</span></div><div class="gh-branch-line"><span class="gh-branch-relation">${gh('wantsToMergeInto')}</span><span class="gh-branch">${ghScenery(context.pullRequest.base)}</span><span class="gh-branch-relation">${gh('from')}</span><span class="gh-branch">${ghScenery(context.pullRequest.branch)}</span>${branchSlot}</div></header><nav class="gh-content-tabs">${tabs}</nav><div class="gh-pr-grid"><article class="gh-conversation-card"><div class="gh-card-heading"><span class="gh-avatar" lang="en">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span><b>${ghScenery(context.owner)}</b><span>${gh('openedBy')} ${ghScenery(context.owner)}</span><button type="button" class="gh-muted-button">${gh('edit')}</button></div><div class="gh-card-body"><p>${ghScenery(context.pullRequest.title)}</p><div class="gh-merge-summary"><span class="gh-state gh-state-open">${gh('open')}</span><span>${gh('noConflicts')}</span></div><span>${gh('mergingAutomatically')}</span></div><div class="gh-card-footer"><span>${gh('comments')}</span><span>${gh('reviews')}</span></div></article><aside class="gh-sidebar"><h2>${gh('reviewers')}</h2><p>${gh('noReviews')}</p><h2>${gh('assignees')}</h2><p>${gh('noneYet')}</p><h2>${gh('labels')}</h2><p>${gh('noneYet')}</p><h2>${gh('milestone')}</h2><p>${gh('noneYet')}</p><h2>${gh('development')}</h2><p>${gh('noneYet')}</p></aside></div>`;
  } else if (kind === 'pr-list') {
    const listSlot = renderSlot('pr-list', snapshot, showPlaceholders);
    body = `<header class="gh-list-heading"><h1>${gh('pullRequests')}</h1><button type="button" class="gh-green-button">${gh('newPullRequest')}</button></header><div class="gh-list-tools">${listSlot}<div class="gh-filter-row"><span>${gh('filters')}</span><span>${gh('author')}</span><span>${gh('labels')}</span><span class="gh-spacer"></span><span>${gh('sort')}: ${gh('updated')}</span></div></div><div class="gh-list"><div class="gh-list-row"><span class="gh-open-dot">●</span><b>${ghScenery(context.pullRequest.title)}</b><span class="gh-row-meta">#${context.pullRequest.number}</span></div><div class="gh-list-row"><span class="gh-open-dot">●</span><span>${gh('noneYet')}</span><span class="gh-row-meta">${gh('author')}</span></div></div>`;
  } else if (kind === 'issue') {
    const issueSlot = renderSlot('issue', snapshot, showPlaceholders);
    body = `<header class="gh-detail-heading"><h1>${ghScenery(context.issue.title)} <span class="gh-number">#${context.issue.number}</span></h1><div class="gh-status-line gh-issue-status"><span class="gh-state gh-state-open">${gh('open')}</span><span>${ghScenery(context.owner)} ${gh('openedBy')} ${ghScenery(context.owner)}</span>${issueSlot}</div></header><nav class="gh-content-tabs">${['conversation', 'commits', 'checks'].map((key, index) => `<span class="gh-content-tab${index === 0 ? ' is-current' : ''}">${gh(key)}</span>`).join('')}</nav><div class="gh-pr-grid"><article class="gh-conversation-card"><div class="gh-card-heading"><span class="gh-avatar" lang="en">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span><b>${ghScenery(context.owner)}</b><span>${gh('openedBy')} ${ghScenery(context.owner)}</span><button type="button" class="gh-muted-button">${gh('edit')}</button></div><div class="gh-card-body"><p>${ghScenery(context.issue.title)}</p><span>${gh('comments')}</span></div><div class="gh-card-footer"><span>${gh('timeline')}</span><span>${gh('updated')}</span></div></article><aside class="gh-sidebar"><h2>${gh('assignees')}</h2><p>${gh('noneYet')}</p><h2>${gh('labels')}</h2><p>${gh('noneYet')}</p><h2>${gh('milestone')}</h2><p>${gh('noneYet')}</p><h2>${gh('development')}</h2><p>${gh('noneYet')}</p></aside></div>`;
  } else if (kind === 'issue-list') {
    const listSlot = renderSlot('issue-list', snapshot, showPlaceholders);
    body = `<header class="gh-list-heading gh-issue-list-heading"><h1>${gh('allIssues')}</h1>${listSlot}<button type="button" class="gh-green-button">${gh('newIssue')}</button></header><div class="gh-list-tools"><div class="gh-filter-row"><span>${gh('filters')}</span><span>${gh('author')}</span><span>${gh('labels')}</span><span class="gh-spacer"></span><span>${gh('sort')}: ${gh('updated')}</span></div></div><div class="gh-list"><div class="gh-list-row"><span class="gh-open-dot">●</span><b>${ghScenery(context.issue.title)}</b><span class="gh-row-meta">#${context.issue.number}</span></div><div class="gh-list-row"><span class="gh-open-dot">●</span><span>${gh('noneYet')}</span><span class="gh-row-meta">${gh('author')}</span></div></div>`;
  } else {
    body = `<header class="gh-repo-overview"><div><span class="gh-public-badge">${gh('public')}</span><h1>${ghScenery(context.repo)}</h1><p>${gh('about')}</p></div><div class="gh-repo-actions"><button type="button">${gh('watch')}</button><button type="button">${gh('fork')}</button><button type="button">${gh('star')}</button></div></header><div class="gh-repo-grid"><section class="gh-readme"><h2>${gh('readme')}</h2><p>${ghScenery(context.repo)}</p><span>${gh('activity')}</span></section><aside class="gh-sidebar"><h2>${gh('branches')}</h2><p>${ghScenery(context.pullRequest.base)}</p><h2>${gh('issues')}</h2><p>${ghScenery(context.issue.title)}</p><h2>${gh('pullRequests')}</h2><p>${ghScenery(context.pullRequest.title)}</p></aside></div>`;
  }

  return `
    <div class="gh-page" data-rendered-kind="${replicaEscape(kind)}">
      <div class="gh-global-bar">
        <span class="gh-octicon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 .8a11.2 11.2 0 0 0-3.54 21.83c.56.1.76-.24.76-.54v-2.1c-3.1.67-3.76-1.31-3.76-1.31-.51-1.29-1.24-1.63-1.24-1.63-1.02-.7.08-.69.08-.69 1.12.08 1.71 1.15 1.71 1.15 1 1.71 2.61 1.22 3.25.93.1-.72.39-1.22.71-1.5-2.48-.28-5.09-1.24-5.09-5.52 0-1.22.44-2.21 1.15-2.99-.12-.28-.5-1.42.11-2.95 0 0 .94-.3 3.08 1.14a10.7 10.7 0 0 1 5.6 0c2.14-1.45 3.08-1.14 3.08-1.14.61 1.53.23 2.67.11 2.95.72.78 1.15 1.77 1.15 2.99 0 4.29-2.61 5.23-5.1 5.51.4.35.76 1.02.76 2.06v3.05c0 .3.2.65.77.54A11.2 11.2 0 0 0 12 .8Z"/></svg></span>
        <span class="gh-search" lang="en">${gh('search')}</span>
        <span class="gh-top-actions">${gh('pullRequests')} <span class="gh-avatar" lang="en">${replicaEscape(context.owner.slice(0, 1).toUpperCase())}</span></span>
      </div>
      <div class="gh-repo-header">
        <div class="gh-repo-crumb"><span class="gh-owner">${ghScenery(context.owner)}</span><span aria-hidden="true">/</span><b>${ghScenery(context.repo)}</b><span class="gh-public-badge">${gh('public')}</span></div>
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
  dragPreset = null;
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
          <aside id="replica-drawer" class="replica-drawer" data-replica-drawer-surface="true" aria-labelledby="replica-drawer-title" aria-hidden="${!drawerOpen}"${drawerOpen ? '' : ' hidden'}>
            <div class="replica-drawer-heading">
              <h2 id="replica-drawer-title">${replicaEscape(replicaText('drawer.title'))}</h2>
              <button type="button" class="replica-drawer-close" data-action="drawer-close" data-focus-key="drawer-close"><span class="replica-sr-only">${replicaEscape(replicaText('drawer.close'))}</span><span aria-hidden="true">×</span></button>
            </div>
            ${renderPresetDrawer(snapshot)}
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

/** Update only the page preview so hovering a card does not replace its drag source. */
function updatePresetPreview(next) {
  if (!mounted) return;
  const target = next ? presetHighlightTarget(next.kind) : null;
  mounted.previewPreset = next;
  mounted.pageKind = target?.pageKind || mounted.drawerOriginPageKind || mounted.pageKind;
  const frame = mounted.root.querySelector('.replica-page-frame');
  if (frame) frame.innerHTML = renderGitHubPage(mounted.pageKind, mounted.snapshot, mounted.showPlaceholders);
  const address = mounted.root.querySelector('.replica-browser-address');
  if (address) address.textContent = routeAddress(mounted.pageKind);
  mounted.root.querySelectorAll('.replica-page-card').forEach(card => {
    card.classList.toggle('is-preset-target', card.dataset.pageKind === target?.pageCardKind);
    card.setAttribute('aria-current', mounted.pageKind === card.dataset.pageKind ? 'page' : 'false');
  });
  mounted.root.querySelectorAll('.replica-preset-card').forEach(card => {
    card.classList.toggle(
      'is-preview',
      card.dataset.presetKind === next?.kind && card.dataset.presetId === next?.presetId,
    );
  });
}

/** @param {Element|null} target */
function updatePresetPreviewFromCard(target) {
  const card = target?.closest('[data-preset-kind][data-preset-id]');
  return card ? { kind: card.dataset.presetKind, presetId: card.dataset.presetId } : null;
}

function refreshPresetPreview() {
  const next = mounted.focusedPreset || mounted.pointerPreset;
  const current = mounted.previewPreset;
  if (current?.kind === next?.kind && current?.presetId === next?.presetId) return;
  updatePresetPreview(next);
}

/** @param {string} key */
function focusReplicaKey(key) {
  const target = [...mounted.root.querySelectorAll('[data-focus-key]')]
    .find(node => node.dataset.focusKey === key);
  target?.focus();
}

/** @param {MouseEvent} event */
function handleReplicaMouseOver(event) {
  if (replicaInteractionIsBlocked(event)) return;
  const target = event.target instanceof Element ? event.target : null;
  const card = target?.closest('[data-preset-kind][data-preset-id]');
  if (!card || card.contains(event.relatedTarget)) return;
  mounted.pointerPreset = updatePresetPreviewFromCard(card);
  refreshPresetPreview();
}

/** @param {MouseEvent} event */
function handleReplicaMouseOut(event) {
  if (replicaInteractionIsBlocked(event)) return;
  const target = event.target instanceof Element ? event.target : null;
  const card = target?.closest('[data-preset-kind][data-preset-id]');
  if (!card || card.contains(event.relatedTarget)) return;
  mounted.pointerPreset = null;
  refreshPresetPreview();
}

/** @param {FocusEvent} event */
function handleReplicaFocusIn(event) {
  if (replicaInteractionIsBlocked(event)) return;
  const preset = updatePresetPreviewFromCard(event.target instanceof Element ? event.target : null);
  if (!preset) return;
  mounted.focusedPreset = preset;
  refreshPresetPreview();
}

/** @param {FocusEvent} event */
function handleReplicaFocusOut(event) {
  if (replicaInteractionIsBlocked(event)) return;
  const target = event.target instanceof Element ? event.target : null;
  const card = target?.closest('[data-preset-kind][data-preset-id]');
  if (!card || card.contains(event.relatedTarget)) return;
  mounted.focusedPreset = null;
  refreshPresetPreview();
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

/** @param {string} kind @param {string} presetId @param {string|null} beforeUid */
async function addPreset(kind, presetId, beforeUid = null) {
  if (!mounted) return null;
  const action = presetAddAction(kind, presetId, beforeUid);
  if (!action) return null;
  try {
    const result = await mounted.engine.dispatch(action);
    mounted.snapshot = result?.snapshot || mounted.engine.getSnapshot();
    if (result?.ok) {
      mounted.status = '';
      mounted.pageKind = kind;
      mounted.pendingReplace = null;
      mounted.replacePicker = null;
      mounted.pointerPreset = null;
      mounted.focusedPreset = null;
      mounted.previewPreset = null;
      mounted.drawerOpen = false;
      mounted.drawerRestoreElement = null;
      mounted.drawerRestoreFocusKey = null;
      setDrawerVisible(false);
      renderReplica();
      if (result.createdUid) focusReplicaButton(kind, result.createdUid);
    } else {
      mounted.status = result?.reason === 'limit'
        ? replicaText('drawer.limit')
        : replicaText('drawer.actionFailed');
      renderReplica();
    }
    return result;
  } catch {
    mounted.snapshot = mounted.engine.getSnapshot();
    mounted.status = replicaText('drawer.actionFailed');
    renderReplica();
    return null;
  }
}

/** Ask the engine first; only its needs-confirmation response opens this view's confirmation UI. */
async function replacePreset(kind, uid, presetId, confirmed = false) {
  if (!mounted) return null;
  const action = presetReplaceAction(kind, uid, presetId, confirmed);
  if (!action) return null;
  try {
    const result = await mounted.engine.dispatch(action);
    mounted.snapshot = result?.snapshot || mounted.engine.getSnapshot();
    if (result?.reason === 'needs-confirmation' && !confirmed) {
      mounted.pendingReplace = { kind, uid, presetId };
      mounted.status = '';
      renderReplica();
      mounted.root.querySelector('[data-action="preset-replace-confirm"]')?.focus();
    } else if (result?.ok) {
      mounted.pendingReplace = null;
      mounted.replacePicker = null;
      mounted.status = '';
      mounted.pageKind = kind;
      mounted.pointerPreset = null;
      mounted.focusedPreset = null;
      mounted.previewPreset = null;
      mounted.drawerOpen = false;
      mounted.drawerRestoreElement = null;
      mounted.drawerRestoreFocusKey = null;
      setDrawerVisible(false);
      renderReplica();
      focusReplicaButton(kind, uid);
    } else {
      mounted.status = result?.reason === 'limit'
        ? replicaText('drawer.limit')
        : replicaText('drawer.actionFailed');
      renderReplica();
    }
    return result;
  } catch {
    mounted.snapshot = mounted.engine.getSnapshot();
    mounted.status = replicaText('drawer.actionFailed');
    renderReplica();
    return null;
  }
}

/** @param {HTMLElement} button */
function openButtonEditor(button) {
  if (!mounted || !button) return;
  const { kind, uid } = button.dataset;
  if (mounted.drawerOpen) {
    mounted.drawerOpen = false;
    mounted.pointerPreset = null;
    mounted.focusedPreset = null;
    mounted.drawerRestoreElement = null;
    mounted.drawerRestoreFocusKey = null;
    setDrawerVisible(false);
  }
  if (typeof mounted.editor?.open === 'function') {
    /** @type {ReplicaEditorOpenOptions} */
    const options = { kind, uid, anchor: button, restoreFocusTo: button };
    mounted.editor.open(options);
  }
}

/** Close page-bound surfaces before changing the route so focus cannot restore the old page. */
function selectReplicaPage(kind) {
  if (!mounted || !Object.hasOwn(BUTTON_KINDS, kind)) return false;
  if (typeof mounted.editor?.isOpen === 'function'
    && mounted.editor.isOpen()
    && typeof mounted.editor.close === 'function') {
    mounted.editor.close();
  }
  if (mounted.drawerOpen) {
    mounted.drawerOpen = false;
    mounted.drawerRestoreElement = null;
    mounted.drawerRestoreFocusKey = null;
    setDrawerVisible(false);
  }
  mounted.pendingReplace = null;
  mounted.replacePicker = null;
  mounted.pointerPreset = null;
  mounted.focusedPreset = null;
  mounted.previewPreset = null;
  mounted.pageKind = kind;
  mounted.drawerKind = kind;
  mounted.drawerOriginPageKind = kind;
  return true;
}

/** A fresh pointer action means any unobserved drag click did not arrive. */
function handleReplicaPointerDown(event) {
  if (replicaInteractionIsBlocked(event)) return;
  if (mounted) mounted.dragClickCandidateUid = null;
}

/** @param {Event} event */
function handleReplicaClick(event) {
  if (replicaInteractionIsBlocked(event)) return;
  const pendingUid = mounted?.dragClickCandidateUid || null;
  if (mounted) mounted.dragClickCandidateUid = null;
  const target = event.target instanceof Element ? event.target : null;
  const editButton = target?.closest('[data-replica-button]');
  if (editButton) {
    event.preventDefault();
    if (model.shouldSuppressReplicaDragClick(pendingUid, editButton.dataset.uid, event)) return;
    openButtonEditor(editButton);
    return;
  }
  const actionTarget = target?.closest('[data-action]');
  const action = actionTarget?.dataset.action;
  if (action === 'preset-add') {
    event.preventDefault();
    addPreset(actionTarget.dataset.presetKind, actionTarget.dataset.presetId);
    return;
  }
  if (action === 'preset-replace-picker') {
    event.preventDefault();
    const { presetKind: kind, presetId } = actionTarget.dataset;
    mounted.replacePicker = mounted.replacePicker?.kind === kind && mounted.replacePicker?.presetId === presetId
      ? null
      : { kind, presetId };
    renderReplica();
    focusReplicaKey(`preset:${kind}:${presetId}-replace`);
    return;
  }
  if (action === 'preset-replace-target') {
    event.preventDefault();
    replacePreset(actionTarget.dataset.presetKind, actionTarget.dataset.targetUid, actionTarget.dataset.presetId);
    return;
  }
  if (action === 'preset-replace-confirm') {
    event.preventDefault();
    const pending = mounted.pendingReplace;
    if (pending) replacePreset(pending.kind, pending.uid, pending.presetId, true);
    return;
  }
  if (action === 'preset-replace-cancel') {
    event.preventDefault();
    mounted.pendingReplace = null;
    mounted.status = '';
    renderReplica();
    const key = mounted.replacePicker
      ? `preset:${mounted.replacePicker.kind}:${mounted.replacePicker.presetId}-replace`
      : 'drawer-close';
    focusReplicaKey(key);
    return;
  }
  const pageCard = target?.closest('[data-page-kind]');
  if (pageCard) {
    event.preventDefault();
    selectReplicaPage(pageCard.dataset.pageKind);
    renderReplica();
    const selected = [...mounted.root.querySelectorAll('[data-focus-key]')]
      .find(node => node.dataset.focusKey === `page:${mounted.pageKind}`);
    selected?.focus();
    return;
  }
  if (action === 'placeholders-toggle') {
    event.preventDefault();
    mounted.showPlaceholders = !mounted.showPlaceholders;
    renderReplica();
    mounted.root.querySelector('[data-focus-key="placeholders-toggle"]')?.focus();
  } else if (action === 'drawer-toggle') {
    event.preventDefault();
    if (mounted.drawerOpen) closeDrawerInternal(true);
    else openDrawerInternal(true, mounted.pageKind, actionTarget);
  } else if (action === 'slot-add') {
    event.preventDefault();
    openDrawerInternal(true, actionTarget.dataset.slotKind || mounted.pageKind, actionTarget);
  } else if (action === 'drawer-close') {
    event.preventDefault();
    closeDrawerInternal(true);
  }
}

/** @param {KeyboardEvent} event */
function handleReplicaKeydown(event) {
  if (event.isComposing || event.keyCode === 229) return;
  if (replicaInteractionIsBlocked(event)) return;
  if (mounted) mounted.dragClickCandidateUid = null;
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
  if (replicaInteractionIsBlocked(event)) return;
  if (mounted) mounted.dragClickCandidateUid = null;
  const eventTarget = event.target instanceof Element ? event.target : null;
  const presetCard = eventTarget?.closest('[data-preset-kind][data-preset-id]');
  if (presetCard && mounted.snapshot.load?.loaded) {
    dragPreset = { kind: presetCard.dataset.presetKind, presetId: presetCard.dataset.presetId };
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'copy';
      event.dataTransfer.setData('text/plain', `preset:${dragPreset.kind}:${dragPreset.presetId}`);
    }
    presetCard.classList.add('is-dragging');
    return;
  }
  const target = eventTarget?.closest('[data-replica-button]');
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
  if (replicaInteractionIsBlocked(event)) return;
  if (!dragUid && !dragPreset) return;
  const target = event.target instanceof Element
    ? event.target.closest('[data-replica-button], [data-drop-kind]')
    : null;
  const source = dragPreset || dragUid;
  if (!target || (target.dataset.kind || target.dataset.dropKind) !== source.kind) return;
  event.preventDefault();
  event.dataTransfer && (event.dataTransfer.dropEffect = dragPreset ? 'copy' : 'move');
  mounted.root.querySelectorAll('.is-drop-target').forEach(node => node.classList.remove('is-drop-target'));
  target.classList.add('is-drop-target');
}

/** @param {DragEvent} event */
function handleReplicaDrop(event) {
  if (replicaInteractionIsBlocked(event)) return;
  if (!dragUid && !dragPreset) return;
  const source = dragPreset || dragUid;
  const isPreset = Boolean(dragPreset);
  const target = event.target instanceof Element ? event.target.closest('[data-replica-button], [data-drop-kind]') : null;
  if (!target || (target.dataset.kind || target.dataset.dropKind) !== source.kind) return;
  event.preventDefault();
  dragUid = null;
  if (isPreset && target.hasAttribute('data-replica-button')) {
    dragPreset = null;
    mounted.dragClickCandidateUid = target.dataset.uid;
    mounted.root.querySelectorAll('.is-drop-target, .is-dragging').forEach(node => node.classList.remove('is-drop-target', 'is-dragging'));
    replacePreset(source.kind, target.dataset.uid, source.presetId);
    return;
  }
  if (isPreset) {
    const buttons = mounted.snapshot.buttons?.[source.kind] || [];
    const slot = [...mounted.root.querySelectorAll('.replica-slot[data-drop-kind]')]
      .find(node => node.dataset.dropKind === source.kind);
    const positions = [...(slot?.querySelectorAll('[data-replica-button]') || [])]
      .map(button => {
        const rect = button.getBoundingClientRect();
        return { uid: button.dataset.uid, left: rect.left, width: rect.width, top: rect.top, height: rect.height };
      });
    const beforeUid = presetInsertionBeforeUid(source.kind, buttons, positions, event.clientX, event.clientY);
    dragPreset = null;
    mounted.root.querySelectorAll('.is-drop-target, .is-dragging').forEach(node => node.classList.remove('is-drop-target', 'is-dragging'));
    addPreset(source.kind, source.presetId, beforeUid);
    return;
  }
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
    mounted.dragClickCandidateUid = source.uid;
    sendReplicaAction(action, `button:${source.kind}:${source.uid}`);
  }
}

function handleReplicaDragEnd() {
  if (!mounted) return;
  dragUid = null;
  dragPreset = null;
  mounted.root.querySelectorAll('.is-drop-target, .is-dragging').forEach(node => node.classList.remove('is-drop-target', 'is-dragging'));
}

/** @param {boolean} focusClose @param {string} kind */
function openDrawerInternal(focusClose, kind = mounted?.pageKind, opener = null) {
  if (!mounted) return;
  if (mounted.drawerOpen) return;
  const active = opener || mounted.root.ownerDocument.activeElement;
  const toolbar = mounted.root.querySelector('[data-focus-key="drawer-toggle"]');
  mounted.drawerRestoreElement = active && mounted.root.contains(active) ? active : toolbar;
  mounted.drawerRestoreFocusKey = mounted.drawerRestoreElement?.dataset?.focusKey || 'drawer-toggle';
  mounted.drawerOriginPageKind = mounted.pageKind;
  mounted.pointerPreset = null;
  mounted.focusedPreset = null;
  mounted.previewPreset = null;
  mounted.pendingReplace = null;
  mounted.replacePicker = null;
  if (typeof mounted.editor?.close === 'function') mounted.editor.close();
  mounted.drawerKind = Object.hasOwn(BUTTON_KINDS, kind) ? kind : mounted.pageKind;
  setDrawerVisible(true);
  renderReplica();
  if (focusClose) mounted.root.querySelector('[data-focus-key="drawer-close"]')?.focus();
}

/** @param {boolean} restoreFocus */
function closeDrawerInternal(restoreFocus) {
  if (!mounted) return;
  if (!mounted.drawerOpen) return;
  mounted.pointerPreset = null;
  mounted.focusedPreset = null;
  mounted.previewPreset = null;
  mounted.pendingReplace = null;
  mounted.replacePicker = null;
  updatePresetPreview(null);
  setDrawerVisible(false);
  renderReplica();
  if (restoreFocus) {
    const saved = mounted.drawerRestoreElement;
    if (saved?.isConnected) saved.focus();
    else {
      const key = mounted.drawerRestoreFocusKey || 'drawer-toggle';
      [...mounted.root.querySelectorAll('[data-focus-key]')]
        .find(node => node.dataset.focusKey === key)?.focus();
    }
  }
  mounted.drawerRestoreElement = null;
  mounted.drawerRestoreFocusKey = null;
}

/** @param {MouseEvent} event */
function handleDocumentClick(event) {
  if (replicaInteractionIsBlocked(event)) return;
  if (!mounted?.drawerOpen) return;
  if (!model.isOutsideDrawerEventPath(event.composedPath())) return;
  closeDrawerInternal(true);
}

/** @param {KeyboardEvent} event */
function handleDocumentKeydown(event) {
  if (event.isComposing || event.keyCode === 229) return;
  if (replicaInteractionIsBlocked(event)) return;
  if (event.key !== 'Escape' || !mounted?.drawerOpen) return;
  event.preventDefault();
  closeDrawerInternal(true);
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
    mounted.root.removeEventListener('mouseover', handleReplicaMouseOver);
    mounted.root.removeEventListener('mouseout', handleReplicaMouseOut);
    mounted.root.removeEventListener('focusin', handleReplicaFocusIn);
    mounted.root.removeEventListener('focusout', handleReplicaFocusOut);
    mounted.root.ownerDocument.removeEventListener('pointerdown', handleReplicaPointerDown, true);
    mounted.root.ownerDocument.removeEventListener('click', handleDocumentClick);
    mounted.root.ownerDocument.removeEventListener('keydown', handleDocumentKeydown);
  }
  mounted = {
    root,
    engine,
    editor,
    pageKind: REPLICA_KIND_ORDER[0],
    drawerKind: REPLICA_KIND_ORDER[0],
    showPlaceholders: true,
    drawerOpen: false,
    drawerOriginPageKind: REPLICA_KIND_ORDER[0],
    drawerRestoreElement: null,
    drawerRestoreFocusKey: null,
    previewPreset: null,
    pointerPreset: null,
    focusedPreset: null,
    replacePicker: null,
    pendingReplace: null,
    status: '',
    dragClickCandidateUid: null,
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
  root.addEventListener('mouseover', handleReplicaMouseOver);
  root.addEventListener('mouseout', handleReplicaMouseOut);
  root.addEventListener('focusin', handleReplicaFocusIn);
  root.addEventListener('focusout', handleReplicaFocusOut);
  root.ownerDocument.addEventListener('pointerdown', handleReplicaPointerDown, true);
  root.ownerDocument.addEventListener('click', handleDocumentClick);
  root.ownerDocument.addEventListener('keydown', handleDocumentKeydown);
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
    selectReplicaPage(kind);
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
  openDrawerInternal(true, mounted?.pageKind, mounted?.root.querySelector('[data-focus-key="drawer-toggle"]'));
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
