/** @typedef {{kind: OptionsButtonKind, uid: string, anchor: HTMLElement, restoreFocusTo: HTMLElement}} OptionsEditorOpenOptions */
/** @typedef {{ok: boolean, reason?: 'not-loaded'|'busy'|'limit'|'not-found'|'needs-confirmation'|'invalid'|'failed', createdUid?: string, snapshot: OptionsEngineSnapshot}} OptionsDispatchResult */
/** @typedef {{mount: (root: HTMLElement, engine: OptionsEngine) => void, open: (options: OptionsEditorOpenOptions) => void, close: () => void, isOpen: () => boolean}} OptionsEditor */

const SECTION_VARIABLE_HELP = Object.freeze({
  pr: () => tHTML('ext.section.pr.variables'),
  'pr-list': () => tHTML('ext.section.prList.variables'),
  issue: () => tHTML('ext.section.issue.variables'),
  'issue-list': () => tHTML('ext.section.issueList.variables'),
  repo: () => tHTML('ext.section.repo.variables'),
});

const REQUIRED_FIELD_MESSAGE = Object.freeze({
  face: (storageKey, position) => tr('ext.validate.face', storageKey, position),
  label: (storageKey, position) => tr('ext.validate.tooltip', storageKey, position),
  command: (storageKey, position) => tr('ext.validate.command', storageKey, position),
});

/** @returns {boolean} */
function fitsFieldLimit(value, limit) {
  return typeof value === 'string' && Number.isInteger(limit) && limit >= 0 && value.length <= limit;
}

/** @returns {string} */
function appendFaceCharacter(face, addition, limit) {
  const current = typeof face === 'string' ? face : '';
  const next = typeof addition === 'string' ? addition : '';
  return fitsFieldLimit(current + next, limit) ? current + next : current;
}

/** @returns {string[]} */
function variablesForKind(kind) {
  if (typeof kind !== 'string' || !Object.hasOwn(BUTTON_KINDS, kind)) return [];
  return [...new Set([...APP_VARIABLES, ...BUTTON_KINDS[kind].variables])];
}

/** @returns {string[]} */
function validationFor(snapshot, kind, button, { includeWarnings = true } = {}) {
  const diagnostic = snapshot?.validation?.buttons?.find(entry => entry.kind === kind && entry.uid === button?.uid);
  if (!diagnostic) return [];
  const list = snapshot?.buttons?.[kind] || [];
  const index = list.findIndex(entry => entry.uid === button.uid);
  const position = Math.max(0, index);
  const storageKey = BUTTON_KINDS[kind]?.storageKey || '';
  const messages = [];
  for (const field of diagnostic.errors || []) {
    const describe = REQUIRED_FIELD_MESSAGE[field];
    if (describe) messages.push(describe(storageKey, position));
  }
  if (includeWarnings) {
    for (const warning of diagnostic.warnings || []) {
      if (warning === 'claude-inputs-without-claude-command') {
        messages.push(tr('ext.field.claudeInputs.warn'));
      }
    }
  }
  return messages;
}

/** @returns {boolean} */
function requiresPresetConfirmation(button) {
  return button?.customCommand === true;
}

/** @returns {{type: 'button-move', kind: string, uid: string, beforeUid: string|null}|null} */
function buttonMoveAction(source, kind, uid, direction) {
  const list = source?.buttons?.[kind] || [];
  const index = list.findIndex(button => button.uid === uid);
  if (index < 0 || (direction !== -1 && direction !== 1)) return null;
  if (direction < 0) {
    const beforeUid = list[index - 1]?.uid;
    return beforeUid ? { type: 'button-move', kind, uid, beforeUid } : null;
  }
  if (index >= list.length - 1) return null;
  return { type: 'button-move', kind, uid, beforeUid: list[index + 2]?.uid ?? null };
}

/** @returns {{type: 'preset-replace', kind: string, uid: string, presetId: string, confirmed?: true}} */
function presetReplaceAction(kind, uid, presetId, confirmed = false) {
  return {
    type: 'preset-replace', kind, uid, presetId,
    ...(confirmed ? { confirmed: true } : {}),
  };
}

/** @param {Event} event @returns {boolean} */
function eventPathIncludesEditor(event) {
  if (typeof event?.composedPath !== 'function') return false;
  return event.composedPath().some(node => node?.dataset?.optionsEditorSurface === 'popover');
}

/** @returns {'shell'|'slash'|'directive'|'message'} */
function classifyClaudeInput(value) {
  const text = typeof value === 'string' ? value.replace(/^ +/, '') : '';
  if (text.startsWith('!')) return 'shell';
  if (text.startsWith('/')) return 'slash';
  if (text.startsWith('#')) return 'directive';
  return 'message';
}

/** @returns {Record<string, string|number>} */
function exampleValuesForKind(kind, context) {
  const pullRequest = context?.pullRequest || {};
  const issue = context?.issue || {};
  const isPullRequest = kind === 'pr' || kind === 'pr-list';
  const branch = pullRequest.branch;
  const candidateValues = {
    repo: context?.repo,
    owner: context?.owner,
    main: pullRequest.base,
    number: isPullRequest ? pullRequest.number : issue.number,
    branch,
    base: pullRequest.base,
    branch_underbar: typeof branch === 'string' ? branch.replace(/\//g, '_') : undefined,
    cd: context?.repoPath,
  };
  const values = {};
  for (const name of variablesForKind(kind)) {
    const value = candidateValues[name];
    if (typeof value === 'string' || typeof value === 'number') values[name] = value;
  }
  return values;
}

function shellDisplayValue(value) {
  const text = String(value);
  if (/^[A-Za-z0-9_./-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, "'\\''")}'`;
}

/** @returns {{text: string, unsupported: string[], missing: string[]}} */
function expandExampleTemplate(template, kind, context) {
  const source = typeof template === 'string' ? template : '';
  const values = exampleValuesForKind(kind, context);
  const allowed = new Set(variablesForKind(kind));
  const unsupported = new Set();
  const missing = new Set();
  const text = source.replace(/\{(\w+)\}/g, (token, name) => {
    if (!allowed.has(name)) {
      unsupported.add(name);
      return token;
    }
    if (!Object.hasOwn(values, name)) {
      missing.add(name);
      return token;
    }
    if (name === 'cd') return `cd ${shellDisplayValue(values[name])}`;
    return String(values[name]);
  });
  return { text, unsupported: [...unsupported], missing: [...missing] };
}

/** @returns {string[]} */
function splitCommandSteps(command) {
  const source = typeof command === 'string' ? command : '';
  if (!source) return [];
  const steps = [];
  const stack = [];
  const compoundWords = new Set([
    'case', 'do', 'done', 'elif', 'else', 'esac', 'fi', 'for', 'function',
    'if', 'select', 'then', 'until', 'while',
  ]);
  let quote = '';
  let escaped = false;
  let comment = false;
  let start = 0;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (comment) {
      if (character === '\n') comment = false;
      continue;
    }
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quote) {
      if (quote !== "'" && character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = '';
      }
      continue;
    }
    if (character === '\\') {
      escaped = true;
      continue;
    }
    if (character === "'" || character === '"' || character === '`') {
      quote = character;
      continue;
    }
    if (character === '[' && source[index + 1] === '[') return [source];
    if (/[A-Za-z_]/.test(character) && !/[A-Za-z0-9_]/.test(source[index - 1] || '')) {
      const word = source.slice(index).match(/^[A-Za-z_][A-Za-z0-9_]*/)?.[0];
      if (compoundWords.has(word)) return [source];
    }
    if (character === '#' || (character === '<' && source[index + 1] === '<')) return [source];
    if (character === '(' || character === '{') {
      stack.push(character === '(' ? ')' : '}');
      continue;
    }
    if (character === ')' || character === '}') {
      if (stack.pop() !== character) return [source];
      continue;
    }
    if (character === '&' && source[index + 1] === '&' && stack.length === 0) {
      if (source[index - 1] === '&' || source[index + 2] === '&') return [source];
      const step = source.slice(start, index).trim();
      if (!step) return [source];
      steps.push(step);
      start = index + 2;
      index += 1;
    }
  }

  if (quote || escaped || stack.length) return [source];
  const last = source.slice(start).trim();
  if (!last) return [source];
  steps.push(last);
  return steps;
}

