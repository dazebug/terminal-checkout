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

test('the key spaces are separate, whatever is in them', () => {
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

// Every message id the page can name. `options.js` can only name one with a literal (checked
// below), and `options.html` names them in an attribute — so between them this is the whole set.
const keysInJs = new Set([...optionsJs.matchAll(/'(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]));
const keysInHtml = new Set([...optionsHtml.matchAll(/data-i18n="([^"]+)"/g)].map(m => m[1]));
const referencedKeys = new Set([...keysInJs, ...keysInHtml]);

// Which half of the text/markup split a key is on. A key reached through `t(` becomes textContent,
// a title or a `confirm()`; a key reached through `tHTML(` or `data-i18n` becomes innerHTML.
const textKeys = new Set([...optionsJs.matchAll(/\bt\('(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]));
const markupKeys = new Set([
  ...[...optionsJs.matchAll(/\btHTML\('(ext\.[A-Za-z0-9.]+)'/g)].map(m => m[1]),
  ...keysInHtml,
]);

const placeholdersOf = value => (value.match(/%\d+\$[sd]/g) ?? []).sort();
const tagsOf = value => (value.match(/<\/?[a-z][^>]*>/g) ?? []).map(tag => tag.replace(/\s+class="[^"]*"/, '')).sort();
const codeSpansOf = value => (value.match(/<code>[^<]*<\/code>/g) ?? []).sort();

test('en and ko carry the same keys, and every value says something', () => {
  const en = globalThis.TC_I18N.en;
  const ko = globalThis.TC_I18N.ko;
  assert.deepEqual(Object.keys(ko).sort(), Object.keys(en).sort());
  assert.ok(Object.keys(en).length >= 89, `the catalogue shrank to ${Object.keys(en).length}`);
  for (const [tag, table] of [['en', en], ['ko', ko]]) {
    for (const [key, value] of Object.entries(table)) {
      assert.equal(typeof value, 'string', `${tag}/${key}`);
      assert.ok(value.trim().length > 0, `${tag}/${key} is empty`);
    }
  }
  // ja and zh are item 24's; leaving them empty here is the state, not an oversight
  for (const tag of ['ja', 'zh-Hans', 'zh-Hant']) {
    assert.deepEqual(Object.keys(globalThis.TC_I18N[tag]), [], `${tag} was filled early`);
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
  for (const [key, value] of Object.entries(globalThis.TC_I18N.en)) {
    assert.deepEqual(placeholdersOf(globalThis.TC_I18N.ko[key]), placeholdersOf(value), `ko/${key}`);
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
    for (const tag of ['en', 'ko']) {
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
    for (const tag of ['en', 'ko']) {
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
    // there reports a hit that is not one — the relation above is what covers both languages.
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
  for (const tag of ['en', 'ko']) {
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
  const first = optionsJs.indexOf('uiLocale = localeToRenderIn(null, browserLanguage());');
  const fill = optionsJs.indexOf('applyStaticText();\n\n// And the app');
  const adopt = optionsJs.indexOf('adoptLocaleFromCache();\n');
  assert.ok(first > 0 && fill > first, 'the page no longer fills itself synchronously');
  assert.ok(adopt > fill, 'the cache is read before the synchronous fill, which reinstates the gap');
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
