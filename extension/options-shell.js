/**
 * @typedef {Object} OptionsShellViewState
 * @property {'blocked'|'saved'|'dirty'|'saving'} saveState
 * @property {boolean} saveDisabled
 * @property {boolean} discardDisabled
 * @property {boolean} showLoadError
 * @property {boolean} retryDisabled
 * @property {boolean} showStaleBanner
 * @property {boolean} showMigration
 * @property {boolean} migrationPanelOpen
 * @property {boolean} showStatus
 */

/** @param {OptionsEngineSnapshot} snapshot @returns {OptionsShellViewState} */
function optionsShellViewState(snapshot) {
  const { load, save } = snapshot;
  const saveState = !load.loaded ? 'blocked'
    : save.saving ? 'saving'
      : save.hasUnsavedWork ? 'dirty' : 'saved';
  return {
    saveState,
    saveDisabled: !save.canSave || save.saving,
    discardDisabled: !load.loaded || !save.hasUnsavedWork || save.saving || Boolean(save.importing),
    showLoadError: !load.loaded && load.status === 'error' && load.retryAvailable,
    retryDisabled: !load.retryAvailable || load.inFlight > 0,
    showStaleBanner: snapshot.sync.staleSinceLoad,
    showMigration: snapshot.migration.pending,
    migrationPanelOpen: snapshot.migration.pending && snapshot.migration.panelOpen,
    showStatus: snapshot.status.type !== 'idle' && Boolean(snapshot.status.message),
  };
}

/** @param {OptionsEngineSnapshot} snapshot @returns {{disabled: boolean, defaultMain: string, showEmptyOverrides: boolean, overrides: Array<{index: number, repo: string, branch: string, validationMessage: {key: string, args: Array<string|number>}|null}>}} */
function optionsShellSettingsViewState(snapshot) {
  const diagnostics = new Map(snapshot.validation.overrides.map(row => [row.index, row.errors]));
  const overrides = snapshot.globalSettings.repoMainBranch.map(row => {
    const errors = diagnostics.get(row.index) || [];
    const validationMessage = errors.includes('duplicate')
      ? { key: 'ext.validate.override.duplicate', args: [row.index + 1, row.repo.trim()] }
      : errors.includes('incomplete')
        ? { key: 'ext.validate.override.incomplete', args: [row.index + 1] }
        : null;
    return { ...row, validationMessage };
  });
  return {
    disabled: !snapshot.load.loaded || snapshot.save.saving || snapshot.save.importing,
    defaultMain: snapshot.globalSettings.defaultMain,
    showEmptyOverrides: overrides.length === 0,
    overrides,
  };
}

