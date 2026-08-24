// The mixed-generation execution matrix: A3's completion condition, and the first implementation
// evidence for the class that took four design reviews to state.
//
// **Why existence checks were not enough.** Compatibility was scoped to "the files the old reader
// imports are still there", then to "the file names match", then to "`tr` still exists" — each true
// for the set it named and silent about the next set out. What an adjacent generation needs is
// **behaviour**: the interface between those files. So this runs them, both ways round, and lets a
// missing symbol surface as a throw instead of as an omission from somebody's list (D164, D170).
//
// **And running the top of each file was not enough either** (D175). Two of the symbols an old
// consumer reaches for are referenced only from deferred code — a callback handed to a requester, a
// cache read inside a first-render gate — so initialization alone passes against a stub that throws
// and against a symbol that is not there at all. Every named lifecycle boundary is driven here:
// the native response's bookkeeping and its outcome, the content script's locale notification, the
// options page's storage notification.
//
// **The old side is the real artifact.** `tests/fixtures/baseline/` holds the scripts as they were at
// the last commit before the lookup changed, and the hashes below pin them — computed over the exact
// bytes the realm executes, because hashing the file while feeding something else makes the pin
// decorative (D186).
'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const { generationRealm } = require('./realm.js');
const { catalogueBackend } = require('./chrome-messages.js');

const BASELINE_HASHES = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'baseline', 'HASHES.json'), 'utf8'));

// **The load order is read from the generation, never written here.** The service worker names its
// own list with `importScripts`, the content script's list is the manifest's, and the options page's
// is the script tags in its markup — so a consumer that starts loading something new is loaded that
// way here too, rather than against a list in a test that would go stale silently.
const loadOrder = (consumer, side) => {
  const directory = side === 'baseline' ? path.join(__dirname, 'fixtures', 'baseline') : path.join(__dirname, '..', 'extension');
  if (consumer === 'background.js') return ['background.js'];  // it imports its own dependencies
  if (consumer === 'content.js') {
    const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
    return manifest.content_scripts.flatMap(entry => entry.js);
  }
  const markup = fs.readFileSync(path.join(directory, 'options.html'), 'utf8');
  return [...markup.matchAll(/<script src="([^"]+)"><\/script>/g)].map(match => match[1]);
};

const load = (realm, consumer, side) => {
  for (const file of loadOrder(consumer, side)) realm.feed(file);
};

const CONSUMERS = ['background.js', 'content.js', 'options.js'];

// The four pairings. "baseline × baseline" is not redundant: it is the control that says the harness
// can run the old generation at all, so a failure in a mixed pairing is about the mixture.
const PAIRINGS = [
  { skeleton: 'current', consumers: 'current', what: 'the migrated tree' },
  { skeleton: 'baseline', consumers: 'current', what: 'the old skeleton under new consumers' },
  { skeleton: 'current', consumers: 'baseline', what: 'the new skeleton under old consumers' },
  { skeleton: 'baseline', consumers: 'baseline', what: 'the baseline, as a control' },
];

// Chrome answers from the shipped catalogue, so a raw key or a blank is visible as itself.
const platformFor = (directory = 'ja') => {
  const backend = catalogueBackend(directory);
  return { getMessage: (id, subs) => backend(id, subs), uiLanguage: directory === 'zh_CN' ? 'zh-CN' : directory };
};

const drained = () => new Promise(resolve => setImmediate(resolve));

// A document language is a dictionary tag; a catalogue lives in Chrome's directory spelling. The two
// stores agree on the values themselves — that is what `tools/check-locales.js` holds — so either can
// answer for "what does this catalogue say", and `_locales` is the one that is canonical now.
const CHROME_DIRECTORY = { en: 'en', ko: 'ko', ja: 'ja', 'zh-Hans': 'zh_CN', 'zh-Hant': 'zh_TW' };

