// A realm for running one generation of the extension, and the record of what was fed to it.
//
// **It stubs platform boundaries and nothing else** (D176). `chrome.*`, the DOM, timers, the
// observer, `history`: those are the browser. Our own symbols are never predefined — if a consumer
// reaches for something its generation of `i18n.js` does not export, that is a `ReferenceError` and
// the point of the exercise. Predefining one would make this double more generous than Chrome, which
// is the class this repository named D89: the matrix passes and the browser does not.
//
// **What was fed is hashed here** (D186). The pin is not "the file on disk is unchanged" — it is
// "the bytes this realm executed are the ones the baseline was pinned at", and those are only the
// same thing while nothing transforms the source on the way in. Nothing does today; the hash is
// taken of the string handed to `vm.runInContext` so that stays true by construction rather than by
// intention.
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const repository = path.join(__dirname, '..');
const CURRENT = path.join(repository, 'extension');
const BASELINE = path.join(__dirname, 'fixtures', 'baseline');

// The files that make up the lookup skeleton, as opposed to the consumers that use it. A mixed
// generation is exactly this split: one side's skeleton under the other side's consumer.
const SKELETON = ['i18n.js', '_i18n/en.js', '_i18n/ko.js', '_i18n/ja.js', '_i18n/zh-Hans.js', '_i18n/zh-Hant.js'];

const sha256 = text => crypto.createHash('sha256').update(text, 'utf8').digest('hex');

// A DOM double. Permissive on purpose — every query answers — because the question here is whether a
// generation *runs*, not whether the page has a given node. That generosity is a platform boundary
// and is recorded as a residual: "an element that is not there" is not something this matrix tests.
const domElement = (id = '') => {
  const element = {
    id,
    dataset: {},
    style: {},
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    children: [],
    value: '',
    checked: false,
    disabled: false,
    textContent: '',
    innerHTML: '',
    title: '',
    hidden: false,
    scrollTop: 0,
    addEventListener() {},
    removeEventListener() {},
    appendChild(child) { element.children.push(child); return child; },
    append(...nodes) { element.children.push(...nodes); },
    add(option) { element.children.push(option); },  // `<select>`'s own way of taking an option
    replaceChildren(...nodes) { element.children = nodes; },
    cloneNode() { return domElement(id); },
    remove() {},
    insertBefore(child) { element.children.push(child); return child; },
    querySelector: () => domElement(),
    querySelectorAll: () => [],
    closest: () => null,
    getBoundingClientRect: () => ({ top: 0, left: 0, width: 0, height: 0 }),
    setAttribute() {},
    getAttribute: () => null,
    removeAttribute() {},
    focus() {},
    click() {},
    contains: () => false,
  };
  return element;
};

const domDocument = () => {
  const document = {
    documentElement: domElement('html'),
    body: domElement('body'),
    head: domElement('head'),
    title: '',
    readyState: 'complete',
    getElementById: id => domElement(id),
    querySelector: () => domElement(),
    querySelectorAll: () => [],
    createElement: tag => domElement(tag),
    createTextNode: text => ({ text }),
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true; },
    location: { href: 'https://github.com/owner/repo/pull/1', hostname: 'github.com', pathname: '/owner/repo/pull/1' },
  };
  return document;
};

// The Chrome surface these three consumers touch, with the seams a test needs to drive left as
// injection points: `nativeResponse`, `storage`, and the listener registries the boundaries fire.
const chromeStub = (options = {}) => {
  const listeners = { message: [], action: [], storageChanged: [], installed: [], startup: [] };
  const calls = { native: [], set: [], notified: [] };
  const local = new Map();
  const sync = new Map();
  const chrome = {
    runtime: {
      id: 'test-extension-id',
      lastError: null,
      getURL: file => `chrome-extension://test/${file}`,
      onMessage: { addListener: fn => listeners.message.push(fn) },
      onInstalled: { addListener: fn => listeners.installed.push(fn) },
      onStartup: { addListener: fn => listeners.startup.push(fn) },
      sendMessage: async () => ({ success: true }),
      sendNativeMessage: async (host, message) => {
        calls.native.push({ host, message });
        if (options.nativeResponse) return options.nativeResponse(message);
        return { success: true };
      },
    },
    storage: {
      local: {
        get: async (keys) => {
          if (options.holdLocalGet) await options.holdLocalGet();
          const wanted = Array.isArray(keys) ? keys : [keys];
          return Object.fromEntries(wanted.filter(key => local.has(key)).map(key => [key, local.get(key)]));
        },
        set: async (entries) => {
          calls.set.push(entries);
          for (const [key, value] of Object.entries(entries)) local.set(key, value);
        },
      },
      sync: {
        get: async (keys) => {
          const wanted = Array.isArray(keys) ? keys : [keys];
          return Object.fromEntries(wanted.filter(key => sync.has(key)).map(key => [key, sync.get(key)]));
        },
        set: async () => {},
      },
      onChanged: { addListener: fn => listeners.storageChanged.push(fn) },
    },
    tabs: {
      query: async () => [{ id: 1, url: 'https://github.com/owner/repo' }],
      sendMessage: async (id, message) => { calls.notified.push({ id, message }); },
    },
    scripting: { executeScript: async () => [{ result: null }] },
    action: { onClicked: { addListener: fn => listeners.action.push(fn) } },
    i18n: {
      getUILanguage: () => options.uiLanguage || 'en',
      getMessage: (id, subs) => (options.getMessage ? options.getMessage(id, subs) : id),
    },
  };
  return { chrome, listeners, calls, local, sync };
};

// One generation, loaded. `skeleton` and `consumers` name directories independently, which is what
// makes a mixed generation expressible at all.
const generationRealm = ({ skeleton = 'current', consumers = 'current', platform = {} } = {}) => {
  const directoryFor = side => (side === 'baseline' ? BASELINE : CURRENT);
  const resolve = (name) => {
    const side = SKELETON.includes(name) ? skeleton : consumers;
    return path.join(directoryFor(side), name);
  };
  const { chrome, listeners, calls, local, sync } = chromeStub(platform);
  const fed = {};
  const context = vm.createContext({});
  const feed = (name) => {
    const file = resolve(name);
    const source = fs.readFileSync(file, 'utf8');
    // The hash is of this string — the one about to be executed — and not of a re-read of the file.
    fed[path.relative(repository, file)] = sha256(source);
    vm.runInContext(source, context, { filename: file });
  };
  Object.assign(context, {
    chrome,
    console: { log() {}, warn() {}, error() {} },
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: handle => clearTimeout(handle),
    setInterval: () => 0,
    clearInterval: () => {},
    queueMicrotask,
    MutationObserver: class { observe() {} disconnect() {} },
    importScripts: (...names) => names.forEach(feed),
    fetch: async () => ({ ok: true, json: async () => ({}) }),
    // The page's own event surface, and the two element constructors this page builds by hand.
    addEventListener() {},
    removeEventListener() {},
    Option: class { constructor(text, value) { this.text = text; this.value = value; } },
    Image: class {},
  });
  const document = domDocument();
  Object.assign(context, {
    document,
    location: document.location,
    history: { pushState() {}, replaceState() {} },
    window: context,
    self: context,
    navigator: { language: platform.uiLanguage || 'en' },
    alert() {},
    confirm: () => true,
  });
  return {
    context,
    chrome,
    listeners,
    calls,
    local,
    sync,
    fed,
    feed,
    run: expression => vm.runInContext(expression, context),
  };
};

module.exports = { generationRealm, SKELETON, sha256, BASELINE, CURRENT };
