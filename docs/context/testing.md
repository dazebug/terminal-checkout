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

Retiring `_i18n` (#45) was the same move again, executed 2026-08-25 with this entry as its checklist: every gate that read the frozen store was retargeted to the live one or deleted with its subject. See `localization.md`, "The compatibility passenger protected a state Chrome refuses to construct".

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

## A layout gate that drives its own layout is not measuring the window that ships

**Type:** incident
**Type:** constraint
**Status:** active
**Evidence:** confirmed — six setup-window cases were green while the shipped window was visibly clipped; removing one forced traversal produced eight failures across seven cases at the sizes measured on the device, and the pending-work signal fires between 0 and 4 times per run
**Source:** issue #34; commits `37887c7`, `5645d14`; `app/Tests/AppTests/SetupWindowTestSupport.swift`
**Revisit when:** these tests gain a way to observe an AppKit display cycle without pumping wall-clock time, or the window stops changing its own size from inside a layout pass

The setup-window tests settled the tree by calling `layoutSubtreeIfNeeded()`. That is exactly what hid the defect they existed to catch. A forced traversal continues past the window resize the layout pass performs, so the enclosing scroll view lays out a second time and the stale clip never appears; the real display cycle has already finished with the scroll view by then. Measured against the same subject, forced traversal reported a 702-point clip where the display cycle produced 547.

**Rejected — keeping the forced call for determinism.** Four configurations were compared: window shown, window not shown, forced traversal, and no `NSApplication.run()` at all. Only the forced one hid the defect. The decision variable is *who drives layout*, not whether the window is on screen — so the settle helper pumps the main run loop and forces nothing, and terminates on a fixed point rather than on elapsed time, failing at a named cap. Wall-clock pumping is the cost; the cap keeps it bounded.

**Geometry unchanged is not the same as work done.** A queued main-queue update, a registered restore callback, and an unserviced `needsLayout` all leave the geometry identical while the work is still owed, so two matching snapshots read as settled. All three are part of the fixed point. This was got wrong three times in a row, once per signal, which is the argument for asking "what else is pending" rather than adding the signal that just bit.

**There is exactly one settle.** Two divergent copies existed and only one of them could see the defect. A second copy of a contract is the same failure as the frozen fixture above, one file later.

**A test's admission class depends on the harness being faithful, and it moves in both directions.** One assertion classified as "passes on the old code, admissible only as an invariant" became a genuine red once the forced traversal was gone. Two others, classified as genuine reds while the harness was still returning early, turned out to be invariants once the pending-work signal removed the flakiness — they had been failing for a harness reason, not for the reason they were credited with. Classification therefore cannot be settled before the harness is trusted, and one made earlier has to be re-run rather than carried forward.

**Failures here were flaky, not deterministic.** The pending-work signal fires 0–4 times in otherwise identical runs. Before it existed, one of five locales failed — which reads like a deterministic red for that locale and was not. A layout gate that has passed once has not been shown to pass.

**A crash is not a red, and it disables everything after it.** `defer { window.close() }` in a test aborts the whole suite with SIGSEGV: `isReleasedWhenClosed` defaults to true, so the close releases the window and XCTest's autorelease-pool pop releases it again. Every test after that point simply does not run, and a search for failing assertions finds none. The same code outside XCTest does not crash, so a standalone harness will not reproduce it. **Rejected — `isReleasedWhenClosed = false`;** the rest of the file never closes the windows it creates, so the inconsistency was the defect and not a missing rule.

## Some defects cannot be a red here, and saying so beats building a seam

**Type:** decision
**Status:** active
**Evidence:** confirmed — the two-display failure needs two attached screens whose visible frames disagree, which the suite cannot construct; the arithmetic it reduces to is pinned directly
**Source:** issue #34; commit `56baa0d`; `docs/new-terminal-checklist.md`
**Revisit when:** the suite gains a way to present more than one screen geometry to `NSScreen`, or the placement logic stops depending on the attached displays

The window-placement defect only appears when two displays are attached and two independent reads pick different ones. A test-only stand-in for "which screen" would have tested the stand-in, not the choice.

So the property was split. The arithmetic the invariant names — centring then clamping with one rect leaves the window centred, and clamping with a different rect is what drags it to an edge — is pinned as a direct, screen-free test, admissible as an invariant rather than as a red. The display-dependent half is a step on the hands-on checklist, verified by measuring a real launch.

**Rejected — inventing a seam to manufacture a red.** It would have produced a green gate whose subject was a fixture, which is the failure the frozen-store entry above describes.

The same split applies to a step this work could *not* perform: whether a language change leaves the window where the user put it is pinned by a test, but was never confirmed on a device, because the language picker is not reachable through the accessibility tree — enumerating pop-up buttons and radio buttons in that window both return empty, since the controls are custom. Driving it means clicking coordinates and guessing at a menu, which is not evidence. It is on the checklist as a step to perform, recorded as unperformed.

## An out-of-tree DOM harness needs its own red toggles

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured)
**Source:** commit `933fc68`; the session scratchpad `ci-harness/verify.js`; the native-drop constraint in `CLAUDE.md`
**Revisit when:** the suite gains a faithful DOM harness, or browser automation can complete a native `drop`

The options page has no DOM unit-test harness, and this change did not add one. The replacement for the hands-on portion was an out-of-tree jsdom harness that loads the real `options.html` with only `chrome` stubbed. Its geometry is deliberately supplied: jsdom returns all-zero rectangles, so deterministic stacked rectangles can exercise the zone logic, index arithmetic and focus restore, but not real hit-testing or a native drop. CDP cannot carry the latter either.

The harness's checks need toggles just as the committed suite's checks do. The cross-card check passed when its guard was removed, and a toggle intended to disable the keyboard branch matched an identical `if` a hundred lines earlier and reddened the drag checks instead. Both looked like evidence while proving the wrong thing. An out-of-tree harness receives less scrutiny than the suite, so a check never shown to fail is worth less than no check.

**Rejected alternative — promote the harness or trust green-only checks.** A fake browser or an extracted arithmetic seam would manufacture a unit boundary the production code does not have, while an un-toggled scratchpad check can mistake a missed filter for a working guard. Keep the harness disposable, and require each check to redden only when its named protection is toggled.
