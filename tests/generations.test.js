// The mixed-generation execution matrix: A3's lookup boundary and A4's final-state completion
// condition, and the implementation evidence for the class that took four design reviews to state.
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
// the native response's bookkeeping and outcome, the content script's first render and locale
// notification, and the options page's initial paint and storage notification. Initialization,
// command results, first render and initial paint run in all four pairings. The retired bookkeeping
// and locale-notification work runs in the two baseline-consumer pairings; the two current-consumer
// pairings assert that the same platform events start none of it. That difference is A4's subject,
// not a reason to narrow the matrix to one pairing.
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
const { CHROME_LOCALE_DIRECTORIES } = require('../tools/check-locales.js');

const BASELINE_HASHES = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'baseline', 'HASHES.json'), 'utf8'));

// **The load order is read from the generation, never written here.** The service worker names its
// own list with `importScripts`, the content script's list is the manifest's, and the options page's
// is the script tags in its markup — so a consumer that starts loading something new is loaded that
// way here too, rather than against a list in a test that would go stale silently.
// **Read through the realm, so the inputs that decide the order are pinned like the ones that run.**
// These two were being read straight off the disk, which left their recorded hashes unused — a
// changed script order or a stray space would have altered the fixture with nothing to say so
// (review 39). `realm.read` records the same way `realm.feed` does; it just does not evaluate.
const loadOrder = (realm, consumer) => {
  if (consumer === 'background.js') return ['background.js'];  // it imports its own dependencies
  if (consumer === 'content.js') {
    const manifest = JSON.parse(realm.read('manifest.json'));
    return manifest.content_scripts.flatMap(entry => entry.js);
  }
  const markup = realm.read('options.html');
  return [...markup.matchAll(/<script src="([^"]+)"><\/script>/g)].map(match => match[1]);
};

const load = (realm, consumer, { poisonCurrentCacheSelector = false } = {}) => {
  for (const file of loadOrder(realm, consumer)) {
    if (poisonCurrentCacheSelector && file === consumer) {
      // One boundary, named exactly: the current consumer must not ask the compatibility cache
      // selector. Storage/native/event observations below cover the rest of the retired pipeline.
      // Calling this an oracle for every compatibility symbol would turn one hand-authored list
      // into the ABI authority that D170 explicitly rejects.
      realm.run("localeToRenderIn = () => { throw new Error('current consumer called localeToRenderIn'); };");
    }
    realm.feed(file);
  }
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

const EXPECTED_TAG_BY_DIRECTORY = Object.fromEntries(
  Object.entries(CHROME_LOCALE_DIRECTORIES).map(([tag, directory]) => [directory, tag]),
);

// Chrome's Chinese catalogue directories use underscores, while getUILanguage returns BCP-47.
// Map the sibling spellings as one family: a one-off conversion for either side leaves the other
// looking plausible while the baseline resolver silently falls back to English.
const UI_LANGUAGE_BY_DIRECTORY = {
  zh_CN: 'zh-CN',
  zh_TW: 'zh-TW',
};

// Chrome answers from the shipped catalogue, so a raw key or a blank is visible as itself.
const platformFor = (directory = 'ja') => {
  const backend = catalogueBackend(directory);
  return {
    getMessage: (id, subs) => backend(id, subs),
    uiLanguage: UI_LANGUAGE_BY_DIRECTORY[directory] ?? EXPECTED_TAG_BY_DIRECTORY[directory],
  };
};

const drained = () => new Promise(resolve => setImmediate(resolve));

test('the Chrome realm answers an unknown message with an empty string', () => {
  const realm = generationRealm({ platform: { uiLanguage: 'en' } });
  assert.equal(realm.chrome.i18n.getMessage('not-in-the-catalogue'), '');
});

test('every generation pairing loads, and the baseline it loads is the pinned artifact', () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    for (const consumer of CONSUMERS) {
      const realm = generationRealm({ skeleton, consumers, platform: platformFor() });
      load(realm, consumer, {
        // This oracle is intentionally applicable only to the production current×current pairing:
        // an adjacent old skeleton still needs the current consumer's feature-detected seed branch.
        // The other lifecycle and language assertions below continue to run on all four pairings.
        poisonCurrentCacheSelector: skeleton === 'current' && consumers === 'current',
      });
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
  // ...and every pinned artifact was **verified**, not merely present. Existence was the old check and
  // says nothing about the bytes (review 39): a fixture could drift while its hash sat unread. So the
  // pin is walked and each entry compared against what a realm hands out.
  const auditor = generationRealm({ skeleton: 'baseline', consumers: 'baseline', platform: platformFor() });
  for (const [file, hash] of Object.entries(BASELINE_HASHES)) {
    auditor.read(file.replace('tests/fixtures/baseline/', ''));
    assert.equal(auditor.fed[file], hash, `${file} is not the baseline artifact it was pinned as`);
  }
  assert.equal(
    Object.keys(auditor.fed).length, Object.keys(BASELINE_HASHES).length,
    'the pin and the fixture directory disagree about how many artifacts there are',
  );
});

test('a native response settles independently of bookkeeping in every pairing', async () => {
  // **The oracle inverts here, and this is the one that came from our own mistake** (D180). An
  // earlier revision of the plan required the matrix to drain every promise it started; the code says
  // the opposite in plain words — "the bookkeeping is started, not awaited, and it cannot fail this
  // call" — because awaiting it once turned an already-executed command into a reported failure, and
  // a person who presses a button again after a false failure runs the command twice.
  //
  // So the bookkeeping is **held** while the result is observed, and only then released.
  // All four pairings assert the command result. Only pairings with the baseline consumer own the
  // retired bookkeeping boundary; there it is held and released. Current consumers instead assert
  // that neither a startup query nor bookkeeping happened — A4 removes their use, not the adjacent
  // skeleton's implementation.
  for (const { skeleton, consumers, what } of PAIRINGS) {
    let release;
    const held = new Promise((resolve) => { release = resolve; });
    let reads = 0;
    const realm = generationRealm({
      skeleton,
      consumers,
      platform: {
        ...platformFor(),
        holdLocalGet: () => { reads += 1; return held; },
        nativeResponse: message => message.query === 'locale'
          ? { success: true }
          : { success: true, locale: 'ja', locale_install_id: 'install-a', locale_epoch: 3 },
      },
    });
    load(realm, 'background.js');
    const outcome = realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })');
    const settled = await outcome;
    assert.equal(settled.success, true, `${what}: the command result waited for bookkeeping`);
    // The current skeleton's serialized writer starts its read on the next turn; give it that turn
    // only after the command result has been observed. The held read still cannot finish.
    await drained();
    const keepsBookkeeping = consumers === 'baseline';
    assert.equal(reads, keepsBookkeeping ? 1 : 0, `${what}: the wrong bookkeeping boundary ran`);
    assert.equal(
      realm.calls.native.length,
      keepsBookkeeping ? 2 : 1,
      `${what}: the worker sent an unexpected startup locale query`,
    );
    assert.deepEqual(realm.calls.set, [], `${what}: bookkeeping finished before the result was observed`);
    if (!keepsBookkeeping) continue;
    // Released only after the result was observed, and then it completes on its own.
    release({});
    await drained();
    assert.equal(realm.calls.set.length, 1, `${what}: the held bookkeeping never resumed`);
    assert.equal(realm.calls.set[0].localeCache.locale, 'ja');
  }
});

