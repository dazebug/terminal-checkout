importScripts('defaults.js'); // defaults.js is the single source of truth for button defaults and presets

const NATIVE_HOST_NAME = 'com.dazebug.terminal_checkout';

// Pull owner/repo — and the number, on PR and issue pages — out of a GitHub URL. The extension icon
// can be clicked on any tab, so check the host exactly (a string match would let
// `example.com/github.com/foo/bar` through) and leave "is this a repository page?" to the same
// decision content.js makes (pageTypeOf)
function parseGitHubUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null; // tabs we have no host permission for don't hand us a url
  }
  if (parsed.hostname !== 'github.com') return null;

  const kind = pageTypeOf(parsed.pathname);
  if (!kind) return null;

  const [, owner, repo] = parsed.pathname.split('/');
  return {
    owner,
    repo,
    kind,
    number: parsed.pathname.match(/\/(?:pull|issues)\/(\d+)/)?.[1] || null,
  };
}

// Extract the branch name and the base branch from the DOM
function getBranchAndMainFromDOM() {
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

  if (headBranch) return { branch: headBranch, detectedMain: baseBranch };

  // Legacy UI fallback 1: head-ref element
  const headRef = document.querySelector('.head-ref a, .head-ref span');
  if (headRef) {
    const baseRef = document.querySelector('.base-ref a, .base-ref span');
    return {
      branch: headRef.textContent.trim(),
      detectedMain: baseRef ? baseRef.textContent.trim() : null
    };
  }

  // Legacy UI fallback 2: commit-ref
  const branchElement = document.querySelector('.commit-ref.head-ref');
  if (branchElement) {
    const baseElement = document.querySelector('.commit-ref.base-ref');
    return {
      branch: branchElement.textContent.trim(),
      detectedMain: baseElement ? baseElement.textContent.trim() : null
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
  for (const script of document.querySelectorAll('script[type="application/json"]')) {
    const match = script.textContent.match(pattern);
    if (match) return match[1];
  }
  try {
    const html = await (await fetch(`/${owner}/${repo}`)).text();
    return html.match(pattern)?.[1] || null;
  } catch {
    return null;
  }
}

// null when it can't be read — the caller falls back to the override or the global default
async function detectDefaultBranch(tab, owner, repo) {
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: getDefaultBranchFromPage,
      args: [owner, repo],
    });
    return results[0]?.result || null;
  } catch (error) {
    console.error('Could not detect default branch:', error);
    return null;
  }
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

// Send a message to the native host. The app reports variable validation failures and terminal
// launch failures as a normal {success:false, error} response rather than an exception, so we have
// to throw here for the failure to surface on the button
async function sendToNativeHost(message) {
  let response;
  try {
    response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch (error) {
    console.error('Native host error:', error);
    throw error;
  }
  console.log('Native host response:', response);
  if (!response?.success) throw new Error(response?.error || 'native host returned no result');
  return response;
}

// Run a single button — variable substitution and claude input delivery are the app's job, so we
// only send the raw material
async function runButton(button, variables) {
  const message = { command_template: button.command, variables };
  // Inputs to type, in order, into the claude session the command starts (the app delivers them
  // once it has confirmed claude is up)
  const claudeInputs = (button.claudeInputs || []).map(s => String(s).trim()).filter(Boolean);
  if (claudeInputs.length) message.claude_inputs = claudeInputs;
  await sendToNativeHost(message);
}

// Run a custom command (PR page)
async function executeCommand(tab, buttonIndex) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'pr') throw new Error('Not a GitHub PR page');

  const button = (await loadButtons('pr'))[buttonIndex];
  if (!button) throw new Error(`Button index ${buttonIndex} not found`);

  // Extract the branch and the base branch from the DOM
  const results = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: getBranchAndMainFromDOM
  });

  const domResult = results[0]?.result;
  if (!domResult?.branch) throw new Error('Could not extract branch name');

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
  await runButton(button, variables);
}

// Run a custom command (issue page). An issue has no head branch, so the {branch} family of
// variables isn't passed — if a template uses one, the app rejects it with
// "Variable {branch} not provided"
async function executeIssueCommand(tab, buttonIndex) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'issue') throw new Error('Not a GitHub issue page');

  const button = (await loadButtons('issue'))[buttonIndex];
  if (!button) throw new Error(`Issue button index ${buttonIndex} not found`);

  const main = await resolveMainBranch(target.repo, await detectDefaultBranch(tab, target.owner, target.repo));
  console.log(`Executing issue command: repo=${target.repo}, number=${target.number}, main=${main}`);
  await runButton(button, {
    repo: target.repo,
    owner: target.owner,
    number: target.number,
    main,
  });
}

// Run a custom command (repository page). Unlike PRs and issues there is neither a branch nor a
// number, so only {repo}, {owner}, and {main} are passed
async function executeRepoCommand(tab, buttonIndex) {
  // Repository buttons are also attached to the header of PR and issue pages, so don't check kind
  const target = parseGitHubUrl(tab.url);
  if (!target) throw new Error('Not a GitHub repo page');

  const button = (await loadButtons('repo'))[buttonIndex];
  if (!button) throw new Error(`Repo button index ${buttonIndex} not found`);

  const main = await resolveMainBranch(target.repo, await detectDefaultBranch(tab, target.owner, target.repo));
  console.log(`Executing repo command: repo=${target.repo}, main=${main}`);
  await runButton(button, { repo: target.repo, owner: target.owner, main });
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

// Extension icon click handler → run the first button for this page (repository buttons when it is
// neither a PR nor an issue)
chrome.action.onClicked.addListener(async (tab) => {
  const target = parseGitHubUrl(tab.url);
  if (!target || !await isRepoPage(tab, target.owner, target.repo)) {
    console.log('Not a GitHub repository page');
    return;
  }
  try {
    await RUN_BY_KIND[target.kind](tab, 0);
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
  const kind = Object.hasOwn(ACTION_KIND, message.action) ? ACTION_KIND[message.action] : null;
  if (!kind) return;
  // The index picks a button out of an array; anything that is not one is not a request we can serve
  if (!Number.isInteger(message.buttonIndex)) return;

  RUN_BY_KIND[kind](sender.tab, message.buttonIndex).then(() => {
    sendResponse({ success: true });
  }).catch((error) => {
    sendResponse({ success: false, error: error.message });
  });
  return true; // return true to respond asynchronously
});
