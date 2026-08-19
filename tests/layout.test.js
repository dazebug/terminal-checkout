// extension/layout.js의 순수 함수 테스트 — 리포 루트에서 의존성 없이 `node --test`로 돌린다.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// layout.js는 브라우저용 클래식 스크립트라 export가 없다 (tests/buttons.test.js와 같은 방식).
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../extension/layout.js'), 'utf8'));
const { unclipButtonRow, UNCLIP_MAX_DEPTH } = vm.runInThisContext('({ unclipButtonRow, UNCLIP_MAX_DEPTH })');

// 실제 GitHub PR 헤더를 본뜬 가짜 DOM. 자식 → 조상 순으로 넘긴 overflow-x 값으로 사슬을 만든다
function chain(...overflows) {
  const nodes = overflows.map(overflowX => ({ style: {}, overflowX }));
  nodes.forEach((node, i) => { node.parentElement = nodes[i + 1] || null; });
  return nodes;
}
const overflowXOf = node => node.overflowX;
const minWidths = nodes => nodes.map(n => n.style.minWidth);

// 실측한 구조: [버튼 칸 hidden] → [브랜치 줄 visible] → [헤더 메타 행 hidden] → [그 위 visible]
const prHeader = () => chain('hidden', 'visible', 'hidden', 'visible');

test('unclipButtonRow: 버튼 칸 자신이 overflow:hidden이어도 멈추지 않는다', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  // 여기서 멈추면 정작 줄어들어야 할 브랜치 줄이 그대로라 버튼이 계속 잘린다
  assert.equal(nodes[1].style.minWidth, '0');
});

test('unclipButtonRow: 잘라내는 조상까지만 심고 그 위는 건드리지 않는다', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  assert.deepEqual(minWidths(nodes), ['0', '0', '0', undefined]);
});

test('unclipButtonRow: 잘라내는 조상이 없으면 상한에서 멈춘다', () => {
  const nodes = chain(...Array(UNCLIP_MAX_DEPTH * 3).fill('visible')); // 상한보다 훨씬 긴 사슬
  unclipButtonRow(nodes[0], overflowXOf);
  assert.equal(minWidths(nodes).filter(v => v === '0').length, UNCLIP_MAX_DEPTH);
});

test('unclipButtonRow: 그래도 모자라면 버튼이 다음 줄로 접히게 한다', () => {
  const nodes = prHeader();
  unclipButtonRow(nodes[0], overflowXOf);
  assert.equal(nodes[0].style.flexWrap, 'wrap');
  assert.equal(nodes[1].style.flexWrap, undefined); // 브랜치 줄까지 접으면 "from"이 따로 떨어진다
});
