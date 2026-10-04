/** @typedef {{mount: (root: HTMLElement, engine: OptionsEngine, editor: OptionsEditor) => void}} OptionsReplica */
/** @typedef {{mount: (root: HTMLElement, engine: OptionsEngine) => void, open: (options: OptionsEditorOpenOptions) => void}} OptionsEditor */

/**
 * @typedef {Object} ExampleContext
 * @property {'octo-demo'} owner
 * @property {'sample-repo'} repo
 * @property {{number: 42, branch: 'example/options', base: 'main', title: 'Add button presets'}} pullRequest
 * @property {{number: 17, title: 'Example tracking issue'}} issue
 * @property {'/work/sample-repo'} repoPath
 */

/**
 * @typedef {
 *   'code'|'issues'|'pullRequests'|'actions'|'projects'|'wiki'|'security'|'insights'|'settings'|'search'|
 *   'edit'|'open'|'closed'|'conversation'|'commits'|'checks'|'filesChanged'|'reviewers'|'assignees'|
 *   'labels'|'label'|'milestone'|'milestones'|'development'|'noReviews'|'noneYet'|'newIssue'|
 *   'newPullRequest'|'filters'|'author'|'reviews'|'sort'|'watch'|'fork'|'star'|'public'|'noConflicts'|
 *   'mergingAutomatically'
 * } GitHubUICopyKey
 * @typedef {Readonly<Record<GitHubUICopyKey, string>>} GitHubUICopy
 */

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
});

/** @type {OptionsReplica} */
window.optionsReplica = Object.freeze({
  /** @param {HTMLElement} root @param {OptionsEngine} engine @param {OptionsEditor} editor */
  mount(root, engine, editor) {},
  /** @returns {Readonly<ExampleContext>} */
  getExampleContext() { return EXAMPLE_CONTEXT; },
  EXAMPLE_CONTEXT,
  GITHUB_UI_COPY,
});
