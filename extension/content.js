// 저장소 헤더 버튼 스타일 — GitHub의 초록 액션 버튼과 같은 모양
const REPO_BUTTON_STYLE = `
  background-color: #238636;
  color: white;
  border: none;
  border-radius: 6px;
  padding: 3px 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  margin-left: 8px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
`;

// 저장소 헤더의 커스텀 명령 버튼. PR·이슈의 아이콘 버튼과 달리 채운 버튼으로 그린다 —
// breadcrumb 옆에서는 아이콘만으로 눈에 띄지 않는다.
// 진행 표시도 얼굴을 따라간다: 텍스트 얼굴을 ⏳ 하나로 바꾸면 버튼이 확 좁아져 헤더가 흔들린다.
function createRepoButton(buttonConfig, index) {
  const face = buttonFace(buttonConfig);
  const phases = isTextFace(face)
    ? { busy: 'Opening...', done: 'Done!', error: 'Error!' }
    : { busy: '⏳', done: '✅', error: '❌' };

  const button = document.createElement('button');
  button.textContent = face;
  button.title = buttonConfig.label;
  button.style.cssText = REPO_BUTTON_STYLE;
  button.className = 'terminal-open-btn';
  button.dataset.btnIndex = index;

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = '#2ea043';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = '#238636';
  });

  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();

    button.textContent = phases.busy;
    button.disabled = true;

    try {
      await runButtonCommand('execute_repo_command', index);
      button.textContent = phases.done;
      setTimeout(() => {
        button.textContent = face;
        button.disabled = false;
      }, 2000);
    } catch (error) {
      console.error('repo command error:', error);
      button.textContent = phases.error;
      setTimeout(() => {
        button.textContent = face;
        button.disabled = false;
      }, 2000);
    }
  });

  return button;
}

// 버튼 하나를 실행한다. sendMessage는 background가 {success:false}를 돌려줘도 reject하지
// 않으므로, 응답을 보지 않으면 명령이 거절돼도 버튼에 성공으로 표시된다
async function runButtonCommand(action, index) {
  const response = await chrome.runtime.sendMessage({ action, buttonIndex: index });
  if (!response?.success) throw new Error(response?.error || 'unknown error');
}

// 페이지 종류별 버튼 설정 (저장 키는 defaults.js의 BUTTON_KINDS가 단일 출처).
// storage가 비었거나 읽지 못하면 기본값으로 그린다 — 버튼이 아예 사라지지는 않게
async function loadButtonConfigs(kind) {
  const { storageKey, defaults } = BUTTON_KINDS[kind];
  try {
    const data = await chrome.storage.sync.get([storageKey]);
    return data[storageKey] || defaults;
  } catch {
    return defaults;
  }
}

// PR 브랜치·이슈 배지 옆 커스텀 명령 버튼 생성 (이모지 아이콘 또는 텍스트 필)
function createCommandIconButton(buttonConfig, index, { action, className }) {
  const face = buttonFace(buttonConfig);
  const button = document.createElement('button');
  button.className = className;
  button.title = buttonConfig.label;
  // flex-shrink:0 — 자리가 모자랄 때 줄어들 몫은 브랜치 이름(GitHub이 말줄임한다)이지 버튼이
  // 아니다. 빼면 텍스트 필이 먼저 찌그러져 무슨 버튼인지 읽을 수 없게 된다
  button.style.cssText = isTextFace(face) ? `
    background: transparent;
    border: 1px solid rgba(87, 171, 90, 0.45);
    cursor: pointer;
    padding: 2px 8px;
    margin-left: 4px;
    display: inline-block;
    flex-shrink: 0;
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    vertical-align: middle;
    border-radius: 2em;
    color: #57ab5a;
    font: 600 11px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
  ` : `
    background: transparent;
    border: none;
    cursor: pointer;
    padding: 4px;
    margin-left: 4px;
    display: inline-flex;
    flex-shrink: 0;
    align-items: center;
    border-radius: 4px;
    color: #57ab5a;
    font-size: 14px;
  `;
  button.textContent = face;
  button.dataset.btnIndex = index;

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = 'rgba(87, 171, 90, 0.1)';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = 'transparent';
  });

  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();

    const originalText = button.textContent;
    button.textContent = '⏳';
    button.disabled = true;

    try {
      await runButtonCommand(action, index);
      button.textContent = '✅';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 1500);
    } catch (error) {
      console.error('command error:', error);
      button.textContent = '❌';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 2000);
    }
  });

  return button;
}

