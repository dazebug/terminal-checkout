#!/usr/bin/env node
// Checks the compatibility catalogue against its committed migration baseline. **It does not write.**
//
//     node tools/check-locales.js   # exit 1 if the compatibility baseline has changed
//
// **It used to write, and A3 is where that stopped** (D167). While `_i18n` was canonical, deriving
// the second store by program was what kept a wrong edit from being made identically in both. A3
// moved the authority: `_locales` is what Chrome reads and what the extension draws from, so a
// generator pointed at it would be a path for the frozen compatibility store to overwrite the live
// one. The derivation survives only as a read-only name-and-entry-shape check — the same code, no
// `writeFileSync`, and a test holds it to that.
//
// **What the baseline means now.** `_i18n` is pinned at the migration baseline and `_locales` is
// canonical, so the command pins the compatibility passenger without treating a later canonical
// translation as an illegal edit. The live `_locales` bytes have their own pin in the ownership
// tests: an intentional correction turns that pin red and asks for its committed update (D173).
//
// **It loads the extension's own function rather than restating the rule** (D171, D177):
// `chromeMessageId`, the locale list and the metadata list all come out of `extension/i18n.js` by
// running it. "The same rule" in a generator and in a runtime is two implementations that agree
// until they do not, and the generator is where that divergence would begin, because it needs the
// rule first.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const extension = path.join(__dirname, '..', 'extension');

// These are hashes of the exact bytes in the two catalogue surfaces at the migration boundary.
// The compatibility hashes are the command's authority: a changed `_i18n` file is an unreviewed
// compatibility edit. The `_locales` hashes are the live-catalogue pin used by the ownership gate;
// it is expected to move with an intentional translation change, while the compatibility hashes do
// not. Keeping both in one committed object makes the two meanings visible without comparing two
// live stores and calling that proof of non-editing.
const CATALOGUE_BASELINE_HASHES = {
  compatibility: {
    en: 'cafcae916db9a88cd43673d12c184f3c0e0723d6496ff801a7aea4b1612473a9',
    ja: 'ac0ec5a45fba39fe645846387c44b9d4cde86b5b73dde5c32e9a6e89430bb530',
    ko: 'a7b23e0870c211dba0f4dd10dbd002c68cbc93782cd1e8603685ecea4a3f1f00',
    'zh-Hans': 'd0f503621e69e20e59cd2bdbff591e22bb6fb7c341cb6aeee6d80a0b1b7ae0f3',
    'zh-Hant': 'b72614421825cb6f0c71a89e240cf10a37ba43beff027ce4d1f4929eef111f7d',
  },
  locales: {
    en: 'a36041a50c933627cb1789e4b898dd70ce2bccfa1edbec26e38cdeb1348fe017',
    ja: 'c77ed63cfa15114ddd84572000a6e8b603cab72a8221f2e57970594cee42a8cf',
    ko: '7ed4af9cab494d6df8af50533f01d80833dd730414098f01d613af19a30b8e2c',
    'zh-Hans': 'a15f11b7efa5f1caf8490fcae7df627f9e8b51aa0c630a2654401128bbfc390a',
    'zh-Hant': '6db3096d64bf6186782ed8745c3978e5de1e6a7624e21ba6d80c820e24856115',
  },
};

// **The only file capability this module has is reading, and it is injected.** The gate that used to
// hold this file to being read-only listed four spellings of writing and missed `fs.writeFile`,
// `fs.write`, `copyFileSync` and every rename-based replacement (review 39) — an authored blacklist
// standing in for a property, which is the class this work keeps finding. So the property is
// structural instead: everything here reads through one reader, and a test can swap it to see that
// nothing else is reachable.
const readOnlyFiles = { read: (file, encoding = 'utf8') => fs.readFileSync(file, encoding) };
const read = name => readOnlyFiles.read(path.join(extension, name), 'utf8');
const readBytes = name => {
  const value = readOnlyFiles.read(path.join(extension, name), null);
  return Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8');
};
const sha256 = bytes => require('node:crypto').createHash('sha256').update(bytes).digest('hex');

