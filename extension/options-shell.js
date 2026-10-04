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

/** @type {{mount: (root: HTMLElement, engine: OptionsEngine) => void}} */
window.optionsShell = Object.freeze({
  /** @param {HTMLElement} root @param {OptionsEngine} engine */
  mount(root, engine) {
    if (!root || !engine) return;

    const shell = optionsShellElement('section', 'options-shell');
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
    const staleActions = optionsShellElement('div', 'options-shell-actions');
    const staleReload = optionsShellButton('shell-stale-reload', 'btn-secondary', tr('ext.d.shell.reload'));
    const staleAccept = optionsShellButton('shell-stale-accept', 'btn-secondary', tr('ext.d.shell.acceptLatest'));
    const staleLater = optionsShellButton('shell-stale-later', 'btn-secondary', tr('ext.d.shell.later'));
    staleActions.append(staleReload, staleAccept, staleLater);
    const staleMessage = optionsShellElement('p', 'options-shell-inline-message');
    staleMessage.hidden = true;
    stale.append(staleTitle, staleActions, staleMessage);

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

    shell.append(saveBar, confirmation, stale, migrationBadge, migrationPanel, loadError, status);
    root.replaceChildren(shell);

    let pendingConfirmation = null;
    let confirmationReturnFocus = null;
    let localStaleMessage = '';
    let migrationSignature = '';
    let migrationFocusUid = null;

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
      confirmationMessage.textContent = isAccept
        ? tr('ext.d.shell.acceptConfirm')
        : tr('ext.d.shell.discardConfirm');
      confirmAction.textContent = isAccept
        ? tr('ext.d.shell.acceptLatest')
        : tr('ext.d.shell.discard');
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

    function render(snapshot) {
      const viewState = optionsShellViewState(snapshot);
      const saveLabels = {
        blocked: tr('ext.d.shell.waiting'),
        saved: tr('ext.status.saved'),
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
      if (!viewState.showStaleBanner) localStaleMessage = '';
    }

    save.addEventListener('click', () => { void runAction({ type: 'save' }); });
    discard.addEventListener('click', () => { void runAction({ type: 'discard' }); });
    keepEditing.addEventListener('click', () => closeConfirmation());
    confirmAction.addEventListener('click', async () => {
      if (!pendingConfirmation) return;
      const action = { ...pendingConfirmation, confirmed: true };
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

    render(engine.getSnapshot());
    engine.subscribe(render);
  },
});
