const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const readmes = [
  { file: 'README.md', appLocale: 'en', extensionLocale: 'en' },
  { file: 'README.ko.md', appLocale: 'ko', extensionLocale: 'ko' },
  { file: 'README.ja.md', appLocale: 'ja', extensionLocale: 'ja' },
  { file: 'README.zh-Hant.md', appLocale: 'zh-Hant', extensionLocale: 'zh_TW' },
];

function appCatalogueValues(locale) {
  const file = path.join(root, 'app/Sources/App/Resources', `${locale}.lproj/Localizable.strings`);
  const result = spawnSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' });
  assert.equal(result.status, 0, `could not read app catalogue ${file}: ${result.stderr}`);
  return Object.values(JSON.parse(result.stdout));
}

function extensionCatalogueValues(locale) {
  const file = path.join(root, 'extension/_locales', locale, 'messages.json');
  return Object.values(JSON.parse(fs.readFileSync(file, 'utf8'))).map(entry => entry.message);
}

function labelsOutsideCodeBlocks(markdown) {
  const labels = [];
  let fence = null;

  for (const [index, line] of markdown.split(/\r?\n/).entries()) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (marker) {
      const current = marker[1];
      if (fence === null) fence = current;
      else if (current[0] === fence[0] && current.length >= fence.length) fence = null;
      continue;
    }
    if (fence !== null) continue;

    for (const match of line.matchAll(/\[([^\]\r\n]+)\](?![([]|:)/g)) {
      if (match[1].startsWith('"')) continue;
      labels.push({ label: match[1], line: index + 1 });
    }
  }
  return labels;
}

test('bracketed README labels are catalogue values for their language', () => {
  const englishValues = new Set([
    ...appCatalogueValues('en'),
    ...extensionCatalogueValues('en'),
  ]);
  const failures = [];

  for (const { file, appLocale, extensionLocale } of readmes) {
    const accepted = new Set([
      ...appCatalogueValues(appLocale),
      ...extensionCatalogueValues(extensionLocale),
      ...englishValues,
    ]);
    const markdown = fs.readFileSync(path.join(root, file), 'utf8');
    for (const { label, line } of labelsOutsideCodeBlocks(markdown)) {
      if (!accepted.has(label)) failures.push(`${file}:${line} [${label}]`);
    }
  }

  assert.deepEqual(failures, [], `README labels missing from the catalogues:\n${failures.join('\n')}`);
});
