// 버튼 기본값·프리셋·표시 규칙은 defaults.js가 단일 출처 (options.html이 먼저 로드한다)

// PR 버튼과 이슈 버튼은 저장 키도 쓸 수 있는 변수도 다르다. 나머지 편집 동작은 같아서
// 섹션 정의만 바꿔 같은 렌더러·이벤트 핸들러를 공유한다.
const SECTIONS = [
  {
    kind: 'pr',
    storageKey: 'buttons',
    presets: PR_PRESETS,
    defaults: DEFAULT_BUTTONS,
    container: 'pr-buttons',
    addButton: 'pr-add',
    addHint: 'pr-add-hint',
  },
  {
    kind: 'issue',
    storageKey: 'issueButtons',
    presets: ISSUE_PRESETS,
    defaults: DEFAULT_ISSUE_BUTTONS,
    container: 'issue-buttons',
    addButton: 'issue-add',
    addHint: 'issue-add-hint',
  },
];

// 표시에 자주 쓰는 이모지 — 클릭하면 표시 칸에 덧붙는다 (여러 개 조합 가능)
const FACE_EMOJI = ['⏏️', '🤖', '🌳', '🪵', '🔍', '🧪', '📝', '🚀', '🔧', '⚡', '📋', '📂'];

// 저장 스키마와 달리 overrides는 배열로 들고 있는다. repo를 키로 쓰면 이름을 고칠 때마다
// 키를 지웠다 다시 넣어야 하고, 그때마다 행을 새로 그리느라 입력 포커스가 날아간다.
const state = {
  buttons: { pr: [], issue: [] },
  overrides: [],
  dirty: false,
  // 편집이 일어날 때마다 오른다. 저장이 끝난 뒤 그 사이에 사용자가 더 고쳤는지 판별한다.
  revision: 0,
};

function section(kind) {
  return SECTIONS.find(s => s.kind === kind);
}

// 프리셋 목록은 섹션마다 고정이므로 한 번만 만들어 카드마다 복제한다
const presetTemplates = Object.fromEntries(SECTIONS.map(({ kind, presets }) => {
  const select = document.createElement('select');
  select.className = 'preset-select';
  select.add(new Option('프리셋 적용…', ''));
  presets.forEach(p => select.add(new Option(p.name, p.name)));
  return [kind, select];
}));

function normalizeButton(btn) {
  return {
    face: btn.face ?? btn.emoji ?? '', // emoji: face 도입 전 저장값 호환
    label: btn.label || '',
    command: btn.command || '',
    claudeInputs: Array.isArray(btn.claudeInputs) ? btn.claudeInputs.map(String) : [],
  };
}

// --- UI 렌더링 ---
// 텍스트를 고칠 때는 state만 갱신하고 다시 그리지 않는다. 다시 그리는 건 카드/행 개수가
// 바뀔 때뿐이고 그 트리거는 전부 버튼 클릭이라, 편집 중에 포커스를 잃을 일이 없다.

