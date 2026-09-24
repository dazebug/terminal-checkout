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
