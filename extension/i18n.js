// The extension's own dictionary machinery. Loaded first, in the content script, the service worker
// and the options page alike.
//
// **Why not `chrome.i18n` for these strings** (D4/D9): `chrome.i18n` resolves against Chrome's UI
// language and has no runtime switch, so a user on Japanese macOS with English Chrome would read
// the app in one language and the buttons in another, with nowhere to fix it. The app owns the
// language and hands it down (D8), which means the lookup has to accept a locale rather than
// discover one. `chrome.i18n` keeps exactly two keys — `extName` and `extDescription` in
// `_locales/` — because a manifest's `name` and `description` cannot be filled any other way.
//
// **Nothing here touches `chrome` at load time, and nothing looks anything up at load time.** Both
// rules come from the same measurement (D6): the three test files run these scripts through
// `vm.runInThisContext` with no `chrome` global at all, and a single `chrome.*` at module scope
// takes all 158 of them down. Lookup happens when a caller asks, which is also what lets a language
// change redraw without reloading anything.

// The tags the extension ships a dictionary for. The same spelling the app uses, on purpose: the
// locale arrives from the app as `zh-Hans`, and a second naming convention here would mean a
// mapping table that can drift. (Chrome's own `_locales/` directories use `zh_CN`/`zh_TW`; that is
// Chrome's namespace, and it holds two keys we never read from JavaScript.)
const TC_I18N_LOCALES = ['en', 'ko', 'ja', 'zh-Hans', 'zh-Hant'];

// Where every question we cannot answer lands — the same choice the app makes for the same reason:
// folding an unshipped language to English is a decision, not a property of the dictionaries.
const TC_I18N_FALLBACK = 'en';

// The registry the `_i18n/<tag>.js` files write into. Declared here so there is one place that says
// what shape it has; the dictionaries create it themselves if they load first, because the file
// order in `manifest.json` is a fact about the manifest rather than about this contract.
globalThis.TC_I18N = globalThis.TC_I18N || {};

// One message, in one language.
//
// The chain is the app's: the asked-for locale, then English, then the key itself. The last step is
// a floor rather than a feature — item 20's registry gate turns a missing key into a red build, and
// a raw key on screen is what that gate exists to prevent.
//
// `dictionaries` is a parameter so a test can hand in its own, and it is read **when called**: a
// dictionary that loads after this file, or a locale that changes after the first render, still
// answers correctly.
function i18nText(key, locale, dictionaries = globalThis.TC_I18N) {
  const table = (dictionaries && dictionaries[locale]) || null;
  if (table && Object.hasOwn(table, key)) return table[key];
  const english = (dictionaries && dictionaries[TC_I18N_FALLBACK]) || null;
  if (english && Object.hasOwn(english, key)) return english[key];
  return key;
}

// `Object.hasOwn` and not `table[key]`: a key read out of stored settings can name a prototype
// member (`constructor`, `toString`), and the same rule already applies to every settings-derived
// lookup in `defaults.js`.

// The placeholders a message may carry, and the only thing in a value that is interpreted at all.
//
// **Positional** (`%1$s`, `%2$d`) rather than bare `%s`, because a translation reorders its
// arguments and a bare marker cannot say which one it wanted — Korean puts the count before the
// noun where English puts it after. The digit is the argument, wherever the sentence needs it.
//
// A `%d` is spelled differently from a `%s` for the reader's sake only; nothing here formats a
// number, because a locale-aware number format is a decision this project has not made and a silent
// one is worse than none.
//
// An argument that was not supplied leaves its placeholder standing rather than printing
// `undefined`: `%2$s` on screen is a hole somebody reports, and `undefined` is one they screenshot
// without knowing what it means.
//
// It lives here rather than beside its first caller so that there is one of it. A second formatter
// written for the next caller is the same defect class as the second normalization the button
// fingerprint used to carry — two implementations of one rule, agreeing until they do not.
function formatMessage(template, args = []) {
  return String(template).replace(/%(\d+)\$[sd]/g, (whole, position) => {
    const value = args[Number(position) - 1];
    return value === undefined ? whole : String(value);
  });
}

// The document's own language attribute — the one string here that is not a translation but the
// resolved tag itself, which is why it is applied rather than looked up. Screen readers and
// hyphenation read it, and a page that says `lang="en"` while rendering Korean is telling assistive
// technology something false.
//
// The locale is a parameter because the extension cannot yet decide one: the app publishes it and
// the cache that receives it is item 16's. Until then `options.html` ships `lang="en"`, which is
// the truth while English is the only rendered language.
function applyDocumentLanguage(locale, documentRef = globalThis.document) {
  if (!documentRef || !documentRef.documentElement) return null;
  const tag = TC_I18N_LOCALES.includes(locale) ? locale : TC_I18N_FALLBACK;
  documentRef.documentElement.lang = tag;
  return tag;
}

// ---------------------------------------------------------------------------------------------
// The locale cache: what the app told us, and the rules for replacing it.
// ---------------------------------------------------------------------------------------------

// Where the cache lives. `storage.local` and not `storage.sync`: the locale is a fact about the app
// on **this** machine, and syncing it would push one machine's answer onto another where a different
// app instance is running (the same reason the base directory never leaves the app).
const TC_LOCALE_CACHE_KEY = 'localeCache';