test('every generation pairing loads, and the baseline it loads is the pinned artifact', () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    for (const consumer of CONSUMERS) {
      const realm = generationRealm({ skeleton, consumers, platform: platformFor() });
      load(realm, consumer, consumers);
      // Nothing here asserts a file list. What is asserted is that the combination ran: a symbol the
      // other generation does not provide would have thrown by now.
      assert.ok(Object.keys(realm.fed).length > 0, `${what}: ${consumer} loaded nothing`);
      for (const [file, hash] of Object.entries(realm.fed)) {
        if (!file.startsWith('tests/fixtures/baseline/')) continue;
        assert.equal(
          hash, BASELINE_HASHES[file],
          `${file} is not the baseline artifact this matrix was pinned to — the bytes fed to the realm differ`,
        );
      }
    }
  }
  // ...and the pin covers every baseline file, not only the ones some pairing happened to load
  const missing = Object.keys(BASELINE_HASHES).filter(file => !fs.existsSync(path.join(__dirname, '..', file)));
  assert.deepEqual(missing, [], 'the pin names a baseline artifact that is not in the tree');
});

test('a native response settles while its bookkeeping is deliberately unfinished', async () => {
  // **The oracle inverts here, and this is the one that came from our own mistake** (D180). An
  // earlier revision of the plan required the matrix to drain every promise it started; the code says
  // the opposite in plain words — "the bookkeeping is started, not awaited, and it cannot fail this
  // call" — because awaiting it once turned an already-executed command into a reported failure, and
  // a person who presses a button again after a false failure runs the command twice.
  //
  // So the bookkeeping is **held** while the result is observed, and only then released.
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  let reads = 0;
  const realm = generationRealm({
    skeleton: 'current',
    consumers: 'current',
    platform: {
      ...platformFor(),
      holdLocalGet: () => { reads += 1; return held; },
      nativeResponse: () => ({ success: true, locale: 'ja', locale_install_id: 'install-a', locale_epoch: 3 }),
    },
  });
  load(realm, 'background.js', 'current');
  const outcome = realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })');
  const settled = await outcome;
  assert.equal(settled.success, true, 'the command result waited for the bookkeeping');
  assert.equal(reads, 1, 'the bookkeeping never started');
  assert.deepEqual(realm.calls.set, [], 'the bookkeeping finished before the result, so it was awaited');
  // Released only after the result was observed, and then it completes on its own.
  release({});
  await drained();
  assert.equal(realm.calls.set.length, 1, 'the held bookkeeping never resumed');
  assert.equal(realm.calls.set[0].localeCache.locale, 'ja');
});

test('a refused command stays exactly that refusal, whatever the bookkeeping does', async () => {
  const realm = generationRealm({
    skeleton: 'current',
    consumers: 'current',
    platform: {
      ...platformFor(),
      nativeResponse: () => ({ success: false, error: 'Variable {repo} not provided' }),
    },
  });
  load(realm, 'background.js', 'current');
  await assert.rejects(
    realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })'),
    /Variable \{repo\} not provided/,
    'the refusal was replaced by something else',
  );
});

test('bookkeeping that fails, synchronously or asynchronously, changes and delays nothing', async () => {
  for (const [how, storage] of [
    ['synchronously', { holdLocalGet: () => { throw new Error('storage exploded'); } }],
    ['asynchronously', { holdLocalGet: () => Promise.reject(new Error('storage rejected')) }],
  ]) {
    const realm = generationRealm({
      skeleton: 'current',
      consumers: 'current',
      platform: {
        ...platformFor(),
        ...storage,
        nativeResponse: () => ({ success: true, locale: 'ko', locale_install_id: 'install-b', locale_epoch: 1 }),
      },
    });
    load(realm, 'background.js', 'current');
    const settled = await realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })');
    assert.equal(settled.success, true, `bookkeeping failing ${how} changed the command result`);
    await drained();
    assert.deepEqual(realm.calls.set, [], `bookkeeping failing ${how} still wrote`);
  }
});

