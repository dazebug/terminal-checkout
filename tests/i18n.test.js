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

test('the key spaces are separate before there are keys to sort', () => {
  for (const tag of TC_I18N_LOCALES) {
    for (const key of Object.keys(globalThis.TC_I18N[tag])) {
      assert.ok(key.startsWith('ext.'), `${tag} carries ${key}, which is not in the extension's space`);
    }
  }
  // `chrome.i18n`'s namespace holds exactly the two keys a manifest cannot fill any other way (D9)
  for (const tag of ['en', 'ko']) {
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

const cache = (over = {}) => ({ locale: 'ko', installId: 'install-a', epoch: 3, appliedSeq: 10, ...over });
const generation = (over = {}) => ({ locale: 'ja', installId: 'install-a', epoch: 4, seq: 11, ...over });

test('a different installId is adopted unconditionally, and a late response from the prior install does not undo it', () => {
  const reset = localeCacheUpdate(cache(), generation({ installId: 'install-b', epoch: 0, seq: 11 }));
  assert.equal(reset.changed, true);
  assert.deepEqual(reset.cache, { locale: 'ja', installId: 'install-b', epoch: 0, appliedSeq: 11 });

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

test('a failed query writes nothing and notifies nobody', () => {
  const start = cache();
  for (const response of [null, undefined, { success: false, error: 'command_template is required' }, {}]) {
    const result = localeCacheUpdate(start, localeGenerationOf(response, 11));
    assert.equal(result.changed, false, `${JSON.stringify(response)} changed the cache`);
    assert.deepEqual(result.cache, start);
  }
});

test('a successful response without locale metadata preserves the cache', () => {
  // The ordinary command path, carrying a real result and no generation — not a discarded throat
  const response = { success: true };
  const result = localeCacheUpdate(cache(), localeGenerationOf(response, 11));
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
    assert.deepEqual(adopted.cache, { locale: 'ja', installId: 'install-a', epoch: 4, appliedSeq: 11 });
  }
});

test('an unknown locale in a response is not a generation', () => {
  for (const locale of ['fr', 'zh', 'KO', '', null, 42]) {
    assert.equal(
      localeGenerationOf({ success: true, locale, locale_install_id: 'a', locale_epoch: 1 }, 1),
      null,
      String(locale),
    );
  }
  assert.deepEqual(localeGenerationOf({ locale: 'ko', locale_install_id: 'a', locale_epoch: 1 }, 1), {
    locale: 'ko', installId: 'a', epoch: 1, seq: 1,
  });
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
    assert.equal(localeGenerationOf(response, 1), null, JSON.stringify(response));
  }
  // and the sequence has to be one of ours, not whatever a caller passed
  assert.equal(localeGenerationOf(base, undefined), null);
  assert.equal(localeGenerationOf(base, '3'), null);
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
  const renderer = createLocaleRenderer({
    subscribe: notify => { notify(); },
    redraw: () => { redraws += 1; },
  });
  renderer.start(); // the subscription fires a redraw immediately, mid-click
  assert.equal(redraws, 1);
  assert.equal(button.feedback, null, 'the click finished early — the case proves nothing');

  released();
  await click;
  assert.equal(button.feedback, 'done', 'a redraw during the click lost its result');
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

test('the generation is taken off a response before a failure is raised (lint)', () => {
  // A **lint**: it reads the source, not the behaviour. The wiring it pins needs a `chrome` global
  // to exercise, and what the reducer does with the extracted value is covered above — what is left
  // uncovered is only "does the send path extract at all, and before it throws", which is exactly
  // the line that used to lose the metadata.
  const source = read('background.js');
  const extract = source.indexOf('await applyLocaleGeneration(response, seq)');
  const raise = source.indexOf("if (!response?.success) throw new Error(");
  assert.ok(extract > 0, 'the send path no longer reads the generation off a response');
  assert.ok(raise > 0, 'the failure is no longer raised on the button');
  assert.ok(extract < raise, 'the failure is raised before the generation is read, which loses it');
  // and every request takes a number of ours, which is what the fence orders by
  assert.ok(/const seq = \+\+nativeRequestSeq;/.test(source), 'requests are no longer numbered');
});
