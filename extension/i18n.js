// Chrome chooses the extension language through `chrome.i18n`; the app chooses its own, so the two
// surfaces may differ (`docs/context/localization.md`). Keep this script chrome-free at load time:
// the lookup names `chrome.i18n.getMessage` inside a function because tests load it without
// `chrome`.

// The logical locale tags, in the app-era spelling the dotted message ids grew up with. Chrome's
// canonical `_locales/` directories use `zh_CN`/`zh_TW`; the one locale-to-directory map belongs to
// the read-only catalogue checker rather than to this lookup.
const TC_I18N_LOCALES = ['en', 'ko', 'ja', 'zh-Hans', 'zh-Hant'];

// The key every catalogue answers with its own tag, and the list of keys that are **not** messages.
//
// A catalogue that names itself is how the document language stops being a guess. Chrome
// picks which catalogue answers, including when its UI language is one we do not ship and it falls
// back; asking the catalogue rather than asking Chrome means the answer is the language actually on
// screen. Reimplementing Chrome's fallback here would create a second fallback algorithm.
//
// Metadata, not one of the strings a person reads: it stays out of "is this locale fully
// translated" counts and out of the gate that every message in the catalogue is drawn somewhere.
const TC_I18N_CATALOGUE_TAG_KEY = 'ext.meta.catalogueTag';
const TC_I18N_METADATA_KEYS = [TC_I18N_CATALOGUE_TAG_KEY];

// The one conversion between the id a source names and the name Chrome's `_locales` can hold.
//
// `_locales` message names may contain `[A-Za-z0-9_@]` and are matched **case-insensitively**
// (measured against every extension installed on this machine: 739 `messages.json` files, 25,510
// names, not one with a dot). Our ids are dotted, so something has to give — and what gives is the
// **boundary**, not the source. `tr('ext.header.options')` stays exactly that everywhere it
// is written, and `ext_header_options` exists only where the platform is looking.
//
// **It is here so that there is one of it.** The read-only checker that verifies `_locales` and the
// runtime lookup both load this function from this file. A checker with its own copy of "the same
// rule" is two implementations, and the way to avoid that is for every consumer to load the same
// rule.
function chromeMessageId(key) {
  return String(key).replace(/\./g, '_');
}

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
// It lives here rather than beside its first caller so every caller uses the same formatter. A
// second implementation of this rule could agree until the two copies drift.
function formatMessage(template, args = []) {
  return String(template).replace(/%(\d+)\$[sd]/g, (whole, position) => {
    const value = args[Number(position) - 1];
    return value === undefined ? whole : String(value);
  });
}

// ---------------------------------------------------------------------------------------------
// The lookup, and the one seam in it.
// ---------------------------------------------------------------------------------------------

// **One chain, and only its last link is replaceable**. `tr` converts the logical id to the
// physical one with the function in this file, turns every substitution into a
// string, and hands both to a backend. A test that swaps the backend therefore still goes through
// `chromeMessageId` and through the stringification — swap the *whole* function, as the first
// design of this seam did, and every test in Node passes while production maps keys wrongly or
// hands `chrome.i18n` a number it will not take.
let messageBackend = null;

// Returns the previous backend so a test can put it back; `null` restores the production default.
function installMessageBackend(backend) {
  const previous = messageBackend;
  messageBackend = backend;
  return previous;
}

// **The default is lazy, and in Node it throws.** Lazy because this file has to load with no
// `chrome` in sight, and a lookup resolved at load time would pin whatever was (or was not) there.
// Throwing in Node is the other half: there is no `chrome` there, so a context that forgot to
// inject gets a `ReferenceError` instead of text, and the tests cannot end up with a fake that is
// more generous than the runtime. That is also why the realm tests build their own contexts: a
// `chrome` left on Node's global by another test would answer this call and hide exactly that.
function messageFor(physicalId, substitutions) {
  const backend = messageBackend || ((id, subs) => chrome.i18n.getMessage(id, subs));
  return backend(physicalId, substitutions);
}

// A message, from whichever catalogue Chrome chose. **Resolved when called, never when a file
// loads** — a value captured at load time is the language that context started in, which is the
// defect the options page's preset dropdown had and the app's settings window had before it.
//
// `String(value)` and not the value: `chrome.i18n.getMessage` takes strings, while the count this
// page passes is a number. Both formatting paths therefore convert substitutions at this boundary.
function tr(key, ...args) {
  return messageFor(chromeMessageId(key), args.map(String));
}

// The document's own language attribute — **the catalogue Chrome actually served, asked rather than
// computed**.
//
// Chrome may report `fr` while `getMessage` falls back to the English catalogue, and `lang="fr"`
// over English text tells a screen reader something false. The answer comes from **a message every
// catalogue carries whose value is its own tag**: whichever catalogue answered is the one that
// names itself. Reimplementing Chrome's fallback here would create a second fallback algorithm.
function applyDocumentLanguage(documentRef = globalThis.document) {
  if (!documentRef || !documentRef.documentElement) return null;
  const tag = tr(TC_I18N_CATALOGUE_TAG_KEY);
  if (!tag) return null;
  documentRef.documentElement.lang = tag;
  return tag;
}

// ---------------------------------------------------------------------------------------------
// What a native response means for the page that asked.
// ---------------------------------------------------------------------------------------------

// **It takes the response and nothing else.** Storage and any bookkeeping cannot change what a
// click reports because neither is an input to this function.
//
// `success !== true` rather than `!success`: a response with no envelope is not a failure of the
// command, it is not a response from this app at all, and it lands here as one anyway because there
// is nothing better to tell the page.
function nativeOutcome(response) {
  if (!response || typeof response !== 'object' || response.success !== true) {
    const error = (response && typeof response.error === 'string' && response.error)
      || 'native host returned no result';
    return { failed: true, error };
  }
  return { failed: false, response };
}
