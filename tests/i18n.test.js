// Tests for the extension's dictionary skeleton — `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');
const manifest = JSON.parse(read('manifest.json'));

// The same loader the extension's three hosts use, and the same one the other test files use: a
// classic script, run with **no `chrome` global in sight**. That is the constraint the whole
// skeleton is shaped by (D6) — a single `chrome.*` at module scope would take down every test here
// and the 158 that came before.
vm.runInThisContext(read('i18n.js'));
for (const tag of ['en', 'ko', 'ja', 'zh-Hans', 'zh-Hant']) {
  vm.runInThisContext(read(`_i18n/${tag}.js`));
}
// and defaults.js, whose presets resolve their display text through the dictionaries above
vm.runInThisContext(read('defaults.js'));
const { i18nText, applyDocumentLanguage, TC_I18N_LOCALES, TC_I18N_FALLBACK } =
  vm.runInThisContext('({ i18nText, applyDocumentLanguage, TC_I18N_LOCALES, TC_I18N_FALLBACK })');

test('the five dictionaries register themselves, and nothing else does', () => {
  assert.deepEqual(Object.keys(globalThis.TC_I18N).sort(), [...TC_I18N_LOCALES].sort());
  assert.deepEqual(TC_I18N_LOCALES, ['en', 'ko', 'ja', 'zh-Hans', 'zh-Hant']);
  // The same spelling the app publishes, so a locale arriving from the app needs no mapping table
  assert.equal(TC_I18N_FALLBACK, 'en');
});

test('lookup: the asked-for locale, then English, then the key itself', () => {
  const dictionaries = {
    en: { 'ext.a': 'A', 'ext.b': 'B' },
    ko: { 'ext.a': '가' },
  };
  assert.equal(i18nText('ext.a', 'ko', dictionaries), '가');
  assert.equal(i18nText('ext.b', 'ko', dictionaries), 'B', 'a missing key did not fall back to English');
  assert.equal(i18nText('ext.missing', 'ko', dictionaries), 'ext.missing');
  assert.equal(i18nText('ext.a', 'fr', dictionaries), 'A', 'an unshipped locale did not fall back');
  assert.equal(i18nText('ext.a', undefined, dictionaries), 'A');
});

test('lookup: a key that names a prototype member is not a hit', () => {
  // Keys reach this from stored settings, and `{}.constructor` is not a translation
  const dictionaries = { en: { 'ext.a': 'A' } };
  assert.equal(i18nText('constructor', 'en', dictionaries), 'constructor');
  assert.equal(i18nText('toString', 'ko', dictionaries), 'toString');
});

test('lookup happens when it is called, not when the file loads', () => {
  // It has to go through the **default** argument. Passing a dictionary in proves only that the
  // function reads the object it was handed, which every implementation does — measured: a version
  // that captured `globalThis.TC_I18N` at load time passed that weaker check unchanged.
  const registry = globalThis.TC_I18N;
  try {
    assert.equal(i18nText('ext.late.probe', 'en'), 'ext.late.probe');
    globalThis.TC_I18N = { en: { 'ext.late.probe': 'arrived' } };
    assert.equal(
      i18nText('ext.late.probe', 'en'),
      'arrived',
      'the registry was captured when the file loaded, so a dictionary arriving later is invisible',
    );
  } finally {
    globalThis.TC_I18N = registry;
  }
  // and the dictionaries the other cases rely on are back
  assert.deepEqual(Object.keys(globalThis.TC_I18N).sort(), [...TC_I18N_LOCALES].sort());
});

test('the document language attribute is the resolved tag, not a translation', () => {
  const doc = { documentElement: { lang: 'en' } };
  assert.equal(applyDocumentLanguage('zh-Hant', doc), 'zh-Hant');
  assert.equal(doc.documentElement.lang, 'zh-Hant');
  // An unshipped tag lands where every unanswerable question lands
  assert.equal(applyDocumentLanguage('fr', doc), 'en');
  assert.equal(doc.documentElement.lang, 'en');
  assert.equal(applyDocumentLanguage('ko', undefined), null, 'it reached for a document that is not there');
});

test('the key spaces are separate, whatever is in them', () => {
  for (const tag of TC_I18N_LOCALES) {
    for (const key of Object.keys(globalThis.TC_I18N[tag])) {
      assert.ok(key.startsWith('ext.'), `${tag} carries ${key}, which is not in the extension's space`);
    }
  }
  // `chrome.i18n`'s namespace holds exactly the two keys a manifest cannot fill any other way (D9)
  //
  // **Five directories now, and that reverses item 17's decision to ship two.** Its reason was that
  // an *empty* `messages.json` is a shape nobody had measured, so creating three of them would have
  // added three unverified files to hold nothing. That reason expires the moment there are values to
  // put in them: a filled `messages.json` is the shape Chrome documents and the other two already
  // demonstrate. Leaving them out now would mean the extension's own name and description stay
  // English in three of the five languages it otherwise speaks.
  for (const tag of ['en', 'ko', 'ja', 'zh_CN', 'zh_TW']) {
    const messages = JSON.parse(read(`_locales/${tag}/messages.json`));
    assert.deepEqual(Object.keys(messages).sort(), ['extDescription', 'extName']);
    for (const key of Object.keys(messages)) {
      assert.equal(typeof messages[key].message, 'string');
      assert.ok(messages[key].message.length > 0, `${tag}/${key} is empty`);
    }
  }
});

test('the manifest names those two keys and declares where to fall back', () => {
  assert.equal(manifest.name, '__MSG_extName__');
  assert.equal(manifest.description, '__MSG_extDescription__');
  assert.equal(manifest.default_locale, TC_I18N_FALLBACK);
  assert.ok(
    fs.existsSync(path.join(extension, '_locales', manifest.default_locale, 'messages.json')),
    'default_locale names a directory that is not there — documented as a load failure, not measured here',
  );
});

test('every script the manifest lists exists, and i18n.js comes before content.js', () => {
  const scripts = manifest.content_scripts[0].js;
  for (const file of scripts) {
    assert.ok(fs.existsSync(path.join(extension, file)), `${file} is listed but not on disk`);
  }
  assert.ok(
    scripts.indexOf('i18n.js') < scripts.indexOf('content.js'),
    'the helper is injected after the script that uses it',
  );
  // Chrome injects `js` in array order (documented), which is the whole guarantee here — and the
  // reason `defaults.js` may sit anywhere is that no lookup happens at load time.
  for (const tag of TC_I18N_LOCALES) {
    assert.ok(scripts.includes(`_i18n/${tag}.js`), `${tag} is not injected into the page`);
  }
});

test('nothing in the skeleton touches chrome at load time', () => {
  // Comment lines are dropped first: these files *talk* about `chrome.i18n` at length — why it
  // holds two keys and no more — and prose is not a call. Whole-line comments are enough here
  // because none of these files has a trailing comment or a string containing `//`.
  const code = file =>
    read(file)
      .split('\n')
      .filter(line => !line.trim().startsWith('//'))
      .join('\n');
  for (const file of ['i18n.js', ...TC_I18N_LOCALES.map(tag => `_i18n/${tag}.js`)]) {
    assert.ok(!/\bchrome\./.test(code(file)), `${file} reaches for chrome`);
  }
  // and the check is not vacuous: the prose that was skipped really does mention it
  assert.ok(/chrome\.i18n/.test(read('i18n.js')));
});

// ---------------------------------------------------------------------------------------------
// The cache reducer. Every case names what it asserts, because "the callback came back" is not an
// assertion (D54) — what is checked is the **final cache value** and whether anything was written.
// ---------------------------------------------------------------------------------------------

const { localeCacheUpdate, localeGenerationOf, isUsableLocaleCache, localeToRenderIn, createLocaleRenderer } =
  vm.runInThisContext(
    '({ localeCacheUpdate, localeGenerationOf, isUsableLocaleCache, localeToRenderIn, createLocaleRenderer })',
  );
const { createLocaleCacheWriter, createFirstRenderGate } =
  vm.runInThisContext('({ createLocaleCacheWriter, createFirstRenderGate })');

// One worker's lifetime. The sequence fence only compares numbers minted in the same one, so the
// helpers carry it the way the real path does — a fixture that left it out would be testing a shape
// the code never sees.
const WORKER = 'worker-1';
const cache = (over = {}) => ({
  locale: 'ko', installId: 'install-a', epoch: 3, appliedSeq: 10, appliedSeqScope: WORKER, ...over,
});
const generation = (over = {}) => ({
  locale: 'ja', installId: 'install-a', epoch: 4, seq: 11, seqScope: WORKER, ...over,
});