// 새 GitHub 헤더의 breadcrumb 항목(li, display:block) 안에서 인라인 흐름에 맡기면 버튼이
// baseline을 따라 12px쯤 아래로 처진다. 항목을 flex로 바꿔 저장소 이름·드롭다운과 같은
// 선상(교차축 중앙)에 붙인다. 항목 밖(ol의 형제)으로 빼면 breadcrumb 구분자 "/"가 버튼
// 앞에 새로 나타나므로 안에 두는 쪽이 맞다.
function attachToRepoCrumb(anchor, buttons) {
  const crumb = anchor.closest('li');
  if (crumb) {
    crumb.style.display = 'flex';
    crumb.style.alignItems = 'center';
    buttons.forEach(button => crumb.appendChild(button));
    return;
  }
  // 구 UI: breadcrumb가 아닌 헤더. afterend는 바로 뒤에 넣으므로 방금 넣은 버튼을 다음 기준으로
  // 삼아야 설정한 순서대로 늘어선다
  let after = anchor;
  for (const button of buttons) {
    after.insertAdjacentElement('afterend', button);
    after = button;
  }
}

// PR 헤더에 커스텀 명령 버튼들 추가 (성공 시 true 반환)
async function tryInsertPRButtons() {
  // 이미 버튼이 있으면 스킵
  if (document.querySelector('.terminal-cmd-btn')) {
    return true;
  }

  // 새로운 GitHub UI: PR 소스 브랜치 링크 찾기
  const match = location.pathname.match(/^\/([^/]+\/[^/]+)\/pull\/\d+/);
  if (!match) return false;

  // 크로스 포크 PR: head ref 링크가 포크 레포 경로를 가리킬 수 있으므로 모든 tree 링크 검색
  const branchLinks = document.querySelectorAll('a[href*="/tree/"]');

  // 화면에 보이는 브랜치 링크 찾기
  let headBranchLink = null;
  for (const link of branchLinks) {
    const rect = link.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && rect.top < 300 && rect.top > 0) {
      headBranchLink = link;
    }
  }

  if (!headBranchLink) return false;

  const buttons = await loadButtonConfigs('pr');

  // 위의 await 동안 다른 트리거(1초 폴링·MutationObserver·turbo 이벤트)가 먼저 삽입했을
  // 수 있다 — 재확인 없이는 버튼이 2개씩 생긴다
  if (document.querySelector('.terminal-cmd-btn')) {
    return true;
  }

  // head-ref span 바깥에 삽입 (브랜치 뱃지 안에 들어가지 않도록)
  const headRefSpan = headBranchLink.closest('.head-ref');
  // clipboard-copy를 감싼 wrapper span (head-ref의 다음 형제)
  const copyWrapper = headRefSpan?.nextElementSibling;
  const hasCopy = copyWrapper?.querySelector('clipboard-copy');
  const insertAfter = (hasCopy ? copyWrapper : null) || headRefSpan || headBranchLink;

  // 버튼들을 역순으로 삽입 (insertAdjacentElement afterend는 바로 뒤에 넣으므로)
  for (let i = buttons.length - 1; i >= 0; i--) {
    const iconButton = createCommandIconButton(buttons[i], i, {
      action: 'execute_command', className: 'terminal-cmd-btn',
    });
    insertAfter.insertAdjacentElement('afterend', iconButton);
  }

  unclipButtonRow(insertAfter.parentElement, el => getComputedStyle(el).overflowX);

  return true;
}

// 이슈 헤더의 상태 배지 줄(Open · 연결된 PR · 라벨). 제목(h1) 안에 넣으면 제목 길이에 따라
// 다음 줄로 밀리지만, 이 줄은 flex라 배지들과 같은 선상에 안정적으로 붙는다.
function issueBadgeRow() {
  const state = document.querySelector('[data-testid="header-state"]');
  if (!state) return null;
  // 모듈 CSS 클래스명에는 빌드 해시가 붙어 바뀌므로 레이아웃(flex)으로 행을 찾는다
  let element = state.parentElement;
  for (let depth = 0; depth < 4 && element; depth++) {
    if (getComputedStyle(element).display === 'flex') return element;
    element = element.parentElement;
  }
  return state.parentElement;
}

