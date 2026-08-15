const NATIVE_HOST_NAME = 'com.dazebug.terminal_checkout';

const DEFAULT_BUTTONS = [
  // checkout 실패(브랜치가 워크트리에 체크아웃됨 등) 시 관례 경로의 워크트리로 이동
  { emoji: '⏏️', label: 'Checkout Branch', command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }' }
];

const DEFAULT_MAIN = 'main';

// GitHub PR URL에서 repo 이름 추출
function extractRepoFromUrl(url) {
  const match = url.match(/github\.com\/([^/]+)\/([^/]+)/);
  if (match) {
    return match[2]; // repo 이름만 반환
  }
  return null;
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

// DOM에서 브랜치명만 추출 (기존 호환용)
function getBranchFromDOM() {
  const result = getBranchAndMainFromDOM();
  return result ? result.branch : null;
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

// 버튼 설정 로드
async function loadButtons() {
  const data = await chrome.storage.sync.get(['buttons']);
  return data.buttons || DEFAULT_BUTTONS;
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

// 커스텀 명령 실행 (PR 페이지)
async function executeCommand(tab, buttonIndex) {
  const url = tab.url;

  // GitHub PR 페이지인지 확인
  if (!url.match(/github\.com\/[^/]+\/[^/]+\/pull\/\d+/)) {
    console.log('Not a GitHub PR page');
    return;
  }

  const repo = extractRepoFromUrl(url);
  if (!repo) {
    console.error('Could not extract repo from URL');
    return;
  }

  const buttons = await loadButtons();
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

    const main = await resolveMainBranch(repo, domResult.detectedMain);

    // 어느 터미널에서 실행할지는 Terminal Checkout 앱 설정이 결정한다
    console.log(`Executing command: repo=${repo}, branch=${domResult.branch}, main=${main}`);
    await sendToNativeHost({
      command_template: button.command,
      variables: { repo, branch: domResult.branch, main, branch_underbar: domResult.branch.replace(/\//g, '_') }
    });
  } catch (error) {
    console.error('Error executing command:', error);
  }
}

// checkout 실행 (PR 페이지) - 하위 호환
async function executeCheckout(tab) {
  const url = tab.url;

  // GitHub PR 페이지인지 확인
  if (!url.match(/github\.com\/[^/]+\/[^/]+\/pull\/\d+/)) {
    console.log('Not a GitHub PR page');
    return;
  }

  const repo = extractRepoFromUrl(url);
  if (!repo) {
    console.error('Could not extract repo from URL');
    return;
  }

  // content script에서 브랜치명 가져오기
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: getBranchFromDOM
    });

    const branch = results[0]?.result;
    if (!branch) {
      console.error('Could not extract branch name');
      return;
    }

    console.log(`Checking out ${repo}:${branch}`);
    await sendToNativeHost({ repo, branch });
  } catch (error) {
    console.error('Error executing checkout:', error);
  }
}

// open 실행 (저장소 페이지)
async function executeOpen(tab) {
  const url = tab.url;

  // GitHub 저장소 페이지인지 확인
  if (!url.match(/github\.com\/[^/]+\/[^/]+/)) {
    console.log('Not a GitHub repo page');
    return;
  }

  const repo = extractRepoFromUrl(url);
  if (!repo) {
    console.error('Could not extract repo from URL');
    return;
  }

  console.log(`Opening ${repo}`);
  await sendToNativeHost({ command_template: 'z {repo}', variables: { repo } });
}

// 확장 아이콘 클릭 핸들러 → 첫 번째 버튼 실행
chrome.action.onClicked.addListener(async (tab) => {
  await executeCommand(tab, 0);
});

// content.js에서 메시지 수신
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'execute_command') {
    executeCommand(sender.tab, message.buttonIndex).then(() => {
      sendResponse({ success: true });
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true; // 비동기 응답을 위해 true 반환
  }

  if (message.action === 'checkout') {
    executeCheckout(sender.tab).then(() => {
      sendResponse({ success: true });
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true;
  }

  if (message.action === 'open') {
    executeOpen(sender.tab).then(() => {
      sendResponse({ success: true });
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true;
  }
});
