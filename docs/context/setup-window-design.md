# Setup window design

## Three toolbar panes with per-pane previews

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user chose B2 on 2026-10-03 and said they liked B with explanatory illustrations added; the dimensions below are from the mockups, not the shipped window
**Source:** user decision (2026-10-03); PR #108; mockups A, B, B2 and C, not kept in the repository; `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/SetupWindowGeneralPane.swift`, `app/Sources/App/SetupWindowGitHubPane.swift`, `app/Sources/App/SetupWindowSlackPane.swift`, and `app/Sources/App/SetupWindowPreviewView.swift`
**Revisit when:** the user chooses a different settings-window structure or preview treatment

The old setup window stacked eleven equally weighted cards into a 600 × 1410 pt scroll and showed its help paragraphs even when nothing needed attention. The chosen B2 mockup has a macOS preference toolbar for General, GitHub and Slack and shows one pane at a time, with a shared problem and first-install area below the toolbar. Showing one pane at a time lets each category include its own preview without stacking all three panes into a long window. In the A mockup, terminal and after-running settings were shared by two entry points and sat above the tabs, so they remained visible from either tab; its usual mockup size was 720 × 515 pt. B2's mockup sizes were General 720 × 405 pt, GitHub 720 × 328 pt and Slack 720 × 364 pt. The B mockup was the shortest usual state at 600 × 279 pt for General, but had no illustration; the user asked to add the explanatory illustration. C used A's tab and shared-settings structure without illustrations as a comparison.

**Rejected — A, tabs with previews and shared settings above the tabs.** A kept terminal and after-running settings visible from both tabs and measured 720 × 515 pt in its usual mockup state; the user chose B2's pane-specific arrangement.

**Rejected — B, toolbar without previews.** B was the shortest usual mockup at 600 × 279 pt for General, but omitted the illustrations the user wanted added.

**Rejected — C, A's tab structure without previews.** C was the comparison layout; the user chose B2 with one illustrated pane visible at a time.

## A request record, not a pipeline health claim

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user decided that the status must report receipt of an extension request rather than say “normal”; the app records arrival, not command success
**Source:** user decision (2026-10-03); PR #108; `app/Sources/App/SetupWindowPresentation.swift` and `app/Sources/App/SetupWindowGeneralPane.swift`
**Revisit when:** the recorded event changes from request arrival to evidence of command completion

The status says that an extension request reached the app and gives its relative time. The request record does not prove that the request parsed, a command succeeded, or claude input finished.

**Rejected — a pipeline strip and “normal” status.** The strip was read as a claim that the command had succeeded, which the request record cannot support.

## Problems appear first and use a status dot

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user chose opening reasons first, newest first, followed by errors and warnings, and rejected a colored edge strip as “AI-like”
**Source:** user decisions (2026-10-03); PR #108; `app/Sources/App/SetupWindowPresentation.swift`, `app/Sources/App/SetupWindowSharedPanel.swift`, and `app/Sources/App/SetupWindowController.swift`
**Revisit when:** problem ordering, opening-reason lifetime, or the shared problem area's placement changes

The common problem area sits below the toolbar and before every pane. It lists the reason that opened the window first, newest first, then errors and warnings; a status dot before each title conveys severity. Opening reasons are not saved across app restarts because they describe the event that opened this window and would look current if shown on a later launch. Slack request failure clears when a later Slack request succeeds; a claude-input rejection clears when the window closes or its cause is resolved.

**Rejected — a colored strip along a block edge.** The user said that treatment looked “AI-like”; filled surfaces, brightness and a status dot carry state instead.

## The repository base folder speaks only when unusable

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user said the window does not need to explain repository lookup order and should show a notice only when the setting cannot be used
**Source:** user decision (2026-10-03); PR #108; `app/Sources/App/SetupWindowPresentation.swift` and `app/Sources/App/SetupWindowGitHubPane.swift`
**Revisit when:** the user asks for repository lookup guidance or the base-folder fallback changes

The GitHub pane keeps the repository base-folder field without a help paragraph about search order or advice about an older button. It shows a notice only for an invalid saved value, a folder that does not exist yet, or an empty value with no zoxide fallback.

**Rejected — explaining lookup order and the older button in the pane.** The user judged that sequence did not need to be taught there.

## Initial selection follows the opening cause

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user chose Slack for a Slack-request failure, General for a claude-input rejection, and otherwise the last pane selected during this app run, defaulting to General
**Source:** user decision (2026-10-03); PR #108; `app/Sources/App/AppDelegate.swift` and `app/Sources/App/SetupWindowController.swift`
**Revisit when:** the opening causes or pane-selection behavior changes

The selected pane is temporary navigation context for the current app run, not a machine preference to restore after a later launch. A language rebuild keeps the current pane.

**Rejected — saving the pane in UserDefaults.** The user chose not to carry a selection across app runs; an old pane choice is not an opening cause for a later launch.

## App and extension icon identity

**Type:** decision
**Status:** active
**Evidence:** confirmed — the user asked for more app identity in the settings window and specified app-derived Chrome extension icons while preserving the extension ID
**Source:** user decisions (2026-10-03); PR #108; `app/AppIcon.icns`, `docs/assets/icon.png`, `app/Sources/App/SetupWindowGeneralPane.swift`, `app/Sources/App/SetupWindowPreviewView.swift`, and `extension/manifest.json`
**Revisit when:** the source app icon is replaced or the user changes the icon treatment

The General toolbar item and General header use the app icon so its identity appears in the settings window; GitHub and Slack use SF Symbols. The preview prompt uses the green closest to the icon, selected by comparing the source colors. Chrome icons are regenerated from `app/AppIcon.icns`: unpack it with `iconutil -c iconset`, measure the nontransparent tile from the alpha channel, crop the tile for 16 and 32 px so it fills the toolbar canvas, and resize with `sips`; retain the source transparent margin for 48 and 128 px, resizing the 128 px image from a 512 px source. The measured alpha bounds on the 1024 × 1024 source are x=97…926 and y=97…926 inclusive. The manifest points to these PNGs and keeps its existing key so the extension ID remains stable.

**Rejected — use a gear for General.** The user asked for the app identity to be more visible, so the app icon is used in the toolbar and header.
