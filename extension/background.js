importScripts('defaults.js'); // 버튼 기본값·프리셋은 defaults.js가 단일 출처

const NATIVE_HOST_NAME = 'com.dazebug.terminal_checkout';

// GitHub URL에서 owner·repo와 (PR·이슈면) 번호를 뽑는다. 확장 아이콘은 어느 탭에서나 눌리므로
// 호스트를 정확히 보고(문자열 매칭이면 `example.com/github.com/foo/bar`가 통과한다), 저장소
// 페이지인지는 content.js와 같은 판정(pageTypeOf)에 맡긴다
function parseGitHubUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null; // host 권한이 없는 탭은 url을 주지 않는다
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

// GitHub이 페이지에 심어 두는 리포 정보에서 기본 브랜치를 읽는다. 보고 있는 브랜치가 아니라
// 리포의 기본값이라 `/tree/maint`에서도, upstream과 기본 브랜치가 다른 fork에서도 그 리포
// 자신의 값이 나온다 (실측).
//
// 코드 뷰·이슈 상세에는 이 정보가 있지만 이슈 목록·pulls·Actions 탭에는 없어서(실측) 그때는
// 저장소 홈을 받아 읽는다. 그 fetch는 반드시 여기 — 페이지 쪽에서 해야 한다: service worker에서
// 부르면 확장 origin에서 나가는 요청이라 같은 URL이어도 이 정보가 없는 응답이 온다 (실측:
// 이슈 목록에서 master 리포가 main으로 떨어졌다).
//
// chrome.scripting은 이 함수만 떼어 주입하므로 바깥 상수·헬퍼를 참조할 수 없다.
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

// 못 읽으면 null — 호출부가 오버라이드·글로벌 기본값으로 폴백한다 (종전 동작)
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

// main 브랜치 결정: storage 오버라이드 → 페이지 감지 → 글로벌 기본값
async function resolveMainBranch(repo, detectedMain) {
  const data = await chrome.storage.sync.get(['repoMainBranch', 'defaultMain']);

  // 1. 리포별 오버라이드
  const repoOverride = data.repoMainBranch?.[repo];
  if (repoOverride) return repoOverride;

  // 2. 페이지에서 읽은 값 — PR은 base ref, 저장소·이슈는 리포의 기본 브랜치
  if (detectedMain) return detectedMain;

  // 3. 글로벌 기본값
  return data.defaultMain || DEFAULT_MAIN;
}

async function loadButtons(kind) {
  const { storageKey, defaults } = BUTTON_KINDS[kind];
  const data = await chrome.storage.sync.get([storageKey]);
  return data[storageKey] || defaults;
}

// Native Host에 메시지 전송. 앱은 변수 검증 실패·터미널 실행 실패를 예외가 아니라 정상
// 응답 {success:false, error}로 돌려주므로, 여기서 던져야 버튼에 실패가 드러난다
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
  if (target?.kind !== 'pr') throw new Error('Not a GitHub PR page');

  const button = (await loadButtons('pr'))[buttonIndex];
  if (!button) throw new Error(`Button index ${buttonIndex} not found`);

  // DOM에서 branch와 base branch 추출
  const results = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: getBranchAndMainFromDOM
  });

  const domResult = results[0]?.result;
  if (!domResult?.branch) throw new Error('Could not extract branch name');

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
}

// 커스텀 명령 실행 (이슈 페이지). 이슈에는 head 브랜치가 없어 {branch} 계열 변수를 주지 않는다 —
// 템플릿이 쓰면 앱이 "Variable {branch} not provided"로 거절한다
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

// 커스텀 명령 실행 (저장소 페이지). PR·이슈와 달리 브랜치도 번호도 없어 {repo} {owner} {main}만 준다
async function executeRepoCommand(tab, buttonIndex) {
  // 저장소 버튼은 PR·이슈 페이지 헤더에도 붙으므로 kind는 따지지 않는다
  const target = parseGitHubUrl(tab.url);
  if (!target) throw new Error('Not a GitHub repo page');

  const button = (await loadButtons('repo'))[buttonIndex];
  if (!button) throw new Error(`Repo button index ${buttonIndex} not found`);

  const main = await resolveMainBranch(target.repo, await detectDefaultBranch(tab, target.owner, target.repo));
  console.log(`Executing repo command: repo=${target.repo}, main=${main}`);
  await runButton(button, { repo: target.repo, owner: target.owner, main });
}

// 이 페이지가 정말 저장소로 렌더됐는지 본다. GitHub이 저장소로 그린 페이지에만 헤더에 저장소
// 이름 링크(private이면 자물쇠)가 있고, 404·비저장소 경로에는 없다 (실측). 경로 패턴과 예약어
// 목록만으로는 없는 리포와 앞으로 생길 GitHub 경로를 가릴 수 없다.
// chrome.scripting은 이 함수만 떼어 주입하므로 바깥 상수·헬퍼를 참조할 수 없다.
function isRepoPageFromDOM(owner, repo) {
  const header = document.querySelector('header[role="banner"]');
  if (!header) return false;
  return !!(header.querySelector(`a[href="/${owner}/${repo}"]`) || header.querySelector('svg.octicon-lock'));
}

// 버튼 클릭은 이 확인이 필요 없다 — content script가 같은 단서를 찾아야만 버튼을 붙이므로,
// 눌렸다는 것 자체가 저장소 페이지라는 뜻이다. 확인이 필요한 쪽은 content script를 거치지
// 않는 확장 아이콘 클릭이다
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

// 페이지 종류 → 실행 함수. 확장 아이콘 클릭과 content.js 메시지가 같은 표를 쓴다
const RUN_BY_KIND = { pr: executeCommand, issue: executeIssueCommand, repo: executeRepoCommand };
const ACTION_KIND = { execute_command: 'pr', execute_issue_command: 'issue', execute_repo_command: 'repo' };

// 확장 아이콘 클릭 핸들러 → 페이지에 맞는 첫 번째 버튼 실행 (PR·이슈가 아니면 저장소 버튼)
chrome.action.onClicked.addListener(async (tab) => {
  const target = parseGitHubUrl(tab.url);
  if (!target || !await isRepoPage(tab, target.owner, target.repo)) {
    console.log('Not a GitHub repository page');
    return;
  }
  try {
    await RUN_BY_KIND[target.kind](tab, 0);
  } catch (error) {
    console.error('Error executing command:', error); // 아이콘 클릭에는 실패를 보여줄 버튼이 없다
  }
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
