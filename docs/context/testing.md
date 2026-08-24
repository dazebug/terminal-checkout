# Testing decisions

This file holds test-design constraints that are not recoverable from a test count or from the production code. Test mechanics and commands stay with the test files and `CLAUDE.md`.

## Source-audit claims are typed and derived

**Type:** constraint
**Status:** active
**Evidence:** confirmed — `node --test tests/source-audit.test.js` derives 13 source-audit sites and accepts all 13 against the declared claim vocabulary
**Source:** PR #41 (closing change); `app/Sources/TestSupport/SourceAudit.swift`, `tests/source-audit.test.js`, and the source-reading tests under `app/Tests/`
**Revisit when:** a test target needs a source-reading path that cannot go through `auditSource(_:claim:)`, or the Swift package gains a compiler-enforced test-support boundary

Tests that read repository source use the shared `auditSource(_:claim:)` boundary. Its `SourceAuditClaim` is an enum rather than prose, the claim argument has no default, and the returned `AuditedSource` retains the path and caller site alongside the text. A new source-reading test therefore has to choose a named contract at the call site.

The Node gate walks the test tree and derives balanced `auditSource` call sites from the files that actually contain them; it derives the accepted claim values from `SourceAuditClaim` itself. It does not carry a hand-written list of reader spellings, files or label phrases, and it fails when a discovered call has no claim, more than one claim or a value outside the enum. The low-level file read is centralized in the support target, so the gate follows the declared source-reader boundary rather than trying to keep a list of Foundation and Node API aliases.

This is deliberately a contract gate, not a runtime claim about what a source-only lint proves. Such tests label their source half as a lint and add a live oracle when the behaviour is observable; an unobservable boundary remains human-review scope.

## Closure decisions preserved from PR #41

- **D288:** the test audit classified every added declaration and used a cross-file pass for duplicate boundaries; a sweep row did not replace a test, and no new test gap was invented to make the audit look complete.
- **D289:** the audit's `new gaps: 0` summary was not a durable control for the source-lint property; 13 source-reading sites and four prose label shapes were the trigger for this typed, derived gate.
- **D290:** deleting the migration plan is safe only after its durable context is moved; every Source field that survives the loop must resolve for a reader without the plan file.
- **D292:** a durable Source field uses inline reasoning when the entry needs it and PR #41 when it is pure provenance; it does not point at a deleted plan or rely on a bare commit SHA.
