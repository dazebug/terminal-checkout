// Terminal Checkout 버튼 스타일
const BUTTON_STYLE = `
  background-color: #238636;
  color: white;
  border: none;
  border-radius: 6px;
  padding: 5px 12px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  margin-left: 8px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
`;

const DEFAULT_BUTTONS = [
  // checkout 실패(브랜치가 워크트리에 체크아웃됨 등) 시 관례 경로의 워크트리로 이동
  { face: '⏏️', label: 'Checkout Branch', command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }' }
];

// 버튼 표시 텍스트. face가 새 키이고 emoji는 구버전 저장값 호환용이다.
function buttonFace(config) {
  return (config.face ?? config.emoji ?? '').trim() || '⏏️';
}

// 글자·숫자가 섞이면 텍스트 필(pill)로, 이모지만이면 아이콘으로 그린다.
// 이 스타일은 옵션 페이지의 미리보기(options.js)와 짝을 이룬다 — 바꾸면 같이 바꿀 것.
function isTextFace(face) {
  return /[\p{L}\p{N}]/u.test(face);
}

// 페이지 타입 감지
function getPageType() {
  const path = location.pathname;
  if (path.match(/\/pull\/\d+/)) return 'pr';
  if (path.match(/^\/[^/]+\/[^/]+\/?$/) || path.match(/^\/[^/]+\/[^/]+\/(tree|blob|issues|actions|settings|releases|tags|wiki|security|pulse|graphs|network|projects|commits|branches|pulls|discussions|compare)/)) return 'repo';
  return null;
}

// 버튼 생성 (공통 - 저장소 페이지용)
function createButton(text, action) {
  const button = document.createElement('button');
  button.textContent = text;
  button.style.cssText = BUTTON_STYLE;
  button.className = action === 'checkout' ? 'terminal-checkout-btn' : 'terminal-open-btn';

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = '#2ea043';
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = '#238636';
  });

  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();

    const originalText = button.textContent;
    button.textContent = action === 'checkout' ? 'Checking out...' : 'Opening...';
    button.disabled = true;

    try {
      await chrome.runtime.sendMessage({ action: action });
      button.textContent = 'Done!';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 2000);
    } catch (error) {
      console.error(`${action} error:`, error);
      button.textContent = 'Error!';
      setTimeout(() => {
        button.textContent = originalText;
        button.disabled = false;
      }, 2000);
    }
  });

  return button;
}

// PR 브랜치 옆 커스텀 명령 버튼 생성 (이모지 아이콘 또는 텍스트 필)
function createCommandIconButton(buttonConfig, index) {
  const face = buttonFace(buttonConfig);
  const button = document.createElement('button');
  button.className = 'terminal-cmd-btn';
  button.title = buttonConfig.label;
  button.style.cssText = isTextFace(face) ? `
    background: transparent;
    border: 1px solid rgba(87, 171, 90, 0.45);
    cursor: pointer;
    padding: 2px 8px;
    margin-left: 4px;
    display: inline-block;
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
      await chrome.runtime.sendMessage({ action: 'execute_command', buttonIndex: index });
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

// 저장소 페이지용 open 버튼 생성 (터미널 선택은 앱이 관리하므로 라벨은 중립적으로)
async function createOpenButton() {
  return createButton('Open in Terminal', 'open');
}

// 새 GitHub 헤더의 breadcrumb 항목(li, display:block) 안에서 인라인 흐름에 맡기면 버튼이
// baseline을 따라 12px쯤 아래로 처진다. 항목을 flex로 바꿔 저장소 이름·드롭다운과 같은
// 선상(교차축 중앙)에 붙인다. 항목 밖(ol의 형제)으로 빼면 breadcrumb 구분자 "/"가 버튼
// 앞에 새로 나타나므로 안에 두는 쪽이 맞다.
function attachToRepoCrumb(anchor, button) {
  const crumb = anchor.closest('li');
  if (crumb) {
    crumb.style.display = 'flex';
    crumb.style.alignItems = 'center';
    crumb.appendChild(button);
  } else {
    anchor.insertAdjacentElement('afterend', button); // 구 UI: breadcrumb가 아닌 헤더
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

  // storage에서 버튼 설정 로드
  let buttons;
  try {
    const data = await chrome.storage.sync.get(['buttons']);
    buttons = data.buttons || DEFAULT_BUTTONS;
  } catch {
    buttons = DEFAULT_BUTTONS;
  }

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
    const iconButton = createCommandIconButton(buttons[i], i);
    insertAfter.insertAdjacentElement('afterend', iconButton);
  }

  return true;
}

// 저장소 헤더에 버튼 추가 (성공 시 true 반환)
async function tryInsertRepoButton() {
  if (document.querySelector('.terminal-open-btn')) {
    return true;
  }

  const header = document.querySelector('header[role="banner"]');
  const lockIcon = header?.querySelector('svg.octicon-lock');

  if (lockIcon) {
    // Private 저장소: 자물쇠 아이콘이 있는 breadcrumb 항목에 추가
    const button = await createOpenButton();
    // await 사이에 다른 트리거가 먼저 삽입했으면 중복을 만들지 않는다
    if (document.querySelector('.terminal-open-btn')) return true;
    button.style.padding = '3px 8px';
    button.style.fontSize = '11px';
    attachToRepoCrumb(lockIcon, button);
    return true;
  }

  // Public 저장소: 저장소 이름 링크 뒤에 추가
  const pathMatch = location.pathname.match(/^\/([^/]+\/[^/]+)/);
  if (!pathMatch) return false;

  const repoPath = '/' + pathMatch[1];
  const repoLink = header?.querySelector(`a[href="${repoPath}"]`);
  if (repoLink) {
    const button = await createOpenButton();
    if (document.querySelector('.terminal-open-btn')) return true;
    button.style.padding = '3px 8px';
    button.style.fontSize = '11px';
    attachToRepoCrumb(repoLink, button);
    return true;
  }

  return false;
}

// 페이지 타입에 따라 버튼 삽입
async function tryInsertButton() {
  const pageType = getPageType();
  if (!pageType) return false;

  let result = false;

  // 저장소/PR 페이지 모두 헤더에 Open 버튼 삽입
  result = await tryInsertRepoButton() || result;

  // PR 페이지는 추가로 커스텀 명령 버튼도 삽입
  if (pageType === 'pr') {
    result = await tryInsertPRButtons() || result;
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
