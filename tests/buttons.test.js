// extension/defaults.js의 순수 함수 테스트 — 의존성 없이 `node --test tests/`로 돌린다.
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
  assert.deepEqual(next[1], next[0]);
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