function renderButtons(kind) {
  const { container: containerId, addButton, addHint } = section(kind);
  const container = document.getElementById(containerId);
  container.innerHTML = '';

  state.buttons[kind].forEach((btn, i) => {
    const card = document.createElement('div');
    card.className = 'btn-card';
    card.dataset.index = i;
    card.dataset.kind = kind;
    // 값은 HTML에 끼워 넣지 않고 아래에서 프로퍼티로 넣는다 (이스케이프가 필요 없어진다)
    card.innerHTML = `
      <div class="btn-card-header">
        <span class="btn-number"><span class="prompt">❯</span> ${kind === 'issue' ? 'issueButtons' : 'buttons'}[${i}]</span>
        ${state.buttons[kind].length > 1 ? '<button class="remove-btn">삭제</button>' : ''}
      </div>
      <div class="btn-row">
        <div class="field field-face">
          <label for="${kind}-${i}-face">표시</label>
          <input id="${kind}-${i}-face" class="face-input" data-field="face" maxlength="24">
        </div>
        <div class="field field-preview">
          <label>미리보기</label>
          <span class="face-preview"></span>
        </div>
        <div class="field field-label">
          <label for="${kind}-${i}-label">툴팁</label>
          <input id="${kind}-${i}-label" class="label-input" data-field="label" placeholder="버튼 툴팁">
        </div>
        <div class="field field-preset">
          <label for="${kind}-${i}-preset">프리셋</label>
        </div>
      </div>
      <div class="face-palette">
        <span class="palette-label">표시 추가:</span>
        ${FACE_EMOJI.map(e => `<button class="palette-btn" title="표시에 ${e} 추가">${e}</button>`).join('')}
      </div>
      <div class="field field-command">
        <label for="${kind}-${i}-command">command</label>
        <div class="cmd-block">
          <span class="cmd-prompt">$</span>
          <textarea id="${kind}-${i}-command" class="command-input" data-field="command" rows="2"
                    spellcheck="false" placeholder="z {repo} && claude"></textarea>
        </div>
      </div>
      <div class="claude-queue">
        <div class="claude-queue-head"><span class="ret">⏎</span> claude 입력
          <span class="help-inline">— command가 claude를 띄우면, 준비된 순서대로 그 세션에 타이핑됩니다</span>
        </div>
        <div class="claude-warn" hidden>⚠ command가 claude를 실행하지 않아 이 입력들은 전달되지 않습니다</div>
        <div class="claude-rows"></div>
        <button class="add-input-btn">+ 입력 추가</button>
      </div>
    `;

    const select = presetTemplates[kind].cloneNode(true);
    select.id = `${kind}-${i}-preset`;
    card.querySelector('.field-preset').appendChild(select);

    card.querySelector('.face-input').value = btn.face;
    card.querySelector('.label-input').value = btn.label;
    card.querySelector('.command-input').value = btn.command;

    const rows = card.querySelector('.claude-rows');
    btn.claudeInputs.forEach((text, j) => {
      const row = document.createElement('div');
      row.className = 'claude-row';
      row.dataset.ci = j;
      row.innerHTML = `
        <span class="ci-marker">⏎${j + 1}</span>
        <input class="ci-input" placeholder="!gh issue view {number} 또는 이 이슈를 요약해줘">
        <button class="ci-remove" title="삭제">×</button>
      `;
      row.querySelector('.ci-input').value = text;
      rows.appendChild(row);
    });
    card.querySelector('.add-input-btn').disabled = btn.claudeInputs.length >= MAX_CLAUDE_INPUTS;

    updateFacePreview(card, btn.face);
    updateClaudeWarn(card, btn);
    container.appendChild(card);
    autosize(card.querySelector('.command-input')); // 붙인 뒤라야 scrollHeight가 잡힌다
  });

  const atMax = state.buttons[kind].length >= MAX_BUTTONS;
  document.getElementById(addButton).disabled = atMax;
  document.getElementById(addHint).hidden = !atMax;
}

// content.js의 버튼 렌더 규칙(defaults.js의 판정 공유)과 짝을 이룬다 — 실제로 어떻게 보일지 그대로 재현
function updateFacePreview(card, face) {
  const el = card.querySelector('.face-preview');
  const shown = face.trim() || '⏏️';
  el.textContent = shown;
  el.className = 'face-preview ' + (isTextFace(shown) ? 'gh-btn-text' : 'gh-btn-emoji');
}

function updateClaudeWarn(card, btn) {
  const hasInputs = btn.claudeInputs.some(s => s.trim());
  card.querySelector('.claude-warn').hidden = !hasInputs || /\bclaude\b/.test(btn.command);
}

function renderOverrides() {
  const tbody = document.getElementById('overrides-body');
  tbody.innerHTML = '';

  state.overrides.forEach((row, i) => {
    const tr = document.createElement('tr');
    tr.dataset.index = i;
    tr.innerHTML = `
      <td><input type="text" class="override-repo" placeholder="remy-worker"></td>
      <td><input type="text" class="override-branch" placeholder="master"></td>
      <td><button class="remove-row" title="삭제">✕</button></td>
    `;
    tr.querySelector('.override-repo').value = row.repo;
    tr.querySelector('.override-branch').value = row.branch;
    tbody.appendChild(tr);
  });

  const isEmpty = state.overrides.length === 0;
  document.querySelector('.override-table').hidden = isEmpty;
  document.getElementById('overrides-empty').hidden = !isEmpty;
}

