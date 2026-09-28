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
// **It also holds the worker to its side of every call**, because answering whatever was asked lets a
// defect through the same way: a worker changed to read another tab, or to name another native host,
// passed every test while the stand-in looked only at which reader it was handed. Each call is
// checked against what the worker owes it — the tab the click came from, the arguments each page
// reader has to be handed, the one host the app registers, keys the settings live under, message ids
// the catalogue carries, one listener per event — and the expected values come from the click and
// from defaults.js loaded on its own, never from the call being checked. A call that misses is a
// breach and is recorded — an asynchronous one also fails without an answer, the way the worker's own
// code sees a failed call — and the click or icon press it happened in then fails whatever the worker
// made of it, which matters where the worker is allowed to shrug a failed read off.
//
// **The page readers are answered, not run.** executeScript is told which reader it was given by the
// function's name and answers from a page model — a fixture of GitHub's HTML would be the frozen store
// `docs/context/testing.md` warns about, and whether those readers find the right elements is settled
// in a browser. What this measures is the worker's own flow around them: which checks run, in what
// order, with what, and what, if anything, is sent.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const util = require('node:util');
const vm = require('node:vm');
const { catalogueBackend } = require('./chrome-messages.js');

const EXTENSION = path.join(__dirname, '..', 'extension');
const GITHUB = 'https://github.com';

// The one native host the stand-in answers: the name the app's installer registers
// (`nativeHostName`, app/Sources/Core/NativeHostManifest.swift)
const NATIVE_HOST = 'com.dazebug.terminal_checkout';

// The id of the tab a click comes from, unless a test gives another. Any integer would do; this one is
// neither 0 nor 1, so a worker that wrote an id in rather than reading the click's does not pass by luck.
const TAB_ID = 314;

// The catalogue getMessage answers from, read here as well to tell an id it carries from one it does not
const CATALOGUE = JSON.parse(fs.readFileSync(path.join(EXTENSION, '_locales', 'en', 'messages.json'), 'utf8'));

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

// defaults.js in a realm of its own, for the values a call has to carry: the keys the settings live
// under, the PR header's branch-link selector, the repository crumb, and how a URL names a page. Kept
// apart from the worker's realm so nothing the worker does can move them; one per extension folder.
const canons = new Map();
function canonOf(extensionDir) {
  if (!canons.has(extensionDir)) {
    const context = vm.createContext({ URL, TextEncoder });
    for (const name of ['i18n.js', 'defaults.js']) {
      vm.runInContext(fs.readFileSync(path.join(extensionDir, name), 'utf8'), context, { filename: name });
    }
    canons.set(extensionDir, vm.runInContext(
      '({ SETTINGS_KEYS, PR_BRANCH_LINK_SELECTOR, repoCrumbSelectors, pageTargetOfUrl })', context,
    ));
  }
  return canons.get(extensionDir);
}

// What each page reader has to be handed for the page the click came from — `undefined` for nothing
const LIST_ROW_KIND = { 'pr-list': 'pr', 'issue-list': 'issue' };
const READER_ARGS = {
  getBranchAndMainFromDOM: canon => [canon.PR_BRANCH_LINK_SELECTOR],
  getDefaultBranchFromPage: (canon, page) => [page.owner, page.repo],
  readCurrentHref: () => undefined,
  readListSelectionFromPage: (canon, page) => [{ kind: LIST_ROW_KIND[page.kind], owner: page.owner, repo: page.repo }],
  isRepoPageFromDOM: (canon, page) => [canon.repoCrumbSelectors(page.owner, page.repo)],
};

// Structural equality across realms: both sides are cloned into this one first. A value that cannot be
// cloned — a function among the arguments — equals nothing.
function sameValue(a, b) {
  try {
    return util.isDeepStrictEqual(structuredClone(a), structuredClone(b));
  } catch {
    return false;
  }
}

// The host's answer when a test gives none: every command ran
function everythingRan(message) {
  return Array.isArray(message.items)
    ? { success: true, items: message.items.map(() => ({ success: true })) }
    : { success: true };
}