test('a different installId is adopted unconditionally, and a late response from the prior install does not undo it', () => {
  const reset = localeCacheUpdate(cache(), generation({ installId: 'install-b', epoch: 0, seq: 11 }));
  assert.equal(reset.changed, true);
  assert.deepEqual(reset.cache,
    { locale: 'ja', installId: 'install-b', epoch: 0, appliedSeq: 11, appliedSeqScope: WORKER });

  // The stale install response: the old instance answers a request we sent *earlier*, and its
  // `installId` differs, which rule 2 alone would accept. The sequence fence is what refuses it.
  const late = localeCacheUpdate(reset.cache, generation({ installId: 'install-a', epoch: 99, seq: 9 }));
  assert.equal(late.changed, false, 'a stale install response replaced a newer cached locale');
  assert.deepEqual(late.cache, reset.cache);
});

test('an out-of-order response leaves the newer locale in the cache', () => {
  const newer = localeCacheUpdate(cache(), generation({ epoch: 7, locale: 'ja', seq: 11 }));
  assert.equal(newer.cache.epoch, 7);
  const older = localeCacheUpdate(newer.cache, generation({ epoch: 5, locale: 'en', seq: 12 }));
  assert.equal(older.changed, false);
  assert.deepEqual(older.cache, newer.cache, 'the final cache is not the newer locale');
});

test('the same installId with an equal epoch and a different locale is refused', () => {
  const result = localeCacheUpdate(cache(), generation({ epoch: 3, locale: 'ja', seq: 11 }));
  assert.equal(result.changed, false, 'equal counted as greater');
  assert.equal(result.cache.locale, 'ko', 'the cache took a second locale at one epoch');
});

test('a response carrying no generation writes nothing and notifies nobody', () => {
  // Not because it failed — a failure the app composed carries its publication now (R11 C) —
  // but because nothing here has any to carry: a dead socket, an older app answering
  // `command_template is required`, an empty object. The absence is the whole signal.
  const start = cache();
  for (const response of [null, undefined, { success: false, error: 'command_template is required' }, {}]) {
    const result = localeCacheUpdate(start, localeGenerationOf(response, 11, WORKER));
    assert.equal(result.changed, false, `${JSON.stringify(response)} changed the cache`);
    assert.deepEqual(result.cache, start);
  }
});

test('a successful response without locale metadata preserves the cache', () => {
  // The ordinary command path, carrying a real result and no generation — not a discarded throat
  const response = { success: true };
  const result = localeCacheUpdate(cache(), localeGenerationOf(response, 11, WORKER));
  assert.equal(result.changed, false);
  assert.deepEqual(result.cache, cache());
});

test('a corrupt storage.local value is neither adopted nor rewritten', () => {
  const corruptValues = [
    'ko',
    42,
    null,
    { locale: 'ko' },
    { locale: 'fr', installId: 'a', epoch: 1, appliedSeq: 0 },
    { locale: 'ko', installId: '', epoch: 1, appliedSeq: 0 },
  ];
  for (const corrupt of corruptValues) {
    assert.equal(isUsableLocaleCache(corrupt), false, `${JSON.stringify(corrupt)} passed validation`);
    // Nothing valid arriving: the corrupt value stays exactly as it is, evidence intact
    const idle = localeCacheUpdate(corrupt, null);
    assert.equal(idle.changed, false);
    assert.equal(idle.cache, corrupt);
    // Something valid arriving: it is adopted, because a value we cannot read is not a generation
    const adopted = localeCacheUpdate(corrupt, generation());
    assert.equal(adopted.changed, true);
    assert.deepEqual(adopted.cache,
      { locale: 'ja', installId: 'install-a', epoch: 4, appliedSeq: 11, appliedSeqScope: WORKER });
  }
});

test('an unknown locale in a response is not a generation', () => {
  for (const locale of ['fr', 'zh', 'KO', '', null, 42]) {
    assert.equal(
      localeGenerationOf({ success: true, locale, locale_install_id: 'a', locale_epoch: 1 }, 1, WORKER),
      null,
      String(locale),
    );
  }
  // **This assertion used to run the other way, and it was wrong.** A bare
  // `{locale, locale_install_id, locale_epoch}` is not a response this app can compose — everything
  // `hostResponse` returns carries `success` — so accepting it meant the "did the app compose it"
  // rule was really only checking the shape of the metadata. The test blessed the hole it left.
  assert.equal(
    localeGenerationOf({ locale: 'ko', locale_install_id: 'a', locale_epoch: 1 }, 1, WORKER),
    null,
    'a response with no envelope was taken for one the app composed',
  );
  // Origin, not outcome: both envelopes are accepted (D83)
  for (const success of [true, false]) {
    assert.deepEqual(
      localeGenerationOf({ success, locale: 'ko', locale_install_id: 'a', locale_epoch: 1 }, 1, WORKER),
      { locale: 'ko', installId: 'a', epoch: 1, seq: 1, seqScope: WORKER },
      `success: ${success}`,
    );
  }
});

test('a malformed generation field is not a generation', () => {
  const base = { locale: 'ko', locale_install_id: 'a', locale_epoch: 1 };
  const broken = [
    { ...base, locale_epoch: '1' },
    { ...base, locale_epoch: 1.5 },
    { ...base, locale_epoch: -1 },
    { ...base, locale_install_id: '' },
    { ...base, locale_install_id: 7 },
  ];
  for (const response of broken) {
    assert.equal(localeGenerationOf(response, 1, WORKER), null, JSON.stringify(response));
  }
  // and the sequence has to be one of ours, not whatever a caller passed
  assert.equal(localeGenerationOf(base, undefined, WORKER), null);
  assert.equal(localeGenerationOf(base, '3', WORKER), null);
});

test('rendering never waits for the app: the language comes from what is already there', () => {
  assert.equal(localeToRenderIn(cache(), 'en-US'), 'ko', 'a usable cache did not win');
  // No cache: Chrome's own language, folded to something we ship
  assert.equal(localeToRenderIn(null, 'ko'), 'ko');
  assert.equal(localeToRenderIn(null, 'ja-JP'), 'ja');
  assert.equal(localeToRenderIn(null, 'zh-TW'), 'zh-Hant');
  assert.equal(localeToRenderIn(null, 'zh-CN'), 'zh-Hans');
  assert.equal(localeToRenderIn(null, 'fr-CA'), 'en', 'an unshipped browser language did not fall back');
  assert.equal(localeToRenderIn(undefined, undefined), 'en');
  assert.equal(
    localeToRenderIn({ locale: 'fr', installId: 'a', epoch: 1, appliedSeq: 0 }, 'ja'),
    'ja',
    'a corrupt cache was rendered from',
  );
});

// ---------------------------------------------------------------------------------------------
// The redraw contracts. Counted, not inspected: what goes wrong here is a listener registered twice
// and a click that fires twice, neither of which shows up in the shape of the DOM.
// ---------------------------------------------------------------------------------------------

test('the locale observer is registered once, not once per redraw', () => {
  let subscriptions = 0;
  let redraws = 0;
  const renderer = createLocaleRenderer({
    subscribe: () => { subscriptions += 1; },
    redraw: () => { redraws += 1; },
  });
  assert.equal(renderer.start(), true);
  for (let i = 0; i < 5; i += 1) assert.equal(renderer.start(), false, 'it subscribed again');
  assert.equal(subscriptions, 1, `subscribed ${subscriptions} times`);
  assert.equal(renderer.subscribed, true);
  assert.equal(redraws, 0, 'starting drew something on its own');
});

test('a redraw does not detach a button whose click is in flight', async () => {
  // The click is modelled the way the page runs it: it holds its own handle and reports on that
  // handle when it comes back, so a redraw replacing the nodes cannot silence it.
  let released;
  const inFlight = new Promise(resolve => { released = resolve; });
  const button = { label: 'A', feedback: null };
  const click = (async () => { await inFlight; button.feedback = 'done'; })();

  let redraws = 0;
  let notified;
  const renderer = createLocaleRenderer({
    subscribe: notify => { notified = notify(); },
    redraw: () => { redraws += 1; },
  });
  renderer.start(); // the subscription fires a redraw immediately, mid-click
  await notified;   // queued now, so it lands on a later tick rather than inside `subscribe`
  assert.equal(redraws, 1);
  assert.equal(button.feedback, null, 'the click finished early — the case proves nothing');

  released();
  await click;
  assert.equal(button.feedback, 'done', 'a redraw during the click lost its result');
});

