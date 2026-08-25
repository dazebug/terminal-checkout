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

## When authority moves between two stores, the gates stay on the old one and everything passes

**Type:** constraint
**Type:** incident
**Status:** active
**Evidence:** confirmed — three mutations of `_locales` (a command literal, a Simplified-for-Traditional replacement, an HTML attribute escape) left every gate green while the gate named for each defect read the frozen `_i18n` instead
**Source:** PR #41 (ledger D296, D297, D300); `tests/i18n.test.js`, `extension/_locales/`, `extension/_i18n/`
**Revisit when:** the compatibility passengers are retired (a second authority move, in the opposite direction), or a third catalogue surface appears

The extension's canonical store moved from `_i18n` to `_locales`. The runtime followed. The content gates did not, and **nothing went red**, because `_i18n` is pinned byte-for-byte and therefore cannot change — a gate reading a frozen file is green forever.

The consequence was not theoretical. The gate named *"a command literal reads the same in every language"* could not see `{cd}` translated to `{디렉터리이동}` in the variable list users are told to type, which the app answers with `Unknown variable`. The gate named *"the two Chinese catalogues are not one script converted into the other"* could not see 122 of 125 Traditional messages replaced with Simplified text. Both were found by a review with no history of the change, after fourteen rounds of review that did have that history.

**What generalises.** A gate's subject is not stated anywhere a reader checks — it is wherever the fixture happens to point. When the thing being described moves, the gate keeps compiling, keeps passing, and keeps its name. Two properties follow, and both are cheap:

- A gate whose claim is about *what a user sees* must read the store the product reads, and which store that is should be derivable rather than repeated in each fixture. Duplicating every assertion across both stores was rejected: a later move strands one copy again, which is this defect with an extra file.
- Repairing one instance of this is not repairing it. The instance that surfaced first was a single argument-identity oracle; the family was every content gate in the file. **The question a found instance obliges you to ask is which other gates read the store that stopped being canonical**, and the answer that time was "all of them."

