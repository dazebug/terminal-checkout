# Slack thread shortcut

Why the Slack desktop workflow is Copy link plus a global shortcut the app registers itself, and which measured behaviors ruled out the Shortcuts app and the URL scheme it needed.

## The trigger is Copy link plus a keyboard shortcut

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decision and driver measurements, 2026-10-02; [Slack Help — Manage apps in an Enterprise organization](https://slack.com/help/articles/360000281563-Manage-apps-in-an-Enterprise-organization); [Slack docs — Using Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode)
**Verification:** corroborated by the linked Slack docs for app visibility and Socket Mode routing
**Revisit when:** Slack documents a user-private message shortcut for its desktop app, or Socket Mode gains a per-user routing guarantee

The trigger is Slack desktop's **Copy link** followed by a keyboard shortcut. A Slack app message shortcut was rejected because an installed workspace app is available to all members by default, with per-user restrictions reserved for Enterprise, and multiple Socket Mode connections can receive an event on any connection. Isolating that route would require a separate app per user. A content script on `app.slack.com` was rejected because the user works in Slack's desktop app.

## The app registers the shortcut itself

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decision and driver measurements, 2026-10-03, Darwin 27.0.0
**Verification:** measured end to end with the installed app — ⌃⇧⌘C pressed with Slack in front opened one session while the app's Accessibility permission was reset
**Revisit when:** a shortcut assigned in the Shortcuts app fires whichever app is in front, or the app stops staying resident after it launches

A keyboard shortcut assigned in the Shortcuts app is stored as a Services key equivalent — `pbs` held `(null) - <workflow id> - runShortcutAsService` with `key_equivalent` `@^$c` — and its run starts inside the frontmost app's process: the `Starting shortcut run from client` log line came from Finder. It worked with Finder in front and did nothing with Slack in front, the one app this workflow is for. The app instead registers a Carbon hotkey with `RegisterEventHotKey`, which the window server matches before any app sees the key; a disposable probe fired with Slack and with cmux in front, and the installed app needed no Accessibility permission. It registers with `kEventHotKeyExclusive`: without it, a combination another process holds exclusively registers with noErr and never fires, while with it Carbon returns -9878, which the Slack pane shows (measured across two processes; within one process a duplicate is refused either way). A press reads the clipboard text at that moment.

There is no default shortcut: one given to every user would take a key combination away from every other app. A combination must include ⌘, ⌃ or ⌥, so it cannot take over ordinary typing. The shortcut works only while the app runs, and after a login nothing starts the app until a Chrome button or the user does, so the Slack pane offers a login item (`SMAppService.mainApp`). A login launch should not open the settings window; it is recognized by the open event's `keyAELaunchedAsLogInItem`, which has not been observed here because that needs a logout — without it the window opens at login and can be closed. `uninstall.sh` runs the app with `--unregister-login-item` before deleting it, because only the app can withdraw its own login item (measured: the item was gone afterwards).

A Slack request still waiting on the serial execution queue can be lost without execution or a visible error if the app exits or restarts for a language change, such as while a long cmux batch is ahead of it; a socket caller instead sees failure when its relay receives no response.

## The clipboard can choose a thread, not a command

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decisions, 2026-10-02 and 2026-10-03; the request contract in `app/Sources/Core/SlackThreadRequest.swift`
**Verification:** corroborated by Core parser and request tests
**Revisit when:** the request accepts another caller-controlled value or changes how the initial claude input is delivered

The whole clipboard text, without surrounding whitespace, must be one validated Slack message link; nothing is extracted from prose. The work folder, instruction, and command come only from app-local settings, so the clipboard can choose the thread but cannot replace what runs. The `terminal-checkout://` URL scheme existed only to carry the link from Shortcuts and was removed with that route, together with its exposure: any webpage could open the URL.

The link is the first text in claude's one plain-text opening argument, followed by the optional instruction. A validated link begins with `https`, which prevents its first character from selecting claude's `!`, `/`, or `#` input modes. This route uses argv only and fails closed if argv admission is unavailable; it never falls back to typing. The app does not call Slack APIs: claude reads the thread through the user's Slack MCP, so the MCP must be available to that session. The thread author's content remains model input and is not filtered by this app.

## The Shortcuts workflow was signed and configured locally

**Type:** decision
**Status:** superseded — the app registers its own shortcut (see "The app registers the shortcut itself"); the measurements below are kept for anyone who reconsiders Shortcuts
**Superseded by:** user decision, 2026-10-03
**Evidence:** confirmed
**Source:** User decision; [Apple — Run a shortcut while working on your Mac](https://support.apple.com/en-asia/guide/shortcuts-mac/apd163eb9f95/mac); driver measurements, 2026-10-02
**Verification:** corroborated by the removed Shortcuts installer and driver import/run measurements
**Revisit when:** a Shortcuts-based trigger is reconsidered

The app created the workflow and signed it on the user's Mac with `people-who-know-me`; the public repository contained neither the signed archive nor a signing identity. The user assigned the keyboard shortcut in Shortcuts. No public programmatic assignment path was found, and the examined Shortcuts database had no hotkey column — the assignment lives in the Services status shown above. The Shortcuts CLI has no delete command, so an imported workflow stays in the user's library until they delete it.

Driver measurements on Darwin 27.0.0 constrained the workflow file and its opening order:

- The URL Encode action encodes `?`, `=`, and `&`, while leaving `:` and `/` unchanged. Its input must be serialized as a `WFTextTokenString`; a plain output attachment imported as an empty text field and opened the app with an empty `url` value.
- Shortcuts imports the shortcut under the opened file's name without its extension.
- Opening the signed file while the Shortcuts app is still launching created an extra blank shortcut; opening it after `isFinishedLaunching` did not.
- `shortcuts sign --mode people-who-know-me` succeeded and produced an archive beginning with the `AEA1` magic.
- `shortcuts sign` rejects an input file whose name does not end in `.shortcut` — the same workflow plist named `.plist` failed with "The file couldn't be opened because it isn't in the correct format." (exit 1).
- The first run of the imported shortcut stops at a Shortcuts prompt asking whether it may send one text item to the app, and `shortcuts run` did not return while the prompt was unanswered, so only the Shortcuts UI can answer it.

## URL launch ordering was measured

**Type:** constraint
**Status:** superseded — the app no longer registers a URL scheme; the platform behavior is unchanged
**Superseded by:** user decision, 2026-10-03
**Evidence:** confirmed
**Source:** Driver AppKit probe, 2026-10-02, Darwin 27.0.0
**Verification:** corroborated by the recorded probe results
**Revisit when:** the app registers a URL scheme again

On a cold URL launch, `application(_:open:)` arrives before `applicationDidFinishLaunching`, and `launchIsDefault` is false. `applicationWillFinishLaunching` has no current Apple Event at that point. A normal launch and a relay launch with `--background` both report a default launch.

LaunchServices did not send URL events to an app bundle under `/tmp`, despite a registered scheme claim; a URL cold-launch check has to use an installed app under `~/Applications`.
