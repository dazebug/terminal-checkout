const PRESETS = [
  // checkout 실패(브랜치가 워크트리에 체크아웃됨 등) 시 관례 경로의 워크트리로 이동.
  // { }는 서브셸이 아니라 그룹핑 — cd가 현재 셸에 남아야 하므로 ( )를 쓰면 안 된다
  { name: 'Checkout Branch', emoji: '⏏️', command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }' },
  { name: 'Checkout + Claude', emoji: '🤖', command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; } && claude' },
  { name: 'Worktree + Claude', emoji: '🌳', command: 'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch} && claude' },
  { name: 'Worktree', emoji: '🪵', command: 'z {repo} && git fetch origin && ([ -d ../{repo}-{branch_underbar} ] || git worktree add -f ../{repo}-{branch_underbar} {branch}) && cd ../{repo}-{branch_underbar} && git merge --ff-only origin/{branch}' },
];

const DEFAULT_BUTTONS = [
  { emoji: '⏏️', label: 'Checkout Branch', command: 'z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }' }
];

const MAX_BUTTONS = 3;

// 저장 스키마와 달리 overrides는 배열로 들고 있는다. repo를 키로 쓰면 이름을 고칠 때마다
// 키를 지웠다 다시 넣어야 하고, 그때마다 행을 새로 그리느라 입력 포커스가 날아간다.
const state = {
  buttons: [],
  overrides: [],
  dirty: false,
  // 편집이 일어날 때마다 오른다. 저장이 끝난 뒤 그 사이에 사용자가 더 고쳤는지 판별한다.
  revision: 0,
};

// 프리셋 목록은 고정이므로 한 번만 만들어 카드마다 복제한다
const presetSelectTemplate = document.createElement('select');
presetSelectTemplate.className = 'preset-select';
presetSelectTemplate.add(new Option('프리셋 적용…', ''));
PRESETS.forEach(p => presetSelectTemplate.add(new Option(p.name, p.name)));

function normalizeButton(btn) {
  return { emoji: btn.emoji || '', label: btn.label || '', command: btn.command || '' };
}

// --- UI 렌더링 ---
// 텍스트를 고칠 때는 state만 갱신하고 다시 그리지 않는다. 다시 그리는 건 카드/행 개수가
// 바뀔 때뿐이고 그 트리거는 전부 버튼 클릭이라, 편집 중에 포커스를 잃을 일이 없다.

function renderButtons() {
  const container = document.getElementById('buttons-container');
  container.innerHTML = '';

  state.buttons.forEach((btn, i) => {
    const card = document.createElement('div');
    card.className = 'btn-card';
    card.dataset.index = i;
    // 값은 HTML에 끼워 넣지 않고 아래에서 프로퍼티로 넣는다 (이스케이프가 필요 없어진다)
    card.innerHTML = `
      <div class="btn-card-header">
        <span class="btn-number">Button ${i + 1}</span>
      </div>
      ${state.buttons.length > 1 ? '<button class="remove-btn">Remove</button>' : ''}
      <div class="btn-row">
        <div class="field field-emoji">
          <label for="btn-${i}-emoji">Emoji</label>
          <input id="btn-${i}-emoji" class="emoji-input" data-field="emoji" maxlength="4">
        </div>
        <div class="field field-label">
          <label for="btn-${i}-label">Label</label>
          <input id="btn-${i}-label" class="label-input" data-field="label" placeholder="버튼 툴팁">
        </div>
        <div class="field field-preset">
          <label for="btn-${i}-preset">Preset</label>
        </div>
      </div>
      <div class="btn-row">
        <div class="field field-command">
          <label for="btn-${i}-command">Command</label>
          <textarea id="btn-${i}-command" class="command-input" data-field="command" rows="2"
                    spellcheck="false" placeholder="z {repo} && git checkout {branch}"></textarea>
        </div>
      </div>
    `;

    const select = presetSelectTemplate.cloneNode(true);
    select.id = `btn-${i}-preset`;
    card.querySelector('.field-preset').appendChild(select);

    card.querySelector('.emoji-input').value = btn.emoji;
    card.querySelector('.label-input').value = btn.label;
    card.querySelector('.command-input').value = btn.command;
    container.appendChild(card);
    autosize(card.querySelector('.command-input')); // 붙인 뒤라야 scrollHeight가 잡힌다
  });

  const atMax = state.buttons.length >= MAX_BUTTONS;
  document.getElementById('add-btn').disabled = atMax;
  document.getElementById('add-btn-hint').hidden = !atMax;
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
  textarea.style.height = `${textarea.scrollHeight + 2}px`; // +2: 위아래 보더
}