/** @returns {{type: 'input-move', kind: string, buttonUid: string, fromIndex: number, beforeIndex: number}|null} */
function inputMoveAction(kind, buttonUid, inputs, fromIndex, beforeIndex) {
  if (!Array.isArray(inputs) || typeof kind !== 'string' || typeof buttonUid !== 'string'
    || !Number.isInteger(fromIndex) || !Number.isInteger(beforeIndex)
    || fromIndex < 0 || fromIndex >= inputs.length || beforeIndex < 0 || beforeIndex > inputs.length
    || beforeIndex === fromIndex || beforeIndex === fromIndex + 1) return null;
  return { type: 'input-move', kind, buttonUid, fromIndex, beforeIndex };
}

/** @returns {number} */
function inputMoveTargetIndex(fromIndex, beforeIndex) {
  return beforeIndex > fromIndex ? beforeIndex - 1 : beforeIndex;
}

/** @returns {boolean} */
function canAddClaudeInput(count) {
  return Number.isInteger(count) && count >= 0 && count < MAX_CLAUDE_INPUTS;
}

/** @param {KeyboardEvent} event @returns {boolean} */
function isImeCompositionKeyEvent(event) {
  return event?.isComposing === true || event?.keyCode === 229;
}

/**
 * Computes fixed-position geometry from viewport client rects. `height` and `width` are the
 * measured popover dimensions; a constrained height is applied to the scrollable surface.
 * @returns {{top: number, left: number, width: number, height: number, maxHeight: number, arrowX: number, placement: 'top'|'bottom'}}
 */
function calculatePopoverPosition(anchor, popover, viewport, margin = 12, gap = 12) {
  const viewportWidth = Math.max(0, Number(viewport?.width) || 0);
  const viewportHeight = Math.max(0, Number(viewport?.height) || 0);
  const safeMargin = Math.max(0, Number(margin) || 0);
  const safeGap = Math.max(0, Number(gap) || 0);
  if (!viewportWidth || !viewportHeight) {
    return { top: 0, left: 0, width: 0, height: 0, maxHeight: 0, arrowX: 0, placement: 'bottom' };
  }
  const width = Math.min(Math.max(0, Number(popover?.width) || 0), Math.max(0, viewportWidth - safeMargin * 2));
  const viewportMaxHeight = Math.max(0, viewportHeight - safeMargin * 2);
  const maxLeft = Math.max(safeMargin, viewportWidth - safeMargin - width);
  const left = Math.min(maxLeft, Math.max(safeMargin, Number(anchor?.left) || 0));
  const belowSpace = Math.max(0, viewportHeight - safeMargin - (Number(anchor?.bottom) || 0) - safeGap);
  const aboveSpace = Math.max(0, (Number(anchor?.top) || 0) - safeMargin - safeGap);
  const naturalHeight = Math.max(0, Number(popover?.height) || 0);
  const belowFits = naturalHeight <= belowSpace;
  const aboveFits = naturalHeight <= aboveSpace;
  const placement = !belowFits && (aboveFits || aboveSpace > belowSpace) ? 'top' : 'bottom';
  const availableSpace = placement === 'top' ? aboveSpace : belowSpace;
  const minimumUsableHeight = Math.min(160, viewportMaxHeight);
  const maxHeight = Math.min(viewportMaxHeight, Math.max(availableSpace, minimumUsableHeight));
  const height = Math.min(naturalHeight, maxHeight);
  const proposedTop = placement === 'top'
    ? (Number(anchor?.top) || 0) - safeGap - height
    : (Number(anchor?.bottom) || 0) + safeGap;
  const top = Math.min(Math.max(safeMargin, viewportHeight - safeMargin - height), Math.max(safeMargin, proposedTop));
  const anchorCenter = ((Number(anchor?.left) || 0) + (Number(anchor?.right) || 0)) / 2;
  const arrowX = Math.max(Math.min(16, width / 2), Math.min(width - Math.min(16, width / 2), anchorCenter - left));
  return { top, left, width, height, maxHeight, arrowX, placement };
}

/** @returns {boolean} */
function hasMeasurableViewport(viewport) {
  return Number.isFinite(viewport?.width) && viewport.width > 0
    && Number.isFinite(viewport?.height) && viewport.height > 0;
}

let root = null;
let engine = null;
let snapshot = null;
let unsubscribe = null;
let active = null;
let pendingPresetId = null;
let failureMessage = '';
let instanceCounter = 0;
let inputDrag = null;
let armedInputDragRow = null;
let popoverPositionFrame = null;
let cancelPopoverPositionFrame = null;

function disarmInputDrag() {
  if (armedInputDragRow) armedInputDragRow.draggable = false;
  armedInputDragRow = null;
  document.removeEventListener('mouseup', handleInputMouseUp);
}

function clearInputDropMarks() {
  root?.querySelectorAll('.options-editor-input-row')
    .forEach(row => row.classList.remove('drop-before', 'drop-after', 'dragging'));
}

function cancelInputDrag() {
  disarmInputDrag();
  if (inputDrag?.row) inputDrag.row.draggable = false;
  inputDrag = null;
  clearInputDropMarks();
}

function handleInputMouseUp() {
  disarmInputDrag();
}

function editorMessage(name, ...args) {
  switch (name) {
    case 'title': return tr('ext.d.editor.title');
    case 'close': return tr('ext.d.editor.close');
    case 'variableInsert': return tr('ext.d.editor.variableInsert', ...args);
    case 'moveEarlier': return tr('ext.d.editor.moveEarlier');
    case 'moveLater': return tr('ext.d.editor.moveLater');
    case 'replacePreset': return tr('ext.d.editor.replacePreset');
    case 'confirmReplace': return tr('ext.d.editor.confirmReplace', ...args);
    case 'confirm': return tr('ext.d.editor.confirm');
    case 'cancel': return tr('ext.d.editor.cancel');
    case 'cannotUpdate': return tr('ext.d.editor.cannotUpdate');
    case 'limitReached': return tr('ext.d.editor.limitReached');
    case 'deleteUnavailable': return tr('ext.d.editor.deleteUnavailable');
    case 'inputLimit': return tr('ext.d.editor.inputLimit', ...args);
    case 'inputExample': return tr('ext.d.editor.inputExample', ...args);
    case 'inputLabel': return tr('ext.d.editor.inputLabel', ...args);
    case 'inputRemove': return tr('ext.d.editor.inputRemove', ...args);
    case 'inputTypeShell': return tr('ext.d.editor.inputTypeShell');
    case 'inputTypeSlash': return tr('ext.d.editor.inputTypeSlash');
    case 'inputTypeDirective': return tr('ext.d.editor.inputTypeDirective');
    case 'inputTypeMessage': return tr('ext.d.editor.inputTypeMessage');
    case 'exampleTitle': return tr('ext.d.editor.exampleTitle');
    case 'exampleNotice': return tr('ext.d.editor.exampleNotice');
    case 'exampleCommand': return tr('ext.d.editor.exampleCommand');
    case 'exampleEmptyCommand': return tr('ext.d.editor.exampleEmptyCommand');
    case 'exampleInputs': return tr('ext.d.editor.exampleInputs');
    case 'exampleNoInputs': return tr('ext.d.editor.exampleNoInputs');
    case 'exampleCdNote': return tr('ext.d.editor.exampleCdNote', ...args);
    case 'exampleUnsupported': return tr('ext.d.editor.exampleUnsupported', ...args);
    default: return '';
  }
}

function makeElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function makeButton(label, className, action) {
  const button = makeElement('button', className, label);
  button.type = 'button';
  if (action) button.dataset.editorAction = action;
  return button;
}

function inputTypeMessage(type) {
  switch (type) {
    case 'shell': return editorMessage('inputTypeShell');
    case 'slash': return editorMessage('inputTypeSlash');
    case 'directive': return editorMessage('inputTypeDirective');
    default: return editorMessage('inputTypeMessage');
  }
}

function buildClaudeInputRow() {
  const row = makeElement('div', 'options-editor-input-row');
  const handle = makeButton('⠿', 'options-editor-input-drag-handle', null);
  handle.setAttribute('aria-label', tr('ext.claudeInput.reorder.aria', 1));
  const number = makeElement('span', 'options-editor-input-number');
  const type = makeElement('span', 'options-editor-input-type');
  const input = makeElement('input', 'options-editor-input');
  input.type = 'text';
  input.spellcheck = false;
  input.id = `options-editor-input-${++instanceCounter}`;
  const inputLabel = makeElement('label', 'options-editor-sr-only', editorMessage('inputLabel', 1));
  inputLabel.htmlFor = input.id;
  const example = makeElement('span', 'options-editor-input-example');
  const earlier = makeButton('↑', 'btn-secondary options-editor-input-move options-editor-input-move-earlier', 'input-move-earlier');
  earlier.setAttribute('aria-label', tr('ext.d.editor.moveEarlier'));
  const later = makeButton('↓', 'btn-secondary options-editor-input-move options-editor-input-move-later', 'input-move-later');
  later.setAttribute('aria-label', tr('ext.d.editor.moveLater'));
  const remove = makeButton('×', 'btn-secondary options-editor-input-remove', 'input-remove');
  remove.setAttribute('aria-label', tr('ext.d.editor.inputRemove', 1));
  const tooltip = makeElement('span', 'options-editor-reorder-tooltip', tr('ext.reorder.tooltip'));
  tooltip.id = `options-editor-reorder-tooltip-${++instanceCounter}`;
  tooltip.setAttribute('role', 'tooltip');
  handle.setAttribute('aria-describedby', tooltip.id);
  earlier.setAttribute('aria-describedby', tooltip.id);
  later.setAttribute('aria-describedby', tooltip.id);
  row.append(handle, number, type, inputLabel, input, example, earlier, later, remove, tooltip);
  return row;
}

function buildClaudeInputSection() {
  const section = makeElement('section', 'options-editor-claude-section');
  const heading = makeElement('h3', 'options-editor-section-heading', tr('ext.field.claudeInputs'));
  const help = makeElement('div', 'options-editor-claude-help');
  help.innerHTML = tHTML('ext.field.claudeInputs.help');
  const hint = makeElement('div', 'options-editor-claude-hint');
  hint.innerHTML = tHTML('ext.field.claudeInputs.hint');
  hint.hidden = true;
  const warning = makeElement('p', 'options-editor-claude-warning', tr('ext.field.claudeInputs.warn'));
  warning.hidden = true;
  warning.setAttribute('role', 'status');
  const rows = makeElement('div', 'options-editor-input-rows');
  const limit = makeElement('p', 'options-editor-input-limit', editorMessage('inputLimit', MAX_CLAUDE_INPUTS));
  limit.hidden = true;
  const add = makeButton(tr('ext.button.addInput'), 'btn-secondary options-editor-input-add', 'input-add');
  section.append(heading, help, hint, warning, rows, limit, add);
  return section;
}

function buildExampleDock() {
  const dock = makeElement('section', 'options-editor-example-dock');
  const heading = makeElement('h3', 'options-editor-section-heading', editorMessage('exampleTitle'));
  const notice = makeElement('p', 'options-editor-example-notice', editorMessage('exampleNotice'));
  const cdNote = makeElement('p', 'options-editor-example-cd-note');
  const warning = makeElement('p', 'options-editor-example-warning');
  warning.setAttribute('role', 'status');
  warning.hidden = true;
  const commandHeading = makeElement('h4', 'options-editor-example-subheading', editorMessage('exampleCommand'));
  const command = makeElement('ol', 'options-editor-example-command');
  const inputHeading = makeElement('h4', 'options-editor-example-subheading', editorMessage('exampleInputs'));
  const inputs = makeElement('ol', 'options-editor-example-inputs');
  const emptyCommand = makeElement('p', 'options-editor-example-empty-command', editorMessage('exampleEmptyCommand'));
  emptyCommand.hidden = true;
  const emptyInputs = makeElement('p', 'options-editor-example-empty-inputs', editorMessage('exampleNoInputs'));
  dock.append(heading, notice, cdNote, warning, commandHeading, command, emptyCommand, inputHeading, inputs, emptyInputs);
  return dock;
}

function facePalette() {
  return typeof FACE_EMOJI === 'undefined' ? [] : FACE_EMOJI;
}

function currentButton(source = snapshot, target = active) {
  if (!source || !target || !Object.hasOwn(source.buttons || {}, target.kind)) return null;
  return source.buttons[target.kind].find(button => button.uid === target.uid) || null;
}

function clientRect(element) {
  const rect = element.getBoundingClientRect();
  return {
    left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom,
    width: rect.width, height: rect.height,
  };
}

function buttonIndex(source, kind, uid) {
  return (source?.buttons?.[kind] || []).findIndex(button => button.uid === uid);
}

function currentPanel() {
  return root?.querySelector('.options-editor-popover') || null;
}

function fieldInPanel(name) {
  return currentPanel()?.querySelector(`[data-editor-field="${name}"]`) || null;
}

function focusElement(element) {
  if (!element?.isConnected || typeof element.focus !== 'function') return false;
  try {
    element.focus({ preventScroll: true });
  } catch {
    element.focus();
  }
  return true;
}

function focusFallback(kind, uid) {
  const target = window.optionsReplica?.focusButton?.(kind, uid);
  if (target && typeof target.focus === 'function') focusElement(target);
}

function closePopover({ restoreFocus = true } = {}) {
  if (!active) return;
  const { kind, uid, restoreFocusTo } = active;
  cancelInputDrag();
  if (popoverPositionFrame !== null) cancelPopoverPositionFrame?.();
  popoverPositionFrame = null;
  cancelPopoverPositionFrame = null;
  active = null;
  pendingPresetId = null;
  failureMessage = '';
  root?.replaceChildren();
  if (!restoreFocus) return;
  if (restoreFocusTo?.isConnected) focusElement(restoreFocusTo);
  else focusFallback(kind, uid);
}

function readViewportSize() {
  const rootElement = document.documentElement;
  return {
    width: Number.isFinite(window.innerWidth) ? window.innerWidth : Number(rootElement.clientWidth) || 0,
    height: Number.isFinite(window.innerHeight) ? window.innerHeight : Number(rootElement.clientHeight) || 0,
  };
}

function schedulePopoverPosition() {
  if (!active || popoverPositionFrame !== null) return;
  const place = () => {
    popoverPositionFrame = null;
    cancelPopoverPositionFrame = null;
    if (active && hasMeasurableViewport(readViewportSize())) positionPopover();
  };
  if (typeof window.requestAnimationFrame === 'function') {
    popoverPositionFrame = window.requestAnimationFrame(place);
    cancelPopoverPositionFrame = () => window.cancelAnimationFrame?.(popoverPositionFrame);
  } else {
    popoverPositionFrame = window.setTimeout(place, 0);
    cancelPopoverPositionFrame = () => window.clearTimeout(popoverPositionFrame);
  }
}

