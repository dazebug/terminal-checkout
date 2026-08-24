#!/usr/bin/env node
// Checks `extension/_locales/<directory>/messages.json` against what `extension/_i18n/<tag>.js`
// derives. **It does not write.**
//
//     node tools/check-locales.js   # exit 1 if the two stores have come apart
//
// **It used to write, and A3 is where that stopped** (D167). While `_i18n` was canonical, deriving
// the second store by program was what kept a wrong edit from being made identically in both. A3
// moved the authority: `_locales` is what Chrome reads and what the extension draws from, so a
// generator pointed at it would be a path for the frozen compatibility store to overwrite the live
// one. The derivation survives only as a comparison — the same code, no `writeFileSync`, and a test
// holds it to that.
//
// **What the comparison means now.** `_i18n` is pinned at the migration baseline and `_locales` is
// canonical, so this is a mixed-generation check rather than a definition: it says the two still
// agree, which is what the compatibility passengers need while both ship. A legitimate correction
// made in `_locales` would turn it red — and that day is when A7's rewrite is due, which makes the
// contract "pinned to the committed baseline" instead of "equal" (D173).
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
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');

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

const serialize = messages => `${JSON.stringify(messages, null, 2)}\n`;

const main = () => {
  const context = loadExtensionI18n();
  let differences = 0;
  for (const tag of context.TC_I18N_LOCALES) {
    const { directory, messages } = deriveCatalogue(tag, context);
    const file = path.join(extension, '_locales', directory, 'messages.json');
    if (fs.readFileSync(file, 'utf8') !== serialize(messages)) {
      differences += 1;
      process.stderr.write(`_locales/${directory}/messages.json is not what _i18n/${tag}.js derives\n`);
    }
  }
  if (differences > 0) process.exit(1);
  process.stdout.write(`all ${context.TC_I18N_LOCALES.length} catalogues match what _i18n derives\n`);
};

module.exports = {
  loadExtensionI18n,
  deriveCatalogue,
  deriveMessage,
  serialize,
  placeholderName,
  CHROME_LOCALE_DIRECTORIES,
  MANIFEST_KEYS,
};

if (require.main === module) main();