function cardIndex(el) {
  return Number(el.closest('.btn-card').dataset.index);
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
// 드롭다운은 현재 상태를 나타내지 않는다. 상태는 아래 세 칸이 보여주고 드롭다운은
// 템플릿을 불러오는 액션일 뿐이라, 고른 즉시 placeholder로 되돌린다.

function applyPreset(select) {
  const name = select.value;
  select.value = ''; // 적용하든 취소하든 언제나 placeholder로 되돌아간다
  if (!name) return;

  const preset = PRESETS.find(p => p.name === name);
  if (!preset) return;

  const index = cardIndex(select);
  const current = state.buttons[index].command.trim();
  const isCustom = current !== '' && !PRESETS.some(p => p.command === current);
  if (isCustom && !confirm(`Button ${index + 1}의 내용을 "${preset.name}" 프리셋으로 덮어씁니다. 계속할까요?`)) {
    return;
  }

  state.buttons[index] = { emoji: preset.emoji, label: preset.name, command: preset.command };

  const card = select.closest('.btn-card');
  card.querySelector('.emoji-input').value = preset.emoji;
  card.querySelector('.label-input').value = preset.name;
  const command = card.querySelector('.command-input');
  command.value = preset.command;
  autosize(command);
  markDirty();
}

// --- 유효성 검사 ---

const REQUIRED_FIELDS = [
  { field: 'emoji', label: 'Emoji를' },
  { field: 'label', label: 'Label을' },
  { field: 'command', label: 'Command를' },
];

function validateButtons() {
  for (let i = 0; i < state.buttons.length; i++) {
    for (const { field, label } of REQUIRED_FIELDS) {
      if (state.buttons[i][field].trim()) continue;
      return {
        message: `Button ${i + 1}: ${label} 입력하세요.`,
        focus: document.querySelector(`.btn-card[data-index="${i}"] [data-field="${field}"]`),
      };
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
          message: `Override ${i + 1}: Repository와 Main Branch를 모두 입력하세요.`,
          focus: overrideInput(i, repo ? '.override-branch' : '.override-repo'),
        },
      };
    }
    if (entries.has(repo)) {
      return {
        error: {
          message: `Override ${i + 1}: "${repo}" 리포가 중복됩니다.`,
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
  const data = await chrome.storage.sync.get(['buttons', 'defaultMain', 'repoMainBranch']);

  state.buttons = (data.buttons?.length ? data.buttons : DEFAULT_BUTTONS).map(normalizeButton);
  state.overrides = Object.entries(data.repoMainBranch || {}).map(([repo, branch]) => ({ repo, branch }));
  document.getElementById('default-main').value = data.defaultMain || 'main';

  renderButtons();
  renderOverrides();
}

async function saveSettings() {
  const invalidButton = validateButtons();
  if (invalidButton) return showError(invalidButton);

  const overrides = serializeOverrides();
  if (overrides.error) return showError(overrides.error);

  const defaultMain = document.getElementById('default-main').value.trim() || 'main';
  const savedRevision = state.revision;

  try {
    await chrome.storage.sync.set({
      buttons: state.buttons,
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
  state.overrides = Object.entries(overrides.value).map(([repo, branch]) => ({ repo, branch }));
  renderOverrides();

  clearDirty();
  showStatus('success', '설정이 저장되었습니다.');
}

// 저장은 Save 하나로만 일어난다. 여기서는 화면만 되돌리고 저장소는 건드리지 않는다.
function resetSettings() {
  state.buttons = DEFAULT_BUTTONS.map(normalizeButton);
  state.overrides = [];
  document.getElementById('default-main').value = 'main';

  renderButtons();
  renderOverrides();
  markDirty();
  showStatus('info', '기본값으로 되돌렸습니다. Save를 눌러야 저장됩니다.');
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

const buttonsContainer = document.getElementById('buttons-container');

buttonsContainer.addEventListener('input', (e) => {
  const field = e.target.dataset.field;
  if (!field) return;
  state.buttons[cardIndex(e.target)][field] = e.target.value;
  if (field === 'command') autosize(e.target);
  markDirty();
});

buttonsContainer.addEventListener('change', (e) => {
  if (e.target.classList.contains('preset-select')) applyPreset(e.target);
});

buttonsContainer.addEventListener('click', (e) => {
  if (!e.target.classList.contains('remove-btn')) return;
  state.buttons.splice(cardIndex(e.target), 1);
  markDirty();
  renderButtons();
});

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

document.getElementById('add-btn').addEventListener('click', () => {
  if (state.buttons.length >= MAX_BUTTONS) return;

  const used = new Set(state.buttons.map(b => b.emoji));
  const emoji = PRESETS.map(p => p.emoji).find(e => !used.has(e)) || PRESETS[0].emoji;

  state.buttons.push({ emoji, label: 'New Button', command: '' });
  markDirty();
  renderButtons();
  document.querySelector(`.btn-card[data-index="${state.buttons.length - 1}"] .command-input`).focus();
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
