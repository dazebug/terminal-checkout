// Tests for the extension's dictionary skeleton — `node --test` from the repo root, no dependencies.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const extension = path.join(__dirname, '../extension');
const read = name => fs.readFileSync(path.join(extension, name), 'utf8');
const manifest = JSON.parse(read('manifest.json'));
// The checker's own functions, imported so the gates below run them rather than a description of
// them — the same reason the liveness sweep extracts its predicate.
const {
  loadExtensionI18n, MANIFEST_KEYS, CHROME_LOCALE_DIRECTORIES,
  CATALOGUE_BASELINE_HASHES, checkLiveLocaleStructure, checkLiveLocaleBaseline,
} = require('../tools/check-locales.js');

// The same loader the extension's three hosts use, and the same one the other test files use: a
// classic script, run with **no `chrome` global in sight**. That is the constraint the whole
// skeleton is shaped by — a single `chrome.*` at module scope would take down every test here
// and the 158 that came before.
vm.runInThisContext(read('i18n.js'));
// and defaults.js, whose presets resolve their display text lazily through `tr`
vm.runInThisContext(read('defaults.js'));
const {
  applyDocumentLanguage, chromeMessageId,
  TC_I18N_LOCALES, TC_I18N_CATALOGUE_TAG_KEY, TC_I18N_METADATA_KEYS,
} = vm.runInThisContext('({ applyDocumentLanguage, chromeMessageId, TC_I18N_LOCALES, TC_I18N_CATALOGUE_TAG_KEY, TC_I18N_METADATA_KEYS })');
// Node has no `chrome`, so every lookup throws unless a backend is installed. This one
// reads the shipped `_locales` catalogues, and it is a double for Chrome's substitution rather
// than evidence about Chrome — the real load is a release gate.
const { catalogueBackend } = require('./chrome-messages.js');
vm.runInThisContext('({ installMessageBackend })').installMessageBackend(catalogueBackend('en'));

// One projection for every assertion whose subject is what Chrome will show. Keeping the physical
// entries here is the boundary that prevents a future authority move from leaving the content
// gates behind again.
const liveCataloguePathFor = tag => {
  const directory = CHROME_LOCALE_DIRECTORIES[tag];
  assert.ok(directory, `no Chrome catalogue directory is mapped for ${tag}`);
  return `_locales/${directory}/messages.json`;
};
const LIVE_CATALOGUES = Object.fromEntries(
  TC_I18N_LOCALES.map(tag => [tag, JSON.parse(read(liveCataloguePathFor(tag)))])
);
const liveEntryFor = (tag, logicalKey) => LIVE_CATALOGUES[tag][chromeMessageId(logicalKey)];
const liveMessageFor = (tag, logicalKey) => liveEntryFor(tag, logicalKey)?.message ?? '';
const livePhysicalKeysFor = tag => Object.keys(LIVE_CATALOGUES[tag]);
const liveValuesFor = tag => Object.values(LIVE_CATALOGUES[tag]).map(entry => entry.message);
const livePlaceholderNamesFor = entry => Object.keys(entry.placeholders ?? {}).sort();
const liveMessagesFor = tag => new Proxy({}, {
  get: (_target, logicalKey) => liveMessageFor(tag, logicalKey),
});

test('every file has a role, and a role is what makes a file enter a gate', () => {
  // The universe, and the fact that being in it is the same thing as being read. A file with no role
  // fails here; a role with no files fails here; and a role whose files are not the ones the
  // pipelines below take would be a third authority, which is what this replaced.
  const unclassified = EXTENSION_FILES.filter(file => roleOf(file) === null);
  assert.deepEqual(
    unclassified, [],
    'the extension ships a file with no role — give it one, or say here what it is and which gate owns it',
  );
  for (const [role, files] of Object.entries({
    speakingSource: SPEAKING_FILES,
    markupSource: HTML_FILES,
    manifest: MANIFEST_FILES,
    localeCatalogue: CATALOGUE_FILES,
  })) {
    assert.ok(files.length > 0, `nothing in the extension is ${role}, so its gates read nothing`);
  }
  // Each data role is exactly what its name claims rather than "whatever had that suffix": one
  // manifest, and one catalogue per shipped locale. A stray `probe.json` is neither.
  assert.deepEqual(MANIFEST_FILES, ['manifest.json']);
  assert.equal(CATALOGUE_FILES.length, TC_I18N_LOCALES.length, 'the catalogues and the locales disagree');
  assert.deepEqual(
    CATALOGUE_FILES,
    TC_I18N_LOCALES.map(cataloguePathForLocale).sort(),
    'the catalogue paths are not the paths derived from the shipped locale mapping',
  );
  assert.equal(roleOf('_locales/not-shipped/messages.json'), null, 'an unshipped catalogue path was classified');
  assert.equal(roleOf('_locales/en/probe.js'), null, 'a file under the catalogue tree became a consumer');
  // And the sets the gates use are derived from the roles, not re-filtered beside them
  assert.deepEqual(MARKUP_FILES, [...SPEAKING_FILES, ...HTML_FILES].sort());
  assert.deepEqual(
    EXTENSION_FILES.filter(file => roleOf(file) !== null).sort(),
    [...MARKUP_FILES, ...MANIFEST_FILES, ...CATALOGUE_FILES].sort(),
    'a file has a role that no set takes',
  );
});
test('the document language names the catalogue that answered, not the language Chrome is set to', () => {
  // Why `<html lang>` moves in the same commit as the lookup: Chrome
  // may be set to a language we do not ship and still serve the English catalogue; writing what
  // Chrome is set to would then declare English text as French. So the tag is asked of the
  // catalogue that answered.
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const previous = installMessageBackend(catalogueBackend('ja'));
  try {
    const doc = { documentElement: { lang: 'en' } };
    assert.equal(applyDocumentLanguage(doc), 'ja');
    assert.equal(doc.documentElement.lang, 'ja');
    assert.match(tr('ext.header.options'), /[ぁ-んァ-ン一-龥]/, 'the text drawn is not the catalogue that named itself');
    // Chrome set to a language we do not ship: the English catalogue answers and says so, so the
    // document says `en` — not `fr`, which is the accessibility defect in reverse.
    installMessageBackend(catalogueBackend('en'));
    assert.equal(applyDocumentLanguage(doc), 'en');
    assert.equal(doc.documentElement.lang, 'en');
  } finally {
    installMessageBackend(previous);
  }
  // No document, nothing to say
  assert.equal(applyDocumentLanguage(undefined), null, 'it reached for a document that is not there');
});

test('the key spaces are separate, whatever is in them', () => {
  // `chrome.i18n`'s namespace holds exactly the two keys a manifest cannot fill any other way
  //
  // **Five directories are required.** An empty `messages.json` is a shape nobody had measured, but
  // an *empty* `messages.json` is a shape nobody had measured, so creating three of them would have
  // added three unverified files to hold nothing. That reason expires the moment there are values to
  // put in them: a filled `messages.json` is the shape Chrome documents and the other two already
  // demonstrate. Leaving them out now would mean the extension's own name and description stay
  // English in three of the five languages it otherwise speaks.
  //
  // **And `_locales` carries the extension's own messages too.** It holds two namespaces,
  // not one: the two keys a manifest cannot fill any other way, and one converted name per
  // logical id. They do not overlap and cannot — every converted name begins `ext_`, which is
  // what the dotted prefix becomes, and the two manifest keys have no dot to convert.
  for (const tag of TC_I18N_LOCALES) {
    const messages = LIVE_CATALOGUES[tag];
    assert.deepEqual(
      Object.keys(messages).filter(name => !name.startsWith('ext_')).sort(),
      ['extDescription', 'extName'],
      `${CHROME_LOCALE_DIRECTORIES[tag]} carries something that is neither a manifest key nor an extension id`,
    );
    for (const name of [...MANIFEST_KEYS, ...livePhysicalKeysFor('en')]) {
      assert.ok(Object.hasOwn(messages, name), `${tag} is missing ${name}, which en carries`);
    }
    for (const key of Object.keys(messages)) {
      assert.ok(
        MANIFEST_KEYS.includes(key) || key.startsWith('ext_'),
        `${tag} carries undeclared message ${key}`,
      );
      assert.equal(typeof messages[key].message, 'string');
      assert.ok(messages[key].message.length > 0, `${tag}/${key} is empty`);
    }
  }
});

test('the manifest names those two keys and declares where to fall back', () => {
  assert.equal(manifest.name, '__MSG_extName__');
  assert.equal(manifest.description, '__MSG_extDescription__');
  assert.equal(manifest.default_locale, 'en');
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
});

test('nothing in the skeleton touches chrome at load time, and one statement names it at all', () => {
  // **Driven, not grepped.** This asked whether the string `chrome.` appeared anywhere in the file,
  // which was true while nothing used `chrome` at all and became false the moment the lookup did —
  // even though the property it names never changed. The property is that **loading these files in
  // a context with no `chrome` does not throw**, so that is what runs: the service worker, the
  // content script and the options page all load this file before any of them could install
  // anything, and an old worker after a copy swap never installs at all.
  const realm = vm.createContext({});
  vm.runInContext(read('i18n.js'), realm);
  assert.equal(vm.runInContext('typeof tr', realm), 'function', 'the skeleton did not finish loading');
  // **One statement names `chrome.i18n.getMessage` in the whole extension**. More than one is
  // a second lookup path, and a second lookup path is where the preprocessing gets skipped.
  // Prose is not a call: these files explain the seam at length, and the sentence above this one in
  // `i18n.js` names the function it is describing. Whole-line comments come out first.
  const code = file => read(file).split('\n').filter(line => !line.trim().startsWith('//')).join('\n');
  const calls = MARKUP_FILES.flatMap(file => [...code(file).matchAll(/chrome\.i18n\.getMessage/g)].map(() => file));
  assert.deepEqual(calls, ['i18n.js'], 'the lookup is named somewhere other than its one seam');
});

// ---------------------------------------------------------------------------------------------
// The options page's own catalogue.
//
// The page carries no prose: `options.html` names messages (`data-i18n`) and `options.js` asks for
// them. Which means the two questions a catalogue gate has to answer — "is every key it can ask for
// there" and "is every key there asked for" — are **enumerations** rather than estimates, and these
// tests are what keeps them that way.
// ---------------------------------------------------------------------------------------------

// `options.js` by name, because the checks below that name it are about *that* script's order of
// operations. The markup is not read by name anywhere any more — see `HTML_FILES`.
const optionsJs = read('options.js');

// **Every file that can name a message**, not only the options page: the presets, the
// button phase markers and the update notice's prose into the dictionaries too, and a gate that
// scanned one file would have called all of those unreferenced.
//
// The set is **read from the directory**, not listed. As a list of five it was complete — the two
// scripts it omitted name no messages — but "every file" was then a promise about a directory that
// can grow, and a new script naming a key nobody put in the catalogue would have gone unseen in
// exactly the direction that shows a user a raw key (measured with a planted file).
//
// **And it descends.** `readdirSync` on its own reads immediate children, so "every file" was still
// a promise about one level — the same defect the Swift source scan was fixed for elsewhere,
// left standing here by the same sweep. A directory
// listing is not a source tree on either side of this repository.
const walkFiles = (dir, keep, prefix = '') => fs.readdirSync(dir, { withFileTypes: true })
  .flatMap(entry => (entry.isDirectory()
    ? walkFiles(path.join(dir, entry.name), keep, `${prefix}${entry.name}/`)
    : (keep(entry.name) ? [`${prefix}${entry.name}`] : [])))
  .sort();
// **One classifier, and every file set below comes out of it.** The version this replaces had two
// authorities: a suffix list that decided whether a file was *accounted for*, and three more suffix
// filters that decided what each pipeline actually *read*. Two ways through the gap: put
// `.mjs` on the audited list with a real `.mjs` file — accounted for, read by nothing — or drop any
// `probe.json` into the tree and have it classified as manifest-or-catalogue data on the strength of
// a suffix, with no gate owning it. The shape in one sentence: the authored input
// classification did not imply entry into the application.
//
// So a path gets a **role**, the roles are the only way a file enters anything, and the data roles
// are recognised **by exact path** rather than by suffix. Chrome catalogue paths come from the one
// locale-to-Chrome mapping owned by `tools/check-locales.js`, and compatibility paths come from the
// same shipped app-tag set. Anything else under either catalogue tree is unclassified rather than
// becoming a consumer by its `.js` suffix. This classifier does not inspect catalogue contents or
// prove that a file's data belongs to its locale — `check-locales.js` and the Swift ownership gate
// enforce that identity. A file with no role fails the gate below, which is what "fails closed" has
// to mean once the classification and the entry are one operation. Same move as `auditSource`, one
// level out.
const cataloguePathForLocale = tag => {
  const directory = CHROME_LOCALE_DIRECTORIES[tag];
  assert.ok(directory, `no Chrome catalogue directory is mapped for ${tag}`);
  return `_locales/${directory}/messages.json`;
};
const CATALOGUE_PATHS = new Set(TC_I18N_LOCALES.map(cataloguePathForLocale));
const roleOf = (relativePath) => {
  if (relativePath === 'manifest.json') return 'manifest';
  if (CATALOGUE_PATHS.has(relativePath)) return 'localeCatalogue';
  if (relativePath.startsWith('_locales/')) return null;
  if (relativePath.endsWith('.js')) return 'speakingSource';
  if (relativePath.endsWith('.html')) return 'markupSource';
  return null;
};
const EXTENSION_FILES = walkFiles(extension, () => true);
const filesInRole = role => EXTENSION_FILES.filter(file => roleOf(file) === role);

