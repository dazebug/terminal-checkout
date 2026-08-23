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

// The language **this context** draws in, and the one translator every file in it shares.
//
// A context is a page or a worker, and each has exactly one: the options page has the locale it
// resolved, a content script has the locale it drew its buttons in, and the service worker has
// none that matters because it draws nothing. Holding it here rather than in whichever file
// happened to need it first is what lets `defaults.js`, `migrations.js` and `content.js` ask for a
// message without each inventing a way to find the locale — and inventing one each is how three
// files come to disagree about what language the page is in.
//
// It is a `let` and not a parameter because the alternative is threading a locale through every
// function that might one day contain a sentence. The cost is that a caller cannot ask for a
// message in a language other than the current one; nothing needs to, and a test can set it.
let TC_CURRENT_LOCALE = TC_I18N_FALLBACK;

// Set once the context knows, and again whenever the app moves it. Unshipped tags fold to English
// here rather than at every call site, so `currentLocale()` always names a dictionary we have.
function setCurrentLocale(tag) {
  TC_CURRENT_LOCALE = TC_I18N_LOCALES.includes(tag) ? tag : TC_I18N_FALLBACK;
  return TC_CURRENT_LOCALE;
}

function currentLocale() {
  return TC_CURRENT_LOCALE;
}

// A message in the current language. **Resolved when called, never when a file loads** — a value
// captured at load time is the language that context started in, which is the defect the options
// page's preset dropdown had and the app's settings window had before it.
function tr(key, ...args) {
  return formatMessage(i18nText(key, TC_CURRENT_LOCALE), args);
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
//
// `appliedSeqScope` is optional because a cache written before the scope existed is still a perfectly
// good answer to "what language" — it is only the *fence* that cannot apply to it, which is exactly
// right: the sequence in it was minted by a worker that is gone.
//
// A negative `appliedSeq` is refused rather than clamped. It cannot arise from anything we write, so
// its presence means the value came from somewhere else, and a number we cannot account for is not a
// number to compare against.
function isUsableLocaleCache(value) {
  return !!value
    && typeof value === 'object'
    && TC_I18N_LOCALES.includes(value.locale)
    && typeof value.installId === 'string' && value.installId.length > 0
    && Number.isInteger(value.epoch) && value.epoch >= 0
    && Number.isInteger(value.appliedSeq) && value.appliedSeq >= 0
    && (value.appliedSeqScope === undefined
      || (typeof value.appliedSeqScope === 'string' && value.appliedSeqScope.length > 0));
}

// The metadata a response carries, paired with the request of ours it answers.
//
// **The test is whether the app produced the response, not whether the app liked the request.** That
// is a correction: item 15 attached the generation to successful responses only, and it was wrong.
// A validation failure can be the **first successful contact with the running app** — the cold-start
// query never ran, or failed, or an older app answered it, and then the user presses a button, the
// relay launches the app, and the app refuses the command. The app is running and has a language;
// the response that says so is a failure. Under a success-only rule the extension stays in the wrong
// language for as long as the user keeps making mistakes.
//
// So the boundary is **origin**: everything the app composes about itself — a successful command, a
// refused one, an answered query — carries the generation, and everything the app did not compose —
// a relay error, a transport failure, an older app's answer, the internal-error literal emitted when
// the app could not serialize its own response — simply has no such fields and is no input here.
// That is a rule with fewer exceptions than "success only", because the criterion is where a
// response came from rather than how it turned out.
//
// `seq` and `scope` together name **our** request. The scope is the worker that sent it (see
// `localeCacheUpdate`), and both are required: a generation that could not say which request it
// answers cannot be ordered against one, and silently treating it as unordered would put the very
// hole back that the fence exists to close.
function localeGenerationOf(response, seq, scope) {
  if (!response || typeof response !== 'object') return null;
  // **The envelope is part of "the app composed it".** Without this the rule was only checking the
  // *shape of the metadata*, and a bare `{locale, locale_install_id, locale_epoch}` — a response
  // `hostResponse` cannot produce, because everything it returns carries `success` — was accepted
  // and cached. A test used to bless exactly that object. Both values are welcome: a refusal is a
  // statement about the language too (D83). What is refused is something that never came from a
  // response at all.
  if (typeof response.success !== 'boolean') return null;
  const locale = response.locale;
  const installId = response.locale_install_id;
  const epoch = response.locale_epoch;
  if (!TC_I18N_LOCALES.includes(locale)) return null;
  if (typeof installId !== 'string' || installId.length === 0) return null;
  if (!Number.isInteger(epoch) || epoch < 0) return null;
  if (!Number.isInteger(seq) || seq < 0) return null;
  if (typeof scope !== 'string' || scope.length === 0) return null;
  return { locale, installId, epoch, seq, seqScope: scope };
}

// The whole cache decision, as one pure function: what to keep, and whether anything changed.
//
// Three rules, in this order, and the order is the point.
//
// **1. Our own sequence fence, and only within the worker that minted it** (D50). Every request this
// extension sends takes the next number, and a response is ignored when its request is older than
// the newest one already applied **by the same worker**. The number never goes on the wire:
// `sendNativeMessage` resolves per call, so the extension already knows which request each response
// answers, and ordering by **what we sent** rather than by anything the app says is what makes the
// fence work against an older app that knows nothing about any of this.
//
// The scope is the correction, and the defect it repairs was ours. `appliedSeq` is persisted and the
// counter is not: it restarts at zero with every service worker, so a cache holding `appliedSeq: 10`
// refused the next worker's perfectly good `seq: 1` **forever**, whatever its epoch or install id
// said. The comment that used to sit on that counter argued the opposite — that a fresh worker was
// safe *because* the cache carries the last applied sequence — which is the cause presented as the
// reassurance. It is the class this loop keeps sweeping for, committed by us.
//
// **Why a worker-scoped fence is enough, and where that stands as evidence.** The fence orders
// *writes to the cache*, and every such write is made by `applyLocaleGeneration`, which runs in the
// same worker that awaited the response — so a worker that has been terminated writes nothing at
// all, whatever the native host later does with its reply. Two responses can only need ordering
// against each other while both are outstanding, and both can only be outstanding in one realm. That
// argument is read off our own control flow, not off Chrome's termination semantics: Chrome
// documents that a pending extension API call keeps the worker alive, so a worker is not normally
// killed with one outstanding, but a forced termination is not something this repository can drive
// from `node --test`. **It is reasoning, not a measurement**, and it is the reason to prefer this
// over the alternative of seeding the counter from the cached `appliedSeq` at startup: that
// alternative pretends the number is meaningful across workers, and if a cross-worker reply ever
// were delivered it would rank a dead worker's high sequence above a live worker's low one — the
// regression this fence exists to prevent, reintroduced by the repair.
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
  // Same worker, so the two sequences are comparable. Both sides have to name a scope: two entries
  // that merely fail to name one are not thereby the same worker, and treating `undefined` as a
  // match would fence a fresh worker out on the strength of a number it never minted.
  const sameScope = !!usable
    && typeof usable.appliedSeqScope === 'string' && usable.appliedSeqScope.length > 0
    && usable.appliedSeqScope === incoming.seqScope;
  if (sameScope && incoming.seq <= usable.appliedSeq) return { cache: cached, changed: false };
  if (usable && incoming.installId === usable.installId && incoming.epoch <= usable.epoch) {
    return { cache: cached, changed: false };
  }
  return {
    cache: {
      locale: incoming.locale,
      installId: incoming.installId,
      epoch: incoming.epoch,
      appliedSeq: incoming.seq,
      appliedSeqScope: incoming.seqScope,
    },
    changed: true,
  };
}

