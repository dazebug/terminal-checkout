# Options page design

## GitHub is the editing surface

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user said the grouped B view felt dense and that separated sections made buttons hard to find; they wanted each button's place to be visible and chose the GitHub-like D view.
**Revisit when:** the user changes the priority between seeing placement in context and editing a compact grouped list

The page shows each button where it belongs on its corresponding GitHub page, so the user can see placement while editing. The user rejected B because it felt dense and splitting it into sections meant searching for a button. The preserved decision says A and C were rejected but does not record a separate reason for either; it supports the placement criterion for D, not a retrospective claim about their individual flaws.

## The scenery is fixed; the buttons are live

**Type:** decision
**Status:** active
**Evidence:** confirmed — the selected design pairs one fixed example context with the current edit-state buttons; the stability rationale is inferred from that split.
**Revisit when:** the replica stops serving as an editing preview or the example is replaced with another explicit preview model

A fixed example keeps the GitHub locations stable while the buttons show the values being edited. A completely hard-coded mockup would not preview the edits that Save will write; using live repository scenery would make the preview depend on which real page supplied it. The design keeps those roles separate so the page demonstrates placement without presenting sample scenery as a user's repository.

## Views project engine state and own confirmation

**Type:** decision
**Status:** active
**Evidence:** confirmed — the view contract reads engine snapshots and sends actions through dispatch; dispatch returns `needs-confirmation` instead of opening a browser dialog.
**Revisit when:** the options page no longer uses one engine as the source of edit state or its confirmation surface changes

The engine owns edit state, and views render its snapshots and request changes through dispatch so validation and dirty state have one authority. Confirmation belongs to the view that presents the action: it can explain what will be replaced in context and send the confirmed action only after the user agrees. Having the engine call `confirm()` would move a view decision into a browser modal and prevent the view from owning that interaction.

## Hidden content stays hidden across modules

**Type:** incident
**Status:** active
**Evidence:** confirmed — after a successful load, the load-failure panel still appeared because its `display: flex` author rule overrode the browser's default styling for the `hidden` attribute.
**Revisit when:** module visibility no longer uses the HTML `hidden` attribute

The page-level `[hidden] { display: none !important; }` rule gives the state attribute the last word over display rules in every module. Fixing only the load-failure panel would leave the same cascade defect available to the next module that combines `hidden` with an explicit display value.

## Word-boundary breaking applies only to Korean

**Type:** decision
**Status:** active
**Evidence:** confirmed — Korean labels were observed breaking between syllables, while Japanese and Chinese have no spaces at which `keep-all` could break.
**Revisit when:** another page language needs language-specific word-boundary behavior

The page applies `word-break: keep-all` under `:lang(ko)` and permits emergency wrapping with `overflow-wrap: anywhere`. Keeping that rule on a shared module would also affect Japanese and Chinese and could leave a sentence unable to wrap; the language selector applies the correction only where word boundaries need it.

## GitHub copy and extension copy have different owners

**Type:** decision
**Status:** active
**Evidence:** inferred — the design centralizes GitHub's replica labels as English copy and puts extension-authored text in the five locale catalogues.
**Revisit when:** the replica follows GitHub's localized UI instead of using its fixed English scenery

GitHub's labels describe the scenery being imitated, so one English table keeps that borrowed UI vocabulary consistent. Buttons, instructions, status and confirmation text belong to the extension and use its catalogues so they follow the extension's selected language. Translating both sets as extension copy would make the replica claim control over GitHub's language; scattering the GitHub terms through the renderer would let the copied vocabulary drift.

## GitHub colors do not mirror the app palette

**Type:** decision
**Status:** active
**Evidence:** confirmed — the `--gh-` tokens represent GitHub's page colors; the extension-owned options surfaces retain their `Theme.swift` mirror relationship.
**Revisit when:** the replica stops imitating GitHub's palette or the app and extension theme ownership changes

The app palette describes the extension's own surfaces. The replica uses GitHub colors to make the example recognizable, so its `--gh-` tokens stay independent; making them mirror `Theme.swift` would couple two different surfaces and change the page being imitated when the app theme changes.

## Discard reloads saved settings without writing

**Type:** decision
**Status:** active
**Evidence:** confirmed — discard reads settings again through the existing load path and updates edit state; storage writes remain on Save.
**Revisit when:** the meaning of discard changes or settings stop being read from the existing load path

Discard means abandoning the local draft and returning to saved settings, so it uses the normal load path rather than writing a saved snapshot back to storage. A write would make Cancel itself a sync mutation and could overwrite settings that changed elsewhere since the page loaded. Reloading changes only the page's edit state; Save remains the sole write action.