// The extension's scripts are classic scripts that register into their global, so a context is all
// they need — and a fresh one, so nothing here can be answered by something Node happened to define.
// The bindings are read by evaluating an expression **in that context** rather than off the context
// object: a classic script's top-level `const` is a lexical binding and never becomes a property of
// the global, so `context.TC_I18N_LOCALES` is `undefined` while `TC_I18N_LOCALES` inside it is the
// array. (`TC_I18N` itself is a property, because the dictionaries assign it deliberately.) The test
// file reaches its own bindings the same way, which is where this shape was learned.
const loadExtensionI18n = () => {
  const context = vm.createContext({});
  vm.runInContext(read('i18n.js'), context);
  for (const tag of vm.runInContext('TC_I18N_LOCALES', context)) {
    vm.runInContext(read(`_i18n/${tag}.js`), context);
  }
  return vm.runInContext(
    '({ chromeMessageId, TC_I18N, TC_I18N_LOCALES, TC_I18N_CATALOGUE_TAG_KEY, TC_I18N_METADATA_KEYS })',
    context,
  );
};

// The one place that knows Chrome's directory spelling. `zh-Hans`/`zh-Hant` are what the app and the
// dictionaries say; `zh_CN`/`zh_TW` are what Chrome's `_locales` requires, and this is the only line
// in the repository where those two namespaces meet — which makes it exactly where a wrong
// directory name would hide, so the real-Chrome release gate names those two locales explicitly.
const CHROME_LOCALE_DIRECTORIES = {
  en: 'en',
  ko: 'ko',
  ja: 'ja',
  'zh-Hans': 'zh_CN',
  'zh-Hant': 'zh_TW',
};

// `%1$s` becomes `$ARG1$` plus a declaration binding `ARG1` to the first substitution. The name
// carries identity and `content` pins the source position, so a translation may put the arguments
// in any order without the binding moving — which is the property `chrome.i18n` has and the old
// positional format did not need, because there the position *was* the name.
//
// The name is derived rather than invented: a mechanical `ARG<n>` is checkable against the source
// index by anybody reading either file, and a hand-chosen semantic name in five catalogues is five
// chances to bind the wrong one. What keeps them honest is the argument-identity oracle in
// `tests/i18n.test.js`, which renders both formats with distinct sentinels and requires the same
// bytes out.
const PLACEHOLDER = /%(\d+)\$[sd]/g;
const placeholderName = index => `ARG${index}`;

// A literal `$` in a message means "start of a placeholder" to Chrome unless it is doubled. Escaping
// is done per literal segment rather than over the whole string, because the placeholders we are
// about to write contain `$` themselves.
const escapeDollars = text => text.split('$').join('$$');

const deriveMessage = (value) => {
  const placeholders = {};
  const source = String(value);
  let message = '';
  let cursor = 0;
  for (const match of source.matchAll(PLACEHOLDER)) {
    message += escapeDollars(source.slice(cursor, match.index));
    const index = Number(match[1]);
    const name = placeholderName(index);
    placeholders[name] = { content: `$${index}` };
    message += `$${name}$`;
    cursor = match.index + match[0].length;
  }
  message += escapeDollars(source.slice(cursor));
  return Object.keys(placeholders).length > 0 ? { message, placeholders } : { message };
};

// The two keys Chrome's namespace holds are not derived from anything: a manifest's `name` and
// `description` cannot be filled from our dictionaries, so they live here and only here. The
// derivation carries them across rather than inventing them, and refuses if they are missing —
// silently regenerating a file without them would leave the extension unnamed in that language.
const MANIFEST_KEYS = ['extName', 'extDescription'];