test('two redraws do not overlap, so the older language cannot land last', async () => {
  // Found by sweeping for the class rather than reported: a redraw reads the cache and then assigns
  // the language it drew in, with an await between the two. Two of them at once can finish in the
  // order they did not start in, leaving the older language on screen — the same shape as the
  // unserialized cache write, in the other file.
  const order = [];
  let started = 0;
  let notify;
  const renderer = createLocaleRenderer({
    subscribe: (fn) => { notify = fn; },
    async redraw() {
      const id = started++;
      order.push(`start-${id}`);
      await new Promise(resolve => setTimeout(resolve, id === 0 ? 20 : 0)); // the first one is slow
      order.push(`end-${id}`);
    },
  });
  renderer.start();
  await Promise.all([notify(), notify()]);
  assert.deepEqual(order, ['start-0', 'end-0', 'start-1', 'end-1'], `redraws overlapped: ${order}`);
});

test('a redraw that throws does not stop the ones behind it', async () => {
  let notify;
  let succeeded = 0;
  let calls = 0;
  const renderer = createLocaleRenderer({
    subscribe: (fn) => { notify = fn; },
    async redraw() {
      calls += 1;
      if (calls === 1) throw new Error('the page went away');
      succeeded += 1;
    },
  });
  renderer.start();
  await notify();
  await notify();
  assert.equal(succeeded, 1, 'one failed redraw made the page deaf to the next language');
});

test('a redraw does not invalidate a command already sent to the host', async () => {
  let sends = 0;
  const send = async () => { sends += 1; return { success: true }; };
  const renderer = createLocaleRenderer({
    subscribe: notify => { notify(); notify(); }, // two notifications
    redraw: () => {},                             // drawing draws; it does not send
  });
  await send();
  renderer.start();
  assert.equal(sends, 1, `the redraw path sent ${sends} commands`);
  await send();
  assert.equal(sends, 2, 'the counter is not measuring anything');
});

test('sendToNativeHost does not wait for locale bookkeeping', async () => {
  // **This used to be a source lint, and that was the gap.** The composition it described lived in
  // `background.js`, which needs `chrome` at module scope, so nothing ran it — the separated pieces
  // were tested and their arrangement was read. Two reviews in a row found defects in exactly that
  // sort of unrun arrangement, so the arrangement moved into a function that a test can drive.
  //
  // The storage here never settles. If the answer waited on it, this test would time out.
  const { createNativeRequester } = vm.runInThisContext('({ createNativeRequester })');
  let recordedSeq = null;
  const request = createNativeRequester({
    async send() { return { success: true, ok: 1 }; },
    record(response, seq, scope) {
      recordedSeq = { seq, scope };
      return new Promise(() => {}); // a storage round trip that never comes back
    },
    log: () => {},
  });

  const answer = await request({ command_template: 'z {repo}' }, 'worker-1');
  assert.deepEqual(answer, { success: true, ok: 1 }, 'the answer waited for the bookkeeping');
  assert.deepEqual(recordedSeq, { seq: 1, scope: 'worker-1' }, 'the request was not recorded');
});

test('a rejected app command keeps its own error while bookkeeping is still pending', async () => {
  const { createNativeRequester } = vm.runInThisContext('({ createNativeRequester })');
  const request = createNativeRequester({
    async send() { return { success: false, error: 'Unknown variable: {evil}' }; },
    record() { return new Promise(() => {}); },
    log: () => {},
  });
  await assert.rejects(request({}, 'worker-1'), /Unknown variable/);
});

test('a bookkeeping failure never reaches the caller', async () => {
  const { createNativeRequester } = vm.runInThisContext('({ createNativeRequester })');
  const failures = [];
  const request = createNativeRequester({
    async send() { return { success: true }; },
    record() { throw new Error('storage.local.set failed'); },
    log: (...parts) => failures.push(parts.join(' ')),
  });
  assert.deepEqual(await request({}, 'w'), { success: true });
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.ok(failures.some(line => line.includes('storage.local.set failed')), 'the failure vanished');
});

test('every request takes the next number, and the response is recorded against its own', async () => {
  // The fence orders by what **we** sent, so the number has to belong to the request rather than to
  // whatever happens to answer first.
  const { createNativeRequester } = vm.runInThisContext('({ createNativeRequester })');
  const seen = [];
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  const request = createNativeRequester({
    async send(message) { if (message.slow) await held; return { success: true }; },
    record(response, seq) { seen.push(seq); },
    log: () => {},
  });
  const slow = request({ slow: true }, 'w');
  const fast = request({}, 'w');
  await fast;
  release();
  await slow;
  assert.deepEqual(seen, [2, 1], 'a response was recorded against another request’s number');
});

test('the transport failure path carries no metadata and raises (lint)', () => {
  // The one branch left unexercised above: `sendNativeMessage` itself rejecting. Driving it needs no
  // chrome, but what it does — rethrow before anything is recorded — is one line, and the assertion
  // that matters is that nothing was recorded, which the composition above already shows for the
  // paths that do record.
  const source = read('i18n.js');
  const requester = source.slice(source.indexOf('function createNativeRequester('));
  const body = requester.slice(0, requester.indexOf('\n}\n'));
  const raise = body.indexOf('throw error;');
  const record = body.indexOf('startBookkeeping(');
  assert.ok(raise > 0 && record > raise, 'a transport failure is now recorded as a generation');
});

// ---------------------------------------------------------------------------------------------
// The options page's own catalogue (item 21).
//
// The page carries no prose: `options.html` names messages (`data-i18n`) and `options.js` asks for
// them. Which means the two questions a catalogue gate has to answer — "is every key it can ask for
// there" and "is every key there asked for" — are **enumerations** rather than estimates, and these
// tests are what keeps them that way.
// ---------------------------------------------------------------------------------------------

const optionsJs = read('options.js');
const optionsHtml = read('options.html');

// **Every file that can name a message**, not only the options page: item 22 moved the presets, the
// button phase markers and the update notice's prose into the dictionaries too, and a gate that
// scanned one file would have called all of those unreferenced.
//
// The set is **read from the directory**, not listed. As a list of five it was complete — the two
// scripts it omitted name no messages — but "every file" was then a promise about a directory that
// can grow, and a new script naming a key nobody put in the catalogue would have gone unseen in
// exactly the direction that shows a user a raw key (measured with a planted file).
const SPEAKING_FILES = fs.readdirSync(extension).filter(name => name.endsWith('.js')).sort();
assert.ok(SPEAKING_FILES.length >= 5, `only ${SPEAKING_FILES.length} extension scripts found`);
const speakingSource = SPEAKING_FILES.map(read).join('\n');