function optionsShellElement(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function optionsShellButton(id, className, text) {
  const button = optionsShellElement('button', className, text);
  button.id = id;
  button.type = 'button';
  return button;
}

function optionsShellMessage(value) {
  return value || tr('ext.migration.noTooltip');
}

function optionsShellHtmlElement(tag, className, html) {
  const node = optionsShellElement(tag, className);
  node.innerHTML = html;
  return node;
}

/** @type {{mount: (root: HTMLElement, engine: OptionsEngine) => void}} */
window.optionsShell = Object.freeze({
  /** @param {HTMLElement} root @param {OptionsEngine} engine */
  mount(root, engine) {
    if (!root || !engine) return;

    const shell = optionsShellElement('section', 'options-shell');
    const sticky = optionsShellElement('div', 'options-shell-sticky');
    const saveBar = optionsShellElement('div', 'options-shell-savebar');
    saveBar.setAttribute('role', 'region');
    const regionName = optionsShellElement('span', 'options-shell-sr-only', tr('ext.header.options'));
    regionName.id = 'shell-region-name';
    saveBar.setAttribute('aria-labelledby', 'shell-region-name');
    const saveState = optionsShellElement('span', 'options-shell-save-state');
    saveState.setAttribute('aria-live', 'polite');
    const discard = optionsShellButton('shell-discard', 'btn-secondary', tr('ext.d.shell.discard'));
    const save = optionsShellButton('shell-save', 'btn-primary', tr('ext.button.save'));
    saveBar.append(regionName, saveState, discard, save);

    const confirmation = optionsShellElement('div', 'options-shell-confirm');
    confirmation.hidden = true;
    confirmation.setAttribute('role', 'alertdialog');
    confirmation.setAttribute('aria-modal', 'true');
    const confirmationMessage = optionsShellElement('p', 'options-shell-confirm-message');
    confirmationMessage.id = 'shell-confirm-message';
    confirmation.setAttribute('aria-labelledby', 'shell-confirm-message');
    const keepEditing = optionsShellButton('shell-confirm-cancel', 'btn-secondary', tr('ext.d.shell.keepEditing'));
    const confirmAction = optionsShellButton('shell-confirm-accept', 'btn-primary', '');
    const confirmationActions = optionsShellElement('div', 'options-shell-confirm-actions');
    confirmationActions.append(keepEditing, confirmAction);
    confirmation.append(confirmationMessage, confirmationActions);

    const stale = optionsShellElement('section', 'options-shell-notice options-shell-stale');
    stale.hidden = true;
    stale.setAttribute('aria-labelledby', 'shell-stale-title');
    const staleTitle = optionsShellElement('p', 'options-shell-notice-title', tr('ext.d.shell.stale'));
    staleTitle.id = 'shell-stale-title';
    const staleHelp = optionsShellElement('p', 'options-shell-stale-help', tr('ext.d.shell.staleHelp'));
    const staleActions = optionsShellElement('div', 'options-shell-actions');
    const staleReload = optionsShellButton('shell-stale-reload', 'btn-secondary', tr('ext.d.shell.reload'));
    const staleAccept = optionsShellButton('shell-stale-accept', 'btn-secondary', tr('ext.d.shell.acceptLatest'));
    const staleLater = optionsShellButton('shell-stale-later', 'btn-secondary', tr('ext.d.shell.later'));
    staleActions.append(staleReload, staleAccept, staleLater);
    const staleMessage = optionsShellElement('p', 'options-shell-inline-message');
    staleMessage.hidden = true;
    stale.append(staleTitle, staleHelp, staleActions, staleMessage);

    const migrationBadge = optionsShellButton('shell-migration-badge', 'options-shell-migration-badge', '');
    migrationBadge.hidden = true;
    migrationBadge.setAttribute('aria-expanded', 'false');
    migrationBadge.setAttribute('aria-controls', 'shell-migration-panel');
    const migrationPanel = optionsShellElement('section', 'options-shell-migration');
    migrationPanel.id = 'shell-migration-panel';
    migrationPanel.hidden = true;

    const loadError = optionsShellElement('section', 'options-shell-load-error');
    loadError.hidden = true;
    loadError.setAttribute('role', 'alert');
    const loadErrorMessage = optionsShellElement('p', 'options-shell-notice-title');
    const retry = optionsShellButton('shell-retry', 'btn-secondary', tr('ext.button.retry'));
    loadError.append(loadErrorMessage, retry);

    const status = optionsShellElement('div', 'options-shell-status');
    status.hidden = true;
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');

    sticky.append(saveBar, confirmation, stale, migrationBadge, migrationPanel, loadError, status);

    const mainSettings = optionsShellElement('section', 'section options-shell-panel');
    mainSettings.setAttribute('aria-labelledby', 'shell-main-title');
    const mainTitle = optionsShellHtmlElement('h2', 'section-prompt', tHTML('ext.section.main.title'));
    mainTitle.id = 'shell-main-title';
    const mainHelp = optionsShellHtmlElement('p', 'help', tHTML('ext.section.main.help'));
    mainHelp.id = 'shell-main-help';
    const defaultMainLabel = optionsShellElement('label', '', tr('ext.field.defaultMain'));
    defaultMainLabel.htmlFor = 'shell-default-main';
    const defaultMain = document.createElement('input');
    defaultMain.type = 'text';
    defaultMain.id = 'shell-default-main';
    defaultMain.className = 'options-shell-main-input';
    const overrideTable = optionsShellElement('table', 'override-table options-shell-override-table');
    const overrideHead = document.createElement('thead');
    const overrideHeaderRow = document.createElement('tr');
    const repoHeading = optionsShellElement('th', '', tr('ext.table.repository'));
    repoHeading.scope = 'col';
    const branchHeading = optionsShellElement('th', '', tr('ext.table.mainBranch'));
    branchHeading.scope = 'col';
    const removeHeading = document.createElement('th');
    removeHeading.scope = 'col';
    overrideHeaderRow.append(repoHeading, branchHeading, removeHeading);
    overrideHead.appendChild(overrideHeaderRow);
    const overrideBody = document.createElement('tbody');
    overrideBody.id = 'shell-overrides-body';
    overrideTable.append(overrideHead, overrideBody);
    const overridesEmpty = optionsShellElement('div', 'override-empty', tr('ext.override.empty'));
    overridesEmpty.id = 'shell-overrides-empty';
    const addOverride = optionsShellButton('shell-add-override', 'btn-secondary', tr('ext.button.addOverride'));
    const mainActions = optionsShellElement('div', 'options-shell-settings-actions');
    mainActions.appendChild(addOverride);
    mainSettings.append(mainTitle, mainHelp, defaultMainLabel, defaultMain, overrideTable, overridesEmpty, mainActions);

    const backup = optionsShellElement('section', 'section options-shell-panel');
    backup.setAttribute('aria-labelledby', 'shell-backup-title');
    const backupTitle = optionsShellHtmlElement('h2', 'section-prompt', tHTML('ext.section.backup.title'));
    backupTitle.id = 'shell-backup-title';
    const backupHelp1 = optionsShellHtmlElement('p', 'help', tHTML('ext.section.backup.help1'));
    const backupHelp2 = optionsShellHtmlElement('p', 'help', tHTML('ext.section.backup.help2', tr('ext.button.save')));
    const backupHelp3 = optionsShellHtmlElement('p', 'help', tHTML('ext.section.backup.help3'));
    const backupActions = optionsShellElement('div', 'options-shell-backup-actions');
    const exportButton = optionsShellButton('shell-export', 'btn-secondary', tr('ext.button.export'));
    const importButton = optionsShellButton('shell-import', 'btn-secondary', tr('ext.button.import'));
    const resetButton = optionsShellButton('shell-reset', 'btn-secondary', tr('ext.button.reset'));
    const importFile = document.createElement('input');
    importFile.type = 'file';
    importFile.id = 'shell-import-file';
    importFile.accept = 'application/json,.json';
    importFile.hidden = true;
    backupActions.append(exportButton, importButton, resetButton, importFile);
    backup.append(backupTitle, backupHelp1, backupHelp2, backupHelp3, backupActions);

    shell.append(sticky, mainSettings, backup);
    root.replaceChildren(shell);

    let pendingConfirmation = null;
    let confirmationReturnFocus = null;
    let localStaleMessage = '';
    let migrationSignature = '';
    let migrationFocusUid = null;
    let overrideSignature = null;

    function closeConfirmation(restoreFocus = true) {
      pendingConfirmation = null;
      confirmation.hidden = true;
      if (restoreFocus && confirmationReturnFocus?.isConnected) confirmationReturnFocus.focus();
      confirmationReturnFocus = null;
    }

    function showConfirmation(action) {
      pendingConfirmation = action;
      confirmationReturnFocus = document.activeElement;
      const isAccept = action.type === 'adopt-latest';
      const isReset = action.type === 'reset';
      confirmationMessage.textContent = isAccept
        ? tr('ext.d.shell.acceptConfirm')
        : isReset
          ? tr('ext.d.shell.resetConfirm', tr('ext.button.save'))
          : tr('ext.d.shell.discardConfirm');
      confirmAction.textContent = isAccept
        ? tr('ext.d.shell.acceptLatest')
        : isReset ? tr('ext.button.reset') : tr('ext.d.shell.discard');
      confirmation.hidden = false;
      keepEditing.focus();
    }

    async function runAction(action) {
      const result = await engine.dispatch(action);
      render(result.snapshot || engine.getSnapshot());
      if (!result.ok && result.reason === 'needs-confirmation') showConfirmation(action);
      return result;
    }

    function appendMigrationDiff(target, before, after) {
      const from = optionsShellElement('div', 'options-shell-migration-from', `− ${before}`);
      const to = optionsShellElement('div', 'options-shell-migration-to', `+ ${after}`);
      target.append(from, to);
    }

    function renderMigration(migration, viewState) {
      migrationBadge.hidden = !viewState.showMigration;
      migrationBadge.textContent = tr('ext.migration.badge');
      migrationBadge.setAttribute('aria-expanded', String(viewState.migrationPanelOpen));
      migrationPanel.hidden = !viewState.migrationPanelOpen;

      const signature = JSON.stringify(migration);
      if (signature === migrationSignature) return;
      migrationSignature = signature;
      migrationPanel.replaceChildren();
      if (!viewState.showMigration) return;

      const migrationHeading = optionsShellElement('h2', 'options-shell-panel-title', tr('ext.d.shell.migrationTitle'));
      const reviewOnlyMessage = migration.summary.reviewOnly
        ? (migration.summary.informationalCount
          ? tr('ext.migration.intro.nothingSafe')
          : tr('ext.migration.intro.nothingToDo', tr('ext.migration.gotIt')))
        : '';
      const intro = [migration.summary.descriptions, reviewOnlyMessage].filter(Boolean).join(' ').trim();
      const description = optionsShellElement('p', 'options-shell-migration-intro', intro);
      migrationPanel.append(migrationHeading, description);

      const actionable = optionsShellElement('div', 'options-shell-migration-list');
      for (const item of migration.actionable) {
        const row = optionsShellElement('article', 'options-shell-migration-item');
        const heading = optionsShellElement('div', 'options-shell-migration-heading');
        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.checked = item.selected;
        checkbox.dataset.migrationUid = item.uid;
        const label = optionsShellElement('label', 'options-shell-migration-label');
        label.append(checkbox, optionsShellElement('span', '', optionsShellMessage(item.label)));
        const position = optionsShellElement('span', 'options-shell-migration-position', `#${item.index + 1}`);
        const source = optionsShellElement('span', 'options-shell-migration-source', item.source === 'prefix'
          ? tr('ext.d.shell.sourcePrefix')
          : tr('ext.d.shell.sourceVerbatim'));
        heading.append(checkbox, label, position, source);
        if (item.effect === 'behavior-change') {
          heading.appendChild(optionsShellElement('span', 'options-shell-migration-effect', tr('ext.migration.effect.behaviorChange')));
        }
        row.appendChild(heading);

        const diff = optionsShellElement('div', 'options-shell-migration-diff');
        if (item.from !== item.to) appendMigrationDiff(diff, item.from, item.to);
        if (item.fromInputs) {
          item.fromInputs.forEach((input, index) => {
            if (input !== item.toInputs[index]) appendMigrationDiff(diff, input, item.toInputs[index]);
          });
        }
        if (diff.childNodes.length) row.appendChild(diff);
        if (item.effect === 'behavior-change' && item.describe) {
          row.appendChild(optionsShellElement('p', 'options-shell-migration-why', item.describe));
        }
        actionable.appendChild(row);
      }
      if (actionable.childNodes.length) migrationPanel.appendChild(actionable);

      const informational = optionsShellElement('div', 'options-shell-migration-list');
      for (const item of migration.informational) {
        const row = optionsShellElement('article', 'options-shell-migration-item options-shell-migration-readonly');
        row.appendChild(optionsShellElement('strong', 'options-shell-migration-label', optionsShellMessage(item.label)));
        row.appendChild(optionsShellElement('code', 'options-shell-migration-command', item.command));
        row.appendChild(optionsShellElement('p', 'options-shell-migration-note', item.note));
        informational.appendChild(row);
      }
      if (informational.childNodes.length) migrationPanel.appendChild(informational);

      const actions = optionsShellElement('div', 'options-shell-actions');
      const apply = optionsShellButton('shell-migration-apply', 'btn-primary', tr('ext.migration.apply'));
      apply.disabled = migration.summary.nothingToApply;
      apply.hidden = migration.summary.reviewOnly;
      const keep = optionsShellButton('shell-migration-keep', 'btn-secondary', tr(migration.summary.reviewOnly
        ? 'ext.migration.gotIt'
        : 'ext.migration.keep'));
      actions.append(apply, keep);
      migrationPanel.appendChild(actions);
      const hint = migration.summary.reviewOnly
        ? tr('ext.migration.hint.reviewOnly', tr('ext.button.save'))
        : tr('ext.migration.hint.selected', migration.summary.selectedCount,
          migration.summary.actionableCount, tr('ext.button.save'));
      migrationPanel.appendChild(optionsShellElement('p', 'options-shell-migration-hint', hint));

      if (migrationFocusUid) {
        const focused = [...migrationPanel.querySelectorAll('[data-migration-uid]')]
          .find(input => input.dataset.migrationUid === migrationFocusUid);
        if (focused) focused.focus({ preventScroll: true });
        migrationFocusUid = null;
      }
    }

    function createOverrideRow(row) {
      const trElement = document.createElement('tr');
      trElement.dataset.index = String(row.index);

      const repoCell = document.createElement('td');
      const repoLabel = optionsShellElement('label', 'options-shell-sr-only', `${tr('ext.table.repository')} ${row.index + 1}`);
      repoLabel.htmlFor = `shell-override-${row.index}-repo`;
      const repoInput = document.createElement('input');
      repoInput.type = 'text';
      repoInput.id = repoLabel.htmlFor;
      repoInput.dataset.overrideField = 'repo';
      const error = optionsShellElement('p', 'options-shell-override-error');
      error.hidden = true;
      error.setAttribute('aria-live', 'polite');
      repoCell.append(repoLabel, repoInput, error);

      const branchCell = document.createElement('td');
      const branchLabel = optionsShellElement('label', 'options-shell-sr-only', `${tr('ext.table.mainBranch')} ${row.index + 1}`);
      branchLabel.htmlFor = `shell-override-${row.index}-branch`;
      const branchInput = document.createElement('input');
      branchInput.type = 'text';
      branchInput.id = branchLabel.htmlFor;
      branchInput.dataset.overrideField = 'branch';
      branchCell.append(branchLabel, branchInput);

      const actionsCell = document.createElement('td');
      const remove = optionsShellButton(`shell-override-remove-${row.index}`, 'btn-secondary', tr('ext.button.remove'));
      remove.dataset.overrideRemove = String(row.index);
      actionsCell.appendChild(remove);
      trElement.append(repoCell, branchCell, actionsCell);
      return trElement;
    }

    function renderSettings(snapshot) {
      const settings = optionsShellSettingsViewState(snapshot);
      if (defaultMain.value !== settings.defaultMain) defaultMain.value = settings.defaultMain;
      defaultMain.disabled = settings.disabled;
      addOverride.disabled = settings.disabled;
      exportButton.disabled = settings.disabled;
      importButton.disabled = settings.disabled;
      resetButton.disabled = settings.disabled;
      importFile.disabled = settings.disabled;
      overrideTable.hidden = settings.showEmptyOverrides;
      overridesEmpty.hidden = !settings.showEmptyOverrides;

      const signature = settings.overrides.map(row => row.index).join(',');
      if (signature !== overrideSignature) {
        overrideBody.replaceChildren(...settings.overrides.map(createOverrideRow));
        overrideSignature = signature;
      }
      for (const row of settings.overrides) {
        const rowElement = overrideBody.querySelector(`tr[data-index="${row.index}"]`);
        if (!rowElement) continue;
        const repoInput = rowElement.querySelector('[data-override-field="repo"]');
        const branchInput = rowElement.querySelector('[data-override-field="branch"]');
        if (repoInput.value !== row.repo) repoInput.value = row.repo;
        if (branchInput.value !== row.branch) branchInput.value = row.branch;
        const error = rowElement.querySelector('.options-shell-override-error');
        error.hidden = !row.validationMessage;
        error.textContent = !row.validationMessage ? ''
          : row.validationMessage.key === 'ext.validate.override.duplicate'
            ? tr('ext.validate.override.duplicate', row.validationMessage.args[0], row.validationMessage.args[1])
            : tr('ext.validate.override.incomplete', row.validationMessage.args[0]);
      }
    }

    function render(snapshot) {
      const viewState = optionsShellViewState(snapshot);
      const saveLabels = {
        blocked: tr('ext.d.shell.waiting'),
        saved: tr('ext.d.shell.saved'),
        dirty: tr('ext.status.unsaved'),
        saving: tr('ext.d.shell.saving'),
      };
      saveState.textContent = saveLabels[viewState.saveState];
      saveState.dataset.state = viewState.saveState;
      save.disabled = viewState.saveDisabled;
      discard.disabled = viewState.discardDisabled;

      stale.hidden = !viewState.showStaleBanner;
      staleMessage.hidden = !localStaleMessage || !viewState.showStaleBanner;
      staleMessage.textContent = localStaleMessage;
      loadError.hidden = !viewState.showLoadError;
      loadErrorMessage.textContent = snapshot.load.errorMessage || tr('ext.error.loadFailed');
      retry.disabled = viewState.retryDisabled;
      status.hidden = !viewState.showStatus;
      status.className = `options-shell-status ${snapshot.status.type}`;
      status.textContent = snapshot.status.message;
      renderMigration(snapshot.migration, viewState);
      renderSettings(snapshot);
      if (!viewState.showStaleBanner) localStaleMessage = '';
    }

    save.addEventListener('click', () => { void runAction({ type: 'save' }); });
    discard.addEventListener('click', () => { void runAction({ type: 'discard' }); });
    keepEditing.addEventListener('click', () => closeConfirmation());
    confirmAction.addEventListener('click', async () => {
      if (!pendingConfirmation) return;
      const action = pendingConfirmation.type === 'reset'
        ? pendingConfirmation
        : { ...pendingConfirmation, confirmed: true };
      closeConfirmation(false);
      const result = await runAction(action);
      if (result.ok) save.focus();
      else if (engine.getSnapshot().load.retryAvailable) retry.focus();
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && !confirmation.hidden) {
        event.preventDefault();
        closeConfirmation();
      }
    });
    staleReload.addEventListener('click', async () => {
      const result = await runAction({ type: 'reload-latest' });
      if (!result.ok) {
        localStaleMessage = tr('ext.d.shell.reloadFailed');
        render(result.snapshot);
      }
    });
    staleAccept.addEventListener('click', () => { void runAction({ type: 'adopt-latest' }); });
    staleLater.addEventListener('click', async () => {
      await runAction({ type: 'defer-latest' });
      localStaleMessage = tr('ext.d.shell.deferred');
      render(engine.getSnapshot());
    });
    retry.addEventListener('click', () => { void runAction({ type: 'retry-load' }); });
    migrationBadge.addEventListener('click', () => { void runAction({ type: 'migration-panel-toggle' }); });
    migrationPanel.addEventListener('change', event => {
      const checkbox = event.target.closest('[data-migration-uid]');
      if (!checkbox) return;
      migrationFocusUid = checkbox.dataset.migrationUid;
      void runAction({
        type: 'migration-selection',
        uid: checkbox.dataset.migrationUid,
        selected: checkbox.checked,
      });
    });
    migrationPanel.addEventListener('click', event => {
      const button = event.target.closest('#shell-migration-apply, #shell-migration-keep');
      if (!button) return;
      void runAction({ type: button.id === 'shell-migration-apply' ? 'migration-apply' : 'migration-keep' });
    });
    defaultMain.addEventListener('input', () => {
      void runAction({ type: 'main-patch', value: defaultMain.value });
    });
    overrideBody.addEventListener('input', event => {
      const input = event.target.closest('[data-override-field]');
      const row = input?.closest('tr[data-index]');
      if (!input || !row) return;
      const patch = { [input.dataset.overrideField]: input.value };
      void runAction({ type: 'override-patch', index: Number(row.dataset.index), patch });
    });
    addOverride.addEventListener('click', async () => {
      const result = await runAction({ type: 'override-add' });
      if (!result.ok) return;
      const lastIndex = result.snapshot.globalSettings.repoMainBranch.length - 1;
      overrideBody.querySelector(`#shell-override-${lastIndex}-repo`)?.focus();
    });
    overrideBody.addEventListener('click', async event => {
      const button = event.target.closest('[data-override-remove]');
      if (!button) return;
      const index = Number(button.dataset.overrideRemove);
      const result = await runAction({ type: 'override-remove', index });
      if (!result.ok) return;
      const nextIndex = Math.min(index, result.snapshot.globalSettings.repoMainBranch.length - 1);
      if (nextIndex >= 0) overrideBody.querySelector(`#shell-override-${nextIndex}-repo`)?.focus();
      else addOverride.focus();
    });
    exportButton.addEventListener('click', () => { void runAction({ type: 'export-saved' }); });
    importButton.addEventListener('click', () => importFile.click());
    importFile.addEventListener('change', () => {
      const file = importFile.files?.[0];
      importFile.value = '';
      if (file) void runAction({ type: 'import-file', file });
    });
    resetButton.addEventListener('click', () => showConfirmation({ type: 'reset' }));

    render(engine.getSnapshot());
    engine.subscribe(render);
  },
});