function positionPopover() {
  const panel = currentPanel();
  if (!panel || !active?.anchor) return;
  const viewport = readViewportSize();
  if (!hasMeasurableViewport(viewport)) {
    schedulePopoverPosition();
    return;
  }
  panel.style.width = '';
  panel.style.maxHeight = '';
  const content = panel.querySelector('.options-editor-content');
  if (content) content.style.maxHeight = '';
  let popoverRect = panel.getBoundingClientRect();
  const { width: viewportWidth, height: viewportHeight } = viewport;
  if (!popoverRect.width || !popoverRect.height) {
    const fallbackWidth = Math.min(440, viewportWidth - 24);
    const fallbackHeight = Math.min(panel.scrollHeight || 560, viewportHeight - 24);
    popoverRect = { width: popoverRect.width || fallbackWidth, height: popoverRect.height || fallbackHeight };
  }
  let anchorRect = active.anchorRect || { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
  if (active.anchor?.isConnected) {
    anchorRect = clientRect(active.anchor);
    active.anchorRect = anchorRect;
    active.anchorScrollX = window.scrollX || 0;
    active.anchorScrollY = window.scrollY || 0;
  } else if (active.anchorRect) {
    const deltaX = (window.scrollX || 0) - (active.anchorScrollX || 0);
    const deltaY = (window.scrollY || 0) - (active.anchorScrollY || 0);
    anchorRect = {
      ...active.anchorRect,
      left: active.anchorRect.left - deltaX,
      right: active.anchorRect.right - deltaX,
      top: active.anchorRect.top - deltaY,
      bottom: active.anchorRect.bottom - deltaY,
    };
  }
  const placed = calculatePopoverPosition(
    anchorRect,
    popoverRect,
    { width: viewportWidth, height: viewportHeight },
  );
  panel.style.left = `${placed.left}px`;
  panel.style.top = `${placed.top}px`;
  panel.style.width = `${placed.width}px`;
  panel.style.maxHeight = `${placed.maxHeight}px`;
  if (content) content.style.maxHeight = `${Math.max(0, placed.maxHeight - 2)}px`;
  panel.style.setProperty('--editor-arrow-x', `${placed.arrowX}px`);
  panel.dataset.placement = placed.placement;
}

function updateEditorFacePreview(button) {
  const preview = currentPanel()?.querySelector('.options-editor-face-preview');
  if (!preview) return;
  const shown = buttonFace({ face: button.face });
  preview.textContent = shown;
  preview.className = 'options-editor-face-preview';
  if (active.kind === 'repo') preview.classList.add('is-repository');
  else preview.classList.add(isTextFace(shown) ? 'is-text-face' : 'is-emoji-face');
}

function renderValidation(button) {
  const list = currentPanel()?.querySelector('.options-editor-validation');
  if (!list) return;
  list.replaceChildren();
  const messages = validationFor(snapshot, active.kind, button, { includeWarnings: false });
  list.hidden = messages.length === 0;
  for (const text of messages) list.appendChild(makeElement('p', 'options-editor-diagnostic', text));
}

function renderClaudeInputs(button) {
  const panel = currentPanel();
  const rows = panel?.querySelector('.options-editor-input-rows');
  if (!rows) return;
  cancelInputDrag();
  const values = Array.isArray(button.claudeInputs) ? button.claudeInputs : [];
  while (rows.children.length < values.length) rows.appendChild(buildClaudeInputRow());
  while (rows.children.length > values.length) rows.lastElementChild.remove();

  [...rows.children].forEach((row, index) => {
    const value = typeof values[index] === 'string' ? values[index] : '';
    row.dataset.inputIndex = String(index);
    const handle = row.querySelector('.options-editor-input-drag-handle');
    const number = row.querySelector('.options-editor-input-number');
    const type = row.querySelector('.options-editor-input-type');
    const input = row.querySelector('.options-editor-input');
    const inputLabel = row.querySelector('.options-editor-sr-only[for]');
    const example = row.querySelector('.options-editor-input-example');
    const earlier = row.querySelector('[data-editor-action="input-move-earlier"]');
    const later = row.querySelector('[data-editor-action="input-move-later"]');
    number.textContent = `⏎${index + 1}`;
    type.textContent = inputTypeMessage(classifyClaudeInput(value));
    input.dataset.inputIndex = String(index);
    inputLabel.textContent = editorMessage('inputLabel', index + 1);
    if (document.activeElement !== input && input.value !== value) input.value = value;
    example.textContent = editorMessage('inputExample', tr('ext.field.claudeInput.placeholder'));
    example.hidden = value.length > 0;
    handle.disabled = values.length < 2;
    earlier.disabled = index <= 0;
    later.disabled = index >= values.length - 1;
    handle.setAttribute('aria-label', tr('ext.claudeInput.reorder.aria', index + 1));
    row.querySelector('.options-editor-input-remove')
      ?.setAttribute('aria-label', tr('ext.d.editor.inputRemove', index + 1));
  });

  const normalizedValues = normalizeClaudeInputs(values);
  const hint = panel.querySelector('.options-editor-claude-hint');
  const warning = panel.querySelector('.options-editor-claude-warning');
  const add = panel.querySelector('[data-editor-action="input-add"]');
  const limit = panel.querySelector('.options-editor-input-limit');
  hint.hidden = normalizedValues.length === 0;
  const diagnostic = snapshot?.validation?.buttons?.find(entry => entry.kind === active.kind && entry.uid === button.uid);
  warning.hidden = !(diagnostic?.warnings || []).includes('claude-inputs-without-claude-command');
  add.disabled = !canAddClaudeInput(values.length);
  limit.hidden = values.length < MAX_CLAUDE_INPUTS;
  positionPopover();
}

function renderExampleDock(button) {
  const panel = currentPanel();
  const dock = panel?.querySelector('.options-editor-example-dock');
  if (!dock) return;
  const context = window.optionsReplica?.getExampleContext?.() || {};
  const values = Array.isArray(button.claudeInputs) ? button.claudeInputs : [];
  const command = expandExampleTemplate(button.command, active.kind, context);
  const commandSteps = splitCommandSteps(command.text);
  const commandList = dock.querySelector('.options-editor-example-command');
  const inputList = dock.querySelector('.options-editor-example-inputs');
  const warning = dock.querySelector('.options-editor-example-warning');
  const emptyCommand = dock.querySelector('.options-editor-example-empty-command');
  const emptyInputs = dock.querySelector('.options-editor-example-empty-inputs');
  const cdNote = dock.querySelector('.options-editor-example-cd-note');
  const samplePath = typeof context.repoPath === 'string' ? context.repoPath : '';
  cdNote.textContent = editorMessage('exampleCdNote', samplePath);
  cdNote.hidden = ![button.command, ...values].some(value => typeof value === 'string' && /\{cd\}/.test(value));
  commandList.replaceChildren();
  emptyCommand.hidden = commandSteps.length > 0;
  for (const [index, step] of commandSteps.entries()) {
    const item = makeElement('li', 'options-editor-example-step');
    const code = makeElement('code', '', step);
    item.dataset.exampleStep = String(index);
    item.appendChild(code);
    commandList.appendChild(item);
  }
  inputList.replaceChildren();
  const projectedInputs = values.map(value => expandExampleTemplate(value, active.kind, context));
  for (const [index, projection] of projectedInputs.entries()) {
    const item = makeElement('li', 'options-editor-example-input');
    const type = makeElement('span', 'options-editor-example-input-type', inputTypeMessage(classifyClaudeInput(values[index])));
    const code = makeElement('code', 'options-editor-example-input-value', projection.text);
    item.dataset.exampleInput = String(index);
    item.append(type, code);
    inputList.appendChild(item);
  }
  emptyInputs.hidden = values.length > 0;

  const allUnresolved = new Set([
    ...command.unsupported, ...command.missing,
    ...projectedInputs.flatMap(input => [...input.unsupported, ...input.missing]),
  ]);
  const kindsAllowVariables = buttonUsesAllowedVariables(active.kind, button);
  const shouldWarn = !kindsAllowVariables || allUnresolved.size > 0;
  warning.hidden = !shouldWarn;
  warning.textContent = shouldWarn
    ? editorMessage('exampleUnsupported', [...allUnresolved].map(name => `{${name}}`).join(', '))
    : '';
  positionPopover();
}

function renderFailure() {
  const status = currentPanel()?.querySelector('.options-editor-status');
  if (!status) return;
  status.textContent = failureMessage;
  status.hidden = !failureMessage;
}

function renderPresetConfirmation(button) {
  const panel = currentPanel();
  const confirmation = panel?.querySelector('.options-editor-preset-confirmation');
  const choices = panel?.querySelector('.options-editor-presets');
  const selected = BUTTON_KINDS[active.kind].presets.find(preset => preset.id === pendingPresetId) || null;
  if (!confirmation || !choices) return;
  confirmation.hidden = !selected;
  choices.hidden = panel.querySelector('.options-editor-preset-toggle').getAttribute('aria-expanded') !== 'true';
  if (!selected) {
    confirmation.replaceChildren();
    return;
  }
  confirmation.replaceChildren();
  const note = makeElement('p', 'options-editor-confirm-copy', editorMessage('confirmReplace', selected.name));
  note.setAttribute('role', 'alert');
  confirmation.appendChild(note);
  const actions = makeElement('div', 'options-editor-confirm-actions');
  const cancel = makeButton(editorMessage('cancel'), 'btn-secondary', 'cancel-preset');
  const confirm = makeButton(editorMessage('confirm'), 'btn-primary', 'confirm-preset');
  confirm.dataset.presetId = selected.id;
  actions.append(cancel, confirm);
  confirmation.appendChild(actions);
  choices.hidden = true;
  const toggle = panel.querySelector('.options-editor-preset-toggle');
  toggle.setAttribute('aria-expanded', 'false');
  toggle.textContent = editorMessage('replacePreset');
}

function updatePanel() {
  if (!active || !root) return;
  const button = currentButton();
  if (!button) {
    closePopover();
    return;
  }
  const list = snapshot.buttons[active.kind];
  const index = buttonIndex(snapshot, active.kind, active.uid);
  const face = fieldInPanel('face');
  const label = fieldInPanel('label');
  const command = fieldInPanel('command');
  if (face && document.activeElement !== face && face.value !== button.face) face.value = button.face;
  if (label && document.activeElement !== label && label.value !== button.label) label.value = button.label;
  if (command && document.activeElement !== command && command.value !== button.command) command.value = button.command;
  renderClaudeInputs(button);
  renderExampleDock(button);
  const heading = currentPanel().querySelector('.options-editor-heading-name');
  if (heading) heading.textContent = button.label || editorMessage('title');
  updateEditorFacePreview(button);
  renderValidation(button);
  const moveEarlier = currentPanel().querySelector('[data-editor-action="move-earlier"]');
  const moveLater = currentPanel().querySelector('[data-editor-action="move-later"]');
  const duplicate = currentPanel().querySelector('[data-editor-action="duplicate"]');
  const remove = currentPanel().querySelector('[data-editor-action="remove"]');
  moveEarlier.disabled = index <= 0;
  moveLater.disabled = index < 0 || index >= list.length - 1;
  duplicate.disabled = list.length >= MAX_BUTTONS;
  remove.disabled = list.length <= 1;
  const deleteHint = currentPanel().querySelector('.options-editor-delete-hint');
  deleteHint.hidden = !remove.disabled;
  for (const choice of currentPanel().querySelectorAll('[data-editor-action="choose-preset"]')) {
    choice.setAttribute('aria-pressed', String(choice.dataset.presetId === button.presetId));
  }
  renderPresetConfirmation(button);
  renderFailure();
  positionPopover();
}

function createField({ name, label, value, type = 'input', maxLength = null }) {
  const field = makeElement('div', `options-editor-field field-${name}`);
  const id = `options-editor-${++instanceCounter}-${name}`;
  const labelElement = makeElement('label', '', label);
  labelElement.htmlFor = id;
  const control = makeElement(type, 'options-editor-control');
  control.id = id;
  control.dataset.editorField = name;
  if (type === 'textarea') {
    control.rows = 3;
    control.spellcheck = false;
  } else {
    control.type = 'text';
  }
  control.value = value;
  if (maxLength !== null) control.maxLength = maxLength;
  field.append(labelElement, control);
  return { field, control };
}

function replaceVariableReferences(container, kind) {
  const allowed = new Set(variablesForKind(kind));
  for (const code of container.querySelectorAll('code')) {
    const match = code.textContent.match(/^\{([A-Za-z_]\w*)\}$/);
    const name = match?.[1];
    if (!name || !allowed.has(name)) continue;
    const token = makeButton(code.textContent, 'options-editor-variable', 'insert-variable');
    token.dataset.variable = name;
    token.setAttribute('aria-label', tr('ext.d.editor.variableInsert', code.textContent));
    const description = code.nextElementSibling?.classList.contains('faint')
      ? code.nextElementSibling
      : null;
    if (description) {
      description.id = description.id || `options-editor-variable-description-${++instanceCounter}`;
      token.setAttribute('aria-describedby', description.id);
    }
    code.replaceWith(token);
  }
}

function buildPresetChoices(kind) {
  const choices = makeElement('div', 'options-editor-presets');
  choices.hidden = true;
  for (const preset of BUTTON_KINDS[kind].presets) {
    const choice = makeButton('', 'options-editor-preset-choice', 'choose-preset');
    choice.dataset.presetId = preset.id;
    const face = makeElement('span', 'options-editor-preset-face', preset.face);
    const name = makeElement('span', 'options-editor-preset-name', preset.name);
    const command = makeElement('code', 'options-editor-preset-command', preset.command);
    choice.append(face, name, command);
    choices.appendChild(choice);
  }
  return choices;
}

function buildPopover(button) {
  const kind = active.kind;
  const panel = makeElement('section', 'options-editor-popover');
  panel.dataset.optionsEditorSurface = 'popover';
  panel.setAttribute('role', 'dialog');
  const inner = makeElement('div', 'options-editor-content');
  const header = makeElement('header', 'options-editor-header');
  const identity = makeElement('div', 'options-editor-identity');
  const preview = makeElement('span', 'options-editor-face-preview');
  const heading = makeElement('h2', 'options-editor-heading-name', button.label || editorMessage('title'));
  heading.id = `options-editor-heading-${++instanceCounter}`;
  preview.setAttribute('aria-labelledby', heading.id);
  identity.append(preview, heading);
  const close = makeButton('×', 'options-editor-close', 'close');
  close.setAttribute('aria-label', tr('ext.d.editor.close'));
  header.append(identity, close);

  const fields = makeElement('div', 'options-editor-fields');
  const face = createField({ name: 'face', label: tr('ext.field.face'), value: button.face, maxLength: FACE_MAX_LENGTH });
  const label = createField({ name: 'label', label: tr('ext.field.tooltip'), value: button.label });
  fields.append(face.field, label.field);

  const palette = makeElement('div', 'options-editor-palette');
  const paletteLabel = makeElement('span', 'options-editor-palette-label', tr('ext.card.palette.label'));
  palette.appendChild(paletteLabel);
  for (const emoji of facePalette()) {
    const emojiButton = makeButton(emoji, 'options-editor-emoji', 'append-emoji');
    emojiButton.setAttribute('aria-label', tr('ext.card.palette.tooltip', emoji));
    emojiButton.dataset.emoji = emoji;
    palette.appendChild(emojiButton);
  }

  const commandSection = makeElement('section', 'options-editor-command-section');
  const commandField = createField({
    name: 'command', label: tr('ext.field.command'), value: button.command, type: 'textarea',
  });
  const prompt = makeElement('span', 'options-editor-command-prompt', '$');
  const commandBox = makeElement('div', 'options-editor-command-box');
  commandBox.append(prompt, commandField.control);
  commandField.field.appendChild(commandBox);
  const variablesHelp = makeElement('div', 'options-editor-variable-help');
  // These five existing catalogue entries are trusted extension markup; no setting value is used here.
  variablesHelp.innerHTML = SECTION_VARIABLE_HELP[kind]();
  replaceVariableReferences(variablesHelp, kind);
  commandSection.append(commandField.field, variablesHelp);

  const validation = makeElement('div', 'options-editor-validation');
  validation.setAttribute('aria-live', 'polite');
  validation.setAttribute('aria-atomic', 'true');
  const futureSlot = makeElement('div', 'options-editor-followup-slot');
  futureSlot.dataset.editorSlot = 'claude-inputs';
  futureSlot.append(buildClaudeInputSection(), buildExampleDock());

  const actions = makeElement('div', 'options-editor-actions');
  const earlier = makeButton('↑', 'btn-secondary options-editor-order', 'move-earlier');
  earlier.setAttribute('aria-label', tr('ext.d.editor.moveEarlier'));
  const later = makeButton('↓', 'btn-secondary options-editor-order', 'move-later');
  later.setAttribute('aria-label', tr('ext.d.editor.moveLater'));
  const presetToggle = makeButton(editorMessage('replacePreset'), 'btn-secondary options-editor-preset-toggle', 'toggle-presets');
  presetToggle.setAttribute('aria-expanded', 'false');
  const duplicate = makeButton(tr('ext.card.duplicate'), 'btn-secondary', 'duplicate');
  const remove = makeButton(tr('ext.card.delete'), 'btn-secondary options-editor-delete', 'remove');
  const deleteHint = makeElement('span', 'options-editor-delete-hint', editorMessage('deleteUnavailable'));
  deleteHint.id = `options-editor-delete-hint-${++instanceCounter}`;
  deleteHint.hidden = true;
  remove.setAttribute('aria-describedby', deleteHint.id);
  actions.append(earlier, later, presetToggle, duplicate, remove, deleteHint);

  const presetChoices = buildPresetChoices(kind);
  const confirmation = makeElement('div', 'options-editor-preset-confirmation');
  confirmation.hidden = true;
  const status = makeElement('p', 'options-editor-status');
  status.setAttribute('role', 'status');
  status.hidden = true;
  const dialogHeading = makeElement('span', 'options-editor-sr-only', editorMessage('title'));
  dialogHeading.id = `options-editor-title-${++instanceCounter}`;
  panel.setAttribute('aria-labelledby', dialogHeading.id);
  panel.appendChild(dialogHeading);
  inner.append(header, fields, palette, commandSection, validation, futureSlot, presetChoices, confirmation, status, actions);
  panel.appendChild(inner);
  root.replaceChildren(panel);
  updatePanel();
  positionPopover();
  focusElement(fieldInPanel('face'));
}

function refreshAnchorFromReplica() {
  if (!active) return null;
  const previousFocus = document.activeElement;
  const target = window.optionsReplica?.focusButton?.(active.kind, active.uid);
  const focused = target && typeof target.getBoundingClientRect === 'function'
    ? target
    : (!currentPanel()?.contains(document.activeElement) ? document.activeElement : null);
  if (focused?.isConnected && focused !== document.body) {
    active.anchor = focused;
    active.restoreFocusTo = focused;
    active.anchorRect = clientRect(focused);
    active.anchorScrollX = window.scrollX || 0;
    active.anchorScrollY = window.scrollY || 0;
  }
  if (previousFocus?.isConnected && currentPanel()?.contains(previousFocus)) focusElement(previousFocus);
  positionPopover();
  return focused || null;
}

function acceptSnapshot(nextSnapshot) {
  if (!nextSnapshot || typeof nextSnapshot !== 'object') return;
  snapshot = nextSnapshot;
  if (!active) return;
  if (!currentButton()) {
    const restoreFocus = currentPanel()?.contains(document.activeElement) ?? false;
    closePopover({ restoreFocus });
    return;
  }
  updatePanel();
}

function resultSnapshot(result) {
  if (result?.snapshot && typeof result.snapshot === 'object') return result.snapshot;
  if (result?.buttons && typeof result.buttons === 'object') return result;
  return null;
}

function failureForReason(reason) {
  if (reason === 'limit') return editorMessage('limitReached');
  if (reason === 'not-found') return editorMessage('cannotUpdate');
  if (reason === 'needs-confirmation') return editorMessage('cannotUpdate');
  if (reason === 'not-loaded' || reason === 'busy' || reason === 'invalid' || reason === 'failed') {
    return editorMessage('cannotUpdate');
  }
  return '';
}

async function dispatchAction(action) {
  if (!engine) return null;
  const targetAtStart = active ? { kind: active.kind, uid: active.uid } : null;
  const stillEditingTarget = () => targetAtStart
    && active?.kind === targetAtStart.kind && active?.uid === targetAtStart.uid;
  failureMessage = '';
  renderFailure();
  try {
    const result = await engine.dispatch(action);
    const nextSnapshot = resultSnapshot(result);
    if (nextSnapshot) acceptSnapshot(nextSnapshot);
    else acceptSnapshot(engine.getSnapshot());
    if (result?.ok === false && stillEditingTarget()) {
      failureMessage = failureForReason(result.reason);
      renderFailure();
    }
    return result;
  } catch {
    if (stillEditingTarget()) {
      failureMessage = editorMessage('cannotUpdate');
      renderFailure();
    }
    return null;
  }
}

function insertVariable(name) {
  const textarea = fieldInPanel('command');
  if (!textarea) return;
  const token = `{${name}}`;
  const start = Number.isInteger(textarea.selectionStart) ? textarea.selectionStart : textarea.value.length;
  const end = Number.isInteger(textarea.selectionEnd) ? textarea.selectionEnd : textarea.value.length;
  textarea.setRangeText(token, start, end, 'end');
  textarea.focus({ preventScroll: true });
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  positionPopover();
}

function focusReplicaTarget(kind, uid) {
  const previouslyFocused = document.activeElement;
  const target = window.optionsReplica?.focusButton?.(kind, uid);
  if (target && typeof target.focus === 'function') focusElement(target);
  const activeElement = document.activeElement;
  if (activeElement !== previouslyFocused && activeElement && typeof activeElement.getBoundingClientRect === 'function'
    && !currentPanel()?.contains(activeElement) && activeElement !== document.body) return activeElement;
  return target && typeof target.getBoundingClientRect === 'function' ? target : null;
}

async function moveButton(direction) {
  const { kind, uid } = active;
  const button = currentButton();
  const action = button && buttonMoveAction(snapshot, kind, uid, direction);
  if (!action) return;
  const editorFocus = document.activeElement;
  await dispatchAction(action);
  if (!active || active.kind !== kind || active.uid !== uid) return;
  await Promise.resolve();
  if (!active || active.kind !== kind || active.uid !== uid) return;
  refreshAnchorFromReplica();
  if (editorFocus?.isConnected && currentPanel()?.contains(editorFocus)) focusElement(editorFocus);
  positionPopover();
}

async function duplicateEditorButton() {
  const { kind, uid } = active;
  const result = await dispatchAction({ type: 'button-duplicate', kind, uid });
  if (!active || active.kind !== kind || active.uid !== uid) return;
  if (!result?.ok || !result.createdUid) return;
  await Promise.resolve();
  const target = focusReplicaTarget(kind, result.createdUid);
  if (!target) {
    closePopover();
    return;
  }
  window.optionsEditor.open({ kind, uid: result.createdUid, anchor: target, restoreFocusTo: target });
}

async function replaceWithPreset(presetId, confirmed = false) {
  if (!active || !presetId) return;
  const { kind, uid } = active;
  const result = await dispatchAction(presetReplaceAction(kind, uid, presetId, confirmed));
  if (!active || active.kind !== kind || active.uid !== uid) return;
  if (result?.ok) {
    refreshAnchorFromReplica();
    pendingPresetId = null;
    const choices = currentPanel()?.querySelector('.options-editor-presets');
    const toggle = currentPanel()?.querySelector('.options-editor-preset-toggle');
    if (choices) choices.hidden = true;
    if (toggle) toggle.setAttribute('aria-expanded', 'false');
    renderPresetConfirmation(currentButton());
    focusElement(toggle);
  } else if (result?.reason === 'needs-confirmation') {
    failureMessage = '';
    pendingPresetId = presetId;
    renderPresetConfirmation(currentButton());
    focusElement(currentPanel()?.querySelector('[data-editor-action="cancel-preset"]'));
  }
}

async function addClaudeInput() {
  if (!active) return;
  const { kind, uid } = active;
  const button = currentButton();
  if (!button || !canAddClaudeInput(button.claudeInputs?.length || 0)) return;
  const result = await dispatchAction({ type: 'input-add', kind, buttonUid: uid });
  if (!result?.ok || active?.kind !== kind || active?.uid !== uid) return;
  const index = (currentButton()?.claudeInputs?.length || 1) - 1;
  focusElement(currentPanel()?.querySelector(`.options-editor-input-row[data-input-index="${index}"] .options-editor-input`));
}

async function removeClaudeInput(inputIndex) {
  if (!active || !Number.isInteger(inputIndex)) return;
  const { kind, uid } = active;
  const result = await dispatchAction({ type: 'input-remove', kind, buttonUid: uid, inputIndex });
  if (!result?.ok || active?.kind !== kind || active?.uid !== uid) return;
  const values = currentButton()?.claudeInputs || [];
  const nextIndex = Math.min(inputIndex, values.length - 1);
  const focusTarget = nextIndex >= 0
    ? currentPanel()?.querySelector(`.options-editor-input-row[data-input-index="${nextIndex}"] .options-editor-input`)
    : currentPanel()?.querySelector('[data-editor-action="input-add"]');
  focusElement(focusTarget);
}

async function moveClaudeInput(inputIndex, beforeIndex) {
  if (!active) return;
  const { kind, uid } = active;
  const button = currentButton();
  const inputs = button?.claudeInputs || [];
  const action = inputMoveAction(kind, uid, inputs, inputIndex, beforeIndex);
  if (!action) return;
  const result = await dispatchAction(action);
  if (!result?.ok || active?.kind !== kind || active?.uid !== uid) return;
  const targetIndex = inputMoveTargetIndex(inputIndex, beforeIndex);
  const row = currentPanel()?.querySelector(`.options-editor-input-row[data-input-index="${targetIndex}"]`);
  focusElement(row?.querySelector('.options-editor-input-drag-handle')
    || row?.querySelector('[data-editor-action="input-move-earlier"]')
    || row?.querySelector('.options-editor-input'));
}

function handleClick(event) {
  const target = event.target instanceof Element ? event.target.closest('[data-editor-action]') : null;
  if (!target || !root.contains(target) || !active) return;
  const action = target.dataset.editorAction;
  switch (action) {
    case 'close':
      closePopover();
      break;
    case 'append-emoji': {
      const face = fieldInPanel('face');
      if (!face) break;
      const value = appendFaceCharacter(face.value, target.dataset.emoji, FACE_MAX_LENGTH);
      if (value !== face.value) {
        face.value = value;
        face.dispatchEvent(new Event('input', { bubbles: true }));
      }
      focusElement(face);
      break;
    }
    case 'insert-variable':
      insertVariable(target.dataset.variable);
      break;
    case 'move-earlier':
      void moveButton(-1);
      break;
    case 'move-later':
      void moveButton(1);
      break;
    case 'input-add':
      void addClaudeInput();
      break;
    case 'input-remove': {
      const inputIndex = Number(target.closest('.options-editor-input-row')?.dataset.inputIndex);
      void removeClaudeInput(inputIndex);
      break;
    }
    case 'input-move-earlier':
    case 'input-move-later': {
      const inputIndex = Number(target.closest('.options-editor-input-row')?.dataset.inputIndex);
      const beforeIndex = action === 'input-move-earlier' ? inputIndex - 1 : inputIndex + 2;
      void moveClaudeInput(inputIndex, beforeIndex);
      break;
    }
    case 'duplicate':
      void duplicateEditorButton();
      break;
    case 'remove': {
      const { kind, uid } = active;
      void dispatchAction({ type: 'button-remove', kind, uid }).then(result => {
        if (result?.ok && active?.kind === kind && active?.uid === uid) closePopover();
      });
      break;
    }
    case 'toggle-presets': {
      pendingPresetId = null;
      const choices = currentPanel().querySelector('.options-editor-presets');
      const open = target.getAttribute('aria-expanded') !== 'true';
      target.setAttribute('aria-expanded', String(open));
      choices.hidden = !open;
      renderPresetConfirmation(currentButton());
      positionPopover();
      break;
    }
    case 'choose-preset': {
      const presetId = target.dataset.presetId;
      if (requiresPresetConfirmation(currentButton())) {
        pendingPresetId = presetId;
        renderPresetConfirmation(currentButton());
        focusElement(currentPanel()?.querySelector('[data-editor-action="cancel-preset"]'));
        positionPopover();
      } else {
        void replaceWithPreset(presetId);
      }
      break;
    }
    case 'cancel-preset':
      pendingPresetId = null;
      renderPresetConfirmation(currentButton());
      focusElement(currentPanel()?.querySelector('.options-editor-preset-toggle'));
      positionPopover();
      break;
    case 'confirm-preset':
      void replaceWithPreset(target.dataset.presetId, true);
      break;
    default:
      break;
  }
}

function handleInput(event) {
  if (!active || !(event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement)) return;
  if (event.target.classList.contains('options-editor-input')) {
    const inputIndex = Number(event.target.dataset.inputIndex);
    if (!Number.isInteger(inputIndex)) return;
    const row = event.target.closest('.options-editor-input-row');
    const type = row?.querySelector('.options-editor-input-type');
    const example = row?.querySelector('.options-editor-input-example');
    if (type) type.textContent = inputTypeMessage(classifyClaudeInput(event.target.value));
    if (example) example.hidden = event.target.value.length > 0;
    void dispatchAction({
      type: 'input-patch', kind: active.kind, buttonUid: active.uid,
      inputIndex, value: event.target.value,
    });
    return;
  }
  const field = event.target.dataset.editorField;
  if (!field) return;
  if (field === 'face' && !fitsFieldLimit(event.target.value, FACE_MAX_LENGTH)) {
    let clipped = event.target.value.slice(0, FACE_MAX_LENGTH);
    if (/^[\uD800-\uDBFF]$/.test(clipped.slice(-1))) clipped = clipped.slice(0, -1);
    event.target.value = clipped;
  }
  if (field === 'command') {
    event.target.style.height = 'auto';
    event.target.style.height = `${event.target.scrollHeight}px`;
  }
  const patch = { [field]: event.target.value };
  void dispatchAction({ type: 'button-patch', kind: active.kind, uid: active.uid, patch });
  if (field === 'face' || field === 'label') {
    const current = currentButton() || { face: '', label: '' };
    updateEditorFacePreview({ ...current, [field]: event.target.value });
  }
  if (field === 'label') {
    const heading = currentPanel()?.querySelector('.options-editor-heading-name');
    if (heading) heading.textContent = event.target.value || editorMessage('title');
  }
}

function handleKeydown(event) {
  if (!active || isImeCompositionKeyEvent(event)) return;
  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    closePopover();
    return;
  }
  const handle = event.target instanceof Element
    ? event.target.closest('.options-editor-input-drag-handle')
    : null;
  if (!handle || (event.key !== 'ArrowUp' && event.key !== 'ArrowDown')) return;
  const row = handle.closest('.options-editor-input-row');
  const inputIndex = Number(row?.dataset.inputIndex);
  const count = currentButton()?.claudeInputs?.length || 0;
  const direction = event.key === 'ArrowUp' ? -1 : 1;
  const targetIndex = inputIndex + direction;
  if (!Number.isInteger(inputIndex) || targetIndex < 0 || targetIndex >= count) return;
  event.preventDefault();
  event.stopPropagation();
  void moveClaudeInput(inputIndex, direction < 0 ? targetIndex : targetIndex + 1);
}

