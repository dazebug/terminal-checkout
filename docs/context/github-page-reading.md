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
**Evidence:** confirmed (measured on github.com, 2026-09-24 — on a PR with a three-line title the head link sat at 257px until GitHub's stack notice loaded, then at 328px, and no PR button appeared within 8 seconds; the header's `a[data-component="BranchName"]` pair reads base then head in document order on the conversation and changes tabs and on a merged PR, followed by a hidden 0×0 copy; scrolled 1000px down, the pair still reads base `main` and the PR's head)
**Source:** PR #86; `PR_BRANCH_LINK_SELECTOR` in `extension/defaults.js`; `tests/buttons.test.js` (`the PR branch links have one home, and neither reader finds them by screen position`)
**Revisit when:** GitHub's PR header stops naming the base before the head, or stops rendering the branches as links

content.js drew the PR buttons after the last visible `/tree/` link between 0 and 300px from the top of the viewport, and background.js read the branch names at click time by the same rule. A title that wraps to three lines under GitHub's stack notice puts the links at 328px, and a page opened at a comment or scrolled down puts them above the viewport. Either way no button appeared, and a button drawn earlier could not find a branch when clicked.

The band stood in for "the links in the PR header" as opposed to `/tree/` links in the description or the timeline below it. Document order says the same thing from structure: the header comes first, and it names the branches "into BASE from HEAD".

**Decision — the first two rendered matches of one selector, base then head.** The selector lives in `defaults.js` (the redesigned header's `BranchName` links and the legacy `.base-ref`/`.head-ref` links) and reaches the worker's injected reader as an argument, like the repository crumb above.

**Rejected alternative — widen the band.** Any fixed line fails for a longer title or a scrolled page.

**Rejected alternative — the "Copy head branch name to clipboard" control beside the head.** It names the head outright, but through a tooltip's wording.

**Rejected alternative — read the names from the page's embedded JSON.** An undocumented payload, and the buttons still need the header element to sit beside.

**Behavior change, accepted:** with a single rendered link, the old rule took that link as both base and head, so a click would have used the base branch as `{branch}`. The pair rule finds no head there; no button is drawn, and a click reports that it could not read a branch.
