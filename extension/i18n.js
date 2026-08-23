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
