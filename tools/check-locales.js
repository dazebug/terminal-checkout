#!/usr/bin/env node
// Checks the live `_locales` catalogues' machine structure. **It does not write.**
//
//     node tools/check-locales.js   # exit 1 if a live machine contract has changed
//
// `_locales` is canonical, hand-edited, and what Chrome reads. The live bytes have their own pin in
// the live-content tests, while machine-checkable structure stays a live gate here: a changed byte
// may be an intentional translation edit or an unintended structural change, and a pin cannot
// decide which — but a dropped argument, an undeclared placeholder or a key one locale lost can be
// decided, and this command decides them.
//
// **It loads the extension's own function rather than restating the rule**:
// `chromeMessageId`, the locale list and the metadata list all come out of `extension/i18n.js` by
// running it. "The same rule" in a checker and in a runtime is two implementations that agree
// until they do not.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const extension = path.join(__dirname, '..', 'extension');

// Hashes of the exact bytes of each live catalogue. A changed file must be reviewed as an
// intentional translation edit or an unintended structural change before its pin moves; the pin is
// asserted by the live-content tests rather than by this command, so a translation review updates
// the pin and this command keeps judging structure.
const CATALOGUE_BASELINE_HASHES = {
  locales: {
    en: 'a36041a50c933627cb1789e4b898dd70ce2bccfa1edbec26e38cdeb1348fe017',
    ja: 'c77ed63cfa15114ddd84572000a6e8b603cab72a8221f2e57970594cee42a8cf',
    ko: '7ed4af9cab494d6df8af50533f01d80833dd730414098f01d613af19a30b8e2c',
    'zh-Hans': 'a15f11b7efa5f1caf8490fcae7df627f9e8b51aa0c630a2654401128bbfc390a',
    'zh-Hant': '6db3096d64bf6186782ed8745c3978e5de1e6a7624e21ba6d80c820e24856115',
  },
};

// **The only file capability this module has is reading, and it is injected.** Every file access
// goes through one reader, so a test can replace that capability and verify that no writer is
// reachable.
const readOnlyFiles = { read: (file, encoding = 'utf8') => fs.readFileSync(file, encoding) };
const read = name => readOnlyFiles.read(path.join(extension, name), 'utf8');
const readBytes = name => {
  const value = readOnlyFiles.read(path.join(extension, name), null);
  return Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8');
};
const sha256 = bytes => require('node:crypto').createHash('sha256').update(bytes).digest('hex');

// The extension's script is a classic script that registers into its global, so a context is all
// it needs — and a fresh one, so nothing here can be answered by something Node happened to define.
// The bindings are read by evaluating an expression **in that context** rather than off the context
// object: a classic script's top-level `const` is a lexical binding and never becomes a property of
// the global, so `context.TC_I18N_LOCALES` is `undefined` while `TC_I18N_LOCALES` inside it is the
// array. The test file reaches its own bindings the same way, which is where this shape was learned.
const loadExtensionI18n = () => {
  const context = vm.createContext({});
  vm.runInContext(read('i18n.js'), context);
  return vm.runInContext(
    '({ chromeMessageId, formatMessage, TC_I18N_LOCALES, TC_I18N_CATALOGUE_TAG_KEY, TC_I18N_METADATA_KEYS })',
    context,
  );
};

// The one place that knows Chrome's directory spelling. `zh-Hans`/`zh-Hant` are what the app
// says; `zh_CN`/`zh_TW` are what Chrome's `_locales` requires, and this is the only line
// in the repository where those two namespaces meet — which makes it exactly where a wrong
// directory name would hide, so the real-Chrome release gate names those two locales explicitly.
const CHROME_LOCALE_DIRECTORIES = {
  en: 'en',
  ko: 'ko',
  ja: 'ja',
  'zh-Hans': 'zh_CN',
  'zh-Hant': 'zh_TW',
};

// The two keys Chrome's namespace holds that are not messages a page draws: a manifest's `name` and
// `description`. Losing one would leave the extension unnamed in that language, so their presence
// is checked per locale.
const MANIFEST_KEYS = ['extName', 'extDescription'];

const CATALOGUE_PLACEHOLDER = /\$([A-Za-z0-9_@]+)\$/g;

// One catalogue entry, rendered with substitutions the way Chrome renders it: `$NAME$` resolves
// through the declaration to its `$n` position, `$$` is a literal dollar, and anything undeclared
// stays on screen (which is what makes it visible).
const renderCatalogueMessage = (entry, substitutions) => entry.message.replace(
  /\$([A-Za-z0-9_@]+)\$|\$\$/g,
  (whole, name) => {
    if (whole === '$$') return '$';
    const declaration = entry.placeholders && entry.placeholders[name];
    if (!declaration) return whole;
    const position = Number(String(declaration.content).slice(1));
    return substitutions[position - 1] ?? whole;
  },
);

const sentinelProjection = value => [...String(value).matchAll(/<<arg-\d+>>/g)].map(match => match[0]).join('');