// A message id can only be named by a literal (checked below), and `options.html` names them in an
// attribute — so between them this is the whole set.
const keysInJs = new Set([...speakingSource.matchAll(/'(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]));
const keysInHtml = new Set([...optionsHtml.matchAll(/data-i18n="([^"]+)"/g)].map(m => m[1]));
const referencedKeys = new Set([...keysInJs, ...keysInHtml]);

// Which half of the text/markup split a key is on. A key reached through `t(`/`tr(` becomes
// textContent, a title or a `confirm()`; a key reached through `tHTML(` or `data-i18n` becomes
// innerHTML.
const textKeys = new Set(
  [...speakingSource.matchAll(/\bt r?\('(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]),
);
for (const match of speakingSource.matchAll(/\btr\('(ext\.[A-Za-z0-9.]+)'/g)) textKeys.add(match[1]);
for (const match of speakingSource.matchAll(/\bt\('(ext\.[A-Za-z0-9.]+)'/g)) textKeys.add(match[1]);
const markupKeys = new Set([
  ...[...speakingSource.matchAll(/\btHTML\('(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]),
  ...keysInHtml,
]);

const placeholdersOf = value => (value.match(/%\d+\$[sd]/g) ?? []).sort();
const tagsOf = value => (value.match(/<\/?[a-z][^>]*>/g) ?? []).map(tag => tag.replace(/\s+class="[^"]*"/, '')).sort();
const codeSpansOf = value => (value.match(/<code>[^<]*<\/code>/g) ?? []).sort();

test('every locale carries the same keys, and every value says something', () => {
  // **This used to exempt ja and zh, and the exemption was the hole.** It asserted they were
  // *empty*, which was true and useless: a catalogue filled with three keys would have passed it
  // just as a complete one would have failed it. Now every shipped locale answers the same
  // question, and the day a translation is missing one key it is that locale that goes red.
  const en = globalThis.TC_I18N.en;
  assert.ok(Object.keys(en).length >= 89, `the catalogue shrank to ${Object.keys(en).length}`);
  for (const tag of TC_I18N_LOCALES) {
    const table = globalThis.TC_I18N[tag];
    assert.deepEqual(Object.keys(table).sort(), Object.keys(en).sort(), `${tag} does not match en`);
    for (const [key, value] of Object.entries(table)) {
      assert.equal(typeof value, 'string', `${tag}/${key}`);
      assert.ok(value.trim().length > 0, `${tag}/${key} is empty`);
    }
  }
});

test('the page can only ask for keys the catalogue has, and asks for all of them', () => {
  const en = Object.keys(globalThis.TC_I18N.en);
  const missing = [...referencedKeys].filter(key => !en.includes(key));
  const unreferenced = en.filter(key => !referencedKeys.has(key));
  assert.deepEqual(missing, [], 'the page names a message that is not in the catalogue');
  assert.deepEqual(unreferenced, [], 'the catalogue carries a message nothing asks for');
});

test('no message id is computed — the source literals are the whole set', () => {
  // The one call that takes its key from data rather than from a literal is the static fill, and
  // its data is an attribute set in a file we ship. Everything else names a literal, which is what
  // makes "referenced" above an enumeration instead of a guess. (The app does this with a
  // `StaticString` parameter; JavaScript has no such type, so the property is asserted here.)
  const dynamic = [...optionsJs.matchAll(/\bt(?:HTML)?\(([^'\s)][^,)]*)/g)].map(m => m[1].trim());
  assert.deepEqual(dynamic, ['key', 'key', 'key'],
    'a message id is being computed somewhere other than the two declarations and the static fill');
  assert.ok(/node\.innerHTML = tHTML\(key, \.\.\.args\)/.test(optionsJs), 'the static fill moved');
});

test('placeholders match across locales, key by key', () => {
  // A translation that drops `%1$s` loses the label it was quoting; one that invents `%3$d` prints
  // the placeholder back at the user. Neither shows up as an error anywhere else.
  //
  // **Every locale, and it used to check only `ko`** — written when there were two catalogues, so
  // the three that arrived afterwards were never asked. Found by a toggle rather than by the run:
  // adding `%1$s` to a Chinese value passed. That is the same two-locale shape the layout test and
  // the refusal-wording tables carried, in a gate rather than in a fixture.
  for (const tag of TC_I18N_LOCALES) {
    if (tag === 'en') continue;
    for (const [key, value] of Object.entries(globalThis.TC_I18N.en)) {
      assert.deepEqual(
        placeholdersOf(globalThis.TC_I18N[tag][key]), placeholdersOf(value), `${tag}/${key}`,
      );
    }
  }
});

test('text and markup are separate halves, and nothing is on both', () => {
  // The rule the `t` / `tHTML` split exists for: a value that will be parsed as HTML must never be
  // reachable by the path that also carries what a user typed. A repository name goes into
  // `ext.validate.override.duplicate`, which is set with textContent — so it can only ever be text.
  //
  // The two sets are allowed to overlap and do: `ext.button.save` is a button's own label *and* the
  // label six sentences quote. What may not happen is the one direction that breaks something — a
  // value carrying markup being asked for as text, where the tags would be drawn as characters.
  for (const key of textKeys) {
    for (const tag of TC_I18N_LOCALES) {
      assert.deepEqual(tagsOf(globalThis.TC_I18N[tag][key]), [], `${tag}/${key} carries markup into textContent`);
    }
  }
  // and the converse, stated as the set it is: everything with a tag in it is markup-only
  for (const [key, value] of Object.entries(globalThis.TC_I18N.en)) {
    if (!tagsOf(value).length) continue;
    assert.ok(!textKeys.has(key), `${key} has markup and is asked for as text`);
    assert.ok(markupKeys.has(key), `${key} has markup and nothing asks for it as markup`);
  }
  assert.ok(textKeys.size > 30 && markupKeys.size > 30, 'the halves stopped being populated');
});

test('markup in a value is balanced, and the same in every locale', () => {
  // Markup rides in a value only when it decorates translated text — `<b>` on an emphasised word,
  // `<span class="faint">` on a gloss. The alternative is handing JavaScript the pieces of a
  // sentence to put back together, which is the defect the app unlearned across 25 fragments.
  const allowed = new Set(['<b>', '</b>', '<span>', '</span>', '<code>', '</code>']);
  for (const key of markupKeys) {
    const tags = tagsOf(globalThis.TC_I18N.en[key]);
    for (const tag of tags) assert.ok(allowed.has(tag), `${key} uses ${tag}`);
    assert.equal(tags.filter(t => t === '<b>').length, tags.filter(t => t === '</b>').length, `${key} <b>`);
    assert.equal(tags.filter(t => t === '<span>').length, tags.filter(t => t === '</span>').length, `${key} <span>`);
    assert.equal(tags.filter(t => t === '<code>').length, tags.filter(t => t === '</code>').length, `${key} <code>`);
    assert.deepEqual(tagsOf(globalThis.TC_I18N.ko[key]), tags, `ko/${key} has a different tag set`);
  }
});

test('what a <code> span holds is a literal, so it is identical in every locale', () => {
  // This is the half of the markup policy that matters: a tag around translated text may be
  // translated with it, but `<code>{branch_underbar}</code>` is a variable name, and a translation
  // that helpfully localises it produces a command the app rejects as an unknown variable.
  let compared = 0;
  for (const key of markupKeys) {
    const spans = codeSpansOf(globalThis.TC_I18N.en[key]);
    if (!spans.length) continue;
    assert.deepEqual(codeSpansOf(globalThis.TC_I18N.ko[key]), spans, `ko/${key} rewrote a literal`);
    compared += spans.length;
  }
  assert.ok(compared >= 20, `only ${compared} literals were compared`);
});

test('prose that names a control receives the label, it does not spell it out again', () => {
  // D28. The app found this class already broken — body text saying `[권한 요청]` next to a button
  // reading `iTerm2 권한 요청` — and the same drift was here: one paragraph called the field
  // `Face` and another called it `face`. A quotation is a relation between two messages now, so a
  // translator cannot make them disagree.
  const quoting = {
    'ext.section.pr.help1': ['ext.field.face', 'ext.field.tooltip'],
    'ext.section.pr.help2': ['ext.card.duplicate'],
    'ext.section.repo.help': ['ext.field.face'],
    'ext.section.backup.help2': ['ext.button.save'],
    'ext.status.reset': ['ext.button.save'],
    'ext.migration.intro.nothingToDo': ['ext.migration.gotIt'],
    'ext.migration.hint.reviewOnly': ['ext.button.save'],
    'ext.migration.hint.selected': ['ext.button.save'],
    'ext.migration.applied': ['ext.button.save'],
    'ext.migration.appliedWithDeclined': ['ext.button.save'],
    'ext.migration.markedReviewed': ['ext.button.save'],
    'ext.status.imported': ['ext.button.save'],
    'ext.status.importedWithNotes': ['ext.button.save'],
  };
  for (const [key, labels] of Object.entries(quoting)) {
    for (const tag of TC_I18N_LOCALES) {
      const value = globalThis.TC_I18N[tag][key];
      assert.ok(placeholdersOf(value).length >= labels.length, `${tag}/${key}: fewer placeholders than labels`);
    }
    // The relation itself, read off the source: wherever this message is asked for, the label
    // messages it quotes are asked for in the same breath. This is what a translator cannot break —
    // the value never contains the label, only a place for it.
    const windows = [...optionsJs.matchAll(new RegExp(`'${key.replace(/\./g, '\\.')}'`, 'g'))]
      .map(m => optionsJs.slice(m.index, m.index + 260));
    assert.ok(windows.length > 0, `${key} is not asked for anywhere`);
    for (const label of labels) {
      assert.ok(referencedKeys.has(label), `${key} quotes a missing ${label}`);
      assert.ok(windows.some(w => w.includes(`'${label}'`)), `${key} does not receive ${label}`);
    }
    // English also has to be free of the spelled-out label. Only English: a Korean label is a short
    // word that turns up inside ordinary ones (`저장` lives inside `저장된`), so the same check
    // there reports a hit that is not one — the relation above is what covers every language.
    const english = globalThis.TC_I18N.en[key];
    for (const label of labels) {
      const literal = globalThis.TC_I18N.en[label];
      const spelledOut = new RegExp(`(^|[^\\w>])${literal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^\\w<]|$)`);
      assert.ok(!spelledOut.test(english), `en/${key} spells "${literal}" out instead of quoting it`);
    }
  }
});

test('a count sits behind a noun, and the two outcomes are two messages', () => {
  // D31a. The English needed `command`/`commands` and `was`/`were` to agree with two counts, and a
  // translation cannot be assembled out of the pieces that made them agree — so the count moved
  // behind a noun and a colon, where nothing inflects, and each outcome became its own message.
  for (const tag of TC_I18N_LOCALES) {
    for (const key of ['ext.migration.applied', 'ext.migration.appliedWithDeclined']) {
      const value = globalThis.TC_I18N[tag][key];
      assert.ok(!/\(s\)/.test(value), `${tag}/${key} still carries an English plural marker`);
    }
  }
  assert.match(globalThis.TC_I18N.en['ext.migration.applied'], /^Commands updated in the form: %1\$d\./);
  // and the branch that produced the plural is gone from the source
  assert.ok(!/command\$\{applied === 1/.test(optionsJs), 'the plural branch is still in options.js');
  assert.ok(!/\? 'was' : 'were'/.test(optionsJs), 'the was/were branch is still in options.js');
});

test('the markup ships no prose, so there is nothing to paint in the wrong language', () => {
  // The first paint is the whole question on this page: unlike a GitHub page, which the user is
  // already reading when a button appears, the options page is text from edge to edge the moment it
  // opens. English left in the markup would be painted first and translated afterwards for every
  // user whose language is not English — so the markup holds ids and the fill happens while the
  // parser is still blocked on options.js, from `chrome.i18n.getUILanguage()`, which answers
  // without waiting. The cache the app fills corrects it a storage round trip later.
  for (const match of optionsHtml.matchAll(/data-i18n="[^"]+"[^>]*>([^<]*)</g)) {
    assert.equal(match[1].trim(), '', `a localized node still ships prose: ${match[0].slice(0, 70)}`);
  }
  // The synchronous first answer, and the asynchronous correction, in that order
  const first = optionsJs.indexOf('let uiLocale = setCurrentLocale(localeToRenderIn(null, browserLanguage()));');
  const fill = optionsJs.indexOf('applyStaticText();\n\n//');
  // The first cache read is no longer a bare call — it is the renderer's first notification, so it
  // takes its turn in the same queue as every later one (R12 C). What still has to hold is that it
  // happens *after* the synchronous fill.
  const adopt = optionsJs.indexOf('localeRenderer.start();');
  assert.ok(first > 0 && fill > first, 'the page no longer fills itself synchronously');
  assert.ok(adopt > fill, 'the cache is read before the synchronous fill, which reinstates the gap');
  assert.ok(
    !/^adoptLocaleFromCache\(\);$/m.test(optionsJs),
    'the first adoption is outside the queue again',
  );
});

test('formatMessage: positional, uninterpreted, and loud about a hole', () => {
  const { formatMessage } = vm.runInThisContext('({ formatMessage })');
  assert.equal(formatMessage('Press %1$s to apply.', ['Save']), 'Press Save to apply.');
  // Reordered by the translation, which is the whole reason the digits are there
  assert.equal(formatMessage('%2$d개 중 %1$d개 선택됨', [3, 7]), '7개 중 3개 선택됨');
  assert.equal(formatMessage('no placeholders', ['x']), 'no placeholders');
  assert.equal(formatMessage('%1$s', []), '%1$s', 'a missing argument printed undefined');
  assert.equal(formatMessage('%1$s', [0]), '0', 'a falsy argument was treated as missing');
  // A value is data, not a format language: nothing else is touched, including what an argument says
  assert.equal(formatMessage('100% sure %1$s', ['— %2$s']), '100% sure — %2$s');
});

// ---------------------------------------------------------------------------------------------
// The lifecycle the reducer lives in (R11).
//
// The reducer's own tests all passed while three defects sat in the paths that own it: a fence that
// blocked the next service worker forever, a read-reduce-write that could interleave with itself,
// and a first render that raced the cache read. That is the third harness shape this loop has found
// — **a pure function or a source lint passes while the asynchronous, lifecycle-owning path around
// it is never driven** — and these tests exist to drive it.
// ---------------------------------------------------------------------------------------------

test('a fresh worker is not fenced out by the sequence its predecessor persisted', () => {
  // The reproduction, exactly: `appliedSeq` is persisted and the counter is not, so the next
  // worker's first request is `seq: 1` against a cached `appliedSeq: 10`. Under the old rule that
  // response — a different install id, therefore a different app — was refused, and every response
  // after it too. The profile was stuck in the old language until storage was cleared.
  const stale = { locale: 'ko', installId: 'install-a', epoch: 3, appliedSeq: 10, appliedSeqScope: 'worker-1' };
  const fresh = { locale: 'ja', installId: 'install-b', epoch: 0, seq: 1, seqScope: 'worker-2' };
  const result = localeCacheUpdate(stale, fresh);
  assert.equal(result.changed, true, 'a new worker was fenced out by the previous worker’s number');
  assert.equal(result.cache.locale, 'ja');
  assert.equal(result.cache.appliedSeq, 1);
  assert.equal(result.cache.appliedSeqScope, 'worker-2');
});

test('the fence still holds inside one worker', () => {
  // The half that must not be lost with the fix: within a lifetime the numbers are comparable, and
  // an older request answering late is still refused (D50/D81).
  const applied = localeCacheUpdate(cache(), generation({ installId: 'install-b', epoch: 0, seq: 11 }));
  assert.equal(applied.changed, true);
  const late = localeCacheUpdate(applied.cache, generation({ installId: 'install-c', epoch: 0, seq: 9 }));
  assert.equal(late.changed, false, 'a late response from the same worker overwrote a newer one');
  assert.deepEqual(late.cache, applied.cache);
});

test('a cache with no scope is still a language, and never fences', () => {
  // What an upgrade finds in storage: a cache this version did not write. It is a perfectly good
  // answer to "what language" — the user keeps their language across the upgrade — but its number
  // was minted by a worker that no longer exists, so it cannot refuse anything.
  const old = { locale: 'ko', installId: 'install-a', epoch: 3, appliedSeq: 10 };
  assert.equal(isUsableLocaleCache(old), true, 'an upgrade threw the language away');
  assert.equal(localeToRenderIn(old, 'en-US'), 'ko');
  const result = localeCacheUpdate(old, generation({ installId: 'install-b', epoch: 0, seq: 1 }));
  assert.equal(result.changed, true, 'a scopeless cache fenced out the worker that replaced it');
});

test('a negative sequence is refused rather than compared', () => {
  assert.equal(isUsableLocaleCache(cache({ appliedSeq: -1 })), false);
  assert.equal(
    localeGenerationOf({ success: true, locale: 'ja', locale_install_id: 'a', locale_epoch: 0 }, -3, WORKER),
    null,
  );
  // and a generation with no scope cannot be ordered, so it is not a generation
  assert.equal(
    localeGenerationOf({ success: true, locale: 'ja', locale_install_id: 'a', locale_epoch: 0 }, 1, ''),
    null,
  );
  assert.equal(
    localeGenerationOf({ success: true, locale: 'ja', locale_install_id: 'a', locale_epoch: 0 }, 1, undefined),
    null,
  );
});

test('a refused command still tells us the language', () => {
  // The reversal (R11 C): the app attaches its publication to everything it composes, including a
  // validation failure, because a failure can be the first successful contact with the running app
  // — the cold-start query never ran, or an older app answered it, and then the relay launches this
  // app and it refuses the command. Under the success-only rule that response said nothing.
  const refused = {
    success: false,
    error: 'Unknown variable: {evil}',
    locale: 'ja',
    locale_install_id: 'install-b',
    locale_epoch: 2,
  };
  const incoming = localeGenerationOf(refused, 11, WORKER);
  assert.deepEqual(incoming, {
    locale: 'ja', installId: 'install-b', epoch: 2, seq: 11, seqScope: WORKER,
  });
  assert.equal(localeCacheUpdate(cache(), incoming).changed, true);
});

test('concurrent locale cache updates are serialized', async () => {
  // The defect this drives: read, reduce, write, with awaits in between and nothing holding the
  // door. Request 12 reads and writes first; request 11 read the same old value and writes second;
  // the reducer's fence never saw request 12 because it was handed the cache from before it. The
  // cache goes backwards and every page is told to redraw in the older language.
  //
  // Forced, not hoped for: the first read is held open until the second update has been started.
  let stored = cache();
  const notified = [];
  let releaseFirstRead;
  const firstRead = new Promise((resolve) => { releaseFirstRead = resolve; });
  let reads = 0;

  const apply = createLocaleCacheWriter({
    async read() {
      reads += 1;
      if (reads === 1) await firstRead; // hold request 12 inside its read
      return stored;
    },
    async write(cache) { stored = cache; },
    async notify(locale) { notified.push(locale); },
  });

  const twelve = apply(generation({ locale: 'ja', epoch: 4, seq: 12 }));
  const eleven = apply(generation({ locale: 'en', epoch: 5, seq: 11 }));
  releaseFirstRead();
  await Promise.all([twelve, eleven]);

  assert.equal(stored.appliedSeq, 12, `the cache regressed to seq ${stored.appliedSeq}`);
  assert.equal(stored.locale, 'ja');
  assert.deepEqual(notified, ['ja'], 'a page was told to redraw in the older language');
});

test('a serialized update that fails does not stop the ones behind it', async () => {
  // The queue is a chain, and a chain that adopts a rejection stops. One failed write must not make
  // the extension deaf to every later response.
  let stored = cache();
  let writes = 0;
  const apply = createLocaleCacheWriter({
    async read() { return stored; },
    async write(next) {
      writes += 1;
      if (writes === 1) throw new Error('storage full');
      stored = next;
    },
    async notify() {},
  });

  // **It resolves rather than rejecting, and that assertion used to read `rejects`.** The rejection
  // had exactly one production consumer — the send path — and that consumer awaited it before
  // deciding what to tell the page, so a storage failure became a failed command. There is nothing a
  // caller can usefully do with this failure, so it does not get the chance.
  const failed = await apply(generation({ epoch: 4, seq: 11 }));
  assert.equal(failed, null, 'a failed cache update reached its caller');
  await apply(generation({ locale: 'en', epoch: 5, seq: 12 }));
  assert.equal(stored.locale, 'en', 'the queue stopped after one failure');
});

test('nothing is written and nobody is told when the reducer says no', async () => {
  let writes = 0;
  let notifications = 0;
  const apply = createLocaleCacheWriter({
    async read() { return cache(); },
    async write() { writes += 1; },
    async notify() { notifications += 1; },
  });
  await apply(null);                                    // no metadata on the response at all
  await apply(generation({ epoch: 3, seq: 11 }));       // same epoch, so no advance
  assert.equal(writes, 0);
  assert.equal(notifications, 0);
});

test('initial render uses a valid cached locale', async () => {
  // The first draw waited for nothing, so a valid Korean cache lost to the English fallback — and
  // if the app's answer then equalled the cache, the reducer reported no change, no notification
  // went out, and nothing repaired the page. Reading `storage.local` is not waiting for the app,
  // which is the only thing D15 forbids.
  //
  // The read is delayed here while a draw is attempted immediately, which is the shape of the race.
  let resolveRead;
  const read = new Promise((resolve) => { resolveRead = resolve; });
  let locale = TC_I18N_FALLBACK;
  const ready = createFirstRenderGate(async () => {
    await read;
    locale = localeToRenderIn(cache(), 'en-US');
    return locale;
  });

  const drawn = [];
  const draw = async () => { await ready(); drawn.push(locale); };
  const first = draw();
  const second = draw();
  assert.deepEqual(drawn, [], 'a button was drawn before the cache had been read');
  resolveRead();
  await Promise.all([first, second]);
  assert.deepEqual(drawn, ['ko', 'ko'], 'the first render used the fallback despite a valid cache');
});

test('the cache is read once however many times the page tries to draw', async () => {
  let reads = 0;
  const ready = createFirstRenderGate(async () => { reads += 1; });
  await Promise.all([ready(), ready(), ready()]);
  await ready();
  assert.equal(reads, 1, `the gate read the cache ${reads} times`);
});

test('a gate whose read fails still lets the page draw', async () => {
  // A rejected gate would be no buttons, forever. An unreadable cache is a language we do not know,
  // not a page we refuse to render.
  const ready = createFirstRenderGate(async () => { throw new Error('storage unavailable'); });
  await ready();
  await ready();
});

test('the worker scope is minted per worker and rides on every request (lint)', () => {
  // The wiring needs a `chrome` global to exercise; what is pinned here is that the scope exists,
  // is not persisted anywhere, and reaches both the generation and nothing else.
  const source = read('background.js');
  assert.match(source, /const workerSequenceScope = /, 'the worker scope is gone');
  assert.match(
    source,
    /nativeRequester\(message, workerSequenceScope\)/,
    'the request no longer carries the worker it was sent from',
  );
  assert.ok(
    !/storage\.(local|sync)\.set\([^)]*workerSequenceScope/.test(source),
    'the worker scope is being persisted, which would make it not a worker scope',
  );
  // and the orchestration is the serialized writer rather than a bare read-modify-write
  assert.match(source, /createLocaleCacheWriter\(\{/, 'the cache write is no longer serialized');
  assert.ok(
    !/const stored = await chrome\.storage\.local\.get\(\[TC_LOCALE_CACHE_KEY\]\);\n\s*const \{ cache/.test(source),
    'the unserialized read-reduce-write is back',
  );
  // ...and the send path is the composition a test can drive, not a copy written out here again
  assert.match(source, /createNativeRequester\(\{/, 'the worker writes its own send path again');
});

test('every path that draws waits on the gate, not just the first (lint)', () => {
  // Gating the initial call alone would leave the poll, the navigation events and the
  // MutationObserver drawing in the fallback — and the observer can fire before the initial run.
  const source = read('content.js');
  const body = source.slice(source.indexOf('async function tryInsertButton()'));
  assert.match(body.slice(0, 400), /await localeReady\(\);/, 'the draw no longer waits for the cache');
  assert.match(source, /const localeReady = createFirstRenderGate\(refreshLocaleToDrawIn\)/);
});

// ---------------------------------------------------------------------------------------------
// The rest of the extension's strings (item 22).
//
// The judgement this item turns on is **which strings a user actually sees**, and it has three
// answers rather than two. Visible: drawn on a page or the options form. Diagnostic: `console.*`,
// English by policy (D13/D27). And **latent** — written for a user, reaching only the console
// today, and locale-dependent the moment anything displays it. The refusal messages are that third
// kind, and pretending they were either of the other two is what a trace prevented.
// ---------------------------------------------------------------------------------------------

test('a preset says its name in the language being drawn, not the one it loaded in', () => {
  // The class item 21 found in the options page's dropdown, closed at the source this time: the
  // preset itself resolves when read, so no consumer has to remember to re-read it.
  const { setCurrentLocale, currentLocale } = vm.runInThisContext('({ setCurrentLocale, currentLocale })');
  const { PR_PRESETS, REPO_PRESETS } = vm.runInThisContext('({ PR_PRESETS, REPO_PRESETS })');
  const before = currentLocale();
  try {
    setCurrentLocale('en');
    const english = PR_PRESETS[0].name;
    setCurrentLocale('ko');
    assert.notEqual(PR_PRESETS[0].name, english, 'the preset name froze at load');
    // and a repository preset's face is text on the page, so it follows too
    setCurrentLocale('en');
    const englishFace = REPO_PRESETS[0].face;
    setCurrentLocale('ko');
    assert.notEqual(REPO_PRESETS[0].face, englishFace, 'the repository face froze at load');
  } finally {
    setCurrentLocale(before);
  }
});

test('the button drawn when nothing is stored follows the language too', () => {
  const { setCurrentLocale, currentLocale } = vm.runInThisContext('({ setCurrentLocale, currentLocale })');
  const { BUTTON_KINDS } = vm.runInThisContext('({ BUTTON_KINDS })');
  const before = currentLocale();
  try {
    setCurrentLocale('en');
    const english = BUTTON_KINDS.repo.defaults[0].face;
    setCurrentLocale('ko');
    assert.notEqual(BUTTON_KINDS.repo.defaults[0].face, english);
    // ...and what it runs does not, which is the half that must not move
    assert.equal(BUTTON_KINDS.repo.defaults[0].command, '{cd}');
  } finally {
    setCurrentLocale(before);
  }
});

test('a saved button keeps the words it was saved with', () => {
  // The residual, pinned so it stays a decision rather than a surprise: `toStoredButton` writes
  // text, so a button created in one language keeps that language after a switch. Following the
  // language would mean a persistent id in the stored schema — a SETTINGS_VERSION bump, which this
  // plan does not make.
  const { setCurrentLocale, currentLocale } = vm.runInThisContext('({ setCurrentLocale, currentLocale })');
  const { appendButton, toStoredButton, BUTTON_KINDS } =
    vm.runInThisContext('({ appendButton, toStoredButton, BUTTON_KINDS })');
  const before = currentLocale();
  try {
    setCurrentLocale('ko');
    const [added] = appendButton([], BUTTON_KINDS.pr);
    const stored = toStoredButton(added);
    setCurrentLocale('en');
    assert.equal(toStoredButton(stored).label, stored.label, 'a stored label moved with the language');
    assert.ok(stored.label.length > 0);
  } finally {
    setCurrentLocale(before);
  }
});

test('the messages that only reach a console are not in the dictionaries', () => {
  // The boundary, stated as a set. `console.*` is an English diagnostic surface by policy, and a
  // key for one of those would be a translation nobody reads — so the gate is that none of the
  // catalogue's values is one of these sentences.
  const values = new Set(Object.values(globalThis.TC_I18N.en));
  const diagnostics = [
    'This button no longer matches your saved settings — reload the page and try again.',
    'The page changed while this was running — reload and try again.',
    'Not a GitHub PR page',
    'Not a GitHub issue page',
    'Not a GitHub repo page',
    'Could not extract branch name',
  ];
  for (const sentence of diagnostics) {
    assert.ok(!values.has(sentence), `${sentence} was translated, but nothing displays it`);
  }
});

test('every file that draws sets the locale it draws in', () => {
  // One holder per context (`i18n.js`), and the two files that draw have to fill it — otherwise
  // `defaults.js` and `migrations.js`, which have no locale of their own, resolve against the
  // fallback while the page around them is in another language.
  assert.match(read('content.js'), /setCurrentLocale\(localeToRenderIn\(/, 'the content script draws in no particular language');
  assert.match(read('options.js'), /setCurrentLocale\(localeToRenderIn\(/, 'the options page draws in no particular language');
  // and the worker deliberately does not: it draws nothing, so it has no locale to set
  assert.ok(!/setCurrentLocale\(/.test(read('background.js')), 'the service worker set a render locale it cannot use');
});

// ---------------------------------------------------------------------------------------------
// Bookkeeping may not decide what a click reports (R12).
//
// The worst defect this work has found was not a wrong cache value; it was that the cache write was
// **reachable** from the answer a click gets. These pin the separation from both sides: the writer
// cannot fail, and the thing that decides the answer is never handed the writer at all.
// ---------------------------------------------------------------------------------------------

test('a storage failure does not turn an executed command into a failed one', async () => {
  // The repro, at the boundary the old test missed: storage refuses both reads and writes while the
  // app answers normally. The terminal is already open by the time any of this runs.
  const { nativeOutcome, startBookkeeping } = vm.runInThisContext('({ nativeOutcome, startBookkeeping })');
  const logged = [];
  const apply = createLocaleCacheWriter({
    async read() { throw new Error('storage.local.get failed'); },
    async write() { throw new Error('storage.local.set failed'); },
    async notify() {},
    log: (...parts) => logged.push(parts.join(' ')),
  });

  const success = { success: true, locale: 'ja', locale_install_id: 'b', locale_epoch: 1 };
  startBookkeeping(() => apply(localeGenerationOf(success, 1, WORKER)), 'locale cache update', () => {});
  const outcome = nativeOutcome(success);
  assert.equal(outcome.failed, false, 'an executed command was reported as a failure');
  assert.equal(outcome.response, success);

  // ...and the app's own diagnostic survives when the command really did fail
  const refused = { success: false, error: 'Unknown variable: {evil}', locale: 'ja', locale_install_id: 'b', locale_epoch: 1 };
  startBookkeeping(() => apply(localeGenerationOf(refused, 2, WORKER)), 'locale cache update', () => {});
  assert.deepEqual(nativeOutcome(refused), { failed: true, error: 'Unknown variable: {evil}' });

  await new Promise(resolve => setTimeout(resolve, 0));
  assert.ok(logged.length > 0, 'the storage failure vanished without a word');
});

test('a later locale response still updates the cache after storage recovers', async () => {
  let stored;
  let broken = true;
  const apply = createLocaleCacheWriter({
    async read() { if (broken) throw new Error('storage.local.get failed'); return stored; },
    async write(next) { if (broken) throw new Error('storage.local.set failed'); stored = next; },
    async notify() {},
    log: () => {},
  });
  await apply(generation({ seq: 11 }));
  assert.equal(stored, undefined);
  broken = false;
  await apply(generation({ locale: 'ja', epoch: 9, seq: 12 }));
  assert.equal(stored?.locale, 'ja', 'the writer stayed broken after storage came back');
});

test('what a click reports is a function of the response alone', () => {
  // Not "guarded against" the cache — **unable to see it**. The signature is the guarantee.
  const { nativeOutcome } = vm.runInThisContext('({ nativeOutcome })');
  assert.equal(nativeOutcome.length, 1, 'the outcome decision grew a second input');
  assert.deepEqual(nativeOutcome({ success: true, x: 1 }), { failed: false, response: { success: true, x: 1 } });
  assert.deepEqual(nativeOutcome({ success: false, error: 'nope' }), { failed: true, error: 'nope' });
  assert.deepEqual(nativeOutcome(undefined), { failed: true, error: 'native host returned no result' });
  assert.deepEqual(nativeOutcome({}), { failed: true, error: 'native host returned no result' });
  // a non-string error is not an error message
  assert.deepEqual(nativeOutcome({ success: false, error: 42 }), { failed: true, error: 'native host returned no result' });
});

test('startBookkeeping contains a rejection and a synchronous throw alike', async () => {
  const { startBookkeeping } = vm.runInThisContext('({ startBookkeeping })');
  const logged = [];
  const log = (...parts) => logged.push(parts.join(' '));
  assert.equal(startBookkeeping(() => Promise.reject(new Error('async')), 'x', log), undefined);
  assert.equal(startBookkeeping(() => { throw new Error('sync'); }, 'y', log), undefined);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(logged.length, 2, `only ${logged.length} failures were reported`);
});

test('a redraw that returns nothing is noticed rather than silently unserialized', async () => {
  // Class H, recurred in the promotion that named it: the options adapter started an asynchronous
  // redraw and returned nothing, so the queue had nothing to wait for — and the renderer's test did
  // not see it because the injected double *did* return a promise. A double politer than the
  // adapter it stands for is not a test of the adapter.
  let notify;
  const renderer = createLocaleRenderer({
    subscribe: (fn) => { notify = fn; },
    redraw() {},
    log: () => {},
  });
  renderer.start();
  await notify();
  assert.equal(renderer.unwaitableRedraws, 1, 'an unserializable redraw went unnoticed');

  let ok;
  const good = createLocaleRenderer({
    subscribe: (fn) => { ok = fn; },
    async redraw() {},
    log: () => {},
  });
  good.start();
  await ok();
  assert.equal(good.unwaitableRedraws, 0, 'a proper adapter was reported as unserializable');
});

test('the options page hands the renderer something it can wait for (lint)', () => {
  // The wiring needs `chrome` and a DOM to run; what is pinned is the shape the defect had.
  const source = read('options.js');
  assert.match(source, /redraw\(\) \{ return adoptLocaleFromCache\(\); \}/, 'the adapter drops its promise again');
  assert.ok(
    !/^adoptLocaleFromCache\(\);$/m.test(source),
    'the first adoption runs outside the queue again',
  );
  assert.match(source, /onLocaleChanged\(\);\n\s*\},/, 'the first read no longer goes through the queue');
});

test('a translation cannot break out of an HTML attribute', () => {
  // The card template interpolates messages into `title="…"` and `placeholder="…"`. The other gates
  // check tags and placeholders and would not notice a quote, and one `"` in a translation ends the
  // attribute and turns the rest of the sentence into markup.
  const attributeKeys = new Set(
    [...read('options.js').matchAll(/(?:title|placeholder|aria-label)="\$\{t\('(ext\.[A-Za-z0-9.]+)'/g)]
      .map(m => m[1]),
  );
  assert.ok(attributeKeys.size >= 5, `only ${attributeKeys.size} attribute interpolations found`);
  // **Every shipped language, not the two this used to visit.** Four loops in this file walked
  // `['en', 'ko']` because that is what existed when they were written, and three of the five are
  // the machine-translated first pass — the values most likely to carry a stray quote and the ones
  // nobody was checking. Measured: an English plural marker planted in `zh-Hant` passed the old
  // scope and fails this one. Widening them caught nothing in the shipped values, which says they
  // are clean, not that two of five was enough.
  for (const key of attributeKeys) {
    for (const tag of TC_I18N_LOCALES) {
      const value = globalThis.TC_I18N[tag][key];
      assert.ok(!value.includes('"'), `${tag}/${key} would close the attribute it is written into`);
      assert.ok(!value.includes('<'), `${tag}/${key} carries markup into an attribute`);
    }
  }
});

test('no text ships in the markup without a message behind it', () => {
  // Item 12's F class, on this side: a string nobody localized is invisible to a gate that only
  // inspects the elements already carrying `data-i18n`. This reads the other direction — every text
  // node in the body — and refuses anything not on the whitelist below.
  const html = read('options.html');
  const body = html.slice(html.indexOf('<body>'));
  // Whitelisted, with the reason each one is permanent:
  //   `terminal-checkout` / `Terminal Checkout` — the product and command name (an explicit non-goal)
  //   `❯` `▊` `⏎` `$` `⠿` `✕` `×` `●` `⚠` — symbols and cursors, which no language rewrites
  //   `/` `·` `-` — punctuation between them
  // A run of permanent pieces is permanent: the heading is `terminal-checkout ·` next to the
  // localized word, and the parser hands that back as one text node.
  const permanent = /^(terminal-checkout|Terminal Checkout|[❯▊⏎$⠿✕×●⚠·/\-—|\s])+$/;
  const stray = [];
  for (const match of body.matchAll(/>([^<>]+)</g)) {
    const text = match[1].replace(/\s+/g, ' ').trim();
    if (!text || permanent.test(text)) continue;
    stray.push(text);
  }
  assert.deepEqual(stray, [], 'markup carries text that no message owns');
});

// ---------------------------------------------------------------------------------------------
// The shape another gate depends on (item 20).
// ---------------------------------------------------------------------------------------------

test('a dictionary file is one JSON object, so the ownership gate can read it', () => {
  // `CatalogueOwnershipTests` is the only place that can see all three catalogues at once — Swift
  // parses `.strings` natively — and it reads these files as text rather than running them. That
  // works because the body of the assignment is JSON apart from its trailing comma. The assumption
  // is asserted **here**, on the side that owns these files, so a hand edit that breaks it fails
  // where its author is looking rather than in a Swift test about the app.
  for (const tag of TC_I18N_LOCALES) {
    const source = read(`_i18n/${tag}.js`);
    const opening = source.indexOf('] = {');
    const closing = source.lastIndexOf('};');
    assert.ok(opening > 0 && closing > opening, `${tag}.js no longer assigns one object literal`);
    const body = `${source.slice(opening + 4, closing)}}`.replace(/,(\s*)\}$/, '$1}');
    let parsed;
    assert.doesNotThrow(() => { parsed = JSON.parse(body); }, `${tag}.js is not readable as JSON`);
    // and it agrees with what running the file produced, which is the real dictionary
    assert.deepEqual(parsed, globalThis.TC_I18N[tag], `${tag}.js reads differently as text and as code`);
  }
});

// ---------------------------------------------------------------------------------------------
// What only becomes checkable once five locales exist (items 23/24).
// ---------------------------------------------------------------------------------------------

// A command literal: something the user is meant to type or that names a variable the app
// substitutes. Translating one does not read oddly — it produces a command that does not work.
//
// The `<code>` gate above cannot see these: `describe`, `prefixDescribe` and `customNote` are plain
// sentences with `{cd}` and `z {repo}` inside them, no markup at all. So the rule here is about the
// *shape of the token*, not about the markup around it.
//
// **Word boundaries, and the first version of this gate needed them.** Written as plain substrings
// it counted `gh` inside the English word "ri`gh`t" and reported a Korean translation as having lost
// a command — a false positive on its very first run. A gate that cries wolf is a gate somebody
// switches off (the standard item 7 set), so the bare-word literals are matched as words.
const COMMAND_LITERALS = [
  /\{cd\}/g, /\{repo\}/g, /\{owner\}/g, /\{number\}/g, /\{branch\}/g, /\{base\}/g,
  /\{main\}/g, /\{branch_underbar\}/g, /z \{repo\}/g,
  /\bstorage\.sync\b/g, /chrome:\/\/extensions/g, /\bgit pull\b/g,
  /\bgh\b/g, /\bclaude\b/g, /\bzoxide\b/g, /\bbrew install\b/g,
];

test('a command literal reads the same in every language', () => {
  // The most dangerous thing a translator can do to this catalogue is translate `z {repo}`. It is
  // not a phrase; it is what the user's button will run. These sit in plain sentences with no
  // markup around them, so the `<code>` gate above cannot see them.
  let compared = 0;
  for (const [key, english] of Object.entries(globalThis.TC_I18N.en)) {
    for (const literal of COMMAND_LITERALS) {
      const expected = (english.match(literal) ?? []).length;
      if (expected === 0) continue;
      for (const tag of TC_I18N_LOCALES) {
        const value = globalThis.TC_I18N[tag][key];
        if (value === undefined) continue; // the key gate above owns that failure
        const found = (value.match(literal) ?? []).length;
        assert.equal(
          found, expected,
          `${tag}/${key}: ${literal} appears ${found} times, en has ${expected}`,
        );
      }
      compared += 1;
    }
  }
  assert.ok(compared >= 20, `only ${compared} literal occurrences were compared`);
});

// Characters that are written differently in simplified and traditional Chinese. Each pair is one
// character, and each is chosen because the two scripts genuinely disagree about it — a character
// both scripts share would make this check assert nothing at all.
const SCRIPT_PAIRS = [
  ['设', '設'], // set / settings
  ['开', '開'], // open
  ['关', '關'], // close
  ['应', '應'], // should, apply
  ['键', '鍵'], // key
  ['变', '變'], // change
  ['储', '儲'], // store
  ['执', '執'], // execute
];

test('the two Chinese catalogues are not one script converted into the other', () => {
  // Keys and placeholders cannot tell these apart, and neither can a length check: a `zh-Hant` that
  // is a copy of `zh-Hans`, or of English, satisfies every other gate in this file. What separates
  // them is the writing system, so that is what is asked about.
  const hans = globalThis.TC_I18N['zh-Hans'];
  const hant = globalThis.TC_I18N['zh-Hant'];
  const en = globalThis.TC_I18N.en;
  const joined = table => Object.values(table).join('\n');

  const hansText = joined(hans);
  const hantText = joined(hant);
  assert.notEqual(hansText, hantText, 'zh-Hant is a copy of zh-Hans');
  assert.notEqual(hantText, joined(en), 'zh-Hant is a copy of English');
  assert.notEqual(hansText, joined(en), 'zh-Hans is a copy of English');

  let checked = 0;
  for (const [simplified, traditional] of SCRIPT_PAIRS) {
    const inHans = hansText.includes(simplified);
    const inHant = hantText.includes(traditional);
    if (!inHans && !inHant) continue;
    checked += 1;
    assert.ok(
      !hantText.includes(simplified),
      `zh-Hant contains the simplified form "${simplified}"`,
    );
    assert.ok(
      !hansText.includes(traditional),
      `zh-Hans contains the traditional form "${traditional}"`,
    );
  }
  assert.ok(checked >= 4, `only ${checked} script-sensitive characters were found to compare`);
});

test('a translation that is still English is caught where English is not the answer', () => {
  // A value byte-identical to English is the fingerprint of a key that was skipped. It is also
  // legitimate for a product name, a command, or a bare number — so this counts rather than
  // forbids, and the threshold is what makes it a gate instead of a nuisance. **A gate people turn
  // off is worse than no gate** (the standard item 7 set), and a per-key rule here would fire on
  // `main branch` and `Terminal Checkout` forever.
  const en = globalThis.TC_I18N.en;
  const total = Object.keys(en).length;
  for (const tag of TC_I18N_LOCALES) {
    if (tag === 'en') continue;
    const identical = Object.entries(en).filter(([key, value]) => globalThis.TC_I18N[tag][key] === value);
    assert.ok(
      identical.length < total * 0.2,
      `${tag}: ${identical.length}/${total} values are byte-identical to English — `
        + `${identical.slice(0, 5).map(([k]) => k).join(', ')}`,
    );
  }
});