Retiring `_i18n` (#45) is the same move again, so this entry is the precondition for that work rather than a record of a closed episode.

## Closure decisions preserved from PR #41

These rows are self-contained. They keep the numbers they were given in a longer working ledger whose earlier rows were **not** carried over — the numbering starts at D288 for that reason, and nothing here refers to a row that is not below it. That ledger was a Korean working document and was deleted with the migration plan; where one of its decisions still mattered, it became an entry above rather than a citation.

- **D288:** the test audit classified every added declaration and used a cross-file pass for duplicate boundaries; a sweep row did not replace a test, and no new test gap was invented to make the audit look complete.
- **D289:** the audit's `new gaps: 0` summary was not a durable control for the source-lint property; 13 source-reading sites and four prose label shapes were the trigger for this typed, derived gate.
- **D290:** deleting the migration plan is safe only after its durable context is moved; every Source field that survives the loop must resolve for a reader without the plan file.
- **D292:** a durable Source field uses inline reasoning when the entry needs it and PR #41 when it is pure provenance; it does not point at a deleted plan or rely on a bare commit SHA.
- **D294:** the first source-audit gate derived calls to its own door, so two raw `String(contentsOf:)` source reads in `LocalizationCatalogTests` and source-reading helpers elsewhere were invisible; the property belongs at the read boundary, not at the declaration it asks callers to use.
- **D295:** the closing gate recognizes the lexical `contentsOf*` read family and derives source-versus-data from path evidence; catalogue and copied-artifact reads stay direct, while indirect APIs and helper-only path meaning remain an explicit human-review residual.
- **D296:** repairing one live argument-identity oracle did not sweep the family of content gates; the `_locales` command-literal, Chinese-script and attribute mutations stayed green because the remaining assertions still read frozen `_i18n`. The defect was the gates' subject, not anything the translation edits introduced — see the entry above.
- **D297:** content-quality assertions are projected once from the physical `_locales/<directory>/messages.json` entries that Chrome reads; `_i18n` remains the subject only of compatibility-baseline, retained-ABI, format and mixed-generation checks. Duplicating each assertion for a second store was rejected because a future authority move could strand one copy again.
- **D298:** the live name set is a superset contract: every frozen baseline name must remain present, well-shaped live entries may add `ext_` names before the compatibility passenger retires, and non-extension extras remain rejected. The compatibility passenger keeps its exact hash pin; blocking reviewed new messages until passenger retirement was rejected because it would make the canonical store undevelopable.
- **D299:** Swift duplicate-value and containment gates read live Chrome message text under physical names; compatibility dictionaries remain in the cross-store no-two-homes and retained-store checks. The exception tables therefore use the names of the store they judge, without adding a second dot-to-underscore converter.
- **D300:** the C1 mutation proof is load-bearing: the command-literal, HTML-attribute and Traditional-Chinese mutations each leave `node tools/check-locales.js` green but make the corresponding live-content assertion fail with its locale and physical message key. A mutation that only changes the frozen passenger would test the wrong subject.
- **D310:** the catalogue-mismatch test had been a tautology over an authored instruction and claimed a command the production diagnostic did not name; it now exercises `checkLiveLocaleBaseline()` through a real edited read and asserts the exact path-and-fact message, which deliberately does not prescribe running `node tools/check-locales.js` because that command does not run the live pin check.
- **D311:** `LocaleSnapshot`, `localeSnapshotToPublish` and `localeIdentityIsExhausted` had no production caller after publication was removed; their focused Core test was the only reason they survived, so the dead API and its dead gate were deleted together.
- **D312:** the options display-name check remains a source lint because no browser harness observes that lookup, but its oracle now recognizes a `.name` relation on either side of strict or loose equality, including negation; a synthetic reversed operand is the red toggle rather than a claim about one current spelling.
- **D313:** the placeholder gate now classifies every one of the 98 app catalogue keys from direct literal calls, six conditional branches and `format:` forwarding sites; it asserts the unclassified and contradictory sets exactly, so no exemption list or fixed floor can absorb a new call shape.
- **D314:** the VM realm models Chrome's unknown-message result as the empty string, and a focused generation test pins that contract by name; reversing the default returns the id and fails that test, rather than relying on a consumer that may always inject a backend.
- **D315:** adding `fr` to the app's `supportedLocales` alone made the Swift gate execute 481 tests with 1 skipped and 33 failures (13 unexpected), catching the missing app-side resources and mapping, while Node stayed 266/266 and `node tools/check-locales.js` stayed green because the extension locale list, load entries and checker metadata are independent declarations rather than a derived bridge; the README therefore enumerates all authored sites and says which gates validate consistency once each declaration is present.
- **D320:** a gate that asserts a production diagnostic must be toggled by mutating that diagnostic and observing a named red; reverting the fix and seeing the old tautology stay green is evidence of the defect, not evidence of the replacement. The live-pin mutation changed one word and failed the exact production-message assertion.
- **D321:** collection-valued assertions report directional differences rather than two complete sets, and the key-set cross-check is suppressed when the preceding unclassified-set assertion already names the same missing call-site shape; this keeps one cause to one readable red while still reporting both coverage directions when classification itself is complete.
- **D322:** a test-only screen stand-in must invalidate its owning layout view when assigned, because these tests set it after controller construction; requiring every caller to remember a separate `needsLayout` write recreates the inert-double class at the next call site. `visibleFrameOverride` now dirties `FittedContentStackView` in its setter, and the one redundant caller-side invalidation is gone.
- **D323:** measured, because "set after construction" does not by itself mean inert: shrinking the stand-in to 200 points left `testTheWindowFitsItsContentInEveryPopulatedLocale` **passing** before the fix, while the terminal-transition, bottom-edge and permission-refresh tests all failed — the interaction each of those performs next dirties the tree as a side effect, so their stand-ins were live by accident rather than by design. Exactly one of the five sites was inert, and it was the one CI caught on a display shorter than this project's. After the fix all four stand-in users fail the same probe. A layout gate that has only ever run on one machine has not been shown to measure anything.
