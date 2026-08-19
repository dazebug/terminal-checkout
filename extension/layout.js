// GitHub 헤더에 버튼을 끼워 넣을 때 필요한 레이아웃 보정. DOM 노드만 다루고 chrome API·전역
// document를 모르므로 순수 함수로 테스트한다 (tests/layout.test.js). 유일한 전역 의존인
// getComputedStyle은 인자로 받는다 — node 테스트에는 그 전역이 없다.

// PR 헤더 구조(실측): [버튼 칸 overflow:hidden] → [브랜치 줄] → [헤더 메타 행 overflow:hidden].
// flex 항목의 기본값 min-width:auto는 "내용보다 작아지지 않는다"는 뜻이라, 버튼을 끼워 넣은
// 만큼 브랜치 줄이 넓어지고 그 줄이 헤더 메타 행 밖으로 밀려 오른쪽 버튼부터 잘려 나간다.
// 잘라내는 조상까지 min-width:0을 심으면 GitHub 본래대로 브랜치 이름이 말줄임되고 버튼이
// 자리를 지킨다. 버튼 칸 자신도 overflow:hidden이라 거기서 멈추면 아무 효과가 없다.
//
// 브랜치 이름을 끝까지 줄여도 모자랄 만큼 창이 좁으면 그마저 잘리므로, 버튼 칸만
// flex-wrap:wrap으로 두어 마지막 수단으로 다음 줄에 접히게 한다. 브랜치 줄까지 접으면
// "from"과 브랜치 이름이 서로 떨어져 문장이 끊겨 보인다.
const UNCLIP_MAX_DEPTH = 6; // 잘라내는 조상을 못 찾았을 때 페이지 전체로 번지지 않게 하는 상한

function unclipButtonRow(buttonHost, overflowXOf) {
  buttonHost.style.flexWrap = 'wrap';
  for (let el = buttonHost, depth = 0; el && depth < UNCLIP_MAX_DEPTH; el = el.parentElement, depth++) {
    el.style.minWidth = '0';
    if (depth > 0 && overflowXOf(el) !== 'visible') return;
  }
}