// Read, reduce, write, notify — as one step that cannot interleave with another of itself.
//
// The reducer is pure and its fence is exact, and neither helps if two calls read the same cache
// before either writes. That is what the caller used to do: `storage.local.get`, reduce, `set`, with
// awaits in between and nothing holding the door. Request 12 reads and writes first; request 11 read
// the same old value and writes second; the fence in the reducer never saw request 12 because it was
// handed the cache as it was *before* it. The cache goes backwards, and every open page is told to
// redraw in the older language.
//
// The queue is a promise chain rather than a lock because there is exactly one place that needs it:
// a service worker is **one per extension**, so two tabs clicking at once are two messages handled by
// the same worker, in the same realm, on the same task queue. The race is interleaving *inside* the
// worker across `await`, not two workers contending — there is no second writer to lock against, only
// a second continuation. (`storage.local` offers no compare-and-set, so ordering is the only tool
// available even if there were.)
//
// `read`, `write` and `notify` are injected so a test can force the interleaving that the real
// storage will not reliably produce.
function createLocaleCacheWriter({ read, write, notify, log = console.log }) {
  let queue = Promise.resolve();
  return function applyLocaleGeneration(incoming) {
    const result = queue.then(async () => {
      if (!incoming) return null;
      const { cache, changed } = localeCacheUpdate(await read(), incoming);
      if (!changed) return null;
      await write(cache);
      await notify(cache.locale);
      return cache;
    }).catch((error) => {
      // **This never rejects, and that is the fix to the worst defect this work has found.**
      //
      // It used to propagate a `storage.local` failure to its caller, and its caller was
      // `sendToNativeHost`, which awaited it *before* deciding what to tell the page. So a storage
      // error arriving after the app had already returned success turned an executed command into a
      // reported failure: the terminal was open, the page said it had failed, and the obvious thing
      // for a person to do next was press the button again. For a button with scheduled claude
      // input, delivery was already under way — the second press is a duplicate submission, which
      // is the exact outcome CLAUDE.md spends two separate rules preventing on the app side ("after
      // a CR has gone out, that input is never typed again"). Bookkeeping had found a way around
      // them. When the app returned a real failure it was worse in a quieter way: the storage error
      // replaced the app's own diagnostic.
      //
      // So the failure is swallowed **here**, where there is exactly one thing it could mean and
      // nothing that could be done about it, rather than at each call site — a rule kept by
      // convention at every caller is a rule the next caller breaks. Losing a cache update costs a
      // render in the wrong language until the next response; the alternative cost was running a
      // command twice.
      log('Locale cache update failed, continuing:', error?.message || error);
      return null;
    });
    // The chain also has to survive a failing step, which the catch above already guarantees.
    queue = result;
    return result;
  };
}

