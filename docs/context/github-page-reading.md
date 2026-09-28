# Reading GitHub pages

## The repository crumb is found through the banner landmark, from one set of selectors

**Type:** incident
**Type:** decision
**Status:** active
**Evidence:** confirmed (measured on github.com, 2026-09-24 — the redesigned global header is `<header class="GlobalNav …" aria-label="Global navigation menu">` with no `role`, and Chrome's accessibility tree still reports it as `banner`; the page header inside `<main>` also holds the repository link and the lock icon; a 404 has the banner and neither)
**Source:** PR #85; `repoCrumbSelectors` in `extension/defaults.js`; `tests/buttons.test.js` (`the repository crumb selectors have one home, and both readers take them from it`)
**Revisit when:** GitHub's global header stops being a `<header>` outside `<main>` or stops carrying the repository crumb, or the extension gains a build step that could inline shared code into an injected function

On 2026-09-24 the repository buttons disappeared from every repository, PR, issue and list page, and the extension icon refused on all of them without a word. `content.js` and `background.js` each looked up `header[role="banner"]`, and GitHub's redesigned header no longer declares the role. The PR, issue and list buttons kept working because they anchor elsewhere.

**Decision — find the banner as the landmark HTML defines.** An explicit `[role="banner"]`, or a `<header>` outside `<main>` and sectioning content. The attribute was redundant markup GitHub could drop at no cost to anyone else; the landmark is what assistive technology navigates by, which makes it the part of the header least likely to move silently.

**Rejected alternative — `header.GlobalNav`.** GitHub's own naming, which a redesign renames; this code has already outlived one redesign (the legacy branch in `attachToRepoCrumb`).

**Rejected alternative — the first `<header>` in the document.** The page header inside `<main>` carries the same repository link and lock icon, so a reordering would attach the buttons to the page title and let the icon check pass on it.

**Decision — the selectors have one home, `defaults.js`, and reach the worker's injected check as an argument.** chrome.scripting injects a function by its source, so the function cannot call a shared helper; data passed as an argument is what crosses. A GitHub change is then one edit, and the drawing and the icon gate cannot disagree about where the crumb is.

**Rejected alternative — call a helper the content script defined, through the shared isolated world.** It works only in tabs where the content script has been injected. A tab opened before an extension reload would refuse every icon click.

**Rejected alternative — return the element from the injected function and test the result.** What chrome.scripting makes of a DOM node in a result is not documented.

**Rejected alternative — a mirrored copy plus a lockstep test**, as the list-row reader does. That leaves two spellings to edit on the next GitHub change instead of one. The list reader mirrors whole functions; here only data needed to cross.

**Consequence, accepted:** the committed test is a lint over spellings. Whether the selector matches the GitHub that is live today is settled only in a browser; a fixture of GitHub's HTML would be the frozen store `testing.md` warns about.

**Observed once:** GitHub replaced its whole banner about 8 seconds after a load, taking the buttons with it, and the 1-second poll put them back 1.4 seconds later. The mutation observer now also fires when a banner is inserted. The replacement did not recur in two more 10-second watches, so that trigger is verified only by its predicate against the live header.

## A PR header's branch links are picked by document order, never by screen position

**Type:** incident
**Type:** decision
**Status:** active
**Evidence:** confirmed (measured on github.com, 2026-09-24 — on a PR with a three-line title the head link sat at 257px until GitHub's stack notice loaded, then at 328px, and no PR button appeared within 8 seconds; the header's `a[data-component="BranchName"]` pair reads base then head in document order on the conversation and changes tabs and on a merged PR, followed by a hidden 0×0 copy; scrolled 1000px down, the pair still reads base `main` and the PR's head; the commits tab carries 33 `/tree/` links, browse-at-commit ones included, and the selector matches only the header pair and its copy)
**Source:** PR #86; `PR_BRANCH_LINK_SELECTOR` in `extension/defaults.js`; `tests/buttons.test.js` (`the PR branch links have one home, and neither reader finds them by screen position`)
**Revisit when:** GitHub's PR header stops naming the base before the head, or stops rendering the branches as links

content.js drew the PR buttons after the last visible `/tree/` link between 0 and 300px from the top of the viewport, and background.js read the branch names at click time by the same rule. A title that wraps to three lines under GitHub's stack notice puts the links at 328px, and a page opened at a comment or scrolled down puts them above the viewport. Either way no button appeared, and a button drawn earlier could not find a branch when clicked.

The band stood in for "the links in the PR header" as opposed to `/tree/` links in the description or the timeline below it. Document order says the same thing from structure: the header comes first, and it names the branches "into BASE from HEAD".

**Decision — the first two rendered matches of one selector, base then head.** The selector lives in `defaults.js` (the redesigned header's `BranchName` links and the legacy `.base-ref`/`.head-ref` links) and reaches the worker's injected reader as an argument, like the repository crumb above.

**Rejected alternative — widen the band.** Any fixed line fails for a longer title or a scrolled page.

**Rejected alternative — the "Copy head branch name to clipboard" control beside the head.** It names the head outright, but through a tooltip's wording.

**Rejected alternative — read the names from the page's embedded JSON.** An undocumented payload, and the buttons still need the header element to sit beside.

**Behavior change, accepted:** with a single rendered link, the old rule took that link as both base and head, so a click would have used the base branch as `{branch}`. The pair rule finds no head there; no button is drawn, and a click reports that it could not read a branch.

## GitHub's own navigation is noticed by the insert passes, not only by the history wrappers

**Type:** decision
**Status:** active
**Evidence:** confirmed for what was measured. Before the fix, a move made through a `pushState` taken before the wrappers left the previous PR's buttons on the next PR; that an open note popover stayed with them was read from the code (its caret stayed connected), not observed. After it, on a live page — the real scripts injected into github.com's main world, `chrome` stubbed, trusted clicks and keys, in a hidden tab whose throttled poll was helped by passes started by hand — the same move from PR 86 to PR 87 closed an open popover and redrew the buttons at an insert pass within 2.5 seconds, the draft was back when the popover was opened on PR 86 again, and moving from the PR list to the issue list closed the popover and removed the row badges. That GitHub's own navigation goes past the wrappers follows from Chrome's isolated worlds and was not measured
**Source:** `tryInsertButton` and `onUrlChange` in `extension/content.js`; `tests/claude-note.test.js` (`every insert pass asks whether the page moved before it draws, so a move the history wrappers missed is seen (lint)`)
**Revisit when:** the extension gains a main-world script, or GitHub's navigation starts firing an event a content script can hear

The content script wraps `history.pushState` and `replaceState`, but a content script runs in an isolated world: the wrappers replace its own view of `history`, and a call made by GitHub's scripts in the page's world never passes through them. Only `popstate`, a DOM event every world receives, reaches `onUrlChange` directly. So every insert pass — the poll, the mutation observer and GitHub's `turbo:load`, `turbo:render` and `pjax:end` events — calls `onUrlChange` first. It returns at once for a URL that has not moved; for a new target it removes the old page's buttons, closes an open popover (whose draft stays under the page it was opened for) and resets the list selection. A move the wrappers missed is therefore cleared at the next insert pass. The poll asks for one about every second, and in a foreground tab that is roughly when it comes — an interval, not a deadline.

**Rejected alternative — close only the popover when its page differs from the one on screen.** That fixes the reported symptom and leaves the old page's buttons, another list kind's batch buttons included, on the new page.

## An insert pass that waited through a move draws nothing: a page generation, kept apart from the list generation

**Type:** decision
**Status:** active
**Evidence:** confirmed in a DOM harness only — the real content script under jsdom with `chrome` stubbed and the storage read held. The live page check above saw the generation move on a real page change but did not produce the race itself, whose window is one storage read wide
**Source:** `pageGeneration`, `pageChangedSince` and `removeInsertedButtons` in `extension/content.js`; `tests/claude-note.test.js` (`a pass that started on a page draws nothing once that page is gone: every await in it is followed by a page check (lint)`)
**Revisit when:** an insert pass gains an await of a new kind, or the list generation changes meaning

An insert pass reads the page, waits for storage, then draws. In the harness, a pass that waited on PR A and resumed after the page had moved to B drew A's buttons onto B, and the pass that started on B found buttons there and drew nothing, so the old page's buttons stayed until the next change of target; from a PR list to a PR, the waiting pass put a list checkbox and the PR-list buttons on the PR page. Every removal now moves `pageGeneration`. A pass holds the generation it started with and, after each await and before it reads or draws again, asks `pageChangedSince`, which calls `onUrlChange` first so that a move nothing has reported yet counts too. The generation counts the removals that were observed: a move there and back that nothing saw leaves no trace.

**Rejected alternative — compare the page's target instead.** When the move in between was observed, A→B→A ends on the same target, and the pass that started on the first A draws after two page changes.

**Rejected alternative — one insert pass at a time.** Serializing the passes does not stop a waiting pass from drawing after a move.

**Rejected alternative — an `AbortController` per page.** The same job as a counter, with more machinery.

**Rejected alternative — reuse `listDocumentGeneration`.** It also moves when a list's rows change under the same target, and the same pass can move it in `tryInsertListSelection`, so a shared counter would make that pass cancel its own list buttons.
