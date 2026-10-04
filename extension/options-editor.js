/** @typedef {{kind: OptionsButtonKind, uid: string, restoreFocusTo: HTMLElement}} OptionsEditorOpenOptions */

/** @type {{mount: (root: HTMLElement, engine: OptionsEngine) => void, open: (options: OptionsEditorOpenOptions) => void}} */
window.optionsEditor = Object.freeze({
  /** @param {HTMLElement} root @param {OptionsEngine} engine */
  mount(root, engine) {},
  /** @param {OptionsEditorOpenOptions} options */
  open(options) {},
});