// The first draw waits for the cached locale — and for nothing else.
//
// D15 says rendering does not wait for **the app's answer**, and that is the whole of it: a relay
// that has to launch the app blocks for up to 25 seconds, and a page that waited would show no
// buttons at all for that long. A `storage.local` read is not that. It is local, it answers in
// microseconds, and it is the only thing that knows the language the user already has. Drawing
// before it lands means a valid Korean cache loses to the English fallback — and if the app's answer
// then equals the cache, the reducer reports no change, no notification goes out, and nothing ever
// repairs the page. Our own wording was the reason that looked acceptable: "rendering does not wait
// for the locale query" was written broadly enough to read as "does not wait for anything".
//
// Resolved once and shared: every insertion path awaits the same promise, so the read happens once
// however many times the page tries to draw. It never rejects — a cache that cannot be read leaves
// the fallback in place, which is a language, whereas a rejected gate would be no buttons forever.
function createFirstRenderGate(prepare) {
  let pending = null;
  return function ready() {
    if (!pending) pending = (async () => prepare())().catch(() => null);
    return pending;
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
// What a native response means for the page that asked.
// ---------------------------------------------------------------------------------------------

// **It takes the response and nothing else, and that is the whole point.** The defect above was not
// that the bookkeeping was wrong; it was that the bookkeeping was *reachable* from the decision. A
// function that is never handed the cache, the storage, or the writer's result cannot let any of
// them change what a click reports — the dependency is not guarded, it is unstateable.
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

// Work whose result the caller may not see and whose failure may not reach them. It is a function so
// that "detached on purpose" is written down rather than inferred from a missing `await`, and so
// that a synchronous throw is contained too — `.catch()` alone would not have caught one.
function startBookkeeping(work, describe, log = console.log) {
  try {
    const started = work();
    if (started && typeof started.catch === 'function') {
      started.catch(error => log(`${describe} failed, continuing:`, error?.message || error));
    }
  } catch (error) {
    log(`${describe} failed, continuing:`, error?.message || error);
  }
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
function createLocaleRenderer({ subscribe, redraw, log = console.log }) {
  let subscribed = false;
  // How many times `redraw` returned something unwaitable. **The queue below can only serialize
  // work it can wait for**, so an adapter that starts an asynchronous redraw and returns nothing
  // silently opts out of the serialization it looks like it has — which is what the options page
  // did, one promotion after this queue was added for exactly that defect. It stayed invisible
  // because the test's injected `redraw` returned a promise: the double was better behaved than the
  // adapter. Counting it turns a silent opt-out into something a test can see.
  let unwaitableRedraws = 0;
  // Redraws do not overlap. A redraw reads the cache and then assigns the language it drew in, with
  // an await in between, so two of them running at once can finish in the order they did not start
  // in and leave the **older** language on screen — the same shape as the unserialized cache write,
  // found by sweeping for it rather than by being reported. Two notifications in quick succession is
  // all it takes, and the app sends one per accepted response.
  let queue = Promise.resolve();
  return {
    // Returns whether it registered, so a caller (and a test) can tell a first call from a repeat.
    start() {
      if (subscribed) return false;
      subscribed = true;
      subscribe(() => {
        queue = queue.then(() => {
          const started = redraw();
          if (!started || typeof started.then !== 'function') {
            unwaitableRedraws += 1;
            log('A redraw returned nothing to wait for, so it cannot be serialized.');
          }
          return started;
        }).then(() => {}, () => {});
        return queue;
      });
      return true;
    },
    get subscribed() {
      return subscribed;
    },
    get unwaitableRedraws() {
      return unwaitableRedraws;
    },
  };
}
