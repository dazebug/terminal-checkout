import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repository = path.resolve(import.meta.dirname, '..');
const swiftTests = path.join(repository, 'app', 'Tests');
const sourceAuditDeclaration = path.join(
  repository,
  'app',
  'Sources',
  'TestSupport',
  'SourceAudit.swift',
);

const swiftFilesUnder = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
  const entryPath = path.join(directory, entry.name);
  if (entry.isDirectory()) return swiftFilesUnder(entryPath);
  return entry.isFile() && entry.name.endsWith('.swift') ? [entryPath] : [];
});

const lineAt = (source, offset) => source.slice(0, offset).split('\n').length;

const skipSwiftString = (source, start) => {
  let cursor = start;
  while (source[cursor] === '#') cursor += 1;
  if (source[cursor] !== '"') return start + 1;
  const hashes = cursor - start;
  const multiline = source.startsWith('"""', cursor);
  const opening = '"'.repeat(multiline ? 3 : 1);
  const closing = opening + '#'.repeat(hashes);
  const end = source.indexOf(closing, cursor + opening.length);
  return end === -1 ? source.length : end + closing.length;
};

const swiftTokens = source => {
  const tokens = [];
  let index = 0;
  while (index < source.length) {
    const character = source[index];
    const next = source[index + 1];
    if (/\s/.test(character)) {
      index += 1;
      continue;
    }
    if (character === '/' && next === '/') {
      const newline = source.indexOf('\n', index + 2);
      index = newline === -1 ? source.length : newline + 1;
      continue;
    }
    if (character === '/' && next === '*') {
      let depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth += 1;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth -= 1;
          index += 2;
        } else {
          index += 1;
        }
      }
      continue;
    }
    if (character === '"' || (character === '#' && next === '"')) {
      index = skipSwiftString(source, index);
      continue;
    }
    if (/[A-Za-z_]/.test(character)) {
      const start = index;
      index += 1;
      while (/[A-Za-z0-9_]/.test(source[index] ?? '')) index += 1;
      tokens.push({ value: source.slice(start, index), start, end: index });
      continue;
    }
    tokens.push({ value: character, start: index, end: index + 1 });
    index += 1;
  }
  return tokens;
};

const endOfArgument = (source, start) => {
  const stack = [];
  let index = start;
  while (index < source.length) {
    const character = source[index];
    const next = source[index + 1];
    if (character === '/' && next === '/') {
      const newline = source.indexOf('\n', index + 2);
      index = newline === -1 ? source.length : newline + 1;
      continue;
    }
    if (character === '/' && next === '*') {
      let depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth += 1;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth -= 1;
          index += 2;
        } else {
          index += 1;
        }
      }
      continue;
    }
    if (character === '"' || (character === '#' && next === '"')) {
      index = skipSwiftString(source, index);
      continue;
    }
    if ('([{'.includes(character)) {
      stack.push(character);
    } else if (')]}'.includes(character)) {
      if (stack.length === 0) return index;
      stack.pop();
    } else if (character === ',' && stack.length === 0) {
      return index;
    }
    index += 1;
  }
  return source.length;
};

const readTargetKind = (source, token, argumentEnd, receiver) => {
  const expression = source.slice(token.end + 1, argumentEnd);
  const dataPath = /(?:\/Resources\/|\/_locales\/|\/_i18n\/|\.strings\b|\.plist\b|\.json\b|\.toml\b|\/marker\b)/i;
  const sourcePath = /(?:\/Sources(?:\/|\b)|\.swift\b|\.js\b|\.sh\b)/i;
  if (dataPath.test(expression)) return 'data';
  if (sourcePath.test(expression)) return 'source';
  if (receiver === 'Data') return 'data';
  return 'unknown';
};

const sourceReadSitesIn = (file, source) => {
  const tokens = swiftTokens(source);
  const sites = [];
  tokens.forEach((token, index) => {
    // The read family is recognized by its argument-label grammar, not by a list of API names.
    // `contentsOfDirectory` is a directory enumeration, not a file-content read.
    if (!token.value.startsWith('contentsOf') || token.value.endsWith('Directory')) return;
    const colon = tokens[index + 1];
    if (!colon || colon.value !== ':') return;
    const argumentEnd = endOfArgument(source, colon.end);
    const receiver = tokens[index - 2]?.value;
    sites.push({
      file: path.relative(repository, file),
      line: lineAt(source, token.start),
      label: token.value,
      receiver,
      kind: readTargetKind(source, token, argumentEnd, receiver),
    });
  });
  return sites;
};

