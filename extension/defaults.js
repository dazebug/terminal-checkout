// 버튼 기본값·프리셋의 단일 출처. content.js(렌더), background.js(실행),
// options.js(편집) 세 곳이 같은 값을 봐야 하므로 여기 한 곳에만 둔다.
// content script·service worker·options 페이지 모두 이 파일을 먼저 로드한다.

// PR 페이지: 브랜치 옆 버튼. { }는 서브셸이 아니라 그룹핑 — cd가 현재 셸에 남아야 하므로 ( )를 쓰면 안 된다
const PR_PRESETS = [
  {
    name: 'Checkout Branch', face: '⏏️',
    // checkout 실패(브랜치가 워크트리에 체크아웃됨 등) 시 관례 경로의 워크트리로 이동
    command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }',
  },
  {
    name: 'Checkout + Claude', face: '🤖',
    command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude',
  },
  {
    name: 'Worktree + Claude', face: '🌳',
    command: 'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude',
  },
  {
    name: 'Worktree', face: '🪵',
    command: 'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}',
  },
  {
    name: 'PR 리뷰 (claude)', face: '🔍',
    command: 'z {repo} && claude',
    // claude의 `!`는 한 줄을 셸로 넘긴다 — gh 출력이 그대로 claude 컨텍스트에 쌓인다
    claudeInputs: ['!gh pr view {number} --comments', '!gh pr diff {number}'],
  },
];

// 이슈 페이지: 상태 배지 줄 버튼. 브랜치가 없으므로 {branch}·{main}은 쓸 수 없다
const ISSUE_PRESETS = [
  {
    name: '이슈 읽기 (claude)', face: '📋',
    command: 'z {repo} && claude',
    claudeInputs: [
      '!gh issue view {number}',
      '!gh issue view {number} --comments',
      // 이 이슈를 언급한 이슈·PR 번호. --json 쪽 필드로는 "닫을 PR"만 나와서 timeline을 쓴다
      '!gh api repos/{owner}/{repo}/issues/{number}/timeline --jq \'[.[]|select(.event=="cross-referenced")|.source.issue.number]\'',
    ],
  },
  {
    name: '이슈 작업 시작', face: '🌳',
    command: 'z {repo} && git fetch origin && ([ -d ../{repo}-issue-{number} ] || git worktree add -f ../{repo}-issue-{number} -b issue-{number} origin/{main}) && cd ../{repo}-issue-{number} && claude',
    claudeInputs: ['!gh issue view {number} --comments'],
  },
  {
    name: '이슈 열기', face: '📂',
    command: 'z {repo}',
    claudeInputs: [],
  },
];

const DEFAULT_BUTTONS = [
  { face: PR_PRESETS[0].face, label: PR_PRESETS[0].name, command: PR_PRESETS[0].command, claudeInputs: [] },
];

const DEFAULT_ISSUE_BUTTONS = [
  {
    face: ISSUE_PRESETS[0].face, label: ISSUE_PRESETS[0].name,
    command: ISSUE_PRESETS[0].command, claudeInputs: [...ISSUE_PRESETS[0].claudeInputs],
  },
];

const DEFAULT_MAIN = 'main';
const MAX_BUTTONS = 3;
const MAX_CLAUDE_INPUTS = 5;

// 버튼 표시 텍스트. face가 새 키이고 emoji는 구버전 저장값 호환용이다.
function buttonFace(config) {
  return (config.face ?? config.emoji ?? '').trim() || '⏏️';
}

// 글자·숫자가 섞이면 텍스트 필(pill)로, 이모지만이면 아이콘으로 그린다.
// content.js(GitHub 렌더)와 options.js(미리보기)가 이 판정을 공유한다.
function isTextFace(face) {
  return /[\p{L}\p{N}]/u.test(face);
}