const SPEAKING_FILES = filesInRole('speakingSource');
// The markup half on its own, for the checks whose subject is a page rather than the code that fills
// one. **Read from the tree for the same reason**: there is one page today, so a
// scan of `options.html` and a scan of every page agree — by accident, and only until the second one.
const HTML_FILES = filesInRole('markupSource');
// Markup is written in both kinds of file — a page's own HTML and the scripts that build rows into
// it — so a check about markup takes the union rather than the file that happened to hold the
// example when it was written.
const MARKUP_FILES = [...SPEAKING_FILES, ...HTML_FILES].sort();
const MANIFEST_FILES = filesInRole('manifest');
const CATALOGUE_FILES = filesInRole('localeCatalogue');
assert.ok(SPEAKING_FILES.length >= 5, `only ${SPEAKING_FILES.length} extension scripts found`);
assert.ok(HTML_FILES.length >= 1, 'no markup was found at all');
// A consumer names a message through a literal call, a declared key-bearing data position, or a
// `data-i18n` attribute. Catalogue definitions are a separate role and never witness this set.
// The shape of a message id, in one place. The attribute gate asks whether a call names one of
// these, and this set is what such a name is checked against — written twice, the two would
// agree by coincidence until the day one of them was widened.
const MESSAGE_KEY = 'ext\\.[A-Za-z0-9.]+';

// One lexical event stream, with separate semantic projections. Reference discovery needs literal
// values while call discovery must reject call-shaped strings and regular expressions; those are
// different answers over the same grammar, not reasons to duplicate the grammar. Comments never
// become events, static templates become literals, interpolated templates expose the code inside
// each interpolation, and regular-expression bodies stay opaque.
const readQuotedLiteral = (source, start) => {
  const quote = source[start];
  for (let i = start + 1; i < source.length; i += 1) {
    if (source[i] === '\\') { i += 1; continue; }
    if (source[i] === quote) {
      return { start, end: i + 1, value: source.slice(start + 1, i) };
    }
    if (source[i] === '\n') return null;
  }
  return null;
};

const messageKey = new RegExp(`^${MESSAGE_KEY}$`);
const REGEX_PREFIX_KEYWORDS = new Set([
  'await', 'case', 'delete', 'do', 'else', 'in', 'instanceof', 'new', 'of', 'return', 'throw',
  'typeof', 'void', 'yield',
]);
const CONTROL_PAREN_KEYWORDS = new Set(['catch', 'for', 'if', 'switch', 'while', 'with']);
const JAVASCRIPT_PUNCTUATORS = [
  '>>>=', '===', '!==', '>>>', '**=', '&&=', '||=', '??=', '<<=', '>>=', '=>', '==', '!=',
  '<=', '>=', '++', '--', '**', '&&', '||', '??', '?.', '+=', '-=', '*=', '/=', '%=', '&=',
  '|=', '^=', '<<', '>>',
  '(', ')', '[', ']', '{', '}', '.', ',', ';', ':', '?', '+', '-', '*', '/', '%', '&', '|', '^',
  '!', '~', '<', '>', '=',
];

const readRegularExpression = (source, start) => {
  let inCharacterClass = false;
  for (let i = start + 1; i < source.length; i += 1) {
    if (source[i] === '\\') { i += 1; continue; }
    if (source[i] === '\n' || source[i] === '\r') return null;
    if (source[i] === '[') { inCharacterClass = true; continue; }
    if (source[i] === ']' && inCharacterClass) { inCharacterClass = false; continue; }
    if (source[i] !== '/' || inCharacterClass) continue;
    let end = i + 1;
    while (/[A-Za-z]/.test(source[end] ?? '')) end += 1;
    return { start, end };
  }
  return null;
};

const javaScriptEvents = (source) => {
  const events = [];

  const scan = (start = 0, stopAtInterpolationEnd = false, templateDepth = 0) => {
    let braceDepth = 0;
    let expressionCanStart = true;
    const parens = [];
    let previous = null;

    const emit = (event) => {
      const contextual = { ...event, templateDepth };
      events.push(contextual);
      previous = contextual;
    };

    const scanTemplate = (templateStart) => {
      let dynamic = false;
      for (let i = templateStart + 1; i < source.length; i += 1) {
        if (source[i] === '\\') { i += 1; continue; }
        if (source[i] === '$' && source[i + 1] === '{') {
          dynamic = true;
          i = scan(i + 2, true, templateDepth + 1) - 1;
          continue;
        }
        if (source[i] !== '`') continue;
        emit({
          type: 'literal', quote: '`', static: !dynamic,
          value: source.slice(templateStart + 1, i), start: templateStart, end: i + 1,
        });
        return i + 1;
      }
      return source.length;
    };

    for (let i = start; i < source.length;) {
      const character = source[i];
      const next = source[i + 1];
      if (/\s/.test(character)) { i += 1; continue; }
      if (character === '/' && next === '/') {
        const newline = source.indexOf('\n', i + 2);
        i = newline < 0 ? source.length : newline + 1;
        continue;
      }
      if (character === '/' && next === '*') {
        const close = source.indexOf('*/', i + 2);
        i = close < 0 ? source.length : close + 2;
        continue;
      }
      if (character === "'" || character === '"') {
        const literal = readQuotedLiteral(source, i);
        if (!literal) return source.length;
        emit({ type: 'literal', quote: character, static: true, ...literal });
        expressionCanStart = false;
        i = literal.end;
        continue;
      }
      if (character === '`') {
        i = scanTemplate(i);
        expressionCanStart = false;
        continue;
      }
      if (character === '/' && next !== '=' && expressionCanStart) {
        const literal = readRegularExpression(source, i);
        if (literal) {
          emit({ type: 'regex', ...literal });
          expressionCanStart = false;
          i = literal.end;
          continue;
        }
      }
      if (/[A-Za-z_$]/.test(character)) {
        let end = i + 1;
        while (end < source.length && /[A-Za-z0-9_$]/.test(source[end])) end += 1;
        const name = source.slice(i, end);
        emit({ type: 'identifier', name, start: i, end });
        expressionCanStart = REGEX_PREFIX_KEYWORDS.has(name);
        i = end;
        continue;
      }
      if (/[0-9]/.test(character)) {
        let end = i + 1;
        while (end < source.length && /[A-Za-z0-9_.]/.test(source[end])) end += 1;
        emit({ type: 'number', start: i, end });
        expressionCanStart = false;
        i = end;
        continue;
      }
      const value = JAVASCRIPT_PUNCTUATORS.find(candidate => source.startsWith(candidate, i));
      if (!value) { i += 1; continue; }
      if (stopAtInterpolationEnd && value === '}' && braceDepth === 0) return i + 1;
      if (stopAtInterpolationEnd && value === '{') braceDepth += 1;
      if (stopAtInterpolationEnd && value === '}') braceDepth -= 1;
      const before = previous;
      emit({ type: 'punctuator', value, start: i, end: i + value.length });
      if (value === '(') {
        parens.push(before?.type === 'identifier' && CONTROL_PAREN_KEYWORDS.has(before.name));
        expressionCanStart = true;
      } else if (value === ')') {
        expressionCanStart = parens.pop() === true;
      } else if (value === ']' || value === '}' || value === '++' || value === '--') {
        expressionCanStart = false;
      } else if (value === '.' || value === '?.') {
        expressionCanStart = false;
      } else {
        expressionCanStart = true;
      }
      i += value.length;
    }
    return source.length;
  };

  scan();
  return events;
};

const messageStringKeysFrom = events => events
  .filter(event => event.type === 'literal' && event.static && messageKey.test(event.value))
  .map(event => event.value);

const messageCallsFrom = (events) => events.flatMap((event, index) => {
  if (event.type !== 'identifier' || !['t', 'tr', 'tHTML'].includes(event.name)) return [];
  const open = events[index + 1];
  const key = events[index + 2];
  if (open?.type !== 'punctuator' || open.value !== '(') return [];
  if (key?.type !== 'literal' || !key.static || !messageKey.test(key.value)) return [];
  return [{ name: event.name, key: key.value, callIndex: event.start, openIndex: open.start }];
});

const messageStringKeysIn = source => messageStringKeysFrom(javaScriptEvents(source));
const messageCallsIn = source => messageCallsFrom(javaScriptEvents(source));

const declaredMessageKeysFrom = (events) => {
  const keys = [];
  for (let i = 0; i < events.length - 2; i += 1) {
    // `nameKey` and nothing else: a preset's face is a literal, so a `faceKey: 'ext.…'` is not a
    // reference this audit should absolve — it should surface as a catalogue key nobody reads.
    if (events[i].type !== 'identifier' || events[i].name !== 'nameKey') continue;
    if (events[i + 1].type !== 'punctuator' || events[i + 1].value !== ':') continue;
    const literal = events[i + 2];
    if (literal.type === 'literal' && literal.static && messageKey.test(literal.value)) keys.push(literal.value);
  }
  for (let i = 0; i < events.length; i += 1) {
    if (events[i].type !== 'identifier' || events[i].name !== 'STATIC_TEXT_ARGS') continue;
    let open = i + 1;
    while (open < events.length && !(events[open].type === 'punctuator' && events[open].value === '{')) open += 1;
    let depth = 0;
    for (let j = open; j < events.length; j += 1) {
      const event = events[j];
      if (event.type === 'punctuator' && event.value === '{') { depth += 1; continue; }
      if (event.type === 'punctuator' && event.value === '}') {
        depth -= 1;
        if (depth === 0) break;
        continue;
      }
      if (depth !== 1 || event.type !== 'literal' || !event.static || !messageKey.test(event.value)) continue;
      if (events[j + 1]?.type === 'punctuator' && events[j + 1].value === ':') keys.push(event.value);
    }
    break;
  }
  return keys;
};

const consumerReferenceKeysIn = (files, readSource) => {
  const references = new Set();
  for (const file of files) {
    const events = javaScriptEvents(readSource(file));
    const strings = new Set(messageStringKeysFrom(events));
    const calls = messageCallsFrom(events);
    // This containment is guaranteed today: both projections select the same static message-key
    // literal event. It is a tripwire, not independent evidence. It starts doing work if a later
    // change gives calls their own scanner or otherwise lets the projections stop sharing events.
    for (const { key } of calls) {
      assert.ok(strings.has(key), `${file}: ${key} escaped the shared-event projection tripwire`);
      references.add(key);
    }
    for (const key of declaredMessageKeysFrom(events)) references.add(key);
  }
  return references;
};

const assertEveryCatalogueMessageIsReferenced = (catalogueKeys, references, exempt = []) => {
  const exemptKeys = new Set(exempt);
  const unreferenced = catalogueKeys
    .filter(key => !exemptKeys.has(key))
    .filter(key => !references.has(key));
  assert.deepEqual(unreferenced, [], 'the catalogue carries a message nothing asks for');
};

