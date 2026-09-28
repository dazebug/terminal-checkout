# Tab activation

Whether a button's new session comes to the front. The mechanisms are in `TabActivation` and each terminal's launch function; this file holds why there is a choice, and why it differs per terminal.

## New tabs can open in the background

**Type:** decision
**Status:** active
**Evidence:** confirmed for cmux (measured, `cmux-integration.md`); iTerm2 and WezTerm follow their documented commands and are a `docs/new-terminal-checklist.md` item until measured
**Source:** maintainer request after a delivery test
**Revisit when:** a terminal gains a way to create a tab that never takes focus, or Warp gains a way to read a tab that is not focused

The setup window's **Keep the current screen when you press a button** (`tabActivation` in `UserDefaults`, default foreground) makes a button's session open without taking focus: cmux creates the workspace with `focus:false`, iTerm2 skips `activate` and selects the tab the user was on again after capturing the new session, and WezTerm skips `open -a WezTerm` and activates the pane the user was on again. Warp always opens in front and the checkbox is disabled there.

**Reason:** a new tab that comes to the front takes the keyboard with it. Reproduced while testing iTerm2 delivery: iTerm2 activated on the new tab while the maintainer was typing in another app, the typing landed in the new tab's shell, and claude never started there. Claude input does not need the tab in front on any terminal but Warp — reads and writes are addressed by session, pane or surface — so the tab only has to be in front for the user to look at it, and that is their call.

**Why iTerm2 and WezTerm select the old tab again:** leaving the app in the background is not enough. Creating a tab selects it in its window, so a user typing in that same window would still be typing into the new session.

**Why Warp is excluded:** its delivery confirms each input on the screen of the focused tab only, so a tab opened behind would wait until the user looked at it.

**The label names what the user keeps, not where the tab goes.** "Open new tabs in the background" (and Korean "새 탭을 뒤에서 열기") was reported as unintuitive: "behind" is a place, not an outcome, and cmux opens a workspace, not a tab. The label is the user's action and what stays put — "Keep the current screen when you press a button", ticked to stay — and on Warp the box shows unticked and disabled, since a ticked "keep" beside a terminal that always switches would be false.

**Rejected alternative — always background.** Foreground stays the default: most presses are made to look at the session they open.