function handlePointerDown(event) {
  if (!active || eventPathIncludesEditor(event)) return;
  closePopover();
}

function handleWindowChange() {
  schedulePopoverPosition();
}

function handleMouseDown(event) {
  if (!(event.target instanceof Element)) return;
  const dragHandle = event.target.closest('.options-editor-input-drag-handle');
  if (dragHandle && !dragHandle.disabled && event.button === 0) {
    disarmInputDrag();
    root?.querySelectorAll('.options-editor-input-row').forEach(row => { row.draggable = false; });
    const row = dragHandle.closest('.options-editor-input-row');
    if (!row) return;
    row.draggable = true;
    armedInputDragRow = row;
    document.addEventListener('mouseup', handleInputMouseUp, { once: true });
    return;
  }
  if (event.target.closest('[data-editor-action="insert-variable"], [data-editor-action="append-emoji"]')) {
    event.preventDefault();
  }
}

function inputDropBeforeIndex(rows, clientY) {
  const items = [...rows.querySelectorAll('.options-editor-input-row')];
  const index = items.findIndex(row => {
    const rect = row.getBoundingClientRect();
    return clientY < rect.top + rect.height / 2;
  });
  return index < 0 ? items.length : index;
}

function inputDropZone(eventTarget) {
  if (!(eventTarget instanceof Element)) return null;
  const rows = eventTarget.closest('.options-editor-input-rows');
  const panel = currentPanel();
  return rows && panel?.contains(rows) ? rows : null;
}

