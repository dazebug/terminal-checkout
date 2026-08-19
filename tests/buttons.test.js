// extension/defaults.js의 순수 함수 테스트 — 리포 루트에서 의존성 없이 `node --test`로 돌린다.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// defaults.js는 브라우저용 클래식 스크립트라 export가 없다. 통째로 실행한 뒤 이름을 평가해
// 꺼낸다 (스크립트의 top-level const는 globalThis에 붙지 않아 한 번 더 평가해야 한다).
// 별도 컨텍스트가 아니라 이 컨텍스트에서 실행한다 — vm 안에서 만든 객체는 프로토타입이 달라
// deepStrictEqual이 구조가 같아도 실패한다.
vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../extension/defaults.js'), 'utf8'));
const { moveButton, duplicateButton } = vm.runInThisContext('({ moveButton, duplicateButton })');
const { BUTTON_KINDS, pageTypeOf } = vm.runInThisContext('({ BUTTON_KINDS, pageTypeOf })');

const faces = list => list.map(b => b.face);
const sample = () => [
  { face: 'a', label: 'A', command: 'ca', claudeInputs: ['a1'] },
  { face: 'b', label: 'B', command: 'cb', claudeInputs: [] },
  { face: 'c', label: 'C', command: 'cc', claudeInputs: [] },
];

test('moveButton: 뒤로 옮길 때 뺀 만큼 당겨진 자리에 들어간다', () => {
  assert.deepEqual(faces(moveButton(sample(), 0, 3)), ['b', 'c', 'a']); // 맨 끝으로
  assert.deepEqual(faces(moveButton(sample(), 0, 2)), ['b', 'a', 'c']); // c 앞으로
});

test('moveButton: 앞으로 옮길 때는 그 자리에 그대로 들어간다', () => {
  assert.deepEqual(faces(moveButton(sample(), 2, 0)), ['c', 'a', 'b']);
  assert.deepEqual(faces(moveButton(sample(), 2, 1)), ['a', 'c', 'b']);
});

test('moveButton: 제자리 드롭은 순서를 바꾸지 않는다', () => {
  assert.deepEqual(faces(moveButton(sample(), 1, 1)), ['a', 'b', 'c']); // 자기 앞
  assert.deepEqual(faces(moveButton(sample(), 1, 2)), ['a', 'b', 'c']); // 자기 뒤
});

test('moveButton: 원본 배열을 건드리지 않는다', () => {
  const original = sample();
  moveButton(original, 0, 3);
  assert.deepEqual(faces(original), ['a', 'b', 'c']);
});

test('duplicateButton: 사본이 원본 바로 뒤에 들어간다', () => {
  const next = duplicateButton(sample(), 0);
  assert.deepEqual(faces(next), ['a', 'a', 'b', 'c']);
  assert.deepEqual({ ...next[1], label: next[0].label }, next[0]); // 툴팁 말고는 그대로
});

test('duplicateButton: 사본 툴팁 뒤에 번호가 붙는다', () => {
  assert.equal(duplicateButton(sample(), 0)[1].label, 'A (1)');
});

test('duplicateButton: 이미 쓰는 번호는 건너뛴다', () => {
  const once = duplicateButton(sample(), 0);       // A, A (1), B, C
  assert.equal(duplicateButton(once, 0)[1].label, 'A (2)'); // 원본을 다시 복제
  assert.equal(duplicateButton(once, 1)[2].label, 'A (2)'); // 사본을 복제해도 같은 자리
});

test('duplicateButton: 툴팁이 비어 있으면 번호만 붙인다', () => {
  const empty = [{ face: 'a', label: '', command: '', claudeInputs: [] }];
  assert.equal(duplicateButton(empty, 0)[1].label, '(1)');
});

test('duplicateButton: claudeInputs는 원본과 분리된 배열이다', () => {
  const next = duplicateButton(sample(), 0);
  next[1].claudeInputs.push('추가');
  assert.deepEqual(next[0].claudeInputs, ['a1']);
});

test('duplicateButton: 원본 배열을 건드리지 않는다', () => {
  const original = sample();
  duplicateButton(original, 2);
  assert.deepEqual(faces(original), ['a', 'b', 'c']);
});

// --- 페이지별 변수 ---
// 확장이 넘기지 않는 변수를 쓰면 앱이 "Variable {x} not provided"로 거절해 버튼이 아무 일도
// 하지 않는다. 프리셋·기본값은 우리가 배포하는 값이므로 그 자리에서 고정한다.

// command와 claude 입력은 같은 변수 표로 치환된다 (앱의 resolveRequest)
const variablesUsed = btn => [btn.command, ...(btn.claudeInputs || [])]
  .flatMap(text => [...text.matchAll(/\{(\w+)\}/g)].map(m => m[1]));

for (const [kind, { presets, defaults, variables }] of Object.entries(BUTTON_KINDS)) {
  test(`${kind} 프리셋·기본값은 그 페이지에서 주는 변수만 쓴다`, () => {
    const allowed = new Set(variables);
    for (const btn of [...presets, ...defaults]) {
      for (const name of variablesUsed(btn)) {
        assert.ok(allowed.has(name), `${kind} "${btn.name || btn.label}": {${name}}는 이 페이지에 없다`);
      }
    }
  });
}

test('저장소 기본 버튼은 리포로 이동만 한다', () => {
  // 커스터마이즈 이전의 Open in Terminal 동작 — 기본값을 바꾸면 기존 사용자의 버튼이 달라진다
  assert.equal(BUTTON_KINDS.repo.defaults.length, 1);
  assert.equal(BUTTON_KINDS.repo.defaults[0].command, 'z {repo}');
});

test('페이지 종류마다 저장 키가 다르다', () => {
  // 같은 키를 두 페이지가 쓰면 한쪽 설정이 다른 쪽을 덮어쓴다
  const keys = Object.values(BUTTON_KINDS).map(k => k.storageKey);
  assert.equal(new Set(keys).size, keys.length);
});

// --- 페이지 종류 판정 ---
// content.js(버튼 삽입)와 background.js(확장 아이콘 라우팅)가 같은 판정을 써야 한다.
// 아이콘 클릭은 content script를 거치지 않아, 판정이 갈리면 저장소가 아닌 경로가 저장소로
// 읽혀 엉뚱한 이름으로 명령이 돈다.

test('pageTypeOf: PR·이슈·저장소', () => {
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/pull/14'), 'pr');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/issues/3'), 'issue');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout'), 'repo');
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/issues'), 'repo');   // 목록은 저장소 탭이다
  assert.equal(pageTypeOf('/dazebug/terminal-checkout/tree/feat/x'), 'repo');
});

test('pageTypeOf: owner 자리의 예약 경로는 저장소가 아니다', () => {
  // /settings/profile을 저장소로 읽으면 확장 아이콘 클릭이 `z profile`을 실행한다
  assert.equal(pageTypeOf('/settings/profile'), null);
  assert.equal(pageTypeOf('/notifications'), null);
  assert.equal(pageTypeOf('/marketplace/actions/checkout'), null);
  assert.equal(pageTypeOf('/orgs/watcha/projects'), null);
});

test('pageTypeOf: 저장소 이름이 없으면 판정하지 않는다', () => {
  assert.equal(pageTypeOf('/'), null);
  assert.equal(pageTypeOf('/dazebug'), null);
});