function loadWorker({ extensionDir = EXTENSION, store = {}, page = PAGES.pr, reply = everythingRan } = {}) {
  const canon = canonOf(extensionDir);
  const state = structuredClone(page);
  const calls = { storage: [], scripting: [], native: [], i18n: [] };
  const handedOut = []; // every object storage handed the worker, with its JSON at the moment it did
  const afterAnswer = new Map(); // a read — reader name or storage key — -> hook run once, right after it is answered
  const listeners = { 'runtime.onMessage': null, 'action.onClicked': null };
  const breaches = [];
  const logs = [];
  const messages = catalogueBackend('en');
  let inFlight = null; // the tab of the click being served
  let context = null;

  const breach = (reason) => {
    breaches.push(reason);
    return new Error(`chrome stand-in: ${reason}`);
  };
  const answered = (read) => {
    const hook = afterAnswer.get(read);
    afterAnswer.delete(read);
    hook?.();
  };
  const listen = (event, fn) => {
    if (listeners[event]) throw breach(`a second ${event} listener`);
    listeners[event] = fn;
  };

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
      onMessage: { addListener: fn => listen('runtime.onMessage', fn) },
      sendNativeMessage: async (host, message) => {
        calls.native.push({ host, message: JSON.stringify(message) });
        if (!inFlight) throw breach('sendNativeMessage with no click in flight');
        if (host !== NATIVE_HOST) throw breach(`sendNativeMessage names ${JSON.stringify(host)}, not ${NATIVE_HOST}`);
        // The host reads JSON and answers JSON
        return JSON.parse(JSON.stringify(reply(JSON.parse(JSON.stringify(message)))));
      },
    },
    action: { onClicked: { addListener: fn => listen('action.onClicked', fn) } },
    storage: {
      sync: {
        get: async (keys) => {
          calls.storage.push(Array.isArray(keys) ? [...keys] : keys);
          if (!Array.isArray(keys) || !keys.every(key => canon.SETTINGS_KEYS.includes(key))) {
            throw breach(`storage.sync.get(${JSON.stringify(keys)}) asks for a key the settings do not live under`);
          }
          const answer = {};
          for (const key of keys) {
            if (!Object.hasOwn(store, key)) continue;
            answer[key] = structuredClone(store[key]);
            handedOut.push({ object: answer[key], json: JSON.stringify(answer[key]) });
          }
          for (const key of keys) answered(key);
          return answer;
        },
      },
    },
    scripting: {
      executeScript: async (details) => {
        const name = typeof details?.func === 'function' ? details.func.name : '(no function)';
        calls.scripting.push(name);
        const miss = (reason) => { throw breach(`executeScript ${name}: ${reason}`); };
        if (!Object.hasOwn(READER_ARGS, name) || details.func !== vm.runInContext(name, context)) {
          miss('not one of the worker\'s page readers');
        }
        if (!inFlight) miss('no click in flight');
        const clicked = canon.pageTargetOfUrl(inFlight.url);
        if (!clicked) miss(`the click's tab (${inFlight.url}) is not a GitHub page`);
        const args = READER_ARGS[name](canon, clicked);
        const keys = args === undefined ? ['func', 'target'] : ['args', 'func', 'target'];
        const given = Object.keys(details).sort();
        if (!sameValue(given, keys)) miss(`carries ${given.join(', ')} rather than ${keys.join(', ')}`);
        if (!sameValue(details.target, { tabId: inFlight.id })) {
          miss(`targets ${JSON.stringify(details.target)}, not the tab the click came from (${inFlight.id})`);
        }
        if (args !== undefined && !sameValue(details.args, args)) {
          miss(`is handed ${JSON.stringify(details.args)} rather than ${JSON.stringify(args)}`);
        }
        const result = readers[name]();
        answered(name);
        return [{ result, frameId: 0 }];
      },
    },
    i18n: {
      getMessage: (id, substitutions) => {
        calls.i18n.push(id);
        if (!Object.hasOwn(CATALOGUE, id)) breach(`i18n.getMessage asks for ${JSON.stringify(id)}, which the catalogue does not carry`);
        return messages(id, substitutions);
      },
    },
  };

  const quiet = { log: (...a) => logs.push(a), warn: (...a) => logs.push(a), error: (...a) => logs.push(a), info: (...a) => logs.push(a) };
  context = vm.createContext({ chrome, console: quiet, URL, TextEncoder });
  context.importScripts = (...names) => {
    for (const name of names) vm.runInContext(fs.readFileSync(path.join(extensionDir, name), 'utf8'), context, { filename: name });
  };
  vm.runInContext(fs.readFileSync(path.join(extensionDir, 'background.js'), 'utf8'), context, { filename: 'background.js' });
  for (const [event, fn] of Object.entries(listeners)) {
    if (!fn) throw new Error(`the worker registered no ${event} listener`);
  }

  // One click or icon press, served with `tab` as the tab it came from. A breach recorded on the way
  // fails it — checked once the work the worker left pending has run, so a late second answer counts.
  const asClick = async (tab, run) => {
    if (inFlight) throw new Error('one click at a time: calls are checked against the tab of the click in flight');
    inFlight = tab;
    try {
      const outcome = await run();
      await new Promise(resolve => setImmediate(resolve));
      if (breaches.length) throw new Error(`the worker broke its side of the chrome calls:\n  ${breaches.join('\n  ')}`);
      return outcome;
    } finally {
      inFlight = null;
    }
  };
  const tabOf = changes => ({ id: TAB_ID, url: state.href, ...changes });

  return {
    calls,
    logs,
    breaches: () => [...breaches],
    // A binding of the worker's realm, `const`s included
    get: name => vm.runInContext(name, context),
    navigate: (href) => { state.href = href; },
    // Runs `hook` once, right after the stand-in answers `read` — a page reader, by its function name, or
    // a storage key — and before the worker resumes: the page changing on its own between two reads
    afterAnswer: (read, hook) => { afterAnswer.set(read, hook); },
    // What the native host received: the host named, and the message parsed back into this realm
    native: () => calls.native.map(call => ({ host: call.host, message: JSON.parse(call.message) })),
    // True when nothing storage handed out was changed afterwards
    storageUntouched: () => handedOut.every(({ object, json }) => JSON.stringify(object) === json),
    // A runtime message from a content script on the modeled tab, whose fields `tabChanges` may replace.
    // Resolves with the response — JSON-cloned on the way back as well — or `undefined` when the
    // listener declined it without answering, which is what the sender sees in that case.
    dispatch: (message, tabChanges = {}) => {
      const tab = tabOf(tabChanges);
      return asClick(tab, () => new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('the worker never answered')), 5000);
        let responded = false;
        const keepOpen = listeners['runtime.onMessage'](JSON.parse(JSON.stringify(message)), { tab }, (response) => {
          if (responded) {
            breach('sendResponse called a second time');
            return;
          }
          responded = true;
          clearTimeout(timer);
          resolve(response === undefined ? undefined : JSON.parse(JSON.stringify(response)));
        });
        if (keepOpen !== true && !responded) {
          clearTimeout(timer);
          resolve(undefined);
        }
      }));
    },
    clickIcon: (tabChanges = {}) => {
      const tab = tabOf(tabChanges);
      return asClick(tab, () => listeners['action.onClicked'](tab));
    },
  };
}

module.exports = { loadWorker, PAGES, EXTENSION, NATIVE_HOST };