test('the deferred boundaries run: a locale notification and a storage notification, in every pairing', async () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    // The content script's locale notification — the message listener is registered at load and the
    // work behind it is deferred, which is exactly where an initialization-only matrix sees nothing.
    const content = generationRealm({ skeleton, consumers, platform: platformFor() });
    load(content, 'content.js', consumers);
    assert.ok(content.listeners.message.length > 0, `${what}: content.js registered no message listener`);
    for (const listener of content.listeners.message) {
      listener({ action: 'localeChanged', locale: 'ja' }, {}, () => {});
    }
    await drained();

    // The options page's storage notification, likewise.
    const options = generationRealm({ skeleton, consumers, platform: platformFor() });
    load(options, 'options.js', consumers);
    assert.ok(options.listeners.storageChanged.length > 0, `${what}: options.js registered no storage listener`);
    for (const listener of options.listeners.storageChanged) {
      listener({ buttons: { newValue: [] } }, 'sync');
    }
    await drained();
  }
});

test('what the page drew and what the document says are the same catalogue, in every pairing', async () => {
  // **The oracle used to run on one pairing while the load matrix ran on four** (review 39), and both
  // mixed combinations were broken underneath it: the signature of `applyDocumentLanguage` and its
  // call site had moved in opposite directions, so one wrote `en` over Japanese text and the other
  // left the tag untouched. Four pairings loaded and one pairing asserted is the same disease this
  // matrix exists for — a check whose scope is narrower than the set its name promises — arriving
  // **inside the instrument**. So the assertion dimension is generalised to match the load dimension.
  //
  // **And it reads `document.title`, not a call of its own.** Asking `tr` here would prove that *this
  // test* can look a message up; the title is what the page actually drew. It is the same distinction
  // `CLAUDE.md` draws for claude input: seeing our text on screen is not evidence it is in the input
  // box, and the only attribution obtainable from outside is what the thing under test left behind.
  for (const { skeleton, consumers, what } of PAIRINGS) {
    for (const directory of ['en', 'ja', 'zh_TW']) {
      const realm = generationRealm({ skeleton, consumers, platform: platformFor(directory) });
      load(realm, 'options.js', consumers);
      await drained();
      const tag = realm.context.document.documentElement.lang;
      const title = realm.context.document.title;
      assert.ok(tag, `${what} (${directory}): the page never set a document language`);
      assert.ok(title, `${what} (${directory}): the page never set a title`);
      // The title is `Terminal Checkout — <the header message>`, so the message the page drew is what
      // follows the dash. The catalogue to compare against is the one the document names — that is
      // the pair being checked, rather than an assumption about which store answered.
      const drawn = title.slice(title.indexOf('—') + 1).trim();
      const expected = catalogueBackend(CHROME_DIRECTORY[tag])('ext_header_options');
      assert.equal(
        drawn, expected,
        `${what} (${directory}): the page drew ${JSON.stringify(drawn)} while calling itself ${tag}`,
      );
      assert.ok(!drawn.startsWith('ext'), `${what} (${directory}): a raw key reached the title`);
    }
  }
});

test('the old manifest and service worker find every file they name in the migrated tree', () => {
  // **Attack step 5.** A user on the pre-migration release whose extension folder is replaced with
  // this tree: the old `manifest.json` and the old `background.js` name files by hand, and one
  // missing script stops the service worker — commands stop, which is louder than a blank string and
  // cannot be prevented by commit ordering (D157).
  const baseline = path.join(__dirname, 'fixtures', 'baseline');
  const manifest = JSON.parse(fs.readFileSync(path.join(baseline, 'manifest.json'), 'utf8'));
  const named = [
    manifest.background.service_worker,
    ...manifest.content_scripts.flatMap(entry => entry.js),
    ...[...fs.readFileSync(path.join(baseline, 'background.js'), 'utf8')
      .matchAll(/'([^']+\.js)'/g)].map(match => match[1]),
  ];
  const current = path.join(__dirname, '..', 'extension');
  const absent = [...new Set(named)].filter(file => !fs.existsSync(path.join(current, file)));
  assert.deepEqual(absent, [], 'the previous release names a file this tree no longer ships');
});
