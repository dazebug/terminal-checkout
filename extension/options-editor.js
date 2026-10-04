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
  face: 'ext.validate.face',
  label: 'ext.validate.tooltip',
  command: 'ext.validate.command',
});

const WARNING_MESSAGE = new Map([
  ['claude-inputs-without-claude-command', 'ext.field.claudeInputs.warn'],
]);

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
function validationFor(snapshot, kind, button) {
  const diagnostic = snapshot?.validation?.buttons?.find(entry => entry.kind === kind && entry.uid === button?.uid);
  if (!diagnostic) return [];
  const list = snapshot?.buttons?.[kind] || [];
  const index = list.findIndex(entry => entry.uid === button.uid);
  const position = Math.max(1, index + 1);
  const storageKey = BUTTON_KINDS[kind]?.storageKey || '';
  const messages = [];
  for (const field of diagnostic.errors || []) {
    const key = REQUIRED_FIELD_MESSAGE[field];
    if (key) messages.push(tr(key, storageKey, position));
  }
  for (const warning of diagnostic.warnings || []) {
    const key = WARNING_MESSAGE.get(warning);
    if (key) messages.push(tr(key));
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
  const width = Math.min(Math.max(0, Number(popover?.width) || 0), Math.max(0, viewportWidth - safeMargin * 2));
  const viewportMaxHeight = Math.max(0, viewportHeight - safeMargin * 2);
  const maxLeft = Math.max(safeMargin, viewportWidth - safeMargin - width);
  const left = Math.min(maxLeft, Math.max(safeMargin, Number(anchor?.left) || 0));
  const belowSpace = Math.max(0, viewportHeight - safeMargin - (Number(anchor?.bottom) || 0) - safeGap);
  const aboveSpace = Math.max(0, (Number(anchor?.top) || 0) - safeMargin - safeGap);
  const naturalHeight = Math.max(0, Number(popover?.height) || 0);
  const narrow = viewportWidth <= 640;
  const shouldFlip = !narrow && naturalHeight > belowSpace && aboveSpace > belowSpace;
  const placement = shouldFlip ? 'top' : 'bottom';
  const maxHeight = Math.min(viewportMaxHeight, placement === 'top' ? aboveSpace : belowSpace);
  const height = Math.min(naturalHeight, maxHeight);
  const proposedTop = placement === 'top'
    ? (Number(anchor?.top) || 0) - safeGap - height
    : (Number(anchor?.bottom) || 0) + safeGap;
  const top = Math.min(Math.max(safeMargin, viewportHeight - safeMargin - height), Math.max(safeMargin, proposedTop));
  const anchorCenter = ((Number(anchor?.left) || 0) + (Number(anchor?.right) || 0)) / 2;
  const arrowX = Math.max(Math.min(16, width / 2), Math.min(width - Math.min(16, width / 2), anchorCenter - left));
  return { top, left, width, height, maxHeight, arrowX, placement };
}

let root = null;
let engine = null;
let snapshot = null;
let unsubscribe = null;
let active = null;
let pendingPresetId = null;
let failureMessage = '';
let instanceCounter = 0;

function editorMessage(name, ...args) {
  switch (name) {
    case 'title': return tr('ext.d.editor.title');
    case 'close': return tr('ext.d.editor.close');
    case 'commandPlaceholder': return tr('ext.d.editor.commandPlaceholder');
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

function addAccessibleLabel(element, message, ...args) {
  const label = makeElement('span', 'options-editor-sr-only', tr(message, ...args));
  label.id = `options-editor-label-${++instanceCounter}`;
  element.setAttribute('aria-labelledby', label.id);
  element.appendChild(label);
  return label;
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
  active = null;
  pendingPresetId = null;
  failureMessage = '';
  root?.replaceChildren();
  if (!restoreFocus) return;
  if (restoreFocusTo?.isConnected) focusElement(restoreFocusTo);
  else focusFallback(kind, uid);
}

function positionPopover() {
  const panel = currentPanel();
  if (!panel || !active?.anchor) return;
  let popoverRect = panel.getBoundingClientRect();
  const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 1280;
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 800;
  if (!popoverRect.width || !popoverRect.height) {
    const fallbackWidth = Math.min(440, Math.max(0, viewportWidth - 24));
    const fallbackHeight = Math.min(panel.scrollHeight || 560, Math.max(0, viewportHeight - 24));
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
  const content = panel.querySelector('.options-editor-content');
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
  const messages = validationFor(snapshot, active.kind, button);
  list.hidden = messages.length === 0;
  for (const text of messages) list.appendChild(makeElement('p', 'options-editor-diagnostic', text));
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

function createField({ name, labelKey, value, type = 'input', maxLength = null }) {
  const field = makeElement('div', `options-editor-field field-${name}`);
  const id = `options-editor-${++instanceCounter}-${name}`;
  const label = makeElement('label', '', tr(labelKey));
  label.htmlFor = id;
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
  field.append(label, control);
  return { field, control };
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
  addAccessibleLabel(close, 'ext.d.editor.close');
  header.append(identity, close);

  const fields = makeElement('div', 'options-editor-fields');
  const face = createField({ name: 'face', labelKey: 'ext.field.face', value: button.face, maxLength: 24 });
  const label = createField({ name: 'label', labelKey: 'ext.field.tooltip', value: button.label });
  fields.append(face.field, label.field);

  const palette = makeElement('div', 'options-editor-palette');
  const paletteLabel = makeElement('span', 'options-editor-palette-label', tr('ext.card.palette.label'));
  palette.appendChild(paletteLabel);
  for (const emoji of facePalette()) {
    const emojiButton = makeButton(emoji, 'options-editor-emoji', 'append-emoji');
    addAccessibleLabel(emojiButton, 'ext.card.palette.tooltip', emoji);
    emojiButton.dataset.emoji = emoji;
    palette.appendChild(emojiButton);
  }

  const commandSection = makeElement('section', 'options-editor-command-section');
  const commandField = createField({
    name: 'command', labelKey: 'ext.field.command', value: button.command, type: 'textarea',
  });
  const prompt = makeElement('span', 'options-editor-command-prompt', '$');
  const commandBox = makeElement('div', 'options-editor-command-box');
  commandBox.append(prompt, commandField.control);
  commandField.field.appendChild(commandBox);
  commandField.field.appendChild(makeElement(
    'span', 'options-editor-command-example', editorMessage('commandPlaceholder'),
  ));
  const variablesHelp = makeElement('div', 'options-editor-variable-help');
  // These five existing catalogue entries are trusted extension markup; no setting value is used here.
  variablesHelp.innerHTML = SECTION_VARIABLE_HELP[kind]();
  const variableList = makeElement('div', 'options-editor-variables');
  for (const name of variablesForKind(kind)) {
    const token = makeButton(`{${name}}`, 'options-editor-variable', 'insert-variable');
    token.dataset.variable = name;
    addAccessibleLabel(token, 'ext.d.editor.variableInsert', `{${name}}`);
    variableList.appendChild(token);
  }
  commandSection.append(commandField.field, variablesHelp, variableList);

  const validation = makeElement('div', 'options-editor-validation');
  validation.setAttribute('aria-live', 'polite');
  validation.setAttribute('aria-atomic', 'true');
  const futureSlot = makeElement('div', 'options-editor-followup-slot');
  futureSlot.dataset.editorSlot = 'claude-inputs';

  const actions = makeElement('div', 'options-editor-actions');
  const earlier = makeButton('↑', 'btn-secondary options-editor-order', 'move-earlier');
  addAccessibleLabel(earlier, 'ext.d.editor.moveEarlier');
  const later = makeButton('↓', 'btn-secondary options-editor-order', 'move-later');
  addAccessibleLabel(later, 'ext.d.editor.moveLater');
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
  inner.append(header, fields, palette, commandSection, validation, futureSlot, actions, presetChoices, confirmation, status);
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
    closePopover();
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
      const value = appendFaceCharacter(face.value, target.dataset.emoji, 24);
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
  const field = event.target.dataset.editorField;
  if (!field) return;
  if (field === 'face' && !fitsFieldLimit(event.target.value, 24)) {
    let clipped = event.target.value.slice(0, 24);
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
  if (!active || event.key !== 'Escape') return;
  event.preventDefault();
  event.stopPropagation();
  closePopover();
}

function handlePointerDown(event) {
  if (!active || root?.contains(event.target)) return;
  closePopover();
}

function handleWindowChange() {
  positionPopover();
}

function handleMouseDown(event) {
  if (event.target instanceof Element
    && event.target.closest('[data-editor-action="insert-variable"], [data-editor-action="append-emoji"]')) {
    event.preventDefault();
  }
}

function setUpListeners() {
  root.addEventListener('click', handleClick);
  root.addEventListener('input', handleInput);
  root.addEventListener('mousedown', handleMouseDown);
  document.addEventListener('pointerdown', handlePointerDown, true);
  document.addEventListener('keydown', handleKeydown, true);
  window.addEventListener('resize', handleWindowChange);
  window.addEventListener('scroll', handleWindowChange, true);
}

function removeListeners() {
  root?.removeEventListener('click', handleClick);
  root?.removeEventListener('input', handleInput);
  root?.removeEventListener('mousedown', handleMouseDown);
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
