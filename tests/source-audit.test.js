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
