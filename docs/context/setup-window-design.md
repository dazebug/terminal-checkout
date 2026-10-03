# Setup window design

**Type:** product decision
**Status:** active
**Evidence:** the user chose the B2 mockup on 2026-10-03; the integrated General, GitHub and Slack panes were reviewed as one window
**Source:** user decision (2026-10-03); `app/Sources/App/SetupWindowController.swift`, `SetupWindowPresentation.swift`, `SetupWindowSharedPanel.swift`, `SetupWindowGeneralPane.swift`, `SetupWindowGitHubPane.swift`, `SetupWindowSlackPane.swift`, `SetupWindowPreviewView.swift`, `app/AppIcon.icns`, and `extension/manifest.json`
**Revisit when:** the user chooses a different settings-window structure, the meaning of the request record changes, or the source icon is replaced

## Three toolbar panes with previews

The old setup window stacked eleven equally weighted cards into a 600 × 1410 pt scroll and showed every help paragraph even when nothing needed attention. B2 uses General, GitHub and Slack in a preference toolbar and shows one pane at a time, so each pane can include a schematic preview without making the window a long scroll. The shared problem and first-install area stays below the toolbar because it applies regardless of the selected pane.

**Rejected alternative — A, tabs with previews and common settings above the tabs.** B2 keeps the shared problem area below the toolbar and puts one category in the main content; its one-at-a-time pane lets the preview explain the result without returning to a long scroll.

**Rejected alternative — B, a toolbar without previews.** The illustrations helped users understand which terminal screen would be affected.

**Rejected alternative — C, tabs without previews.** It was a comparison layout without the illustrations that helped explain what a button would do.

## A request record, not a pipeline health claim

The app reports that an extension request was received because that is the event it can observe. The record does not establish that the request parsed, a command succeeded, or claude input was delivered. A pipeline strip looked like a success sequence and was read as a promise that the command had run, so the status line names only the request record and its relative time.

## Problems at the top, ordered by cause

The shared problem area comes before the selected pane so an opening cause is visible wherever the user lands. Opening reasons appear first, newest first, followed by errors and warnings; a severity dot before the title conveys state. A colored strip on a block edge was rejected because the user said that treatment looked AI-generated. Filled surfaces, brightness and status dots carry active and warning emphasis instead. Opening reasons are not persisted across app restarts because they describe the event that opened this window, not a durable setting; persisting them would make an old failure look current on a later launch.

## The repository base folder speaks only when unusable

The GitHub pane does not explain repository lookup order, add a general help paragraph, or retain advice about an older button. The user judged that this sequence does not need to be taught in the window. The field remains quiet while its value can be used and shows a notice only for an invalid saved value, a not-yet-created folder, or an empty value with no zoxide fallback.

## Initial selection follows the opening cause

A Slack request failure opens Slack; a Claude-input rejection opens General; other openings use the last pane selected in the current app run, with General as the initial default. The pane choice is not stored in UserDefaults: it is temporary navigation context tied to the current app run and opening event, not a machine preference that should be restored after a later launch. A language rebuild keeps the currently selected pane.

## App and extension icon identity

The app icon belongs in the General toolbar item and beside the app name and version in the General header, making the identity visible inside the settings window rather than only in the Dock. GitHub and Slack use their own SF Symbols. The preview prompt uses `Theme.ok`, chosen by comparing it with the icon's green so the illustration carries the app's identity without changing the control palette. The Chrome extension uses PNGs derived from `app/AppIcon.icns`: unpack the ICNS with `iconutil -c iconset`, measure the nontransparent tile from the source alpha channel, crop that square for the 16 and 32 px toolbar icons, and resize with `sips`; keep the source transparent margin for the 48 and 128 px icons, resizing the 128 px version from a 512 px source. The measured alpha bounds on the 1024 × 1024 source were x=97…926 and y=97…926, inclusive. The manifest declares these files for the extension and action while preserving its existing `key`, so the extension ID remains stable.

**Rejected alternative — use a gear for General.** The user asked for more of the app's identity in the window, so the app icon is used there.