// 명령이 잘려 보이면 편집도 검토도 못 하므로 내용에 맞춰 높이를 늘린다
function autosize(textarea) {
  textarea.style.height = 'auto';
  textarea.style.height = `${textarea.scrollHeight}px`; // cmd-block이 보더를 가지므로 보정 불필요
}

function cardOf(el) {
  const card = el.closest('.btn-card');
  return { card, kind: card.dataset.kind, index: Number(card.dataset.index) };
}

function buttonOf(el) {
  const { kind, index } = cardOf(el);
  return state.buttons[kind][index];
}

function overrideInput(index, selector) {
  return document.querySelector(`#overrides-body tr[data-index="${index}"] ${selector}`);
}

// --- 미저장 변경 표시 ---

function markDirty() {
  state.dirty = true;
  state.revision++;
  document.getElementById('dirty-indicator').hidden = false;
}

function clearDirty() {
  state.dirty = false;
  document.getElementById('dirty-indicator').hidden = true;
}

// --- 프리셋 적용 ---
// 드롭다운은 현재 상태를 나타내지 않는다. 상태는 카드가 보여주고 드롭다운은
// 템플릿을 불러오는 액션일 뿐이라, 고른 즉시 placeholder로 되돌린다.

function applyPreset(select) {
  const name = select.value;
  select.value = ''; // 적용하든 취소하든 언제나 placeholder로 되돌아간다
  if (!name) return;

  const { kind, index } = cardOf(select);
  const preset = section(kind).presets.find(p => p.name === name);
  if (!preset) return;

  const current = state.buttons[kind][index].command.trim();
  const isCustom = current !== '' && !section(kind).presets.some(p => p.command === current);
  if (isCustom && !confirm(`${index}번 버튼의 내용을 "${preset.name}" 프리셋으로 덮어씁니다. 계속할까요?`)) {
    return;
  }

  state.buttons[kind][index] = normalizeButton({
    face: preset.face, label: preset.name, command: preset.command,
    claudeInputs: [...(preset.claudeInputs || [])],
  });
  markDirty();
  renderButtons(kind); // claude 입력 행 개수까지 바뀌므로 카드 전체를 다시 그린다
}

// --- 유효성 검사 ---

const REQUIRED_FIELDS = [
  { field: 'face', label: '표시를' },
  { field: 'label', label: '툴팁을' },
  { field: 'command', label: 'command를' },
];

function validateButtons() {
  for (const { kind } of SECTIONS) {
    const name = kind === 'issue' ? 'issueButtons' : 'buttons';
    for (let i = 0; i < state.buttons[kind].length; i++) {
      for (const { field, label } of REQUIRED_FIELDS) {
        if (state.buttons[kind][i][field].trim()) continue;
        return {
          message: `${name}[${i}]: ${label} 입력하세요.`,
          focus: document.querySelector(
            `.btn-card[data-kind="${kind}"][data-index="${i}"] [data-field="${field}"]`
          ),
        };
      }
    }
  }
  return null;
}

// 배열로 들고 있던 오버라이드를 저장 스키마(객체)로 되돌린다
function serializeOverrides() {
  const entries = new Map();

  for (let i = 0; i < state.overrides.length; i++) {
    const repo = state.overrides[i].repo.trim();
    const branch = state.overrides[i].branch.trim();

    if (!repo && !branch) continue; // 추가만 하고 채우지 않은 행은 조용히 버린다

    if (!repo || !branch) {
      return {
        error: {
          message: `오버라이드 ${i + 1}: repository와 main branch를 모두 입력하세요.`,
          focus: overrideInput(i, repo ? '.override-branch' : '.override-repo'),
        },
      };
    }
    if (entries.has(repo)) {
      return {
        error: {
          message: `오버라이드 ${i + 1}: "${repo}" 리포가 중복됩니다.`,
          focus: overrideInput(i, '.override-repo'),
        },
      };
    }
    entries.set(repo, branch);
  }

  return { value: Object.fromEntries(entries) };
}

// --- 로드/저장 ---