function handleDragStart(event) {
  if (!active || !(event.target instanceof Element)) return;
  const row = event.target.closest('.options-editor-input-row');
  if (!row || !row.draggable || !root?.contains(row)) return;
  const button = currentButton();
  const fromIndex = Number(row.dataset.inputIndex);
  if (!button || !Number.isInteger(fromIndex) || fromIndex < 0 || fromIndex >= (button.claudeInputs?.length || 0)) {
    event.preventDefault();
    row.draggable = false;
    return;
  }
  inputDrag = {
    kind: active.kind, uid: active.uid, fromIndex,
    inputs: button.claudeInputs, row,
  };
  row.classList.add('dragging');
  if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
}

function handleDragOver(event) {
  if (!inputDrag || !active || active.kind !== inputDrag.kind || active.uid !== inputDrag.uid) return;
  const rows = inputDropZone(event.target);
  if (!rows || currentButton()?.claudeInputs !== inputDrag.inputs) {
    clearInputDropMarks();
    return;
  }
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
  clearInputDropMarks();
  const beforeIndex = inputDropBeforeIndex(rows, event.clientY);
  const targetRow = rows.children[beforeIndex] || rows.lastElementChild;
  if (!targetRow) return;
  targetRow.classList.add(beforeIndex >= rows.children.length ? 'drop-after' : 'drop-before');
}