// The argument bindings one entry declares, as "which source argument does each used placeholder
// reach": a set, because a translation may reorder its sentence but may not drop an argument or
// invent one. `null` means the entry is structurally unreadable and the caller reports that instead.
const argumentBindingsOf = (entry) => {
  const declarations = entry.placeholders || {};
  const bindings = new Set();
  for (const [name, declaration] of Object.entries(declarations)) {
    const content = declaration && declaration.content;
    if (typeof content !== 'string' || !/^\$\d+$/.test(content)) return null;
    bindings.add(`${name}=${content}`);
  }
  return bindings;
};

// **Argument identity, with `_locales/en` as the source.** The English catalogue is canonical for
// which arguments a message takes; every other locale must declare exactly the same placeholder
// names bound to exactly the same positions, while its sentence may put them in any order. A locale
// that dropped `$ARG2$` from its text still declares it — the check is on declarations and on every
// used name being declared, because an undeclared `$NAME$` reaches the screen as itself.
const checkLocaleArgumentIdentity = (tag, directory, actual, english) => {
  const failures = [];
  for (const [physical, entry] of Object.entries(actual)) {
    if (!entry || typeof entry.message !== 'string') continue;
    for (const match of entry.message.matchAll(CATALOGUE_PLACEHOLDER)) {
      if (!Object.hasOwn(entry.placeholders || {}, match[1])) {
        failures.push(
          `_locales/${directory}/messages.json: ${physical} uses undeclared placeholder ${match[1]}`,
        );
      }
    }
    const bindings = argumentBindingsOf(entry);
    if (bindings === null) {
      failures.push(`_locales/${directory}/messages.json: ${physical} has a malformed placeholder declaration`);
      continue;
    }
    if (tag === 'en') continue;
    const source = english[physical];
    if (!source || typeof source.message !== 'string') continue;
    const sourceBindings = argumentBindingsOf(source);
    if (sourceBindings === null) continue; // reported on the en pass
    const missing = [...sourceBindings].filter(binding => !bindings.has(binding));
    const extra = [...bindings].filter(binding => !sourceBindings.has(binding));
    if (missing.length > 0 || extra.length > 0) {
      failures.push(
        `_locales/${directory}/messages.json: ${physical} argument bindings differ from en — `
        + `missing [${missing.join(', ')}], extra [${extra.join(', ')}]`,
      );
    }
  }
  return failures;
};

// The live structural contract, per locale: parseable, every entry an object with a string
// `message`, the manifest keys present, and — with `en` as the name authority — the same physical
// name set in both directions. Symmetric on purpose: with a single canonical store there is no
// second store to be a subset of, and a key one locale lost is exactly the defect this command
// exists to name.
const checkLiveLocaleStructure = () => {
  const context = loadExtensionI18n();
  const failures = [];
  const englishDirectory = CHROME_LOCALE_DIRECTORIES.en;
  const english = JSON.parse(read(`_locales/${englishDirectory}/messages.json`));
  for (const tag of context.TC_I18N_LOCALES) {
    const directory = CHROME_LOCALE_DIRECTORIES[tag];
    if (!directory) {
      failures.push(`no _locales directory is declared for ${tag}`);
      continue;
    }
    const actual = JSON.parse(read(`_locales/${directory}/messages.json`));
    for (const key of MANIFEST_KEYS) {
      if (!actual[key] || typeof actual[key].message !== 'string') {
        failures.push(`_locales/${directory}/messages.json has no ${key}`);
      }
    }
    for (const [key, entry] of Object.entries(actual)) {
      if (!entry || typeof entry !== 'object' || typeof entry.message !== 'string') {
        failures.push(`_locales/${directory}/messages.json has an invalid entry for ${key}`);
      }
    }
    if (tag !== 'en') {
      for (const name of Object.keys(english)) {
        if (!Object.hasOwn(actual, name)) {
          failures.push(`_locales/${directory}/messages.json is missing ${name}`);
        }
      }
      for (const name of Object.keys(actual)) {
        if (!Object.hasOwn(english, name)) {
          failures.push(`_locales/${directory}/messages.json has ${name}, which en does not carry`);
        }
      }
    }
    failures.push(...checkLocaleArgumentIdentity(tag, directory, actual, english));
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
        `${relativePath} differs from the committed catalogue baseline pin — `
        + 'review whether this is an intentional translation edit or an unintended structural change before updating the pin',
      );
    }
  }
  return { failures };
};

const main = () => {
  const { failures } = checkLiveLocaleStructure();
  if (failures.length > 0) {
    for (const failure of failures) process.stderr.write(`${failure}\n`);
    process.exit(1);
  }
  const context = loadExtensionI18n();
  process.stdout.write(
    `all ${context.TC_I18N_LOCALES.length} live catalogues carry the same names and argument bindings as en\n`,
  );
};

module.exports = {
  // Exported so a test can hand in its own reader and see that nothing else is reachable.
  readOnlyFiles,
  loadExtensionI18n,
  renderCatalogueMessage,
  sentinelProjection,
  CHROME_LOCALE_DIRECTORIES,
  MANIFEST_KEYS,
  CATALOGUE_BASELINE_HASHES,
  checkLiveLocaleStructure,
  checkLocaleArgumentIdentity,
  checkLiveLocaleBaseline,
};

if (require.main === module) main();
