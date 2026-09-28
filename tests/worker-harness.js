// The real extension/background.js, run in a realm of its own with one stand-in for the chrome API,
// so a test can hand its listeners a message or an icon click and watch what reaches the native host.
//
// **The stand-in follows the calls the worker makes, and only those.** Its answers have the shapes
// those calls rely on: `storage.sync.get` resolves to an object holding only the keys that exist,
// and hands out fresh copies each time as Chrome does; `scripting.executeScript` resolves to an array
// whose first entry carries `result`; `runtime.sendNativeMessage` resolves to the host's reply; a
// runtime message arrives JSON-cloned, which is also why a key whose value is `undefined` does not
// arrive at all; and `onMessage` keeps the channel open only when its listener returns `true`. A
// stand-in that answered in another shape would let a defect pass together with the test.
//
// **The page readers are answered, not run.** executeScript is told which reader it was given by the
// function's name and answers from a page model — a fixture of GitHub's HTML would be the frozen store
// `docs/context/testing.md` warns about, and whether those readers find the right elements is settled
// in a browser. What this measures is the worker's own flow around them: which checks run, in what
// order, and what, if anything, is sent.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { catalogueBackend } = require('./chrome-messages.js');

const EXTENSION = path.join(__dirname, '..', 'extension');
const GITHUB = 'https://github.com';

// One page per kind the extension draws on. `branch`/`base` are what a PR header shows, `defaultBranch`
// what GitHub embeds in the page, and `selected` what a list page's checkboxes hold when the worker
// reads them again.
const PAGES = {
  pr: { href: `${GITHUB}/o/r/pull/7`, branch: 'feat/x', base: 'main', defaultBranch: 'main', selected: [] },
  issue: { href: `${GITHUB}/o/r/issues/3`, branch: null, base: null, defaultBranch: 'main', selected: [] },
  repo: { href: `${GITHUB}/o/r`, branch: null, base: null, defaultBranch: 'main', selected: [] },
  'pr-list': {
    href: `${GITHUB}/o/r/pulls`, branch: null, base: null, defaultBranch: 'main',
    selected: [{ key: 'o/r/pr/7', title: 'Seven' }, { key: 'o/r/pr/8', title: 'Eight' }],
  },
  'issue-list': {
    href: `${GITHUB}/o/r/issues`, branch: null, base: null, defaultBranch: 'main',
    selected: [{ key: 'o/r/issue/3', title: 'Three' }, { key: 'o/r/issue/4', title: 'Four' }],
  },
};

function loadWorker({ extensionDir = EXTENSION, store = {}, page = PAGES.pr } = {}) {
  const state = structuredClone(page);
  const calls = { storage: [], scripting: [], native: [] };
  const handedOut = []; // every object storage handed the worker, with its JSON at the moment it did
  const beforeRead = new Map(); // reader name -> hook run just before that reader is answered
  const listeners = { message: null, clicked: null };
  const logs = [];

  const readers = {
    getBranchAndMainFromDOM: () => (/\/pull\/\d+/.test(state.href) && state.branch
      ? { branch: state.branch, detectedMain: state.base, href: state.href }
      : null),
    getDefaultBranchFromPage: () => ({ branch: state.defaultBranch, href: state.href }),
    readCurrentHref: () => state.href,
    readListSelectionFromPage: () => ({ href: state.href, selected: structuredClone(state.selected) }),
    isRepoPageFromDOM: () => true,
  };

  const chrome = {
    runtime: {
      onMessage: { addListener: fn => { listeners.message = fn; } },
      sendNativeMessage: async (host, message) => {
        calls.native.push({ host, message: JSON.stringify(message) });
        return Array.isArray(message.items)
          ? { success: true, items: message.items.map(() => ({ success: true })) }
          : { success: true };
      },
    },
    action: { onClicked: { addListener: fn => { listeners.clicked = fn; } } },
    storage: {
      sync: {
        get: async (keys) => {
          calls.storage.push([...keys]);
          const answer = {};
          for (const key of keys) {
            if (!Object.hasOwn(store, key)) continue;
            answer[key] = structuredClone(store[key]);
            handedOut.push({ object: answer[key], json: JSON.stringify(answer[key]) });
          }
          return answer;
        },
      },
    },
    scripting: {
      executeScript: async ({ func }) => {
        calls.scripting.push(func.name);
        beforeRead.get(func.name)?.();
        if (!Object.hasOwn(readers, func.name)) throw new Error(`no page reader named ${func.name}`);
        return [{ result: readers[func.name](), frameId: 0 }];
      },
    },
    i18n: { getMessage: catalogueBackend('en') },
  };

  const quiet = { log: (...a) => logs.push(a), warn: (...a) => logs.push(a), error: (...a) => logs.push(a), info: (...a) => logs.push(a) };
  const context = vm.createContext({ chrome, console: quiet, URL, TextEncoder });
  context.importScripts = (...names) => {
    for (const name of names) vm.runInContext(fs.readFileSync(path.join(extensionDir, name), 'utf8'), context, { filename: name });
  };
  vm.runInContext(fs.readFileSync(path.join(extensionDir, 'background.js'), 'utf8'), context, { filename: 'background.js' });

  return {
    calls,
    logs,
    // A binding of the worker's realm, `const`s included
    get: name => vm.runInContext(name, context),
    navigate: (href) => { state.href = href; },
    beforeRead: (reader, hook) => { beforeRead.set(reader, hook); },
    // What the native host received, parsed back into this realm
    native: () => calls.native.map(call => JSON.parse(call.message)),
    // True when nothing storage handed out was changed afterwards
    storageUntouched: () => handedOut.every(({ object, json }) => JSON.stringify(object) === json),
    // A runtime message from a content script on `tab`. Resolves with the response — JSON-cloned on the
    // way back as well — or `undefined` when the listener declined it without answering, which is what
    // the sender sees in that case.
    dispatch: (message, tab = { id: 1, url: state.href }) => new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('the worker never answered')), 5000);
      let answered = false;
      const keepOpen = listeners.message(JSON.parse(JSON.stringify(message)), { tab }, (response) => {
        answered = true;
        clearTimeout(timer);
        resolve(response === undefined ? undefined : JSON.parse(JSON.stringify(response)));
      });
      if (keepOpen !== true && !answered) {
        clearTimeout(timer);
        resolve(undefined);
      }
    }),
    clickIcon: (tab = { id: 1, url: state.href }) => listeners.clicked(tab),
  };
}

module.exports = { loadWorker, PAGES, EXTENSION };