function handleDragLeave(event) {
  const rows = inputDropZone(event.target);
  if (rows && (!rows.contains(event.relatedTarget) || !event.relatedTarget)) clearInputDropMarks();
}

function handleDrop(event) {
  if (!inputDrag || !active || active.kind !== inputDrag.kind || active.uid !== inputDrag.uid) return;
  const rows = inputDropZone(event.target);
  if (!rows || currentButton()?.claudeInputs !== inputDrag.inputs) {
    cancelInputDrag();
    return;
  }
  event.preventDefault();
  const { fromIndex } = inputDrag;
  const beforeIndex = inputDropBeforeIndex(rows, event.clientY);
  cancelInputDrag();
  void moveClaudeInput(fromIndex, beforeIndex);
}

function handleDragEnd() {
  cancelInputDrag();
}

function setUpListeners() {
  root.addEventListener('click', handleClick);
  root.addEventListener('input', handleInput);
  root.addEventListener('mousedown', handleMouseDown);
  root.addEventListener('dragstart', handleDragStart);
  root.addEventListener('dragover', handleDragOver);
  root.addEventListener('dragleave', handleDragLeave);
  root.addEventListener('drop', handleDrop);
  root.addEventListener('dragend', handleDragEnd);
  document.addEventListener('pointerdown', handlePointerDown, true);
  document.addEventListener('keydown', handleKeydown, true);
  window.addEventListener('resize', handleWindowChange);
  window.addEventListener('scroll', handleWindowChange, true);
}

