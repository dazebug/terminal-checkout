// Public data and mount contract checks for the replica module, without rendering a DOM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../extension/options-replica.js'), 'utf8');
const expectedCopy = {
  code: 'Code', issues: 'Issues', pullRequests: 'Pull requests', actions: 'Actions', projects: 'Projects',
  wiki: 'Wiki', security: 'Security', insights: 'Insights', settings: 'Settings', search: 'Type / to search',
  edit: 'Edit', open: 'Open', closed: 'Closed', conversation: 'Conversation', commits: 'Commits',
  checks: 'Checks', filesChanged: 'Files changed', reviewers: 'Reviewers', assignees: 'Assignees',
  labels: 'Labels', label: 'Label', milestone: 'Milestone', milestones: 'Milestones', development: 'Development',
  noReviews: 'No reviews', noneYet: 'None yet', newIssue: 'New issue', newPullRequest: 'New pull request',
  filters: 'Filters', author: 'Author', reviews: 'Reviews', sort: 'Sort', watch: 'Watch', fork: 'Fork',
  star: 'Star', public: 'Public', noConflicts: 'No conflicts with base branch',
  mergingAutomatically: 'Merging can be performed automatically.',
};

test('replica publishes the example context, GitHub copy table, and mount contract', () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(source, context);
  const api = context.window.optionsReplica;
  assert.deepEqual(Object.keys(api).sort(), ['EXAMPLE_CONTEXT', 'GITHUB_UI_COPY', 'getExampleContext', 'mount'].sort());
  assert.equal(api.mount.length, 3);
  assert.equal(typeof api.getExampleContext, 'function');
  assert.equal(api.getExampleContext(), api.EXAMPLE_CONTEXT);
  assert.equal(api.EXAMPLE_CONTEXT.owner, 'octo-demo');
  assert.equal(api.EXAMPLE_CONTEXT.repo, 'sample-repo');
  assert.equal(api.EXAMPLE_CONTEXT.pullRequest.number, 42);
  assert.equal(api.EXAMPLE_CONTEXT.pullRequest.branch, 'example/options');
  assert.equal(api.EXAMPLE_CONTEXT.pullRequest.base, 'main');
  assert.equal(api.EXAMPLE_CONTEXT.pullRequest.title, 'Add button presets');
  assert.equal(api.EXAMPLE_CONTEXT.issue.number, 17);
  assert.equal(api.EXAMPLE_CONTEXT.issue.title, 'Example tracking issue');
  assert.equal(api.EXAMPLE_CONTEXT.repoPath, '/work/sample-repo');
  assert.deepEqual(JSON.parse(JSON.stringify(api.GITHUB_UI_COPY)), expectedCopy);
  assert.equal(Object.values(api.GITHUB_UI_COPY).every(value => typeof value === 'string'), true);
  assert.equal(Object.isFrozen(api.EXAMPLE_CONTEXT), true);
  assert.equal(Object.isFrozen(api.EXAMPLE_CONTEXT.pullRequest), true);
  assert.equal(Object.isFrozen(api.EXAMPLE_CONTEXT.issue), true);
  assert.equal(Object.isFrozen(api.GITHUB_UI_COPY), true);
});

test('replica documents the example and GitHub copy types', () => {
  assert.match(source, /@typedef \{Object\} ExampleContext/);
  assert.match(source, /@typedef \{Readonly<Record<GitHubUICopyKey, string>>\} GitHubUICopy/);
  assert.match(source, /@param \{HTMLElement\} root/);
  assert.match(source, /@param \{OptionsEngine\} engine/);
  assert.match(source, /@param \{OptionsEditor\} editor/);
});
