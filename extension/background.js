importScripts('defaults.js'); // 버튼 기본값·프리셋은 defaults.js가 단일 출처

const NATIVE_HOST_NAME = 'com.dazebug.terminal_checkout';

// GitHub URL에서 owner·repo와 (PR·이슈면) 번호를 뽑는다
function parseGitHubUrl(url) {
  const match = url.match(/github\.com\/([^/]+)\/([^/?#]+)(?:\/(pull|issues)\/(\d+))?/);
  if (!match) return null;
  return {
    owner: match[1],
    repo: match[2],
    kind: match[3] === 'pull' ? 'pr' : match[3] === 'issues' ? 'issue' : null,
    number: match[4] || null,
  };
}

// DOM에서 브랜치명과 base 브랜치 추출
function getBranchAndMainFromDOM() {
  const match = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+/);
  if (!match) return null;

  // 크로스 포크 PR: head ref 링크가 포크 레포 경로를 가리킬 수 있으므로 모든 tree 링크 검색
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
          baseBranch = branch; // 첫 번째 visible = base ref
        }
        headBranch = branch; // 마지막 visible = head ref
      }
    }
  }

  if (headBranch) return { branch: headBranch, detectedMain: baseBranch };

  // 구 UI 대안 1: head-ref 요소
  const headRef = document.querySelector('.head-ref a, .head-ref span');
  if (headRef) {
    const baseRef = document.querySelector('.base-ref a, .base-ref span');
    return {
      branch: headRef.textContent.trim(),
      detectedMain: baseRef ? baseRef.textContent.trim() : null
    };
  }

  // 구 UI 대안 2: commit-ref
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

// main 브랜치 결정: storage 오버라이드 → PR 페이지 감지 → 글로벌 기본값
async function resolveMainBranch(repo, detectedMain) {
  const data = await chrome.storage.sync.get(['repoMainBranch', 'defaultMain']);

  // 1. 리포별 오버라이드
  const repoOverride = data.repoMainBranch?.[repo];
  if (repoOverride) return repoOverride;

  // 2. PR 페이지에서 감지된 base branch
  if (detectedMain) return detectedMain;

  // 3. 글로벌 기본값
  return data.defaultMain || DEFAULT_MAIN;
}

// 페이지마다 버튼 설정이 다른 키에 저장된다 (options.js의 SECTIONS와 같은 짝)
const BUTTON_STORAGE = {
  pr: { key: 'buttons', defaults: DEFAULT_BUTTONS },
  issue: { key: 'issueButtons', defaults: DEFAULT_ISSUE_BUTTONS },
  repo: { key: 'repoButtons', defaults: DEFAULT_REPO_BUTTONS },
};

async function loadButtons(kind) {
  const { key, defaults } = BUTTON_STORAGE[kind];
  const data = await chrome.storage.sync.get([key]);
  return data[key] || defaults;
}

// Native Host에 메시지 전송
async function sendToNativeHost(message) {
  try {
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
    console.log('Native host response:', response);
    return response;
  } catch (error) {
    console.error('Native host error:', error);
    throw error;
  }
}

// 버튼 하나를 실행한다 — 변수 치환과 claude 입력 전달은 앱이 담당하므로 여기서는 재료만 보낸다
async function runButton(button, variables) {
  const message = { command_template: button.command, variables };
  // command가 띄운 claude 세션에 순서대로 타이핑할 입력들 (앱이 claude 기동을 확인한 뒤 전달)
  const claudeInputs = (button.claudeInputs || []).map(s => String(s).trim()).filter(Boolean);
  if (claudeInputs.length) message.claude_inputs = claudeInputs;
  await sendToNativeHost(message);
}