// 터미널 선택은 Terminal Checkout 앱(설정 창)이 단일 소스로 관리한다
async function loadSettings() {
  const keys = SECTIONS.map(s => s.storageKey).concat(['defaultMain', 'repoMainBranch']);
  const data = await chrome.storage.sync.get(keys);

  for (const { kind, storageKey, defaults } of SECTIONS) {
    const saved = data[storageKey];
    state.buttons[kind] = (saved?.length ? saved : defaults).map(normalizeButton);
  }
  state.overrides = Object.entries(data.repoMainBranch || {}).map(([repo, branch]) => ({ repo, branch }));
  document.getElementById('default-main').value = data.defaultMain || 'main';

  SECTIONS.forEach(({ kind }) => renderButtons(kind));
  renderOverrides();
}

async function saveSettings() {
  const invalidButton = validateButtons();
  if (invalidButton) return showError(invalidButton);

  const overrides = serializeOverrides();
  if (overrides.error) return showError(overrides.error);

  const cleaned = Object.fromEntries(SECTIONS.map(({ kind }) => [
    kind,
    state.buttons[kind].map(b => ({
      face: b.face.trim(),
      label: b.label.trim(),
      command: b.command,
      claudeInputs: b.claudeInputs.map(s => s.trim()).filter(Boolean), // 빈 행은 조용히 버린다
    })),
  ]));
  const defaultMain = document.getElementById('default-main').value.trim() || 'main';
  const savedRevision = state.revision;

  try {
    await chrome.storage.sync.set({
      ...Object.fromEntries(SECTIONS.map(({ kind, storageKey }) => [storageKey, cleaned[kind]])),
      defaultMain,
      repoMainBranch: overrides.value,
    });
  } catch (error) {
    showStatus('error', `저장에 실패했습니다: ${error.message}`);
    return;
  }

  // 저장을 기다리는 동안에도 폼은 살아 있다. 그 사이에 사용자가 더 고쳤다면 방금 저장한
  // 스냅샷으로 화면을 되돌리는 순간 그 입력이 사라지므로, 화면은 그대로 두고 dirty도 남긴다.
  if (state.revision !== savedRevision) {
    showStatus('success', '설정을 저장했습니다. 저장 이후 바꾼 내용은 아직 저장되지 않았습니다.');
    return;
  }

  // 저장된 결과와 화면을 맞춘다 (빈 행 정리, 공백 제거 반영)
  document.getElementById('default-main').value = defaultMain;
  for (const { kind } of SECTIONS) {
    state.buttons[kind] = cleaned[kind].map(normalizeButton);
    renderButtons(kind);
  }
  state.overrides = Object.entries(overrides.value).map(([repo, branch]) => ({ repo, branch }));
  renderOverrides();

  clearDirty();
  showStatus('success', '설정이 저장되었습니다.');
}

// 저장은 저장 버튼 하나로만 일어난다. 여기서는 화면만 되돌리고 저장소는 건드리지 않는다.
function resetSettings() {
  for (const { kind, defaults } of SECTIONS) {
    state.buttons[kind] = defaults.map(normalizeButton);
    renderButtons(kind);
  }
  state.overrides = [];
  document.getElementById('default-main').value = 'main';

  renderOverrides();
  markDirty();
  showStatus('info', '기본값으로 되돌렸습니다. 저장을 눌러야 반영됩니다.');
}

let statusTimer = null;

function showStatus(type, message) {
  const el = document.getElementById('status');
  el.className = `status ${type}`;
  el.textContent = message;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { el.className = 'status'; }, 4000);
}

function showError({ message, focus }) {
  showStatus('error', message);
  focus?.focus();
}

// --- 이벤트 ---
// 두 섹션이 같은 카드 구조를 쓰므로 핸들러도 공유한다. 어느 섹션인지는 카드의 data-kind가 말해준다.

function onCardInput(e) {
  const { card, kind, index } = cardOf(e.target);

  if (e.target.classList.contains('ci-input')) {
    const row = Number(e.target.closest('.claude-row').dataset.ci);
    state.buttons[kind][index].claudeInputs[row] = e.target.value;
    updateClaudeWarn(card, state.buttons[kind][index]);
    markDirty();
    return;
  }

  const field = e.target.dataset.field;
  if (!field) return;
  state.buttons[kind][index][field] = e.target.value;
  if (field === 'face') updateFacePreview(card, e.target.value);
  if (field === 'command') {
    autosize(e.target);
    updateClaudeWarn(card, state.buttons[kind][index]);
  }
  markDirty();
}

