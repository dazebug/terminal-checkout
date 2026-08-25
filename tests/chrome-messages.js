// The backend the tests install in place of `chrome.i18n.getMessage`.
//
// **It is a double for somebody else's rule, and it proves nothing about Chrome.** Substitution,
// `$$` escaping and the empty string for a missing name are what Chrome documents; whether Chrome
// *does* them, and which catalogue it picks for a display language we do not ship, is settled by
// loading the extension in a real browser — which is why that load is a release gate rather than
// something this file pretends to cover.
//
// What it is for is narrower and worth having: Node has no `chrome`, so without an installed backend
// every lookup throws. Reading the catalogues Chrome will actually read — the derived
// `_locales`, not the dictionaries they came from — keeps these tests on the same side of the
// migration as the product.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const extension = path.join(__dirname, '..', 'extension');

// `$NAME$` is replaced by the substitution its declaration names; `$$` is a literal dollar; a name
// with no declaration contributes nothing, which is what Chrome does rather than an error.
const substitute = (entry, substitutions) => entry.message.replace(
  /\$([A-Za-z0-9_@]+)\$|\$\$/g,
  (whole, name) => {
    if (whole === '$$') return '$';
    const declared = entry.placeholders && entry.placeholders[name];
    if (!declared) return '';
    const position = Number(String(declared.content).slice(1));
    return substitutions[position - 1] ?? '';
  },
);

// A backend over one shipped catalogue. The directory is Chrome's spelling (`zh_CN`), because that
// is the name of the thing being emulated.
const catalogueBackend = (directory = 'en') => {
  const file = path.join(extension, '_locales', directory, 'messages.json');
  const messages = JSON.parse(fs.readFileSync(file, 'utf8'));
  return (id, substitutions = []) => (
    Object.hasOwn(messages, id) ? substitute(messages[id], substitutions) : ''
  );
};

module.exports = { catalogueBackend, substitute };
