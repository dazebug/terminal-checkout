import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

// A hash may ride along for precision but never alone: this repository squash-merges, so a branch
// commit never lands on main and the hash stops resolving. The "Note on sources" in
// docs/context/knowledge-capture.md owns that rule and the measurement behind it.
const contextDirectory = path.join(path.resolve(import.meta.dirname, '..'), 'docs', 'context');

// Backticked lowercase hex, 7-40 long, with at least one digit — the digit is what keeps English
// words long enough to qualify and made only of hex letters ("deadbeef", "defaced") out.
const commitCitation = /`(?=[0-9a-f]*[0-9])[0-9a-f]{7,40}`/g;
const prReference = /\bPR #\d+/;

// Source and Status are the two lines an entry uses to point outward; the prose around them is
// argument, not citation.
const metadataLine = /^\*\*(Source|Status):\*\*/;

// Recursive even though the directory is flat today: a subdirectory added later would otherwise be
// skipped in silence, and a gate that stopped covering something looks exactly like a gate that
// found nothing.
const offendingLines = () => fs.readdirSync(contextDirectory, { recursive: true })
  .filter(name => name.endsWith('.md'))
  .flatMap(name => fs.readFileSync(path.join(contextDirectory, name), 'utf8')
    .split('\n')
    .flatMap((line, index) => {
      if (!metadataLine.test(line)) return [];
      const hashes = line.match(commitCitation);
      if (!hashes || prReference.test(line)) return [];
      return [`${name}:${index + 1} cites ${hashes.join(', ')} with no PR reference`];
    }));

test('a commit hash in docs/context/ metadata never travels without its PR', () => {
  assert.deepEqual(offendingLines(), []);
});