// 이슈 헤더에 이슈 전용 버튼들 추가 (성공 시 true 반환)
async function tryInsertIssueButtons() {
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  const row = issueBadgeRow();
  if (!row) return false;

  const buttons = await loadButtonConfigs('issue');

  // await 동안 다른 트리거(폴링·MutationObserver·turbo 이벤트)가 먼저 삽입했을 수 있다
  if (document.querySelector('.terminal-issue-btn')) {
    return true;
  }

  buttons.forEach((config, index) => {
    row.appendChild(createCommandIconButton(config, index, {
      action: 'execute_issue_command', className: 'terminal-issue-btn',
    }));
  });

  return true;
}

// 저장소 헤더에 버튼들 추가 (성공 시 true 반환)
async function tryInsertRepoButtons() {
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  const header = document.querySelector('header[role="banner"]');
  // Private 저장소: 자물쇠 아이콘이 있는 breadcrumb 항목 / Public: 저장소 이름 링크 뒤
  let anchor = header?.querySelector('svg.octicon-lock');
  if (!anchor) {
    const pathMatch = location.pathname.match(/^\/([^/]+\/[^/]+)/);
    if (!pathMatch) return false;
    anchor = header?.querySelector(`a[href="/${pathMatch[1]}"]`);
  }
  if (!anchor) return false;

  const buttons = await loadButtonConfigs('repo');

  // 위의 await 동안 다른 트리거(1초 폴링·MutationObserver·turbo 이벤트)가 먼저 삽입했을
  // 수 있다 — 재확인 없이는 버튼이 2개씩 생긴다
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  attachToRepoCrumb(anchor, buttons.map((config, index) => createRepoButton(config, index)));
  return true;
}

// 페이지 타입에 따라 버튼 삽입
async function tryInsertButton() {
  const pageType = pageTypeOf(location.pathname);
  if (!pageType) return false;

  let result = false;

  // 저장소·PR·이슈 페이지 모두 헤더에 저장소 버튼을 붙인다
  result = await tryInsertRepoButtons() || result;

  // PR·이슈 페이지는 각자의 커스텀 명령 버튼도 삽입 (설정이 서로 다르다)
  if (pageType === 'pr') {
    result = await tryInsertPRButtons() || result;
  } else if (pageType === 'issue') {
    result = await tryInsertIssueButtons() || result;
  }

  return result;
}

// URL 변경 감지를 위한 History API 래핑
let lastUrl = location.href;

function onUrlChange() {
  if (location.href !== lastUrl) {
    lastUrl = location.href;
    // URL 변경 시 약간의 지연 후 버튼 삽입 시도
    setTimeout(tryInsertButton, 300);
  }
}

// History API 이벤트 감지
const originalPushState = history.pushState;
history.pushState = function(...args) {
  originalPushState.apply(this, args);
  onUrlChange();
};

const originalReplaceState = history.replaceState;
history.replaceState = function(...args) {
  originalReplaceState.apply(this, args);
  onUrlChange();
};

window.addEventListener('popstate', onUrlChange);

// MutationObserver: 헤더 영역이 추가될 때 감지
const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        // 추가된 노드가 관련 요소이거나 포함하고 있으면 버튼 삽입
        if (node.classList?.contains('gh-header-actions') ||
            node.classList?.contains('AppHeader-context-full') ||
            node.querySelector?.('.gh-header-actions') ||
            node.querySelector?.('.AppHeader-context-full')) {
          tryInsertButton();
          return;
        }
      }
    }
  }
});

observer.observe(document.body, {
  childList: true,
  subtree: true
});

// 주기적 폴링 (백업) - 1초마다 체크
setInterval(tryInsertButton, 1000);

// GitHub 네비게이션 이벤트
document.addEventListener('turbo:load', tryInsertButton);
document.addEventListener('turbo:render', tryInsertButton);
document.addEventListener('pjax:end', tryInsertButton);

// 초기 실행
tryInsertButton();