function onCardClick(e) {
  if (e.target.classList.contains('remove-btn')) {
    const { kind, index } = cardOf(e.target);
    state.buttons[kind].splice(index, 1);
    markDirty();
    renderButtons(kind);
    return;
  }

  if (e.target.classList.contains('palette-btn')) {
    const { card, kind, index } = cardOf(e.target);
    const input = card.querySelector('.face-input');
    state.buttons[kind][index].face += e.target.textContent;
    input.value = state.buttons[kind][index].face;
    updateFacePreview(card, input.value);
    markDirty();
    return;
  }

  if (e.target.classList.contains('add-input-btn')) {
    const { kind, index } = cardOf(e.target);
    const inputs = state.buttons[kind][index].claudeInputs;
    if (inputs.length >= MAX_CLAUDE_INPUTS) return;
    inputs.push('');
    markDirty();
    renderButtons(kind);
    document.querySelector(
      `.btn-card[data-kind="${kind}"][data-index="${index}"] .claude-row[data-ci="${inputs.length - 1}"] .ci-input`
    ).focus();
    return;
  }

  if (e.target.classList.contains('ci-remove')) {
    const { kind, index } = cardOf(e.target);
    const row = Number(e.target.closest('.claude-row').dataset.ci);
    state.buttons[kind][index].claudeInputs.splice(row, 1);
    markDirty();
    renderButtons(kind);
  }
}

for (const { kind, container, addButton, defaults } of SECTIONS) {
  const element = document.getElementById(container);
  element.addEventListener('input', onCardInput);
  element.addEventListener('click', onCardClick);
  element.addEventListener('change', (e) => {
    if (e.target.classList.contains('preset-select')) applyPreset(e.target);
  });

  document.getElementById(addButton).addEventListener('click', () => {
    if (state.buttons[kind].length >= MAX_BUTTONS) return;

    const used = new Set(state.buttons[kind].map(b => b.face));
    const presets = section(kind).presets;
    const face = presets.map(p => p.face).find(f => !used.has(f)) || defaults[0].face;

    state.buttons[kind].push(normalizeButton({ face, label: 'New Button', command: '' }));
    markDirty();
    renderButtons(kind);
    document.querySelector(
      `.btn-card[data-kind="${kind}"][data-index="${state.buttons[kind].length - 1}"] .command-input`
    ).focus();
  });
}

const overridesBody = document.getElementById('overrides-body');

overridesBody.addEventListener('input', (e) => {
  const tr = e.target.closest('tr[data-index]');
  if (!tr) return;
  const row = state.overrides[Number(tr.dataset.index)];
  // 입력 중에는 trim하지 않는다 (공백 정리는 저장할 때 한 번에)
  if (e.target.classList.contains('override-repo')) row.repo = e.target.value;
  else if (e.target.classList.contains('override-branch')) row.branch = e.target.value;
  else return;
  markDirty();
});

overridesBody.addEventListener('click', (e) => {
  if (!e.target.classList.contains('remove-row')) return;
  state.overrides.splice(Number(e.target.closest('tr').dataset.index), 1);
  markDirty();
  renderOverrides();
});

document.getElementById('add-override').addEventListener('click', () => {
  state.overrides.push({ repo: '', branch: '' });
  markDirty();
  renderOverrides();
  overrideInput(state.overrides.length - 1, '.override-repo').focus();
});

document.getElementById('default-main').addEventListener('input', markDirty);

document.getElementById('save-btn').addEventListener('click', saveSettings);
document.getElementById('reset-btn').addEventListener('click', resetSettings);

// manifest가 options_page(전체 탭)라서 이탈 경고 다이얼로그가 실제로 뜬다.
// options_ui(임베드)로 바꾸면 브라우저가 이 경고를 억제한다.
window.addEventListener('beforeunload', (e) => {
  if (!state.dirty) return;
  e.preventDefault();
  e.returnValue = '';
});

// 초기 로드
loadSettings();
