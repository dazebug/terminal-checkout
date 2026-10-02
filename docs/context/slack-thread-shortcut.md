# Slack thread shortcut

Why the Slack desktop workflow uses a user-owned Shortcuts action and a URL scheme, and which measured import and launch behaviors constrain it.

## A user-owned shortcut is the trigger

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decision and driver measurements, 2026-10-02; [Slack Help — Manage apps in an Enterprise organization](https://slack.com/help/articles/360000281563-Manage-apps-in-an-Enterprise-organization); [Slack docs — Using Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode)
**Verification:** corroborated by the linked Slack docs for app visibility and Socket Mode routing
**Revisit when:** Slack documents a user-private message shortcut for its desktop app, or Socket Mode gains a per-user routing guarantee

The trigger is Slack desktop's **Copy link** followed by a keyboard shortcut the user assigns to a shared Shortcuts workflow. A Slack app message shortcut was rejected because an installed workspace app is available to all members by default, with per-user restrictions reserved for Enterprise, and multiple Socket Mode connections can receive an event on any connection. Isolating that route would require a separate app per user. A content script on `app.slack.com` was rejected because the user works in Slack's desktop app.

## The URL can choose a thread, not a command

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decision, 2026-10-02; the URL and request contract in `app/Sources/Core/SlackThreadURLContract.swift` and `app/Sources/Core/SlackThreadRequest.swift`
**Verification:** corroborated by Core parser and request tests
**Revisit when:** the app accepts another caller-controlled URL value or changes how the initial claude input is delivered

Shortcuts opens the app through `terminal-checkout://` rather than running a shell script, which would require enabling script execution in Shortcuts. The tradeoff is accepted: a webpage or another app can also open this URL, and the browser asks before launching an external app. The URL contains one validated Slack message link. The work folder, instruction, and command come only from app-local settings, so a caller can choose the thread but cannot replace what runs.

The link is the first text in claude's one plain-text opening argument, followed by the optional instruction. A validated link begins with `https`, which prevents its first character from selecting claude's `!`, `/`, or `#` input modes. This route uses argv only and fails closed if argv admission is unavailable; it never falls back to typing. The app does not call Slack APIs: claude reads the thread through the user's Slack MCP, so the MCP must be available to that session. The thread author's content remains model input and is not filtered by this app.

## The shortcut is signed and configured locally

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** User decision; [Apple — Run a shortcut while working on your Mac](https://support.apple.com/en-asia/guide/shortcuts-mac/apd163eb9f95/mac); driver measurements, 2026-10-02
**Verification:** corroborated by the Shortcuts installer and driver import/run measurements
**Revisit when:** Shortcuts documents a public API to assign a keyboard shortcut or remove a shortcut from the user's library

The app creates the workflow and signs it on the user's Mac with `people-who-know-me`; the public repository contains neither the signed archive nor a signing identity. The user assigns the keyboard shortcut in Shortcuts. No public programmatic assignment path was found, and the examined Shortcuts database had no hotkey column; the app does not edit that database. The Shortcuts CLI has no delete command, so uninstall removes the generated files from app support but leaves the imported workflow in the user's library.

Driver measurements on Darwin 27.0.0 constrain the workflow file and its opening order:

- The URL Encode action encodes `?`, `=`, and `&`, while leaving `:` and `/` unchanged. Its input must be serialized as a `WFTextTokenString`; a plain output attachment imported as an empty text field and opened the app with an empty `url` value.
- Shortcuts imports the shortcut under the source file's name without its extension. The output filename therefore carries the fixed ASCII shortcut name.
- Opening the signed file while the Shortcuts app is still launching created an extra blank shortcut. The app launches Shortcuts by bundle identifier first when needed, waits for `isFinishedLaunching`, and only then opens the file.
- `shortcuts sign --mode people-who-know-me` succeeded and produced an archive beginning with the `AEA1` magic. The app checks this before opening the import flow.

## URL launch ordering is measured

**Type:** constraint
**Status:** active
**Evidence:** confirmed
**Source:** Driver AppKit probe, 2026-10-02, Darwin 27.0.0
**Verification:** corroborated by the recorded probe results
**Revisit when:** AppKit changes URL delivery ordering or LaunchServices accepts registered URL events for bundles outside installed application locations

On a cold URL launch, `application(_:open:)` arrives before `applicationDidFinishLaunching`, and `launchIsDefault` is false. `applicationWillFinishLaunching` has no current Apple Event at that point. A normal launch and a relay launch with `--background` both report a default launch, so automatic setup-window display uses the documented launch flag and the URL callback is buffered until initialization completes. A failure still explicitly opens the setup window; that failure surface is separate from automatic launch-window policy.

A Slack URL still waiting on the serial execution queue can be lost without execution or a visible error if the app exits or restarts for a language change, such as while a long cmux batch is ahead of it; a socket caller instead sees failure when its relay receives no response.

LaunchServices did not send URL events to an app bundle under `/tmp`, despite a registered scheme claim. The URL cold-launch check therefore uses the installed app under `~/Applications`, not a temporary bundle.