const keysInJs = consumerReferenceKeysIn(SPEAKING_FILES, read);
const keysInHtml = new Set(
  HTML_FILES.flatMap(file => [...read(file).matchAll(/data-i18n="([^"]+)"/g)].map(m => m[1])),
);
const referencedKeys = new Set([...keysInJs, ...keysInHtml]);

// Which half of the text/markup split a key is on. A key reached through `t(`/`tr(` becomes
// textContent, a title or a `confirm()`; a key reached through `tHTML(` or `data-i18n` becomes
// innerHTML. The call reader above supplies the code-only half, while markup still comes from the
// literal `data-i18n` attributes.
const textKeys = new Set();
const markupKeys = new Set(keysInHtml);
for (const file of SPEAKING_FILES) {
  for (const { name, key } of messageCallsIn(read(file))) {
    if (name === 'tHTML') markupKeys.add(key);
    else textKeys.add(key);
  }
}

const placeholdersOf = value => (value.match(/%\d+\$[sd]/g) ?? []).sort();
const tagsOf = value => (value.match(/<\/?[a-z][^>]*>/g) ?? []).map(tag => tag.replace(/\s+class="[^"]*"/, '')).sort();
const codeSpansOf = value => (value.match(/<code>[^<]*<\/code>/g) ?? []).sort();

test('every locale carries the same keys, and every value says something', () => {
  // Every shipped locale answers the same question; a missing key makes that locale go red rather
  // than allowing an empty or partial catalogue to pass.
  const en = LIVE_CATALOGUES.en;
  assert.ok(Object.keys(en).length >= 89, `the catalogue shrank to ${Object.keys(en).length}`);
  for (const tag of TC_I18N_LOCALES) {
    const live = LIVE_CATALOGUES[tag];
    assert.deepEqual(Object.keys(live).sort(), Object.keys(en).sort(), `${tag} does not match en`);
    for (const [key, entry] of Object.entries(live)) {
      assert.equal(typeof entry.message, 'string', `${tag}/${key}`);
      assert.ok(entry.message.trim().length > 0, `${tag}/${key} is empty`);
    }
  }
});

test('each catalogue says which one it is, and that key is metadata rather than a message', () => {
  // **The tag is asked of the catalogue, not computed**. The options page has to put a
  // language on `<html lang>`, and the honest answer is not Chrome's configured UI language —
  // Chrome may report `fr` and then serve the English catalogue, and `lang="fr"` over English text
  // is the accessibility defect we are fixing, reproduced in the other direction. A key whose value
  // is the catalogue's own tag lets **Chrome's fallback choose the answer**: whichever catalogue it
  // picked is the one that replies.
  //
  for (const tag of TC_I18N_LOCALES) {
    assert.equal(liveMessageFor(tag, TC_I18N_CATALOGUE_TAG_KEY), tag, `${tag} does not name itself`);
  }
  // And it is **metadata**: not one of the 122 user-facing strings, so it stays out of the counts
  // that ask whether the extension is fully translated, and out of the gate that says every message
  // in the catalogue is asked for by the page. Nothing asks for it until the current lookup runs.
  assert.ok(TC_I18N_METADATA_KEYS.includes(TC_I18N_CATALOGUE_TAG_KEY));
  // "Nothing draws it" is asked of the sets that mean drawn — `textKeys` and `markupKeys`. The
  // consumer-reference projection excludes this declaration too: a definition cannot witness the
  // property being checked, which is the accidental pass this file has been caught by before.
  assert.ok(!textKeys.has(TC_I18N_CATALOGUE_TAG_KEY), 'a metadata key is drawn as text');
  assert.ok(!markupKeys.has(TC_I18N_CATALOGUE_TAG_KEY), 'a metadata key is drawn as markup');
});

// How many arguments a call or a table entry supplies — a projection over the same lexical events,
// and one that says when it cannot read (the arrangement the attribute scan settled on). It counts
// commas at the top level of one bracket; punctuation inside strings, regexes, nested brackets and
// template interpolations never becomes that bracket's comma. A trailing comma is not an element:
// `[a, b, c,]` supplies three. That last rule is not a nicety — without it
// the one entry in this repository written across several lines reported four arguments for a
// three-argument message, which is a gate failing on its own reading rather than on the code.
const CLOSING_BRACKET = { '(': ')', '[': ']', '{': '}' };
const topLevelParts = (source, openIndex) => {
  const events = javaScriptEvents(source);
  const start = events.findIndex(event => (
    event.start === openIndex && event.type === 'punctuator' && Object.hasOwn(CLOSING_BRACKET, event.value)
  ));
  if (start < 0) return null;
  const templateDepth = events[start].templateDepth;
  const stack = [events[start].value];
  let parts = 0;
  let seenSinceComma = false;
  for (let i = start + 1; i < events.length; i += 1) {
    const event = events[i];
    if (event.templateDepth !== templateDepth) continue;
    if (event.type !== 'punctuator') { seenSinceComma = true; continue; }
    if (Object.hasOwn(CLOSING_BRACKET, event.value)) {
      stack.push(event.value);
      seenSinceComma = true;
      continue;
    }
    if (Object.values(CLOSING_BRACKET).includes(event.value)) {
      const open = stack.pop();
      if (CLOSING_BRACKET[open] !== event.value) return null;
      if (stack.length === 0) return parts + (seenSinceComma ? 1 : 0);
      seenSinceComma = true;
      continue;
    }
    if (event.value === ',' && stack.length === 1) { parts += 1; seenSinceComma = false; continue; }
    seenSinceComma = true;
  }
  return null;
};

// The highest argument a message asks for. `%2$d` in the compatibility dictionary and `$ARG2$` in
// Chrome's live store both mean the message needs two, because the formatter takes them positionally
// — asking for the second without the first is still a call that has to supply two.
const highestArgumentOf = value => Math.max(
  0,
  ...[...String(value ?? '').matchAll(/%(\d+)\$[sd]/g)].map(match => Number(match[1])),
  ...[...String(value ?? '').matchAll(/\$ARG(\d+)\$/g)].map(match => Number(match[1])),
);

// **Argument coverage is a gate rather than a measurement.** The two formats differ when a call supplies
// fewer arguments than its message asks for: today the compatibility formatter leaves `%2$s` standing
// on screen, and `chrome.i18n` instead returns the live message with nothing substituted. That difference is
// unreachable — every call site supplies exactly through the highest index — and the property is
// pinned here rather than left as a paragraph, because the day it stops holding is the day that
// difference becomes a product change nobody decided on.
//
// Both shapes are read: a call naming its key, and the table that fills `data-i18n` nodes, whose
// entries are arrays and are the only place arguments are supplied without a call in sight.
const refuseArgumentMismatches = (file, rawSource, messages) => {
  const supplied = [];
  for (const { key, openIndex } of messageCallsIn(rawSource)) {
    const parts = topLevelParts(rawSource, openIndex);
    assert.ok(parts !== null, `${file}: a call to ${key} runs off the end of the file`);
    supplied.push([key, parts - 1, 'call']);
  }
  const table = rawSource.indexOf('const STATIC_TEXT_ARGS = {');
  if (table >= 0) {
    for (const match of rawSource.slice(table).matchAll(/'(ext\.[A-Za-z0-9.]+)':\s*\(\)\s*=>\s*\[/g)) {
      const open = rawSource.indexOf('[', table + match.index + match[1].length);
      const parts = topLevelParts(rawSource, open);
      assert.ok(parts !== null, `${file}: the static arguments for ${match[1]} run off the end of the file`);
      supplied.push([match[1], parts, 'static fill']);
    }
  }
  for (const [key, count, shape] of supplied) {
    const highest = highestArgumentOf(messages[key]);
    assert.equal(
      count, highest,
      `${file}: the ${shape} for ${key} supplies ${count} argument(s) and the message asks through argument ${highest}`,
    );
  }
  return supplied.length;
};

test('every call supplies arguments through its message, and the gate says so when one does not', () => {
  // The corpus is the subject and cannot be the whole evidence: the property holds today, so nothing
  // here can fail — the same dead-guard shape seen elsewhere. The refusal is therefore entered from a
  // fixture too, one line per way it can be broken, and the corpus counts are stated so that a
  // catalogue or a call site quietly leaving the scan shows up as a smaller number.
  let readSites = 0;
  for (const file of SPEAKING_FILES) readSites += refuseArgumentMismatches(file, read(file), liveMessagesFor('en'));
  // **110 sites are expected after the v2 migration description, two list-help argument fills,
  // and the list result UI argument fills are added.** The count is
  // derived from the source reader rather than a work-log claim: a call written inside a comment in
  // `i18n.js` must not enter the result, while a real zero-argument call must.
  // What matters more than the digit is
  // what it hid: a real zero-argument call could have been removed while the comment-shaped one
  // kept both the count and the arity result intact.
  assert.equal(readSites, 110, `the scan read ${readSites} argument-supplying sites`);

  const refused = (source, messages) => {
    try {
      refuseArgumentMismatches('fixture.js', source, messages);
    } catch (error) {
      if (error.code !== 'ERR_ASSERTION') throw error;
      return error.message;
    }
    return null;
  };
  const messages = { 'ext.a': 'takes %1$s and %2$d', 'ext.b': 'takes nothing' };
  assert.match(refused("t('ext.a', one);", messages), /supplies 1 argument\(s\) and the message asks through argument 2/);
  assert.match(refused("tr('ext.b', one);", messages), /supplies 1 argument\(s\) and the message asks through argument 0/);
  assert.match(
    refused("const STATIC_TEXT_ARGS = {\n  'ext.a': () => [one],\n};", messages),
    /the static fill for ext\.a supplies 1 argument/,
  );
  // A call that supplies exactly what its message asks for is the shape everything here is in
  assert.equal(refused("tHTML('ext.a', one, two);\nt('ext.b');", messages), null);
  // ...including across lines and with a trailing comma, which is how the one multi-line entry in
  // this repository is written
  assert.equal(refused("const STATIC_TEXT_ARGS = {\n  'ext.a': () => [\n    one,\n    two,\n  ],\n};", messages), null);
});

test('a call-shaped string is not a reference, text consumer, or argument-supplying call', () => {
  const source = `const example = "tr('ext.a')";`;
  assert.deepEqual(messageStringKeysIn(source), []);
  assert.deepEqual(messageCallsIn(source), []);
  assert.equal(refuseArgumentMismatches('fixture.js', source, { 'ext.a': 'takes nothing' }), 0);
});
test('message strings and calls are separate projections of every JavaScript lexical state', () => {
  const source = [
    "t('ext.single');",
    'tr("ext.double");',
    'tHTML(`ext.staticTemplate`);',
    "// tr('ext.lineComment');",
    '/* tr("ext.blockComment"); */',
    "const ordinary = \"tr('ext.ordinaryString')\";",
    "const pattern = /tr('ext.a')/;",
    'const rendered = `${tr(\'ext.interpolation\')}`;',
    'tr(`ext.${suffix}`);',
  ].join('\n');
  const expected = ['ext.single', 'ext.double', 'ext.staticTemplate', 'ext.interpolation'];
  const strings = messageStringKeysIn(source);
  const calls = messageCallsIn(source).map(({ name, key }) => `${name}:${key}`);
  assert.deepEqual(strings, expected);
  assert.deepEqual(calls, [
    't:ext.single',
    'tr:ext.double',
    'tHTML:ext.staticTemplate',
    'tr:ext.interpolation',
  ]);
  for (const { key } of messageCallsIn(source)) {
    assert.ok(strings.includes(key), `${key} escaped the shared-event projection tripwire`);
  }
});

test('_locales is pinned by bytes, and its machine structure is checked live', () => {
  // The live `_locales` values are canonical and may evolve, so their exact-byte pin is a review
  // prompt, not an edit ban. The command checks the machine-structure contracts; the test checks
  // the live pin; neither claims that two live catalogues must remain textually equal.
  assert.deepEqual(checkLiveLocaleStructure().failures, []);
  assert.deepEqual(checkLiveLocaleBaseline().failures, []);
  assert.equal(Object.keys(CATALOGUE_BASELINE_HASHES.locales).length, TC_I18N_LOCALES.length);
});
test('a legitimate _locales edit stays green in the structure checker and names only its live pin', () => {
  const { readOnlyFiles } = require('../tools/check-locales.js');
  const original = readOnlyFiles.read;
  const editedPath = path.join(extension, '_locales', 'en', 'messages.json');
  try {
    readOnlyFiles.read = (file, encoding) => {
      const originalValue = original(file, encoding);
      if (file !== editedPath) return originalValue;
      const text = Buffer.isBuffer(originalValue) ? originalValue.toString('utf8') : originalValue;
      const messages = JSON.parse(text);
      messages.ext_header_options.message += ' (edited)';
      const edited = `${JSON.stringify(messages, null, 2)}\n`;
      return Buffer.isBuffer(originalValue) ? Buffer.from(edited) : edited;
    };
    assert.deepEqual(checkLiveLocaleStructure().failures, []);
    const liveFailures = checkLiveLocaleBaseline().failures;
    assert.deepEqual(
      liveFailures,
      [
        '_locales/en/messages.json differs from the committed catalogue baseline pin — review whether this is an intentional translation edit or an unintended structural change before updating the pin',
      ],
      'the live pin must report the edited locale and the fact of the difference, not an authored count or a benign explanation',
    );
  } finally {
    readOnlyFiles.read = original;
  }
});

test('_locales rejects a translation whose placeholder binding moves away from en', () => {
  // `en` is canonical for which arguments a message takes, so it has no external binding oracle —
  // an en edit is reviewed through the byte pin. A translation, though, must bind the same names to
  // the same positions as en, and a moved binding is exactly the defect that renders the wrong
  // value into the right sentence.
  const { readOnlyFiles, checkLiveLocaleStructure } = require('../tools/check-locales.js');
  const original = readOnlyFiles.read;
  const editedPath = path.join(extension, '_locales', 'ko', 'messages.json');
  try {
    readOnlyFiles.read = (file, encoding) => {
      const originalValue = original(file, encoding);
      if (file !== editedPath) return originalValue;
      const text = Buffer.isBuffer(originalValue) ? originalValue.toString('utf8') : originalValue;
      const messages = JSON.parse(text);
      messages.ext_confirm_presetOverwrite.placeholders.ARG2.content = '$1';
      const edited = `${JSON.stringify(messages, null, 2)}\n`;
      return Buffer.isBuffer(originalValue) ? Buffer.from(edited) : edited;
    };
    const failures = checkLiveLocaleStructure().failures;
    assert.ok(
      failures.some(failure => failure.includes(
        '_locales/ko/messages.json: ext_confirm_presetOverwrite argument bindings differ from en',
      )),
      failures.join('\n'),
    );
  } finally {
    readOnlyFiles.read = original;
  }
});

test('the checker can only read, and that is a capability rather than a rule', () => {
  // **The live catalogue is not generated here.** `_locales` is hand-edited and what Chrome reads;
  // a generator pointed at it would be a path for some other store to overwrite the live one.
  //
  // **This used to be a blacklist of four spellings, and it was an overclaim**:
  // `fs.writeFile`, `fs.write`, `copyFileSync` and every rename-based replacement went straight
  // through it. An authored list of forbidden syntax standing in for a property is the class this
  // work keeps finding, so the property is structural now — the checker takes its file access from
  // one injected reader. Swap the reader and every read goes through it; there is nothing else it
  // could reach.
  const { readOnlyFiles, checkLiveLocaleStructure } = require('../tools/check-locales.js');
  const original = readOnlyFiles.read;
  const seen = [];
  try {
    readOnlyFiles.read = (file, encoding) => { seen.push(file); return original(file, encoding); };
    checkLiveLocaleStructure();
  } finally {
    readOnlyFiles.read = original;
  }
  assert.ok(seen.length > 0, 'the checker reached the filesystem some other way');
  assert.ok(
    seen.every(file => file.includes('/extension/')),
    `the checker read outside the extension: ${seen.filter(file => !file.includes('/extension/'))}`,
  );
  // The capability it was given has one verb. Anything it could write with would have to come from
  // somewhere this module does not look.
  assert.deepEqual(Object.keys(readOnlyFiles), ['read']);
});
test('the seam: nothing answers without a backend, and both paths get the same preprocessing', () => {
  // Three realms, built here rather than reused, because the hazard the lazy default carries is
  // not in production — it is Node global pollution: a `chrome` another test left behind would
  // answer for code that forgot to inject, and "forgetting throws" would be quietly false.
  const load = (globals) => {
    const realm = vm.createContext(globals);
    vm.runInContext(read('i18n.js'), realm);
    return realm;
  };
  // ① No `chrome`, no injection: it throws. Not a key, not a blank — nothing that could be drawn.
  const bare = load({});
  assert.throws(() => vm.runInContext("tr('ext.header.options')", bare), /chrome is not defined/);
  // ② A minimal Chrome spy receives the **physical** id and **string** substitutions
  const spy = load({ seen: [] });
  vm.runInContext(
    'chrome = { i18n: { getMessage: (id, subs) => { seen.push(JSON.stringify([id, subs])); return "drawn"; } } };',
    spy,
  );
  assert.equal(vm.runInContext("tr('ext.button.addLimit', 3)", spy), 'drawn');
  assert.deepEqual(vm.runInContext('seen', spy), ['["ext_button_addLimit",["3"]]']);
  // ③ An injected backend gets exactly the same two things — the seam is the backend, not the chain
  const injected = load({ seen: [] });
  vm.runInContext(
    'installMessageBackend((id, subs) => { seen.push(JSON.stringify([id, subs])); return "drawn"; });',
    injected,
  );
  assert.equal(vm.runInContext("tr('ext.button.addLimit', 3)", injected), 'drawn');
  assert.deepEqual(vm.runInContext('seen', injected), ['["ext_button_addLimit",["3"]]']);
  // ...and the realm that forgot is unaffected by the one that did not: ① still throws
  assert.throws(() => vm.runInContext("tr('ext.header.options')", bare), /chrome is not defined/);
});

test('a message whose arguments reorder puts them where its own language wants them', () => {
  // Three numeric sentinels through the one key whose order differs from English
  // in every other catalogue — the case where a binding that is wrong in the same way everywhere
  // would still read plausibly, which is why the compatibility oracle compares the formats and this compares the
  // rendered text a user would see.
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const previous = installMessageBackend(catalogueBackend('en'));
  try {
    const english = tr('ext.migration.hint.selected', 1, 2, '<S3>');
    assert.match(english, /1 of 2 selected/, `English read ${JSON.stringify(english)}`);
    installMessageBackend(catalogueBackend('ko'));
    const korean = tr('ext.migration.hint.selected', 1, 2, '<S3>');
    assert.match(korean, /2개 중 1개/, `Korean read ${JSON.stringify(korean)}`);
    // Both carry all three, and the numbers arrived as strings without anybody formatting them
    for (const rendered of [english, korean]) assert.ok(rendered.includes('<S3>'));
  } finally {
    installMessageBackend(previous);
  }
});

test('a key the catalogue does not have comes back blank, and nothing shipped can be one', () => {
  // `chrome.i18n.getMessage` answers an unknown name with an empty string, which
  // is a blank on screen rather than a raw key — quieter than what it replaces, so the gate that
  // keeps it from happening has to be about the shipped set rather than about the runtime.
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const previous = installMessageBackend(catalogueBackend('en'));
  try {
    assert.equal(tr('ext.thisKeyDoesNotExist'), '', 'the backend invented something for a missing key');
  } finally {
    installMessageBackend(previous);
  }
  // So: every key the page asks for exists in the store Chrome will read, under its physical name.
  // The dictionaries had this gate; it moves here with the authority.
  const shipped = new Set(livePhysicalKeysFor('en'));
  const missing = [...referencedKeys].filter(key => !shipped.has(chromeMessageId(key)));
  assert.deepEqual(missing, [], 'the page asks for a message Chrome will answer with a blank');
});

test('the boundary conversion is legal for every key, and collides for none', () => {
  // **The platform's grammar is satisfied at the boundary and nowhere else**. A `_locales`
  // message name may hold `[A-Za-z0-9_@]` and is compared case-insensitively, so the dotted logical
  // id the source writes cannot be one; `.`→`_` is the whole conversion, and the source keeps its
  // dots — which is what makes "an old dictionary meeting a new consumer" a state that cannot be
  // written down rather than one a gate has to catch.
  //
  // It lives in `i18n.js` because **the read-only checker and the runtime both load this function
  // from here**. "The same rule" written twice is two implementations that agree until they do not.
  assert.equal(chromeMessageId('ext.header.options'), 'ext_header_options');
  assert.equal(chromeMessageId('ext.migration.effect.behaviorChange'), 'ext_migration_effect_behaviorChange');
  // A name already legal is its own conversion — the two Chrome-namespace keys are the case
  assert.equal(chromeMessageId('extName'), 'extName');
  const byFoldedName = new Map();
  for (const name of livePhysicalKeysFor('en')) {
    assert.match(name, /^[A-Za-z0-9_@]+$/, `${name} is a name _locales cannot hold`);
    const folded = name.toLowerCase();
    assert.ok(
      !byFoldedName.has(folded),
      `${name} and ${byFoldedName.get(folded)} become the same name once case is folded away`,
    );
    byFoldedName.set(folded, name);
  }
  assert.equal(byFoldedName.size, livePhysicalKeysFor('en').length);
});

test('the page can only ask for keys the catalogue has, and asks for all of them', () => {
  const shipped = new Set(livePhysicalKeysFor('en'));
  const referencedPhysicalKeys = new Set([...referencedKeys].map(chromeMessageId));
  const missing = [...referencedPhysicalKeys].filter(key => !shipped.has(key));
  // Metadata is exempt **by name**, and the exemption is one line rather than a silence: a key whose
  // value is the catalogue's own tag is not a message the page draws, and until the lookup asks it for the
  // document language nothing reads it at all. Leaving it to pass on the accident that its
  // own declaration looks like a reference would be a gate agreeing for the wrong reason.
  assert.deepEqual(missing, [], 'the page names a message that is not in the catalogue');
  assertEveryCatalogueMessageIsReferenced(
    [...shipped],
    referencedPhysicalKeys,
    [...MANIFEST_KEYS, ...TC_I18N_METADATA_KEYS.map(chromeMessageId)],
  );
});

test('the options page keeps dynamic message dispatch inside its static fill', () => {
  // The static fill reads a key from `data-i18n`, then its three dispatches pass that value through.
  // Those are declared data positions in the reference projection above; any other dynamic dispatch
  // on this page would have no statically enumerable message behind it.
  const dynamic = [...optionsJs.matchAll(/\bt(?:HTML)?\(([^'\s)][^,)]*)/g)].map(m => m[1].trim());
  assert.deepEqual(dynamic, ['key', 'key', 'key'],
    'a message id is being computed somewhere other than the two declarations and the static fill');
  assert.ok(/node\.innerHTML = tHTML\(key, \.\.\.args\)/.test(optionsJs), 'the static fill moved');
});

test('placeholders match across locales, key by key', () => {
  // A translation that drops `%1$s` loses the label it was quoting; one that invents `%3$d` prints
  // the placeholder back at the user. Neither shows up as an error anywhere else.
  //
  // **Every locale is checked.** A placeholder added to a Chinese value must be visible here, just
  // as it is in the layout and refusal-wording tables.
  for (const tag of TC_I18N_LOCALES) {
    if (tag === 'en') continue;
    for (const key of livePhysicalKeysFor('en')) {
      assert.deepEqual(
        livePlaceholderNamesFor(LIVE_CATALOGUES[tag][key]), livePlaceholderNamesFor(LIVE_CATALOGUES.en[key]),
        `${tag}/${key}`,
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
      assert.deepEqual(tagsOf(liveMessageFor(tag, key)), [], `${tag}/${key} carries markup into textContent`);
    }
  }
  // and the converse, stated as the set it is: everything with a tag in it is markup-only
  for (const [physical, entry] of Object.entries(LIVE_CATALOGUES.en)) {
    const value = entry.message;
    if (!tagsOf(value).length) continue;
    const key = [...textKeys, ...markupKeys].find(logical => chromeMessageId(logical) === physical);
    if (!key) continue; // a message nothing asks for is the ask-for-all gate's subject, not this one's
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
    const tags = tagsOf(liveMessageFor('en', key));
    for (const tag of tags) assert.ok(allowed.has(tag), `${key} uses ${tag}`);
    assert.equal(tags.filter(t => t === '<b>').length, tags.filter(t => t === '</b>').length, `${key} <b>`);
    assert.equal(tags.filter(t => t === '<span>').length, tags.filter(t => t === '</span>').length, `${key} <span>`);
    assert.equal(tags.filter(t => t === '<code>').length, tags.filter(t => t === '</code>').length, `${key} <code>`);
    // **Every locale, not `ko`.** All locale loops in this file use the same subject; keeping this
    // check on the original pair would let a malformed tag in `ja` or either Chinese catalogue pass.
    // Those three are the machine-translated pass, where a stray tag is most likely.
    for (const tag of TC_I18N_LOCALES) {
      assert.deepEqual(tagsOf(liveMessageFor(tag, key)), tags, `${tag}/${key} has a different tag set`);
    }
  }
});

// The names whose value is **read to the user**. `value`, `href`, `id` and their like are
// deliberately out: they carry machine data as often as not, and a gate that fires on correct code
// is one somebody switches off (the reason the command-literal gate came down from ordered to
// multiset).
const TEXT_BEARING = 'placeholder|title|aria-label|aria-description|aria-placeholder|alt';

// **A name can be written four ways and its value four**, and the scan this replaced read one
// combination of them: `name="…"`, with the `=` against the name, declaring the other two quotings
// absent by a pair of patterns that required the same thing. So `title = …` with spaces around the
// `=` — how JavaScript assigns a property, and how all four such assignments in this repository are
// written (two template literals, two bare expressions) — was read neither by the scan nor by the
// guards, and neither was an uppercase name or `setAttribute`.
//
// The arrangement that replaced it is the point of the change: **a form on the readable list is
// read, and a name on the list written in a form that is not is a failure rather than a pass.**
// Naming the forbidden forms is an open list that quietly grows every time somebody writes
// JavaScript a way nobody had yet; naming the readable ones closes it.
//
// **What this gate is for, which decides where the list stops.** It is a lint against *shipping
// untranslated prose by accident* — a sentence typed into a `placeholder`, a tooltip written at the
// call site. It is not a boundary against someone determined to get text past it: the gate and the
// code it reads are the same repository with the same authors, so anyone able to write
// `setAttribute('ti' + 'tle', …)` can also delete this file. So the readable list covers **the forms
// people write when they are not thinking about this gate at all** — four ways of naming an
// attribute, four ways of quoting a value. A name the scan cannot read is not on the list, and what
// happens to those is decided at
// the two guards in the gate below rather than here: an assembled name is left alone, a name held
// in a variable is refused where the site can be known to be an attribute write.
//
// `i` because HTML does not care about case. Assignment is an event, not whitespace syntax: every
// ordinary, arithmetic, bitwise and logical assignment operator is explicit in the tokenizer and
// comments are trivia between that event and the value. Equality operators are different events,
// so they cannot enter by sharing an `=` suffix.
const TEXT_BEARING_NAME = new RegExp(`^(?:${TEXT_BEARING})(?![\\w-])`, 'i');
const ASSIGNMENT_OPERATORS = new Set([
  '=', '+=', '-=', '*=', '/=', '%=', '**=', '<<=', '>>=', '>>>=', '&=', '|=', '^=', '&&=', '||=', '??=',
]);
const isAssignment = event => event?.type === 'punctuator' && ASSIGNMENT_OPERATORS.has(event.value);

// **A call names a message when the key is there to read.** `t(dynamicKey)` is not a catalogue
// lookup anybody can check — it is an expression whose text arrives at run time, which is the class
// this gate calls undeclared — and accepting it because it *looks* like a lookup was the hole in the
// acceptance added a round ago. The key has to be one of the static literal calls
// the shared event stream projects, so this lint and the catalogue gate have one answer.
const namesAMessage = (expression) => {
  const trimmed = expression.trim();
  return messageCallsIn(trimmed).some(call => call.callIndex === 0);
};

// The value written at `at`, in whichever form it is in. `null` is "I cannot tell where this ends",
// which the caller turns into a failure — the reader never guesses a boundary it cannot see.
const readAttributeValue = (source, at, events) => {
  const literal = events.find(event => event.type === 'literal' && event.start === at);
  if (literal) return { text: source.slice(at + 1, literal.end - 1), quoted: true };
  if (source[at] === '"' || source[at] === "'" || source[at] === '`') return null;
  // Unquoted: an HTML attribute value ends at whitespace or `>`, an expression at the punctuation
  // that ends the statement or the call it sits in. Taking the first of either is what makes an
  // expression with a space in it stop early — and the failure message prints what was read, so the
  // declaration that answers it is the text in front of its author.
  const stop = source.slice(at).search(/[\s>;,)]/);
  if (stop <= 0) return null;
  return { text: source.slice(at, at + stop), quoted: false };
};

const markupAttributeSitesIn = (source) => {
  const sites = [];
  const pattern = new RegExp(`(?:^|\\s)(${TEXT_BEARING})\\s*=\\s*`, 'gi');
  for (const tag of source.matchAll(/<[A-Za-z][^>]*>/gs)) {
    for (const match of tag[0].matchAll(pattern)) {
      const at = tag.index + match.index + match[0].length;
      const quote = source[at];
      let end = at;
      if (quote === '"' || quote === "'") {
        end = source.indexOf(quote, at + 1);
        if (end < 0) {
          sites.push({ at, name: match[1].toLowerCase(), unreadable: source.slice(tag.index, at + 40) });
          continue;
        }
        sites.push({ at, name: match[1].toLowerCase(), text: source.slice(at + 1, end), quoted: true });
        continue;
      }
      while (end < source.length && !/[\s>]/.test(source[end])) end += 1;
      if (end === at) {
        sites.push({ at, name: match[1].toLowerCase(), unreadable: source.slice(tag.index, at + 40) });
        continue;
      }
      sites.push({ at, name: match[1].toLowerCase(), text: source.slice(at, end), quoted: false });
    }
  }
  return sites;
};

// Every text-bearing attribute `source` writes, in source order. JavaScript assignments come from
// lexical events; HTML attributes use HTML tag syntax, including tags embedded in template text.
const attributeSitesIn = (source) => {
  // Interpolated templates emit their inner events before the enclosing template event is closed;
  // source order makes the event after an assignment operator the value event in every shape.
  const events = javaScriptEvents(source).sort((left, right) => left.start - right.start);
  const sites = markupAttributeSitesIn(source);
  const add = (name, siteStart, valueEvent) => {
    // Comments and whitespace are absent from the event stream, so the next event owns the value
    // start. Falling off the stream preserves an unreadable site for a missing value.
    const at = valueEvent?.start ?? source.length;
    sites.push({
      at,
      name: name.toLowerCase(),
      ...(readAttributeValue(source, at, events) ?? { unreadable: source.slice(siteStart, at + 40) }),
    });
  };
  for (let i = 0; i < events.length; i += 1) {
    const event = events[i];
    if (event.type === 'identifier' && !/[\w$-]/.test(source[event.start - 1] ?? '')) {
      const name = source.slice(event.start).match(TEXT_BEARING_NAME)?.[0];
      if (name) {
        let operator = i + 1;
        while (events[operator]?.start < event.start + name.length) operator += 1;
        if (isAssignment(events[operator])) add(name, event.start, events[operator + 1]);
      }
    }
    if (event.type === 'punctuator' && event.value === '[') {
      const name = events[i + 1];
      const close = events[i + 2];
      const operator = events[i + 3];
      if (name?.type === 'literal' && name.static && TEXT_BEARING_NAME.test(name.value)
          && close?.type === 'punctuator' && close.value === ']' && isAssignment(operator)) {
        add(name.value, event.start, events[i + 4]);
      }
    }
    if (event.type === 'identifier' && event.name === 'setAttribute'
        && events[i - 1]?.type === 'punctuator' && events[i - 1].value === '.'
        && events[i + 1]?.type === 'punctuator' && events[i + 1].value === '(') {
      const name = events[i + 2];
      const comma = events[i + 3];
      if (name?.type === 'literal' && name.static && TEXT_BEARING_NAME.test(name.value)
          && comma?.type === 'punctuator' && comma.value === ',') {
        add(name.value, event.start, events[i + 4]);
      }
    }
  }
  return [...new Map(
    sites.map(site => [`${site.at}\0${site.name}\0${site.text ?? site.unreadable}`, site]),
  ).values()].sort((left, right) => left.at - right.at);
};

// **What a site is, for the list this gate pins.** `(file, attribute)` was the identity and it is a
// multiset: most of these sites share that pair with another one — **how many is asserted, not
// written here** — so a trade between two of them leaves the expectation untouched: remove one,
// leave a write the scan cannot read where it stood, add one back elsewhere, and the list is the
// list. What fills the site is the thing that moves
// when text moves, so it belongs to the identity.
//
// Not the position: line numbers churn under every edit above them, and a gate that fires on
  // unrelated change is a gate somebody switches off (the criterion was written to prevent that;
// role over position for the same reason). What is left indistinguishable is two sites in one file
// writing the same attribute with the **same** value, a trade that moves no text. How many of those
// there are is asserted with the rest — this file has typed that family of numbers wrong twice.
const siteIdentity = (file, site) => `${file} ${site.name} = ${site.text}`;

// **A receiver is any expression, and that sentence used to be false.** The pattern under it read a
// chain of `.name`, `(…)` and `[…]` with nothing nested inside — so
// `document.querySelector(selectorFor('#x'))[name]`, `(document.querySelector('#x'))[name]` and
// `rows[indices[0]].node[name]` were all unread while the comment claimed otherwise.
// Every one of them is a plausible accident, which is this lint's whole threat model, so the
// pattern moved rather than the promise.
//
// Reading them takes knowing which bracket closes which, which a regular expression cannot do — so
// the brackets are paired from the shared lexical events and the receiver is then read **backwards**
// from the write: an identifier, a `.name`
// before it, or a whole balanced group, as far left as those go. What it cannot read it names
// `<unreadable receiver>` and refuses anyway: a write it cannot describe is not a write it should
// pass, which is the arrangement the value reader already uses.
const bracketPairs = (events) => {
  const stack = [];
  const pairs = new Map();
  for (const event of events) {
    if (event.type !== 'punctuator') continue;
    if (event.value === '(' || event.value === '[') { stack.push(event); continue; }
    if (event.value === ')' || event.value === ']') {
      const open = stack.pop();
      if (open !== undefined) pairs.set(event.start, open.start);
    }
  }
  return pairs;
};

// Where the expression being written through starts, read right to left from its `[`.
const receiverStart = (source, bracketAt, pairs) => {
  let index = bracketAt - 1;
  let start = null;
  for (;;) {
    while (index >= 0 && /\s/.test(source[index])) index -= 1;
    if (index < 0) return start;
    const character = source[index];
    if (character === ')' || character === ']') {
      const open = pairs.get(index);
      if (open === undefined) return start;
      start = open;
      index = open - 1;
      continue;
    }
    if (/[\w$]/.test(character)) {
      while (index >= 0 && /[\w$]/.test(source[index])) index -= 1;
      start = index + 1;
      let before = index;
      while (before >= 0 && /\s/.test(source[before])) before -= 1;
      if (before >= 0 && source[before] === '.') { index = before - 1; continue; }
      return start;
    }
    return start;
  }
};

// Both shapes of "an attribute name this scan cannot read", in one function, so that what the gate
// refuses is a value a fixture can produce rather than a `match(…)` inside a loop over the corpus —
// the corpus has none of either (measured: 0 in 13 markup files), which is precisely why the guards
// need a fixture to be alive at all. The two are kept apart because their rules differ, and
// unifying them would quietly give `setAttribute` the declaration escape it has never had.
const computedNameWritesIn = source => ({
  setAttribute: (() => {
    const events = javaScriptEvents(source);
    return events.flatMap((event, index) => {
      if (event.type !== 'identifier' || event.name !== 'setAttribute') return [];
      if (events[index - 1]?.type !== 'punctuator' || events[index - 1].value !== '.') return [];
      const open = events[index + 1];
      const first = events[index + 2];
      if (open?.type !== 'punctuator' || open.value !== '(' || first?.type === 'literal') return [];
      const comma = events.slice(index + 2).find(candidate => (
        candidate.templateDepth === event.templateDepth
        && candidate.type === 'punctuator' && [',', ')'].includes(candidate.value)
      ));
      if (!comma) return [];
      return [`setAttribute(${source.slice(open.end, comma.start).trim()}, …)`];
    });
  })(),
  bracket: (() => {
    // **The name is balanced too, and it was not**. The receiver walked backwards through
    // balanced groups while the *name* was still a character class that stops at the first `]` — so
    // `document.querySelector('#x')[names[index]] = 'prose'` never reached `receiverStart` at all:
    // the match ended inside the name and the assignment was not there to find. The nested-receiver
    // fixture proved a nested receiver and said nothing about a nested name.
    //
    // So the assignment is found first — a `]` followed by an assignment operator and a literal —
    // and its opening `[`
    // comes from the same pair map the receiver already uses. One reader, both halves.
    const events = javaScriptEvents(source);
    const pairs = bracketPairs(events);
    return events.flatMap((event, index) => {
      if (event.type !== 'punctuator' || event.value !== ']') return [];
      if (!isAssignment(events[index + 1]) || events[index + 2]?.type !== 'literal') return [];
      const closing = event.start;
      const opening = pairs.get(closing);
      if (opening === undefined) return [];
      const name = source.slice(opening + 1, closing).trim();
      // A name beginning with a quote or backtick is deliberately outside this refusal; it can
      // continue as an assembled expression (`'ti' + suffix or `` `title${suffix}` ``).
      // excludes assembled names from this lint's mistake model. Exact quoted names are handled by
      // the readable-site scan separately.
      if (name.length === 0 || /^['"`]/.test(name)) return [];
      const start = receiverStart(source, opening, pairs);
      const receiver = start === null ? '<unreadable receiver>' : source.slice(start, opening).trim();
      return [`${receiver}[${name}]`];
    });
  })(),
});

// **The refusal itself, so that removing it is red.** The predicate above can be exercised by a
// fixture, but the check that acts on its answer could not: the corpus has nothing to refuse, so
// deleting both asserts out of the loop left every test passing — the dead-guard class one level up
// from the dead-guard shape exposed by the fixture. The corpus loop and
// the fixture now enter the gate through this one function.
//
// The two refusals are not the same rule. A bare identifier is the shape somebody arrives at by
// accident — a name held in a variable — and `setAttribute` is where that can be said flatly, because
// the call itself is the evidence that an attribute is being written; there is no declaration escape
// and there never has been. **The same rule spelled with brackets** refuses less:
// what can be established from outside is a **literal** written into a computed member, which is text
// shipping through a name nobody can read. With the value an expression too there is nothing to
// classify — no name, no words — and that is the line that also leaves `'ti' + 'tle'` alone, since
// nobody writes that by mistake and against somebody writing it on purpose this gate has no standing
// Deciding whether a receiver is an element would take knowing what `el` is, and a lint does
// not get a parser — so the bracket rule keeps the escape the flat one lacks: a declared receiver.
const refuseUnreadableComputedNames = (file, source, declared) => {
  const computed = computedNameWritesIn(source);
  assert.deepEqual(
    computed.setAttribute, [],
    `${file} sets an attribute whose name it computes — the scan cannot see what it writes`,
  );
  for (const write of computed.bracket) {
    assert.ok(
      Object.hasOwn(declared, write),
      `${file} writes a literal into ${write}, whose name this scan cannot read — spell the name `
        + 'out if it is an attribute, or declare here why that receiver is not an element',
    );
  }
};

// **Everything this gate reads out of one source, as one operation.** The refusal runs and the
// readable sites come back from the same call. With the refusal invoked from the corpus loop and the
// sites collected beside it, deleting only the refusal left both helpers alive while their
// **connection to the corpus was dead**.
//
// Making them one call is the same move as `whileHeld` — a right that can only be read by executing
// under it — and as the helper socket claimed by linking from a pin: two facts that have to imply
// each other are made one operation rather than two that a future edit can separate. Remove the
// audit now and the sites it returns disappear with it, so the identity list below goes red.
const auditSource = (file, source, declared) => {
  refuseUnreadableComputedNames(file, source, declared);
  const sites = [];
  for (const site of attributeSitesIn(source)) {
    assert.ok(
      !site.unreadable,
      `${file} writes a text-bearing attribute in a form this scan cannot read: `
        + `${JSON.stringify(site.unreadable)} — quote the value, or teach the reader that form`,
    );
    sites.push([file, site]);
  }
  return sites;
};

// Which parts of a value ship as text and which are computed. Brace-aware: `${count > 1 ? … : ''}`
// carries braces of its own, and stopping at the first `}` would read the tail of an interpolation
// as text somebody forgot to translate. `null` is an interpolation that never closes.
const splitInterpolations = (text) => {
  const statics = [];
  const expressions = [];
  let start = 0;
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] !== '$' || text[i + 1] !== '{') continue;
    let depth = 1;
    let j = i + 2;
    for (; j < text.length && depth > 0; j += 1) {
      if (text[j] === '{') depth += 1;
      else if (text[j] === '}') depth -= 1;
    }
    if (depth > 0) return null;
    statics.push(text.slice(start, i));
    expressions.push(text.slice(i + 2, j - 1));
    start = j;
    i = j - 1;
  }
  statics.push(text.slice(start));
  return { statics, expressions };
};

test('the attribute scan reads every form on its list, and says so when it cannot', () => {
  // A fixture and not the corpus, because **the corpus is the ceiling on what it can prove**: four
  // of the eleven lines below are written somewhere in this extension and the other seven are not,
  // and about those seven the corpus would keep saying nothing right up until somebody wrote one —
  // which is the miss this exists to make impossible. Every line here is legal in the file it would
  // be written in, and the scan that preceded this one read exactly the first of them.
  const fixture = [
    '<input placeholder="double">',
    "<input placeholder='single'>",
    '<input PLACEHOLDER="upper case, because HTML does not care">',
    '<input placeholder = "spaces around the equals sign">',
    '<input placeholder=unquoted>',
    'el.title = `a template literal ${t(\'ext.a\')}`;',
    'el.title = buttonConfig.label;',
    "el['title'] = 'the bracket form, which is ordinary JavaScript';",
    "el.setAttribute('aria-label', 'through setAttribute');",
    "el.setAttribute ('aria-label', 'a space before the parenthesis');",
    'el.title += " appended to what is already there";',
  ].join('\n');
  assert.deepEqual(attributeSitesIn(fixture).map(site => site.text), [
    'double',
    'single',
    'upper case, because HTML does not care',
    'spaces around the equals sign',
    'unquoted',
    "a template literal ${t('ext.a')}",
    'buttonConfig.label',
    'the bracket form, which is ordinary JavaScript',
    'through setAttribute',
    'a space before the parenthesis',
    ' appended to what is already there',
  ]);
  // A comparison is not a write, and a name that merely ends in one of these is not one of them
  assert.deepEqual(attributeSitesIn('if (el.title === x) f();\n<div data-title="machine data">'), []);
  // **And a value it cannot delimit is a failure rather than a skip.** That is the property the
  // whole arrangement rests on: the forms it reads are a list, so the forms it does not read have
  // to end up somewhere louder than a pass.
  assert.deepEqual(attributeSitesIn('el.title = ;').map(site => Boolean(site.unreadable)), [true]);
  assert.deepEqual(
    attributeSitesIn('<input placeholder="never closed').map(site => Boolean(site.unreadable)),
    [true],
  );

  // The other half of reading a value: which parts of it ship as text and which are computed.
  const split = splitInterpolations("Terminal Checkout — ${t('ext.header.options')}");
  assert.deepEqual(split.statics, ['Terminal Checkout — ', '']);
  assert.deepEqual(split.expressions, ["t('ext.header.options')"]);
  // Brace-aware, because `${count > 1 ? `…` : ''}` carries braces of its own — counting to the
  // first `}` would cut an interpolation in half and read the rest of it as text to translate.
  assert.deepEqual(splitInterpolations('${a ? `${b}` : ""}').expressions, ['a ? `${b}` : ""']);
  assert.equal(splitInterpolations('${never closed'), null);

  // And what counts as a message, which is the other half of what the readable list means: the key
  // has to be *in* the call. A lookup whose key arrives at run time returns whatever it returns.
  assert.ok(namesAMessage("t('ext.someKey')"), 'a call that names its key is a message');
  assert.ok(!namesAMessage('t(dynamicKey)'), 'a key that arrives at run time is not a checkable one');
});

test('two sites in one file that write the same attribute are told apart by what fills them', () => {
  // **`(file, attribute)` is not an identity**. Most of the sites in this extension
  // share their pair with another one — the corpus test below counts them, because a number typed
  // into a comment is one nobody re-derives — and a count-preserving three-way swap moves text
  // through the list without moving the list: take a site out, leave in its place a write whose name
  // the scan cannot read, and put a site back somewhere else. The two sources below are that swap.
  const identities = source => attributeSitesIn(source).map(site => siteIdentity('options.js', site)).sort();
  const before = [
    "row.placeholder = 'master';",
    "field.placeholder = `${t('ext.field.claudeInput.placeholder')}`;",
  ].join('\n');
  const after = [
    "document.querySelector('#row')[name] = 'Type a branch name';",
    "field.placeholder = `${t('ext.field.claudeInput.placeholder')}`;",
    "extra.placeholder = `${t('ext.field.tooltip.placeholder')}`;",
  ].join('\n');
  // This line is what keeps the fixture a *count-preserving* swap: by file and attribute name alone —
  // the identity this replaces — the two sources are indistinguishable, which is the defect.
  const byFileAndName = source => attributeSitesIn(source).map(site => `options.js ${site.name}`).sort();
  assert.deepEqual(byFileAndName(before), byFileAndName(after));
  // And by what fills each site they are not, in both directions: the literal that left is named, and
  // the message that arrived is named.
  assert.deepEqual(identities(before), [
    "options.js placeholder = ${t('ext.field.claudeInput.placeholder')}",
    'options.js placeholder = master',
  ]);
  assert.deepEqual(identities(after), [
    "options.js placeholder = ${t('ext.field.claudeInput.placeholder')}",
    "options.js placeholder = ${t('ext.field.tooltip.placeholder')}",
  ]);
});

test('a write whose attribute name the scan cannot read is refused, in every receiver shape', () => {
  // **The corpus cannot keep these guards alive.** Nothing in this extension writes an attribute
  // through a computed name — measured, 0 across the 13 markup files — so deleting either guard left
  // the suite green: a guard nothing can fail is dead. The fixture below is what fails without them,
  // one line per refusal.
  // **Through the gate's own refusal, not past it.** Asking `computedNameWritesIn` what it found
  // proves the predicate reads the shape; it says nothing about the check that acts on the answer,
  // and that check is unfailable from the corpus too — measured by toggling the commit that added
  // this test: deleting both asserts out of the loop left the suite green. So the fixture calls the
  // refusal, and what it asserts is that the refusal happens and names the write.
  const refused = (source) => {
    let failure = null;
    try {
      auditSource('fixture.js', source, {});
    } catch (error) {
      // Only a refusal is an answer here. Anything else — a typo in a name, a broken regex — stays
      // an error rather than being reshaped into a message this test then matches against.
      if (error.code !== 'ERR_ASSERTION') throw error;
      failure = error.message;
    }
    return failure;
  };
  // `setAttribute` is the flat case: the call itself is the evidence that an attribute is written, so
  // a name that is not a literal is refused whatever the value turns out to be.
  assert.match(refused("el.setAttribute(name, 'prose');"), /sets an attribute whose name it computes/);
  // Brackets carry no such evidence — the receiver could be a plain object — so what is refused is
  // the part that can be established from outside: a **literal** going into a name nobody can read
  // All four receiver shapes, because the reader that read only the first two is the finding,
  // and the message has to name the write it refused or the failure points at nothing:
  assert.match(refused("el[name] = 'prose';"), /writes a literal into el\[name\]/);
  assert.match(refused("page.form.el[name] = 'prose';"), /writes a literal into page\.form\.el\[name\]/);
  // The receiver is named whole: read as `node[name]`, this failure would send its reader to the
  // wrong expression.
  assert.match(refused("rows[0].node[name] = 'prose';"), /writes a literal into rows\[0\]\.node\[name\]/);
  // **A receiver that ends in a call is not a paraphrase of a simple receiver**, and a receiver that ends in a
  // call was read by neither pattern, so this exact line passed the gate.
  assert.match(
    refused("document.querySelector('#x')[name] = 'prose';"),
    /writes a literal into document\.querySelector\('#x'\)\[name\]/,
  );
  // **The remaining receiver shapes** are a call inside a call, a grouped receiver, and an index
  // inside an index.
  assert.match(
    refused("document.querySelector(selectorFor('#x'))[name] = 'prose';"),
    /writes a literal into document\.querySelector\(selectorFor\('#x'\)\)\[name\]/,
  );
  assert.match(
    refused("(document.querySelector('#x'))[name] = 'prose';"),
    /writes a literal into \(document\.querySelector\('#x'\)\)\[name\]/,
  );
  assert.match(
    refused("rows[indices[0]].node[name] = 'prose';"),
    /writes a literal into rows\[indices\[0\]\]\.node\[name\]/,
  );
  // **And a computed name that is itself an expression**: the reader balanced the
  // receiver and not the name, so this exact line was not seen at all.
  assert.match(
    refused("document.querySelector('#x')[names[index]] = 'user-facing prose';"),
    /writes a literal into document\.querySelector\('#x'\)\[names\[index\]\]/,
  );
  assert.match(refused("el[keys.title] = 'prose';"), /writes a literal into el\[keys\.title\]/);
  assert.match(refused("el[name] ??= 'user-facing prose';"), /writes a literal into el\[name\]/);
  assert.match(refused("el[name] ??= /* fallback */ 'prose';"), /writes a literal into el\[name\]/);
  assert.match(refused("el[name] |= 'prose';"), /writes a literal into el\[name\]/);
  assert.deepEqual(
    attributeSitesIn("el.title ||= 'user-facing prose';").map(site => site.text),
    ['user-facing prose'],
  );
  assert.deepEqual(
    attributeSitesIn("el.title ||= /* fallback */ 'prose';").map(site => site.text),
    ['prose'],
  );
  // A receiver it cannot describe is refused too, named for what it is rather than passed
  assert.match(refused("= 'prose';\n[name] = 'prose';"), /<unreadable receiver>\[name\]/);
  // And the two shapes that are outside on purpose. A literal name is not computed at all — the scan
  // above reads it as an ordinary site — and a computed write with no literal in it carries no text
  // to classify, which is the same line that leaves `'ti' + 'tle'` alone.
  assert.equal(refused("el['title'] = 'read as a site, not as a computed name';"), null);
  assert.equal(refused('counts[key] = total;'), null);
  // A declared receiver is accepted, which is the escape the bracket rule has and `setAttribute`
  // does not — the list in the gate is empty today, so this is the only place that shape runs.
  assert.equal(
    (() => {
      try {
        auditSource('fixture.js', "el[name] = 'prose';", { 'el[name]': 'declared' });
        return null;
      } catch (error) { return error.message; }
    })(),
    null,
  )
});

test('every text-bearing attribute in the markup is a message or a declared literal', () => {
  // **The scan looked at values and at interpolations, never at the static markup.**
  // A `placeholder`, `title`, `aria-label` or `alt` written straight into a tag is
  // invisible to every other check here: it is not a catalogue value, so the parity gates never see
  // it, and it is not built by `t(...)`, so the attribute-escaping gate never sees it either. A
  // sentence put there would ship untranslated in five languages with nothing red.
  //
  // **It read one file, and the file it read was not the one with the instances.**
  // `options.js` builds rows into the page and has static ones sitting in it; the
  // whole time, one of them the same branch-name class as the single declaration this list started
  // with. So the subject is every file that can carry markup, taken from the directory.
  //
  // **And it read one spelling of the syntax**: the readable forms are pinned by
  // the fixture above, and the four assignments this repository already writes with
  // spaces around the `=` had never been read by it. What that hole shows is not those four values,
  // which are fine — it is that a sentence written the same way would have been just as invisible.
  //
  // Each value is therefore one of three things. **A message**, filled in from a dictionary at
  // runtime — interpolated into the value, or the whole of it. A **declared literal**, named here
  // with the reason it is not prose — a name a command needs, or the product's own name, which is a
  // stated product non-goal. Or a **declared expression**, where the words are not in front of
  // us at all and what is declared instead is whose they are.
  const DECLARED_LITERALS = {
    main: 'the default branch name — it goes into a command, so it is not prose',
    master: 'a branch name, shown as the example that field takes — the same class as `main`',
    'remy-worker': 'a repository name, shown as the example that field takes',
    '{cd} && claude': 'a command template — its literals are what the command gate holds fixed',
    'Terminal Checkout —': 'the product name, which no language rewrites (a non-goal), and the dash '
      + 'that joins it to the message naming the page',
  };
  const DECLARED_EXPRESSIONS = {
    'buttonConfig.label': "the user's own button label, read back from their settings and shown as "
      + 'its tooltip — it is theirs, and translating it would rename the button they named',
    'listBatchBadgeLabel(result': 'the localized result label shared by a row badge title and aria label',
    'row.title': "GitHub's own row title, shown on the extension-owned list checkbox — it is page "
      + 'content rather than extension prose',
  };
  // The one shape of a computed name that ships text we can see: `el[name] = 'Copy to clipboard'`.
  // Nothing writes one, and the day something does it is declared here with the reason its receiver
  // is not an element — a plain object keyed by a variable is ordinary code, and this list is where
  // that gets declared with its reason.
  const DECLARED_COMPUTED_WRITES = {};
  // Every readable site in the tree, and the refusals that ran to produce them — one call per file,
  // so the list below cannot outlive the checks that guard it (`auditSource`).
  const found = MARKUP_FILES.flatMap(file => auditSource(file, read(file), DECLARED_COMPUTED_WRITES));
  // **The sites themselves, not how many there are.** A floor of twelve against sixteen let four of
  // them move into unread syntax in silence; an exact count closed that and still fixed only
  // cardinality — swap one recognized site for an unrecognized one, add a recognized one elsewhere,
  // and sixteen is sixteen.
  // **File and attribute name were not enough either**: that pair repeats, so a
  // trade between two sites sharing one left this list identical — the swap the fixture above runs is
  // exactly that trade, and how far the repetition goes is counted below. The identity
  // is `siteIdentity` — the same function the fixture above pins — and multiplicity stays, because a
  // set would stop noticing that one of two identical sites went away. Changing this list is a
  // reviewed edit: it says which attribute came or went, and what filled it.
  assert.deepEqual(found.map(([file, site]) => siteIdentity(file, site)).sort(), [
    'content.js aria-label = listBatchBadgeLabel(result',
    'content.js aria-label = row.title',
    'content.js title = buttonConfig.label',
    'content.js title = buttonConfig.label',
    'content.js title = buttonConfig.label',
    'content.js title = buttonConfig.label',
    'content.js title = listBatchBadgeLabel(result',
    'content.js title = row.title',
    "content.js title = tr('ext.list.batch.selection.empty'",
    "content.js title = tr('ext.list.batch.selection.tooMany'",
    'options.html placeholder = main',
    "options.js aria-label = ${t('ext.card.reorder.aria')}",
    "options.js aria-label = ${t('ext.claudeInput.reorder.aria', j + 1)}",
    "options.js placeholder = ${t('ext.field.claudeInput.placeholder')}",
    "options.js placeholder = ${t('ext.field.tooltip.placeholder')}",
    'options.js placeholder = master',
    'options.js placeholder = remy-worker',
    'options.js placeholder = {cd} && claude',
    "options.js title = ${t('ext.button.remove')}",
    "options.js title = ${t('ext.button.remove')}",
    "options.js title = ${t('ext.card.duplicate.tooltip')}",
    "options.js title = ${t('ext.card.palette.tooltip', e)}",
    "options.js title = ${t('ext.reorder.tooltip')}",
    "options.js title = ${t('ext.reorder.tooltip')}",
    'options.js title = Terminal Checkout — ${t(\'ext.header.options\')}',
  ]);
  // **The counts are executed, never typed.** Three sentences in this file used to carry "how many
  // sites share a `(file, attribute)` pair"; one of them said eleven when the answer is fourteen, and
  // it survived the standing step that recorded it as fixed. A ledger row got the neighbouring
  // number wrong the same way. So the numbers live here, computed from the list above,
  // and a change to the corpus is a red test rather than a sentence nobody re-derives.
  const pairs = found.map(([file, site]) => `${file} ${site.name}`);
  const repeated = pairs.filter(pair => pairs.filter(other => other === pair).length > 1);
  assert.equal(repeated.length, 24, `${repeated.length} sites share a (file, attribute) pair`);
  assert.equal(new Set(repeated).size, 5, 'the number of repeated (file, attribute) pairs moved');
  const identities = found.map(([file, site]) => siteIdentity(file, site));
  const sameValueToo = identities.filter(id => identities.filter(other => other === id).length > 1);
  assert.equal(sameValueToo.length, 8, `${sameValueToo.length} sites are indistinguishable even by value`);
  const declared = [];
  for (const [file, site] of found) {
    if (!site.quoted) {
      // Unquoted in a script is an expression — its text is decided at run time, so what is asked
      // of it is where that text comes from. (HTML permits an unquoted value, which is text the
      // user reads; nobody writes one here, and one that appeared would land in this branch too and
      // be refused rather than passed, which is the direction to be wrong in.)
      //
      // A message call is the good answer to that question and is taken as one, the same as an
      // interpolated `${t(…)}` a few lines down. Nothing in the extension writes `title = t(…)`
      // today; refusing it would be this lint firing on the pattern it exists to encourage, which
      // is how a lint gets switched off. **Only with the key in the call**, though — see
      // `namesAMessage`: a lookup whose key arrives at run time is an expression like any other.
      if (namesAMessage(site.text)) continue;
      assert.ok(
        Object.hasOwn(DECLARED_EXPRESSIONS, site.text),
        `${file} fills a text-bearing attribute from ${JSON.stringify(site.text)} — `
          + 'declare here whose text that is, or fill it from a message',
      );
      declared.push(site.text);
      continue;
    }
    const parts = splitInterpolations(site.text);
    assert.ok(parts, `${file}: an interpolation in ${JSON.stringify(site.text)} never closes`);
    // An interpolated attribute has to interpolate a **message**, and then the escaping gate covers
    // it. Anything else in there — a variable holding prose, a string built somewhere else — is
    // outside every check in this file, which is the hole the static ones were in
    for (const expression of parts.expressions) {
      assert.ok(
        namesAMessage(expression),
        `${file} builds a text-bearing attribute from ${JSON.stringify(expression)} — `
          + 'interpolate a message named by its key so the escaping and parity gates can see it',
      );
    }
    // The text between the interpolations is what ships as written, and a value that interpolates
    // nothing is all text. Whitespace between two messages is not a sentence, so it is skipped.
    for (const chunk of parts.statics) {
      const literal = chunk.trim();
      if (!literal) continue;
      assert.ok(
        Object.hasOwn(DECLARED_LITERALS, literal),
        `${file} carries the untranslated attribute text ${JSON.stringify(literal)} — `
          + 'make it a message, or declare it here with the reason it is a literal',
      );
      declared.push(literal);
    }
  }
  // ...and a declaration that stopped being true has to go, or the list becomes a place where old
  // judgements accumulate unread — the same rule the duplicate-value tables are held to.
  for (const literal of [...Object.keys(DECLARED_LITERALS), ...Object.keys(DECLARED_EXPRESSIONS)]) {
    assert.ok(declared.includes(literal), `${literal} is declared but no longer in the markup`);
  }
});

test('what a <code> span holds is a literal, so it is identical in every locale', () => {
  // This is the half of the markup policy that matters: a tag around translated text may be
  // translated with it, but `<code>{branch_underbar}</code>` is a variable name, and a translation
  // that helpfully localises it produces a command the app rejects as an unknown variable.
  let compared = 0;
  for (const key of markupKeys) {
    const spans = codeSpansOf(liveMessageFor('en', key));
    if (!spans.length) continue;
    for (const tag of TC_I18N_LOCALES) {
      assert.deepEqual(codeSpansOf(liveMessageFor(tag, key)), spans, `${tag}/${key} rewrote a literal`);
    }
    compared += spans.length;
  }
  assert.ok(compared >= 20, `only ${compared} literals were compared`);
});

test('prose that names a control receives the label, it does not spell it out again', () => {
  // The app found this class already broken — body text saying `[권한 요청]` next to a button
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
      const value = liveEntryFor(tag, key);
      assert.ok(livePlaceholderNamesFor(value).length >= labels.length, `${tag}/${key}: fewer placeholders than labels`);
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
    const english = liveMessageFor('en', key);
    for (const label of labels) {
      const literal = liveMessageFor('en', label);
      const spelledOut = new RegExp(`(^|[^\\w>])${literal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^\\w<]|$)`);
      assert.ok(!spelledOut.test(english), `en/${key} spells "${literal}" out instead of quoting it`);
    }
  }
});

test('a count sits behind a noun, and the two outcomes are two messages', () => {
  // The English needed `command`/`commands` and `was`/`were` to agree with two counts, and a
  // translation cannot be assembled out of the pieces that made them agree — so the count moved
  // behind a noun and a colon, where nothing inflects, and each outcome became its own message.
  for (const tag of TC_I18N_LOCALES) {
    for (const key of ['ext.migration.applied', 'ext.migration.appliedWithDeclined']) {
      const value = liveMessageFor(tag, key);
      assert.ok(!/\(s\)/.test(value), `${tag}/${key} still carries an English plural marker`);
    }
  }
  assert.match(liveMessageFor('en', 'ext.migration.applied'), /^Commands updated in the form: \$ARG1\$\./);
  // and the branch that produced the plural is gone from the source
  assert.ok(!/command\$\{applied === 1/.test(optionsJs), 'the plural branch is still in options.js');
  assert.ok(!/\? 'was' : 'were'/.test(optionsJs), 'the was/were branch is still in options.js');
});

test('the markup ships no prose, so there is nothing to paint in the wrong language', () => {
  // The first paint is the whole question on this page: unlike a GitHub page, which the user is
  // already reading when a button appears, the options page is text from edge to edge the moment it
  // opens. English left in the markup would be painted first and translated afterwards for every
  // user whose language is not English — so the markup holds ids and the fill happens while the
  // parser is still blocked on options.js, from Chrome's catalogue, which answers without waiting.
  // There is no cache correction or locale redraw in this consumer.
  let localizedNodes = 0;
  for (const file of HTML_FILES) {
    for (const match of read(file).matchAll(/data-i18n="[^"]+"[^>]*>([^<]*)</g)) {
      localizedNodes += 1;
      assert.equal(match[1].trim(), '', `${file} ships prose in a localized node: ${match[0].slice(0, 70)}`);
    }
  }
  // A loop over no matches is a test that says nothing while reading like one that says a lot — a
  // A count distinguishes an empty scan from a scan that actually checked its subject.
  assert.ok(localizedNodes > 30, `only ${localizedNodes} localized nodes were read`);
  // The document language and the synchronous fill, in that order, at the top level of the script.
  const first = optionsJs.indexOf('applyDocumentLanguage();');
  const fill = optionsJs.indexOf('applyStaticText();');
  assert.ok(first > 0 && fill > first, 'the page no longer fills itself synchronously');
  assert.ok(!/adoptLocaleFromCache|localeRenderer/.test(optionsJs), 'the retired locale redraw still runs');
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
// The rest of the extension's strings.
//
// The judgement this item turns on is **which strings a user actually sees**, and it has three
// answers rather than two. Visible: drawn on a page or the options form. Diagnostic: `console.*`,
// English by policy. And **latent** — written for a user, reaching only the console
// today, and locale-dependent the moment anything displays it. The refusal messages are that third
// kind, and pretending they were either of the other two is what a trace prevented.
// ---------------------------------------------------------------------------------------------

test('a preset says its name when it is read, not the one it loaded with', () => {
  // The options page's dropdown is closed at the source: the preset resolves
  // when read, so no consumer has to remember to re-read it.
  //
  // **The runtime source of the language.** Chrome picks the catalogue and the lookup asks it every
  // time. The backend moves instead, which is the same question one layer down: is
  // the name being resolved now, or was it frozen when this file loaded?
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const { PR_PRESETS, ISSUE_PRESETS, REPO_PRESETS } =
    vm.runInThisContext('({ PR_PRESETS, ISSUE_PRESETS, REPO_PRESETS })');
  const previous = installMessageBackend(catalogueBackend('en'));
  try {
    const english = PR_PRESETS[0].name;
    const command = PR_PRESETS[0].command;
    const faces = [...PR_PRESETS, ...ISSUE_PRESETS, ...REPO_PRESETS].map(preset => preset.face);
    installMessageBackend(catalogueBackend('ko'));
    assert.notEqual(PR_PRESETS[0].name, english, 'the preset name froze at load');
    // The other two halves must *not* move. The command is obvious; the face is the one that used
    // to be a message key, and a translated face changes the button's shape through `isTextFace`
    // rather than just its wording.
    assert.equal(PR_PRESETS[0].command, command);
    assert.deepEqual(
      [...PR_PRESETS, ...ISSUE_PRESETS, ...REPO_PRESETS].map(preset => preset.face), faces,
      'a preset face followed the language',
    );
    installMessageBackend(catalogueBackend('en'));
    assert.equal(PR_PRESETS[0].name, english, 'it did not come back');
  } finally {
    installMessageBackend(previous);
  }
});

test('the button drawn when nothing is stored is resolved when it is read too', () => {
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const { BUTTON_KINDS } = vm.runInThisContext('({ BUTTON_KINDS })');
  const previous = installMessageBackend(catalogueBackend('en'));
  try {
    // The label, not the face: the default button reads both through to its preset, and only the
    // label is a translation now.
    const english = BUTTON_KINDS.repo.defaults[0].label;
    const command = BUTTON_KINDS.repo.defaults[0].command;
    const face = BUTTON_KINDS.repo.defaults[0].face;
    installMessageBackend(catalogueBackend('ko'));
    assert.notEqual(BUTTON_KINDS.repo.defaults[0].label, english);
    // ...and what it runs does not, which is the half that must not move
    assert.equal(BUTTON_KINDS.repo.defaults[0].command, command);
    assert.equal(BUTTON_KINDS.repo.defaults[0].face, face, 'the default button face followed the language');
  } finally {
    installMessageBackend(previous);
  }
});

test('a saved button keeps the words it was saved with', () => {
  // The residual, pinned so it stays a decision rather than a surprise: `toStoredButton` writes
  // text, so a button created in one language keeps that language after a switch. Following the
  // language would mean a persistent id in the stored schema — a SETTINGS_VERSION bump, which this
  // plan does not make.
  const { installMessageBackend } = vm.runInThisContext('({ installMessageBackend })');
  const { appendButton, toStoredButton, BUTTON_KINDS } =
    vm.runInThisContext('({ appendButton, toStoredButton, BUTTON_KINDS })');
  const previous = installMessageBackend(catalogueBackend('ko'));
  try {
    const [added] = appendButton([], BUTTON_KINDS.pr);
    const stored = toStoredButton(added);
    installMessageBackend(catalogueBackend('en'));
    assert.equal(toStoredButton(stored).label, stored.label, 'a stored label moved with the language');
    assert.ok(stored.label.length > 0);
  } finally {
    installMessageBackend(previous);
  }
});

test('the messages that only reach a console are not in the dictionaries', () => {
  // The boundary, stated as a set. `console.*` is an English diagnostic surface by policy, and a
  // key for one of those would be a translation nobody reads — so the gate is that none of the
  // catalogue's values is one of these sentences.
  // Every locale, not English alone: the sweep that re-ran after these fixes found this one
  // reading a single catalogue for no reason — a sweep run before the fixes does
  // not cover them). A translation that left one of these sentences in English would be the
  // case it misses, and widening costs one line.
  const values = new Set(TC_I18N_LOCALES.flatMap(liveValuesFor));
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
test('a translation cannot break out of an HTML attribute', () => {
  // The card template interpolates messages into `title="…"` and `placeholder="…"`. The other gates
  // check tags and placeholders and would not notice a quote, and one `"` in a translation ends the
  // attribute and turns the rest of the sentence into markup.
  // **Read off the same scan the gate above uses**, rather than a second pattern that named three
  // of the six attributes, one of the quotings and one file. Two patterns for one
  // subject drift, and this one had drifted already: it could not see a message interpolated into
  // an `alt`, into `title = ` with spaces, or into any file but `options.js`.
  const attributeKeys = new Set();
  for (const file of MARKUP_FILES) {
    for (const site of attributeSitesIn(read(file))) {
      for (const expression of splitInterpolations(site.text ?? '')?.expressions ?? []) {
        const named = messageCallsIn(expression.trim()).find(call => call.callIndex === 0);
        if (named) attributeKeys.add(named.key);
      }
    }
  }
  assert.ok(attributeKeys.size >= 5, `only ${attributeKeys.size} attribute interpolations found`);
  // **Every shipped language.** The machine-translated values are included because they are the
  // most likely to carry a stray quote. A marker planted in `zh-Hant` must fail this gate rather
  // than pass because only a subset of locales was checked.
  for (const key of attributeKeys) {
    for (const tag of TC_I18N_LOCALES) {
      const value = liveMessageFor(tag, key);
      assert.ok(!value.includes('"'), `${tag}/${key} would close the attribute it is written into`);
      assert.ok(!value.includes('<'), `${tag}/${key} carries markup into an attribute`);
    }
  }
});

test('no text ships in the markup without a message behind it', () => {
  // The source gate's F class, on this side: a string nobody localized is invisible to a gate that only
  // inspects the elements already carrying `data-i18n`. This reads the other direction — every text
  // node in the body — and refuses anything not on the whitelist below.
  // Every page, taken from the directory — the same reason `keysInHtml` is.
  const body = HTML_FILES.map((file) => {
    const html = read(file);
    // A fragment need not have one; what matters is that no markup is skipped for lacking it
    return html.includes('<body>') ? html.slice(html.indexOf('<body>')) : html;
  }).join('\n');
  // Whitelisted, with the reason each one is permanent:
  //   `terminal-checkout` / `Terminal Checkout` — the product and command name (an explicit non-goal)
  //   `❯` `▊` `⏎` `$` `⠿` `✕` `×` `●` `⚠` — symbols and cursors, which no language rewrites
  //   `/` `·` `-` — punctuation between them
  // A run of permanent pieces is permanent: the heading is `terminal-checkout ·` next to the
  // localized word, and the parser hands that back as one text node.
  const permanent = /^(terminal-checkout|Terminal Checkout|[❯▊⏎$⠿✕×●⚠·/\-—|\s])+$/;
  const stray = [];
  let nodes = 0;
  for (const match of body.matchAll(/>([^<>]+)</g)) {
    nodes += 1;
    const text = match[1].replace(/\s+/g, ' ').trim();
    if (!text || permanent.test(text)) continue;
    stray.push(text);
  }
  assert.deepEqual(stray, [], 'markup carries text that no message owns');
  // An empty list means either that the markup is clean or that the scan read nothing, and those
  // two look identical from here
  assert.ok(nodes > 100, `only ${nodes} text nodes were read`);
});
// ---------------------------------------------------------------------------------------------
// What only becomes checkable once five locales exist.
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
// switches off (the standard gate set), so the bare-word literals are matched as words.
const COMMAND_LITERALS = [
  /\{cd\}/g, /\{repo\}/g, /\{owner\}/g, /\{number\}/g, /\{pr\}/g, /\{issue\}/g,
  /\{branch\}/g, /\{base\}/g,
  /\{main\}/g, /\{branch_underbar\}/g, /z \{repo\}/g,
  /\bstorage\.sync\b/g, /chrome:\/\/extensions/g, /\bgit pull\b/g,
  /\bgh\b/g, /\bclaude\b/g, /\bzoxide\b/g, /\bbrew install\b/g,
];

test('a command literal reads the same in every language', () => {
  // The most dangerous thing a translator can do to this catalogue is translate `z {repo}`. It is
  // not a phrase; it is what the user's button will run. These sit in plain sentences with no
  // markup around them, so the `<code>` gate above cannot see them.
  // **The expected count is derived from all locales, not English.** Comparing locales to each other
  // means a literal dropped from any one locale disagrees with the rest; English has no special
  // standing and cannot switch the check off by omitting the literal.
  //
  // The remaining hole is deliberate and small: a literal deleted from all five at once leaves them
  // agreeing, and nothing here can tell that from a token that was never there. That is one act
  // across five files, not the slip this catches.
  // **What this compares is the multiset, and calling it "pinned identical" was an overstatement**
  // Every locale must carry each literal the same
  // number of times; where in the sentence they sit is not compared.
  //
  // **Order is not asserted because translations do not preserve it — measured, not assumed.**
  // Strengthening this to a sequence comparison was tried and it failed on shipped, *correct*
  // Korean: `ext.migration.v1.describe` reads `{cd}, z {repo}, {repo}` in English and
  // `z {repo}, {repo}, {cd}` in Korean, because the clause naming the old form comes first there.
  // A gate that fires on a good translation is one somebody switches off (the standard gate set),
  // so the claim comes down rather than the gate going up. What is left uncovered is a translation
  // that keeps every token and reorders them into a different meaning; nothing here can tell that
  // from ordinary word order, and no rule over these strings can.
  let compared = 0;
  for (const key of livePhysicalKeysFor('en')) {
    for (const literal of COMMAND_LITERALS) {
      const counts = TC_I18N_LOCALES
        .filter(tag => LIVE_CATALOGUES[tag][key] !== undefined) // the key gate owns that failure
        .map(tag => [tag, (LIVE_CATALOGUES[tag][key].message.match(literal) ?? []).length]);
      const highest = Math.max(...counts.map(([, n]) => n));
      if (highest === 0) continue; // no locale claims this literal in this message
      for (const [tag, found] of counts) {
        assert.equal(
          found, highest,
          `${tag}/${key}: ${literal} appears ${found} times, ${highest} elsewhere`,
        );
      }
      compared += 1;
    }
  }
  assert.ok(compared >= 20, `only ${compared} literal occurrences were compared`);

  // The `{...}` tokens above are only worth comparing if they are variables the app actually
  // substitutes, and that canon lives in defaults.js rather than in this list — a token renamed
  // there would leave this gate faithfully comparing a string nothing fills in.
  const defaults = read('defaults.js');
  const known = new Set([
    ...[...defaults.matchAll(/'([a-z_]+)'/g)].map(m => m[1]),
  ]);
  for (const literal of COMMAND_LITERALS) {
    const brace = /^\\\{([a-z_]+)\\\}$/.exec(literal.source);
    if (brace) {
      assert.ok(known.has(brace[1]), `{${brace[1]}} is not a variable defaults.js knows about`);
    }
  }
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
  const hans = LIVE_CATALOGUES['zh-Hans'];
  const hant = LIVE_CATALOGUES['zh-Hant'];
  const en = LIVE_CATALOGUES.en;

  for (const [left, right, label] of [
    [hans, hant, 'zh-Hant is a copy of zh-Hans'],
    [hant, en, 'zh-Hant is a copy of English'],
    [hans, en, 'zh-Hans is a copy of English'],
  ]) {
    const same = Object.keys(left).filter(key => left[key]?.message === right[key]?.message);
    assert.ok(
      same.length < Object.keys(left).length,
      `${label}; first unchanged key: ${same[0] ?? '<none>'}`,
    );
  }

  let checked = 0;
  for (const [simplified, traditional] of SCRIPT_PAIRS) {
    const inHans = Object.values(hans).some(entry => entry.message.includes(simplified));
    const inHant = Object.values(hant).some(entry => entry.message.includes(traditional));
    if (!inHans && !inHant) continue;
    checked += 1;
    const simplifiedInTraditional = Object.entries(hant).find(([, entry]) => entry.message.includes(simplified));
    assert.equal(
      simplifiedInTraditional,
      undefined,
      `zh-Hant/${simplifiedInTraditional?.[0] ?? '<unknown>'} contains the simplified form "${simplified}"`,
    );
    const traditionalInSimplified = Object.entries(hans).find(([, entry]) => entry.message.includes(traditional));
    assert.equal(
      traditionalInSimplified,
      undefined,
      `zh-Hans/${traditionalInSimplified?.[0] ?? '<unknown>'} contains the traditional form "${traditional}"`,
    );
  }
  assert.ok(checked >= 4, `only ${checked} script-sensitive characters were found to compare`);
});

test('a translation that is still English is caught where English is not the answer', () => {
  // A value byte-identical to English is the fingerprint of a key that was skipped. It is also
  // legitimate for a product name, a command, or a bare number — so this counts rather than
  // forbids, and the threshold is what makes it a gate instead of a nuisance. **A gate people turn
  // off is worse than no gate** (the standard gate set), and a per-key rule here would fire on
  // `main branch` and `Terminal Checkout` forever.
  // Metadata is out of both halves of the ratio: `ext.meta.catalogueTag` is a tag, not a
  // sentence, and counting it would let the denominator grow with values no translator ever sees.
  const metadata = new Set(TC_I18N_METADATA_KEYS.map(chromeMessageId));
  const en = Object.fromEntries(
    Object.entries(LIVE_CATALOGUES.en).filter(([key]) => !metadata.has(key)),
  );
  const total = Object.keys(en).length;
  for (const tag of TC_I18N_LOCALES) {
    if (tag === 'en') continue;
    const identical = Object.entries(en).filter(([key, entry]) => LIVE_CATALOGUES[tag][key]?.message === entry.message);
    assert.ok(
      identical.length < total * 0.2,
      `${tag}: ${identical.length}/${total} values are byte-identical to English — `
        + `${identical.slice(0, 5).map(([k]) => k).join(', ')}`,
    );
  }
});

test('no extension-root name starts with an underscore except the ones Chrome itself owns', () => {
  // Chrome refuses to load an unpacked extension whose root contains any other `_`-prefixed
  // name — "Filenames starting with \"_\" are reserved for use by the system" — so a directory
  // that every VM-based gate here loads happily can still make the real loader reject the whole
  // folder (measured: `_i18n/` did exactly that on first load). `_locales` is Chrome's own
  // catalogue directory; nothing else may claim the prefix.
  const chromeOwned = new Set(['_locales']);
  const reserved = fs.readdirSync(extension)
    .filter(name => name.startsWith('_') && !chromeOwned.has(name));
  assert.deepEqual(reserved, [], `Chrome will refuse to load the extension: ${reserved.join(', ')}`);
});