const endOfCall = (source, open) => {
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = open; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (character === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === '*' && next === '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (character === '/' && next === '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === '/' && next === '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      continue;
    }
    if (character === '(') depth += 1;
    if (character === ')' && --depth === 0) return index;
  }
  return -1;
};

const sourceAuditSitesIn = (file, source) => {
  const sites = [];
  const callPattern = /\bauditSource\s*\(/g;
  for (let match = callPattern.exec(source); match; match = callPattern.exec(source)) {
    const open = source.indexOf('(', match.index);
    const close = endOfCall(source, open);
    assert.notEqual(close, -1, `${file}: auditSource call has no closing parenthesis`);
    const argumentsSource = source.slice(open + 1, close);
    const claims = [...argumentsSource.matchAll(/\bclaim\s*:\s*\.([A-Za-z_]\w*)/g)].map(
      ([, claim]) => claim,
    );
    sites.push({
      file: path.relative(repository, file),
      line: lineAt(source, match.index),
      claims,
    });
  }
  return sites;
};

const sourceAuditSites = () => swiftFilesUnder(swiftTests).flatMap(file => (
  sourceAuditSitesIn(file, fs.readFileSync(file, 'utf8'))
));

const sourceReadSites = () => swiftFilesUnder(swiftTests).flatMap(file => (
  sourceReadSitesIn(file, fs.readFileSync(file, 'utf8'))
));

const validateSites = (sites, allowedClaims) => {
  for (const site of sites) {
    assert.equal(site.claims.length, 1, `${site.file}:${site.line} must declare exactly one claim`);
    assert.ok(allowedClaims.has(site.claims[0]), `${site.file}:${site.line} uses an unknown claim`);
  }
  assert.equal(
    sites.filter(site => site.claims.length === 1 && allowedClaims.has(site.claims[0])).length,
    sites.length,
    'every derived site must be consumed by the typed claim vocabulary',
  );
};

test('every derived source-audit site carries a typed claim', () => {
  const declaration = fs.readFileSync(sourceAuditDeclaration, 'utf8');
  const claimEnum = declaration.match(/public enum SourceAuditClaim[^{]*\{([\s\S]*?)\n\s*\}/);
  assert.ok(claimEnum, 'SourceAuditClaim declaration is missing');
  const allowedClaims = new Set(
    [...claimEnum[1].matchAll(/\bcase\s+([A-Za-z_]\w*)\b/g)].map(([, claim]) => claim),
  );
  const sites = sourceAuditSites();
  assert.ok(sites.length > 0, 'no source-audit sites were derived from app/Tests');
  validateSites(sites, allowedClaims);
  assert.throws(
    () => validateSites(
      sourceAuditSitesIn('synthetic.swift', 'let value = try auditSource(path)\n'),
      allowedClaims,
    ),
    /must declare exactly one claim/,
    'an unclaimed source reader must be rejected by the same derived check',
  );
});

test('every lexical program-source read goes through the typed door', () => {
  const sites = sourceReadSites();
  const sourceReads = sites.filter(site => site.kind === 'source');
  // An indirect path is deliberately outside this lexical property; it is reported in the
  // context entry as a human-review residual rather than guessed into source or data.
  assert.deepEqual(sourceReads, [], `raw program-source reads bypass auditSource: ${JSON.stringify(sourceReads)}`);

  const fixture = `
    let source = try String(contentsOf: URL(fileURLWithPath: "app/Sources/App/Installer.swift"), encoding: .utf8)
    let data = try Data(contentsOf: URL(fileURLWithPath: "app/Sources/App/Resources/en.lproj/Localizable.strings"))
    let script = try String(contentsOfFile: "extension/defaults.js", encoding: .utf8)
  `;
  const fixtureSites = sourceReadSitesIn('synthetic.swift', fixture);
  assert.deepEqual(fixtureSites.map(site => site.kind), ['source', 'data', 'source']);
});