// A cache entry we are willing to render from. Anything else is treated as if there were no cache:
// not adopted, and — this is the half that is easy to lose — **not rewritten either**. Normalising a
// value we do not understand would destroy the evidence of what actually went wrong.
function isUsableLocaleCache(value) {
  return !!value
    && typeof value === 'object'
    && TC_I18N_LOCALES.includes(value.locale)
    && typeof value.installId === 'string' && value.installId.length > 0
    && Number.isInteger(value.epoch) && value.epoch >= 0
    && Number.isInteger(value.appliedSeq);
}

// The metadata a response carries, once. The app attaches it only to a response it produced and
// succeeded at (item 15), so everything else — a failure, an old app, a dead socket — arrives here
// as `null` and is **no input at all** rather than a reason to change or clear anything.
function localeGenerationOf(response, seq) {
  if (!response || typeof response !== 'object') return null;
  const locale = response.locale;
  const installId = response.locale_install_id;
  const epoch = response.locale_epoch;
  if (!TC_I18N_LOCALES.includes(locale)) return null;
  if (typeof installId !== 'string' || installId.length === 0) return null;
  if (!Number.isInteger(epoch) || epoch < 0) return null;
  if (!Number.isInteger(seq)) return null;
  return { locale, installId, epoch, seq };
}

// The whole cache decision, as one pure function: what to keep, and whether anything changed.
//
// Three rules, in this order, and the order is the point.
//
// **1. Our own sequence fence** (D50). Every request this extension sends takes the next number, and
// a response is ignored when its request is older than the newest one already applied. This is the
// rule that makes the two below safe: without it, a delayed response from an app instance that was
// replaced — a reset, a reinstall — arrives with a *different* `installId` and rule 2 accepts it
// unconditionally, overwriting a newer locale for good (round 10 review, D81). The number never goes
// on the wire: `sendNativeMessage` resolves per call, so the extension already knows which request
// each response answers, and ordering by **what we sent** rather than by anything the app says is
// what makes the fence work against an older app that knows nothing about any of this.
//
// **2. A different `installId` is accepted unconditionally** (D32). That is what makes a reset
// distinguishable from a stale message — a single counter cannot express "the app's data is new
// now, start over", and an app that reset to epoch 0 would otherwise lose to the cached higher one
// forever.
//
// **3. The same `installId` advances only on a strictly greater epoch.** Equal is not greater: two
// different locales at one epoch is the collision the app's single writer exists to prevent, and if
// it ever happens the cache keeps what it has rather than picking by arrival order.
function localeCacheUpdate(cached, incoming) {
  const usable = isUsableLocaleCache(cached) ? cached : null;
  if (!incoming) return { cache: cached, changed: false };
  if (usable && incoming.seq <= usable.appliedSeq) return { cache: cached, changed: false };
  if (usable && incoming.installId === usable.installId && incoming.epoch <= usable.epoch) {
    return { cache: cached, changed: false };
  }
  return {
    cache: {
      locale: incoming.locale,
      installId: incoming.installId,
      epoch: incoming.epoch,
      appliedSeq: incoming.seq,
    },
    changed: true,
  };
}

// Which language to draw in before the app has answered — and it is asked **every render**, never
// resolved once. Rendering waits for nothing (D15): a relay that has to launch the app blocks for up
// to 25 seconds, and a page that waited for that would show no buttons at all.
//
// With no usable cache the fallback is Chrome's own UI language, folded to something we ship. That
// is a guess and it is allowed to be wrong for one render: the response redraws it. It beats English
// for the majority of users whose Chrome and app agree.
function localeToRenderIn(cached, uiLanguage) {
  if (isUsableLocaleCache(cached)) return cached.locale;
  const language = typeof uiLanguage === 'string' ? uiLanguage : '';
  const exact = TC_I18N_LOCALES.find(tag => tag.toLowerCase() === language.toLowerCase());
  if (exact) return exact;
  const base = language.split('-')[0].toLowerCase();
  if (base === 'zh') return language.toLowerCase().includes('tw') || language.toLowerCase().includes('hant')
    ? 'zh-Hant'
    : 'zh-Hans';
  const sameLanguage = TC_I18N_LOCALES.find(tag => tag.split('-')[0].toLowerCase() === base);
  return sameLanguage || TC_I18N_FALLBACK;
}

// ---------------------------------------------------------------------------------------------
// Redrawing when the language changes.
// ---------------------------------------------------------------------------------------------

// The coordinator between "the cache changed" and "draw again".
//
// It exists as its own object because the three contracts a redraw has to keep are countable rather
// than visual, and counting them through a real DOM would mean asserting on connectivity — which is
// what the earlier review said proves nothing about the failure people actually hit:
//
//   * **the subscription is made once**, not once per redraw. A listener registered inside the
//     redraw path is the classic leak: after five language changes a single click sends five
//     commands, and the user watches five tabs open.
//   * **a redraw does not touch work already in flight.** A click that has handed its command to
//     the host is finished as far as this is concerned; nothing here cancels or resends it.
//   * **a redraw does not send anything.** Drawing is drawing.
//
// `subscribe` and `redraw` are injected, so the page supplies the DOM half and this file supplies
// the rule — and a test can count both without a browser.
function createLocaleRenderer({ subscribe, redraw }) {
  let subscribed = false;
  return {
    // Returns whether it registered, so a caller (and a test) can tell a first call from a repeat.
    start() {
      if (subscribed) return false;
      subscribed = true;
      subscribe(() => redraw());
      return true;
    },
    get subscribed() {
      return subscribed;
    },
  };
}
