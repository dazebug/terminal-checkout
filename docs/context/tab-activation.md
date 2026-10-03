# Tab activation

Whether a button's new session comes to the front. The mechanisms are in `TabActivation` and each terminal's launch function; this file holds why there is a choice, and why it differs per terminal.

## New tabs can open in the background

**Type:** decision
**Status:** active
**Evidence:** confirmed for cmux (measured, `cmux-integration.md`); iTerm2 and WezTerm follow their documented commands and are a `docs/new-terminal-checklist.md` item until measured
**Source:** maintainer request after a delivery test
**Revisit when:** a terminal gains a way to create a tab that never takes focus, or Warp gains a way to read a tab that is not focused

The General pane's **After running** choice (`tabActivation` in `UserDefaults`, default foreground) makes a button's session open without taking focus: cmux creates the workspace with `focus:false`, iTerm2 skips `activate` and selects the tab the user was on again after capturing the new session, and WezTerm skips `open -a WezTerm` and activates the pane the user was on again. Warp always opens in front and the choice is disabled there.

**Reason:** a new tab that comes to the front takes the keyboard with it. Reproduced while testing iTerm2 delivery: iTerm2 activated on the new tab while the maintainer was typing in another app, the typing landed in the new tab's shell, and claude never started there. Claude input does not need the tab in front on any terminal but Warp — reads and writes are addressed by session, pane or surface — so the tab only has to be in front for the user to look at it, and that is their call.

**Why iTerm2 and WezTerm select the old tab again:** leaving the app in the background is not enough. Creating a tab selects it in its window, so a user typing in that same window would still be typing into the new session.

**Why Warp is excluded:** its delivery confirms each input on the screen of the focused tab only, so a tab opened behind would wait until the user looked at it.

**The choice names what stays in front, not a background location.** “Background” describes a place rather than the outcome, and cmux opens a workspace rather than a tab. The segmented choice names the user's desired outcome; Warp shows the terminal-in-front choice disabled because it always switches to the new tab.

**WezTerm that is not running is refused, not started.** Its no-mux fallback runs `wezterm start`, whose first window activates the app — nothing from outside can keep it behind — so in background mode the request fails before anything starts, with a message to open a WezTerm window or turn the option off. A visible refusal beats a window that takes the keyboard mid-sentence, which is the one thing the option exists to prevent. Not established for cmux and iTerm2 when they have to be launched first; they are expected to come forward while starting.

**In WezTerm the old pane is active again before the command is sent.** `spawn` selects the new tab, and `send-text` can take up to its timeout; refocusing only afterwards left that whole interval for the user's keystrokes to land in the new shell and mix with the command.

**Rejected alternative — always background.** Foreground stays the default: most presses are made to look at the session they open.