const deriveCatalogue = (tag, context = loadExtensionI18n()) => {
  const directory = CHROME_LOCALE_DIRECTORIES[tag];
  if (!directory) throw new Error(`no _locales directory is declared for ${tag}`);
  const existing = JSON.parse(read(`_locales/${directory}/messages.json`));
  const derived = {};
  for (const key of MANIFEST_KEYS) {
    if (!existing[key] || typeof existing[key].message !== 'string') {
      throw new Error(`_locales/${directory}/messages.json has no ${key} to carry across`);
    }
    derived[key] = existing[key];
  }
  const dictionary = context.TC_I18N[tag];
  for (const key of Object.keys(dictionary).map(context.chromeMessageId).sort()) {
    // Back to the logical id: sorting by the physical name is what makes the file's order a fact
    // about the name rather than about which locale happened to be edited last.
    const logical = Object.keys(dictionary).find(candidate => context.chromeMessageId(candidate) === key);
    derived[key] = deriveMessage(dictionary[logical]);
  }
  return { directory, messages: derived };
};

const checkCompatibilityBaseline = () => {
  const context = loadExtensionI18n();
  const failures = [];
  for (const tag of context.TC_I18N_LOCALES) {
    const compatibilityPath = `_i18n/${tag}.js`;
    const expectedHash = CATALOGUE_BASELINE_HASHES.compatibility[tag];
    const actualHash = sha256(readBytes(compatibilityPath));
    if (actualHash !== expectedHash) {
      failures.push(`${compatibilityPath} differs from the committed migration baseline`);
    }

    // `_locales` remains the live store. The command checks its name set and manifest entries so a
    // compatibility file cannot silently lose a passenger, but deliberately does not compare its
    // message values: a reviewed canonical translation is precisely the edit A7 permits.
    const { directory, messages } = deriveCatalogue(tag, context);
    const actual = JSON.parse(read(`_locales/${directory}/messages.json`));
    if (JSON.stringify(Object.keys(actual).sort()) !== JSON.stringify(Object.keys(messages).sort())) {
      failures.push(`_locales/${directory}/messages.json has a different message-name set`);
    }
    for (const [key, entry] of Object.entries(actual)) {
      if (!entry || typeof entry !== 'object' || typeof entry.message !== 'string') {
        failures.push(`_locales/${directory}/messages.json has an invalid entry for ${key}`);
      }
    }
  }
  return { failures };
};

const checkLiveLocaleBaseline = () => {
  const failures = [];
  const context = loadExtensionI18n();
  for (const tag of context.TC_I18N_LOCALES) {
    const directory = CHROME_LOCALE_DIRECTORIES[tag];
    const relativePath = `_locales/${directory}/messages.json`;
    const actualHash = sha256(readBytes(relativePath));
    if (actualHash !== CATALOGUE_BASELINE_HASHES.locales[tag]) {
      failures.push(
        `${relativePath} differs from the committed A7 baseline pin — `
        + '_locales is canonical, so an intentional translation edit is allowed; update the baseline pin',
      );
    }
  }
  return { failures };
};

const serialize = messages => `${JSON.stringify(messages, null, 2)}\n`;

const main = () => {
  const { failures } = checkCompatibilityBaseline();
  if (failures.length > 0) {
    for (const failure of failures) process.stderr.write(`${failure}\n`);
    process.exit(1);
  }
  const context = loadExtensionI18n();
  process.stdout.write(`all ${context.TC_I18N_LOCALES.length} compatibility catalogues match the pinned migration baseline\n`);
};

module.exports = {
  // Exported so a test can hand in its own reader and see that nothing else is reachable.
  readOnlyFiles,
  loadExtensionI18n,
  deriveCatalogue,
  deriveMessage,
  serialize,
  placeholderName,
  CHROME_LOCALE_DIRECTORIES,
  MANIFEST_KEYS,
  CATALOGUE_BASELINE_HASHES,
  checkCompatibilityBaseline,
  checkLiveLocaleBaseline,
};

if (require.main === module) main();