test('a refused command stays exactly that refusal in every pairing', async () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    const realm = generationRealm({
      skeleton,
      consumers,
      platform: {
        ...platformFor(),
        nativeResponse: message => message.query === 'locale'
          ? { success: true }
          : { success: false, error: 'Variable {repo} not provided' },
      },
    });
    load(realm, 'background.js');
    await assert.rejects(
      realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })'),
      error => {
        assert.equal(error.message, 'Variable {repo} not provided', `${what}: the refusal changed`);
        return true;
      },
      `${what}: the refusal was replaced by something else`,
    );
  }
});

test('bookkeeping failures change and delay nothing in every pairing', async () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    for (const [how, fail] of [
      ['synchronously', () => { throw new Error('storage exploded'); }],
      ['asynchronously', () => Promise.reject(new Error('storage rejected'))],
    ]) {
      let attempts = 0;
      const realm = generationRealm({
        skeleton,
        consumers,
        platform: {
          ...platformFor(),
          holdLocalGet: () => { attempts += 1; return fail(); },
          nativeResponse: message => message.query === 'locale'
            ? { success: true }
            : { success: true, locale: 'ko', locale_install_id: 'install-b', locale_epoch: 1 },
        },
      });
      load(realm, 'background.js');
      const settled = await realm.run('sendToNativeHost({ command_template: "z {repo}", variables: {} })');
      assert.equal(settled.success, true, `${what}: bookkeeping failing ${how} changed the command result`);
      await drained();
      assert.equal(
        attempts,
        consumers === 'baseline' ? 1 : 0,
        `${what}: bookkeeping failing ${how} ran for the wrong consumer generation`,
      );
      assert.deepEqual(realm.calls.set, [], `${what}: bookkeeping failing ${how} still wrote`);
    }
  }
});

