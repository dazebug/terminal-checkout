# Testing decisions

This file holds test-design constraints that are not recoverable from a test count or from the production code. Test mechanics and commands stay with the test files and `CLAUDE.md`.

## Source-audit claims are typed and derived

**Type:** constraint
**Status:** active
**Evidence:** confirmed — `node --test tests/source-audit.test.js` derives 20 typed-door sites, finds no lexical program-source read outside the door, and passes the source/data fixture
**Source:** PR #41 (closing change); `app/Sources/TestSupport/SourceAudit.swift`, `tests/source-audit.test.js`, and the source-reading tests under `app/Tests/`
**Revisit when:** a test target needs a source-reading path that cannot go through `auditSource(_:claim:)`, or the Swift package gains a compiler-enforced test-support boundary

Tests that read repository source use the shared `auditSource(_:claim:)` boundary. Its `SourceAuditClaim` is an enum rather than prose, the claim argument has no default, and the returned `AuditedSource` retains the path and caller site alongside the text. A new source-reading test therefore has to choose a named contract at the call site.

The Node gate walks the test tree and derives two sets from the files themselves: balanced `auditSource` call sites and lexical `contentsOf*` read constructs. It derives the accepted claim values from `SourceAuditClaim` itself, and classifies a read from path evidence as program source or catalogue/artifact data. A source-evidenced raw read fails; data reads remain direct. It does not carry a hand-written list of reader spellings, files or label phrases, and the low-level source read is centralized in the support target.

This is deliberately a contract gate, not a runtime claim about what a source-only lint proves. Such tests label their source half as a lint and add a live oracle when the behaviour is observable; an unobservable boundary remains human-review scope. The lexical reader is intentionally bounded: `FileHandle` and other APIs outside the `contentsOf*` family evade it, and `NSString(contentsOfFile:)` is covered only when that label and its source path are visible rather than hidden behind a helper. An indirect copied-artifact read is therefore a human-review residual, not evidence that the gate understands every file API.

## Closure decisions preserved from PR #41

- **D288:** the test audit classified every added declaration and used a cross-file pass for duplicate boundaries; a sweep row did not replace a test, and no new test gap was invented to make the audit look complete.
- **D289:** the audit's `new gaps: 0` summary was not a durable control for the source-lint property; 13 source-reading sites and four prose label shapes were the trigger for this typed, derived gate.
- **D290:** deleting the migration plan is safe only after its durable context is moved; every Source field that survives the loop must resolve for a reader without the plan file.
- **D292:** a durable Source field uses inline reasoning when the entry needs it and PR #41 when it is pure provenance; it does not point at a deleted plan or rely on a bare commit SHA.
- **D294:** the first source-audit gate derived calls to its own door, so two raw `String(contentsOf:)` source reads in `LocalizationCatalogTests` and source-reading helpers elsewhere were invisible; the property belongs at the read boundary, not at the declaration it asks callers to use.
- **D295:** the closing gate recognizes the lexical `contentsOf*` read family and derives source-versus-data from path evidence; catalogue and copied-artifact reads stay direct, while indirect APIs and helper-only path meaning remain an explicit human-review residual.