function removeListeners() {
  cancelInputDrag();
  root?.removeEventListener('click', handleClick);
  root?.removeEventListener('input', handleInput);
  root?.removeEventListener('mousedown', handleMouseDown);
  root?.removeEventListener('dragstart', handleDragStart);
  root?.removeEventListener('dragover', handleDragOver);
  root?.removeEventListener('dragleave', handleDragLeave);
  root?.removeEventListener('drop', handleDrop);
  root?.removeEventListener('dragend', handleDragEnd);
  document.removeEventListener('pointerdown', handlePointerDown, true);
  document.removeEventListener('keydown', handleKeydown, true);
  window.removeEventListener('resize', handleWindowChange);
  window.removeEventListener('scroll', handleWindowChange, true);
}

/** @type {OptionsEditor} */
window.optionsEditor = Object.freeze({
  /** @param {HTMLElement} editorRoot @param {OptionsEngine} optionsEngine */
  mount(editorRoot, optionsEngine) {
    if (unsubscribe) unsubscribe();
    removeListeners();
    root = editorRoot;
    engine = optionsEngine;
    active = null;
    snapshot = engine.getSnapshot();
    root.replaceChildren();
    setUpListeners();
    unsubscribe = engine.subscribe(nextSnapshot => acceptSnapshot(nextSnapshot));
  },
  /** @param {OptionsEditorOpenOptions} options */
  open(options) {
    if (!root || !engine || !options || !options.anchor || !options.restoreFocusTo) return;
    const next = engine.getSnapshot();
    if (!Object.hasOwn(next.buttons || {}, options.kind)
      || !next.buttons[options.kind].some(button => button.uid === options.uid)) return;
    window.optionsReplica?.closeDrawer?.();
    snapshot = next;
    active = {
      kind: options.kind,
      uid: options.uid,
      anchor: options.anchor,
      restoreFocusTo: options.restoreFocusTo,
      anchorRect: clientRect(options.anchor),
      anchorScrollX: window.scrollX || 0,
      anchorScrollY: window.scrollY || 0,
    };
    pendingPresetId = null;
    failureMessage = '';
    buildPopover(currentButton());
  },
  close() {
    closePopover();
  },
  isOpen() {
    return active !== null;
  },
});