test('deferred platform events exercise every boundary its consumer generation owns', async () => {
  for (const { skeleton, consumers, what } of PAIRINGS) {
    // The baseline content consumer owns a locale notification; A4's current consumer does not. In
    // both cases the platform event is driven, and a local read says whether the retired path ran.
    let contentReads = 0;
    const content = generationRealm({
      skeleton,
      consumers,
      platform: { ...platformFor(), holdLocalGet: async () => { contentReads += 1; } },
    });
    load(content, 'content.js');
    await drained();
    for (const listener of content.listeners.message) {
      listener({ action: 'localeChanged', locale: 'ja' }, {}, () => {});
    }
    await drained();
    await drained();
    assert.equal(
      contentReads,
      consumers === 'baseline' ? 2 : 0,
      `${what}: the content locale notification had the wrong lifecycle`,
    );

    // The options page always owns its settings notification. Only the baseline consumer also owns
    // the retired local-locale notification; both events are fired through the platform registry.
    let optionReads = 0;
    const options = generationRealm({
      skeleton,
      consumers,
      platform: { ...platformFor(), holdLocalGet: async () => { optionReads += 1; } },
    });
    load(options, 'options.js');
    assert.ok(options.listeners.storageChanged.length > 0, `${what}: options.js registered no storage listener`);
    await drained();
    for (const listener of options.listeners.storageChanged) {
      listener({ localeCache: { newValue: {} } }, 'local');
    }
    await drained();
    await drained();
    assert.equal(
      optionReads,
      consumers === 'baseline' ? 2 : 0,
      `${what}: the options locale notification had the wrong lifecycle`,
    );
    for (const listener of options.listeners.storageChanged) {
      listener({ buttons: { newValue: [] } }, 'sync');
    }
    await drained();
  }
});

test('every pairing draws the requested catalogue and names its expected tag', async () => {
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
  // Internal agreement is not enough: English text under `lang="en"` is self-consistent even when
  // Traditional Chinese was requested. Pin both outputs to the requested catalogue instead.
  assert.deepEqual(
    ['zh_CN', 'zh_TW'].map(directory => platformFor(directory).uiLanguage),
    ['zh-CN', 'zh-TW'],
    'the Chinese catalogue siblings were not both converted to Chrome-shaped UI language tags',
  );
  for (const { skeleton, consumers, what } of PAIRINGS) {
    for (const directory of Object.values(CHROME_LOCALE_DIRECTORIES)) {
      const realm = generationRealm({ skeleton, consumers, platform: platformFor(directory) });
      load(realm, 'options.js');
      await drained();
      const tag = realm.context.document.documentElement.lang;
      const title = realm.context.document.title;
      const expectedTag = EXPECTED_TAG_BY_DIRECTORY[directory];
      assert.ok(tag, `${what} (${directory}): the page never set a document language`);
      assert.ok(title, `${what} (${directory}): the page never set a title`);
      assert.equal(tag, expectedTag, `${what} (${directory}): the document named the wrong catalogue`);
      // The title is `Terminal Checkout — <the header message>`, so the message the page drew is what
      // follows the dash. The expected catalogue comes from the requested directory, never from the
      // document's own answer: deriving one output from the other lets both fail together.
      const drawn = title.slice(title.indexOf('—') + 1).trim();
      const expected = catalogueBackend(directory)('ext_header_options');
      assert.equal(
        drawn, expected,
        `${what} (${directory}): the page drew ${JSON.stringify(drawn)} while calling itself ${tag}`,
      );
      assert.ok(!drawn.startsWith('ext'), `${what} (${directory}): a raw key reached the title`);
    }
  }
});

test('with our buttons absent, a failing cache read still draws one in the chosen catalogue', async () => {
  // **Documenting the swallow was not enough** (review 39, answering our own residual). The
  // first-render gate turns every preparation failure into success, so "driven and nothing escaped"
  // proves neither compatibility nor rendering — and the DOM double compounded it by answering every
  // query, so the content script always saw a button of ours and never took the insertion path at
  // all. That path is the *normal* first render.
  //
  // So: our buttons absent, the cache read failing, and the assertion is about what reached the page.
  for (const { skeleton, consumers, what } of PAIRINGS) {
    let localReads = 0;
    const realm = generationRealm({
      skeleton,
      consumers,
      platform: {
        ...platformFor('ja'),
        ourButtonsPresent: false,
        holdLocalGet: () => {
          localReads += 1;
          return Promise.reject(new Error('the cache could not be read'));
        },
      },
    });
    load(realm, 'content.js');
    await drained();
    await drained();
    const inserted = [
      ...realm.context.document.inspectNodes(),
      realm.context.document.body,
    ].flatMap(node => node.children);
    assert.ok(
      inserted.length > 0,
      `${what}: nothing was inserted when the cache read failed and no button of ours was present`,
    );
    // Read the fields rather than serialising the graph: the double's `parentElement` is lazy, so a
    // deep walk builds ancestors forever (measured — `Maximum call stack size exceeded`).
    const words = inserted
      .flatMap(node => [node.title, node.textContent, node.getAttribute && node.getAttribute('aria-label')])
      .filter(text => typeof text === 'string' && text.length > 0);
    assert.ok(words.length > 0, `${what}: what was inserted carries no readable text`);
    assert.ok(
      words.includes(catalogueBackend('ja')('ext_preset_pr_checkout')),
      `${what}: the first render did not use the chosen Japanese catalogue`,
    );
    for (const text of words) {
      assert.ok(!/^ext[._]/i.test(text), `${what}: a raw message id reached the page: ${text}`);
    }
    assert.equal(
      localReads,
      consumers === 'baseline' ? 1 : 0,
      `${what}: the first render used the retired cache path in the wrong consumer generation`,
    );
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
