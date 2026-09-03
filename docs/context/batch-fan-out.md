# Batch fan-out — the extension–app envelope

## A whole-batch rejection keeps the app's words and never asserts the app's age

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured — the app's two no-items answers are read from `app/Sources/Core/Request.swift`, and both fixtures went red before the branch and green after)
**Source:** issue #79; commit `345635f`; `interpretListBatchResponse` in `extension/defaults.js`
**Revisit when:** the app starts returning `items` on a request-shape rejection, or a visible display path for whole-batch errors is added to the list button

The extension has two verdicts to read out of a batch response: the worker's outer `success` says whether the request reached the app at all, and the app's inner `success` says how the batch went. A response with the inner `success: false`, a string `error`, and **no `items` key** used to fall through to the "shapeless response" branch and be replaced by the generic `native host returned no result`. Now that exact shape keeps the app's own text and appends a hedged hint — `… — the app rejected the whole batch without per-item results; an app older than this extension answers this way`.

**Reason:** the shape has two producers, not one. An app that predates batch support answers `command_template is required` because it never saw an `items` envelope, and that was the case the issue described. But the current app answers in the *same* shape whenever it rejects the request before producing per-item results — an over-cap `items` array, a missing `command`, a non-object item — because those parse failures return `{success:false, error}` without `items`. The extension pre-validates the same cap and shape, so reaching that branch with a current app means the extension and the app disagree about the protocol, which is still the diagnosis the user needs; only the *direction* of the mismatch is unknowable from the response alone. The app's text is what tells the two apart, which is why it comes first and the hint stays a possibility rather than a verdict.

**Rejected alternative — assert "update the app."** Reads well for the original report and is simply false for a current app refusing a malformed request: the user would be told to update an app that is not out of date. A diagnosis that can be wrong in one of its two reachable cases is worse than the app's own sentence.

**Rejected alternative — treat any non-array `items` as a whole-batch rejection.** The app never emits `items: null` or a non-array `items`; a response with the key present but malformed did not come from the app the extension knows, so it stays on the fail-closed generic branch. The discriminator is the key's *absence* (`items === undefined`), together with a boolean `false` and a non-empty `error` — `success: true` without `items`, or an empty `error`, are shapeless too.

**Consequence, accepted:** the text reaches the user only through the console. The list button already turns ❌ and logs the error on this path (`appSuccess: null` makes `runListBatchCommand` throw), and adding a visible display route or a localized string was left out on purpose: console diagnostics stay English by the i18n policy, and a new display path is a separate feature, not a repair of a lost message.
