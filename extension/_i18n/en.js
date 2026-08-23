// The English dictionary — the options page's messages (item 21). Item 22 moves the rest in.
//
// A classic browser script, not a module: the content script, the service worker and the options
// page all load it the same way, and `node --test` runs it through `vm.runInThisContext` with no
// `chrome` global at all (D6). Registering into a global is what makes those three loaders and the
// test one thing rather than four.
//
// Keys live in the `ext.` namespace, which is how the extension's space stays separate from the
// app's `app.` one — item 20's ownership gate starts green because the split exists before there
// are any keys to sort (D24/D37).
//
// **Markup in a value is deliberate and bounded.** A tag that decorates translated text rides in
// the value — `<b>` on a word being emphasised, `<span class="faint">` on a gloss — because the
// alternative is handing JavaScript the pieces of a sentence to reassemble, and reassembly is the
// defect the app spent 25 fragments learning about. A tag that wraps a **literal** is the opposite
// case and would be the thing to keep out; `<code>` here only ever holds a variable name or a shell
// word, which is why a test pins those contents identical across locales rather than trusting them
// to survive translation. The gate also checks tag balance and that every locale carries the same
// tag multiset.

(globalThis.TC_I18N = globalThis.TC_I18N || {})['en'] = {
  "ext.header.subtitle": "PR, issue, and repository buttons, commands, main branch — terminal choice, permissions, and the repository base folder live in the Terminal Checkout app settings window",
  "ext.migration.badge": "● Your saved buttons predate the current presets — review",
  "ext.banner.stale": "⚠ Settings changed on another device since this page loaded. Reload to see them — export first if you want to keep unsaved edits.",
  "ext.section.update.title": "update <span class=\"section-where\">— saved commands versus the current presets</span>",
  "ext.migration.apply": "Apply selected",
  "ext.migration.keep": "Keep mine",
  "ext.migration.gotIt": "Got it",
  "ext.migration.effect.behaviorChange": "behavior change",
  "ext.migration.noTooltip": "(no tooltip)",
  "ext.migration.intro.nothingSafe": "Nothing here can be rewritten safely, but these commands still use the old form:",
  "ext.migration.intro.nothingToDo": "Nothing to change — your commands are already current. Press %1$s to mark them as reviewed.",
  "ext.migration.hint.reviewOnly": "Dismissing this marks your settings as reviewed — press %1$s afterwards.",
  "ext.migration.hint.selected": "%1$d of %2$d selected. Applying fills the form; press %3$s to store it.",
  "ext.migration.applied": "Commands updated in the form: %1$d. Press %2$s to apply.",
  "ext.migration.appliedWithDeclined": "Commands updated in the form: %1$d. %2$d changed since the preview was built and were left alone. Press %3$s to apply.",
  "ext.migration.markedReviewed": "Marked as reviewed. Press %1$s to keep your commands as they are.",
  "ext.section.pr.title": "buttons <span class=\"section-where\">— PR pages</span>",
  "ext.section.pr.help1": "Buttons that sit next to the branch name on a PR page (up to %1$d). <b>%2$s</b> is what the button shows — a single emoji, several of them (🌳🤖), or a short name (Review, WT). <b>%3$s</b> appears on hover, and picking a preset fills the card with that template.",
  "ext.section.pr.help2": "Drag the <code>⠿</code> handle on the left of a card, or use the <code>↑</code> <code>↓</code> keys, to reorder — this is the order the buttons appear in on GitHub, and clicking the extension icon runs the first one. <b>%1$s</b> is for making another button like an existing one — the copy's tooltip gets a number such as <code>(1)</code> appended.",
  "ext.section.pr.variables": "Available variables: <code>{cd}</code> <span class=\"faint\">(move into the repository — the app fills this in from its repository base folder setting, so it works on every page)</span> <code>{repo}</code> <code>{owner}</code> <code>{number}</code> <span class=\"faint\">(PR number, digits only)</span> <code>{branch}</code> <span class=\"faint\">(head — the branch being merged)</span> <code>{base}</code> <span class=\"faint\">(base — the branch it merges into)</span> <code>{main}</code> <code>{branch_underbar}</code> <span class=\"faint\">(branch with / replaced by _)</span>",
  "ext.section.pr.migrationHelp": "Rewrites of presets we shipped are pre-checked. A command you customized is offered <b>unchecked</b> and marked as a behavior change: only its leading jump is replaced, and the rest of it will now run wherever the new entry clause lands. Every preset starts with <code>{cd}</code>. With no base folder set it is just <code>z {repo}</code>; with one, it falls back to that folder and clones the repository when it isn't there — so a button works even on a repository you have never opened locally.",
  "ext.section.issue.title": "issueButtons <span class=\"section-where\">— Issue pages</span>",
  "ext.section.issue.help": "Buttons that sit next to the status badge (Open/Closed) on an issue page (up to %1$d). They are configured separately from the PR buttons, and on an issue page clicking the extension icon runs the first button here. Reordering (drag <code>⠿</code>, or <code>↑</code> <code>↓</code>) and duplicating work just like they do for PR buttons.",
  "ext.section.issue.variables": "Available variables: <code>{cd}</code> <span class=\"faint\">(move into the repository — filled in by the app)</span> <code>{repo}</code> <code>{owner}</code> <code>{number}</code> <span class=\"faint\">(issue number, digits only)</span> <code>{main}</code> — an issue has no PR branch, so the <code>{branch}</code> family and <code>{base}</code> are unavailable.",
  "ext.section.issue.claudeHelp": "A claude input that starts with <code>!</code> is typed into claude's shell mode, so the command really runs in that session — the default preset uses <code>gh</code> to put the issue body, its comments and the issues that mention it in front of claude. Consecutive <code>!</code> inputs are typed as one line.",
  "ext.section.repo.title": "repoButtons <span class=\"section-where\">— Repository pages</span>",
  "ext.section.repo.help": "Buttons that sit next to the repository name in the header of a repository page (code, issue list, Actions, and so on) — up to %1$d. Unlike the PR and issue buttons these look like GitHub's green action button, so a name such as <code>%2$s</code> suits the <b>%3$s</b> better than an emoji. On GitHub pages that are neither a PR nor an issue, clicking the extension icon runs the first button here.",
  "ext.section.repo.variables": "Available variables: <code>{cd}</code> <span class=\"faint\">(move into the repository — filled in by the app)</span> <code>{repo}</code> <code>{owner}</code> <code>{main}</code> — a repository page has neither a PR or issue number nor a branch, so <code>{number}</code>, the <code>{branch}</code> family, and <code>{base}</code> are unavailable. <code>{main}</code> is resolved from the repository default branch GitHub embeds in the page — a <code>master</code> repository comes out right without an override.",
  "ext.section.main.title": "main branch",
  "ext.section.main.help": "How <code>{main}</code> is resolved: per-repository override → detected from the page → the default below. Detection reads the base branch on a PR page, and the repository default branch on repository and issue pages — the setting below is the fallback for when detection fails. To always use the branch a PR will actually be merged into, use <code>{base}</code>, which skips both the override and the default.",
  "ext.field.defaultMain": "Default",
  "ext.table.repository": "repository",
  "ext.table.mainBranch": "main branch",
  "ext.override.empty": "No overrides yet.",
  "ext.button.addOverride": "+ Add Override",
  "ext.section.backup.title": "backup <span class=\"section-where\">— export, import, account sync</span>",
  "ext.section.backup.help1": "Settings (PR, issue, and repository buttons, and the main branch) are stored in Chrome's account-synced area (<code>storage.sync</code>). This extension has a fixed ID (the manifest key), so any two Chrome profiles signed in to the <b>same Google account</b> with \"Extensions\" enabled in sync settings share these settings automatically. Export and import are for moving settings without an account, or for keeping a file backup.",
  "ext.section.backup.help2": "Export downloads the <b>saved</b> settings as a file; import only fills in the form — nothing takes effect until you press <b>%1$s</b>.",
  "ext.section.backup.help3": "The file also records which generation of the presets it was written against. Importing an older backup offers the same update notice as stored settings do — and since a file may cover only part of your settings, the notice then reviews the whole form, not just the keys the file carried. A backup written by a <b>newer</b> extension is refused rather than half-read; update the extension first.",
  "ext.button.export": "Export (JSON)",
  "ext.button.import": "Import…",
  "ext.button.save": "Save",
  "ext.button.reset": "Reset to Defaults",
  "ext.button.retry": "Retry",
  "ext.status.unsaved": "● Unsaved changes",
  "ext.button.addButton": "+ Add Button",
  "ext.button.addLimit": "You can add up to %1$d buttons.",
  "ext.card.reorder.aria": "Reorder",
  "ext.card.reorder.tooltip": "Drag, or use the ↑↓ keys, to reorder",
  "ext.card.duplicate": "Duplicate",
  "ext.card.duplicate.tooltip": "Duplicate this button",
  "ext.card.delete": "Delete",
  "ext.card.palette.label": "Add to face:",
  "ext.card.palette.tooltip": "Add %1$s to the face",
  "ext.field.face": "Face",
  "ext.field.preview": "Preview",
  "ext.field.tooltip": "Tooltip",
  "ext.field.tooltip.placeholder": "Button tooltip",
  "ext.field.preset": "Preset",
  "ext.field.preset.placeholder": "Apply preset…",
  "ext.field.command": "command",
  "ext.field.claudeInputs": "claude inputs",
  "ext.field.claudeInputs.help": "— delivered in order; <code>!</code> lines run in claude's shell mode",
  "ext.field.claudeInputs.hint": "<code>!</code> lines are typed into claude's shell mode so they really run as commands — consecutive ones go in as a single line joined with <code>;</code>, each behind a banner. On Warp that typing needs the Accessibility permission. A single plain-text input, with nothing else in the list, skips typing entirely and becomes claude's opening message — that additionally needs the command to end in a bare <code>claude</code>.",
  "ext.field.claudeInputs.warn": "⚠ The command doesn't start claude, so these inputs won't be delivered",
  "ext.button.addInput": "+ Add Input",
  "ext.button.remove": "Remove",
  "ext.field.claudeInput.placeholder": "!gh issue view {number}, or: summarize this issue",
  "ext.status.loading": "Still loading your settings — one moment.",
  "ext.status.saved": "Settings saved.",
  "ext.status.savedWithPendingEdits": "Settings saved. Changes made since then are not saved yet.",
  "ext.status.saveFailed": "Could not save: %1$s",
  "ext.status.reset": "Reset to defaults. Press %1$s to apply.",
  "ext.confirm.presetOverwrite": "Button %1$d will be overwritten with the \"%2$s\" preset. Continue?",
  "ext.validate.face": "%1$s[%2$d]: enter a face.",
  "ext.validate.tooltip": "%1$s[%2$d]: enter a tooltip.",
  "ext.validate.command": "%1$s[%2$d]: enter a command.",
  "ext.validate.override.incomplete": "Override %1$d: enter both a repository and a main branch.",
  "ext.validate.override.duplicate": "Override %1$d: the repository \"%2$s\" appears more than once.",
  "ext.import.notJSON": "This file could not be read as JSON.",
  "ext.import.notObject": "The top level of the settings file is not an object.",
  "ext.import.nothingToImport": "Nothing to import (one of %1$s is required).",
  "ext.import.fileTooLarge": "The settings file is too large (256KB max).",
  "ext.import.skippedNote": "skipped: %1$s",
  "ext.status.importFailed": "Could not import: %1$s",
  "ext.status.imported": "Settings imported. Press %1$s to apply.",
  "ext.status.importedWithNotes": "Settings imported. Press %1$s to apply. (%2$s)",
  "ext.status.exportFailed": "Could not export: %1$s",
  "ext.export.nothingSaved": "No settings have been saved yet. Save first, then export.",
  "ext.export.excludedUnsaved": "Unsaved changes were not included in the export.",
};