// 커스텀 명령 실행 (PR 페이지)
async function executeCommand(tab, buttonIndex) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'pr') {
    console.log('Not a GitHub PR page');
    return;
  }

  const buttons = await loadButtons('pr');
  const button = buttons[buttonIndex];
  if (!button) {
    console.error(`Button index ${buttonIndex} not found`);
    return;
  }

  try {
    // DOM에서 branch와 base branch 추출
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: getBranchAndMainFromDOM
    });

    const domResult = results[0]?.result;
    if (!domResult?.branch) {
      console.error('Could not extract branch name');
      return;
    }

    const main = await resolveMainBranch(target.repo, domResult.detectedMain);

    // 어느 터미널에서 실행할지는 Terminal Checkout 앱 설정이 결정한다
    console.log(`Executing command: repo=${target.repo}, branch=${domResult.branch}, main=${main}`);
    const variables = {
      repo: target.repo,
      owner: target.owner,
      number: target.number,
      branch: domResult.branch,
      main,
      branch_underbar: domResult.branch.replace(/\//g, '_'),
    };
    // {base}: 이 PR이 머지될 브랜치. 오버라이드·글로벌 기본값을 거치는 {main}과 달리 페이지에서 읽은
    // 값만 쓴다 — 못 읽었으면 아예 넘기지 않아 앱이 not provided로 거절하게 한다 (다른 브랜치로
    // 조용히 대체하면 엉뚱한 브랜치에 머지·리베이스하게 되므로)
    if (domResult.detectedMain) variables.base = domResult.detectedMain;
    await runButton(button, variables);
  } catch (error) {
    console.error('Error executing command:', error);
  }
}

// 커스텀 명령 실행 (이슈 페이지). 이슈에는 head 브랜치가 없어 {branch} 계열 변수를 주지 않는다 —
// 템플릿이 쓰면 앱이 "Variable {branch} not provided"로 거절한다
async function executeIssueCommand(tab, buttonIndex) {
  const target = parseGitHubUrl(tab.url);
  if (target?.kind !== 'issue') {
    console.log('Not a GitHub issue page');
    return;
  }

  const buttons = await loadButtons('issue');
  const button = buttons[buttonIndex];
  if (!button) {
    console.error(`Issue button index ${buttonIndex} not found`);
    return;
  }

  try {
    const main = await resolveMainBranch(target.repo, null);
    console.log(`Executing issue command: repo=${target.repo}, number=${target.number}`);
    await runButton(button, {
      repo: target.repo,
      owner: target.owner,
      number: target.number,
      main,
    });
  } catch (error) {
    console.error('Error executing issue command:', error);
  }
}

// 커스텀 명령 실행 (저장소 페이지). PR·이슈와 달리 브랜치도 번호도 없어 {repo} {owner} {main}만 준다
async function executeRepoCommand(tab, buttonIndex) {
  const target = parseGitHubUrl(tab.url);
  if (!target) {
    console.log('Not a GitHub repo page');
    return;
  }

  const buttons = await loadButtons('repo');
  const button = buttons[buttonIndex];
  if (!button) {
    console.error(`Repo button index ${buttonIndex} not found`);
    return;
  }

  try {
    // 저장소 페이지에는 PR base가 없다 — 리포별 오버라이드 또는 글로벌 기본값으로 정해진다
    const main = await resolveMainBranch(target.repo, null);
    console.log(`Executing repo command: repo=${target.repo}, main=${main}`);
    await runButton(button, { repo: target.repo, owner: target.owner, main });
  } catch (error) {
    console.error('Error executing repo command:', error);
  }
}

// 페이지 종류 → 실행 함수. 확장 아이콘 클릭과 content.js 메시지가 같은 표를 쓴다
const RUN_BY_KIND = { pr: executeCommand, issue: executeIssueCommand, repo: executeRepoCommand };
const ACTION_KIND = { execute_command: 'pr', execute_issue_command: 'issue', execute_repo_command: 'repo' };

// 확장 아이콘 클릭 핸들러 → 페이지에 맞는 첫 번째 버튼 실행 (PR·이슈가 아니면 저장소 버튼)
chrome.action.onClicked.addListener(async (tab) => {
  await RUN_BY_KIND[parseGitHubUrl(tab.url)?.kind || 'repo'](tab, 0);
});

// content.js에서 메시지 수신
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const kind = ACTION_KIND[message.action];
  if (!kind) return;

  RUN_BY_KIND[kind](sender.tab, message.buttonIndex).then(() => {
    sendResponse({ success: true });
  }).catch((error) => {
    sendResponse({ success: false, error: error.message });
  });
  return true; // 비동기 응답을 위해 true 반환
});
