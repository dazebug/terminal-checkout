# Localization

How the app decides which language it renders in, where the catalogues live, and who owns the answer. The mechanisms and the invariants live in `CLAUDE.md`; the decision ledger for the work in progress is in `docs/plans/i18n-five-locales.md`. This file holds the forks — what was chosen over what, and why.

## Catalogues live in `Contents/Resources/<tag>.lproj` and are read with `Bundle(path:)`

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured)
**Source:** issue #24, which prescribed the opposite; ledger D1 and D21 in `docs/plans/i18n-five-locales.md`; `app/Sources/App/Localization.swift`, `app/Package.swift:15-21`, `app/verify-bundle.sh`
**Revisit when:** the `.app` stops being assembled by hand in `build.sh`, or SwiftPM's generated accessor stops falling back to a build-machine path

Issue #24 prescribed SwiftPM `resources:` with `Bundle.module`. That was rejected on measurement, not on taste: the generated accessor looks in exactly two places — `Bundle.main.bundleURL/<Name>.bundle`, which is the top of the `.app` and not `Contents/Resources`, and an absolute `.build` path baked into the binary — and calls `fatalError` when neither is there. The consequence is the dangerous one: on the machine that compiled it, a catalogue that was never copied into the bundle still resolves through `.build`, so the missing copy is invisible locally and the crash happens only on someone else's Mac. Reading `Contents/Resources/<tag>.lproj` by path fails in the same place for everybody.

That choice forces `exclude: ["Resources"]` in `Package.swift`. SwiftPM demands a `defaultLocalization` as soon as it notices a `.lproj` under a target, and supplying one starts the machinery this entry rejected.

**Residual, and the device that closes it.** The silent failure does not disappear; it moves to `build.sh`, which assembles the bundle by hand. `app/verify-bundle.sh` closes it by comparing the source `.lproj` files against the built ones byte for byte, comparing the directory sets, requiring regular files, checking `CFBundleDevelopmentRegion`, and running `plutil -lint` on each catalogue. It is a build script rather than a test on purpose: `swift test` runs with no `.app` present at all, so a test would have to skip — and a gate that is green because it did not run has the same shape as the defect the gate exists to catch.

## The app owns the language, and it flows one way to the extension

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** issue #24; ledger D8, D9 and D17 in `docs/plans/i18n-five-locales.md`; the picker in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** the setup window stops being the first screen a user sees, or the extension gains a way to answer before the app can

The requirement is one language across the app and the extension, chosen by the user.

**Rejected alternative — each side follows its own platform locale** (`chrome.i18n` alone). Chrome's UI language is not macOS's and has no runtime switch, so a user on Japanese macOS with English Chrome would see two languages and have no single place to fix it.

**Rejected alternative — the extension is the source of truth.** The reason is ordering, not preference: the setup window is what a user sees *before* the extension is installed, so an extension-owned answer does not exist at the moment it is first needed. The app can always resolve its own language with no extension present.

**Cost, not hidden.** What this buys is eventual consistency, not simultaneity. A content script cannot reach the app directly — it goes through the service worker — so the first render happens before that round trip answers, and right after an app launch or while the app is down two languages can be on screen at once.

`chrome.i18n` still has exactly two keys to itself, `name` and `description` in `manifest.json`, because nothing else can localize those.

**State today:** only the app half exists — the picker, the resolved locale, and the published snapshot. The protocol that carries it to the extension and the cache that consumes it are still plan items 15 and 16.

## The boundary for `AppleLanguages` is the first localization lookup, not the existence of AppKit

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured with a windowless probe bundle)
**Source:** ledger D14, D22 and D79 in `docs/plans/i18n-five-locales.md`; `app/Sources/App/main.swift:19-24`, `app/Sources/App/Localization.swift:95-128`
**Revisit when:** AppKit starts honouring a language change mid-process, or the app gains a second entry point that draws UI

Measured with an `LSUIElement` probe bundle that writes only its own domain: written **after** AppKit has come up, the same process keeps its old language — `preferredLocalizations` does not move and an `NSAlert` button stays `확인`, while only the readback changes; left in place, the next launch picks it up; written **before** AppKit is touched, the same process picks it up immediately (`zh-Hant`, with `好` and `打開`). So the write lives in `main.swift` ahead of `NSApplication.shared`, and a language change during a session needs a restart for AppKit's own chrome. Our own strings do not go through this key at all — they are read with `Bundle(path:)` — which is why they redraw immediately and the chrome does not.

`auto` **removes** the key instead of writing the resolved tag. Writing it would turn "follow the system" into a permanent app-level override: the user changes the macOS language afterwards and every app follows except this one, with nothing on screen to say why.

**Trap worth the next person's time (measured).** After removing the key, `object(forKey:)` still returns a value, because the search list falls through to `NSGlobalDomain` — and that fallthrough is *how `auto` works*, not an obstacle to it. Absence has to be asserted against `persistentDomain(forName:)`, and the useful assertion is that the effective value before a temporary override equals the effective value after removing it.

**Boundary.** `auto` removes only the app-owned override. An `-AppleLanguages` argument on the command line, or a domain of higher priority, still wins.

**Unmeasured.** Whether the TCC permission prompt follows the chosen language is not known. The prompt is drawn by tccd, and measuring it would mean resetting the user's live Automation grant.

## The published locale is one value under one key

**Type:** decision
**Status:** active
**Evidence:** confirmed at the API level — the torn read was reproduced as a failing test before the change; the cross-process and crash behaviour underneath it was not measured
**Source:** round 9 review; ledger D80 and item 34 in `docs/plans/i18n-five-locales.md`; `LocaleState` in `app/Sources/App/Settings.swift`, `app/Tests/AppTests/LocalePublicationTests.swift`
**Revisit when:** a second process gains a reason to write the publication, or the extension stops ordering by `(installId, epoch)`

The app tells the extension three things — an install id, an epoch, and a tag — and the extension accepts a snapshot from the same install only when the epoch is strictly greater. Those three were three `UserDefaults` keys, written one after another.

**A single-writer rule does not make readers atomic.** The rule that only the GUI may write removed the race between two *writers*; it says nothing about a *reader*, which could observe the writer's half-finished sequence: between the epoch write and the tag write, the new epoch carrying the old tag — a pair that was never published. The extension accepts that pair, and then turns down the correct publication behind it for carrying an epoch it already holds, so the language stays wrong for good. The two failures are different axes, and several rounds of designing this contract asked only what to publish, never how to commit it.

One key now holds one dictionary, and what that buys has two halves worth keeping apart.

**At the API level**, a publication is one `set` of one value, so there is no longer a moment when the writer has stored part of it — the observing `UserDefaults` subclass in `LocalePublicationTests` reads after every write the writer makes and sees only the complete old triple or the complete new one.

**Below that level, this is inference and not measurement.** The subclass proves there is no intermediate callback **inside one process**; it says nothing about what a second process sees through `cfprefsd`, and nothing about what survives a crash between the write and the flush. Neither was measured — no two-process run was made — so the claim stops at "a single value has no parts for a reader to mix", which is a property of the API's shape rather than an observed guarantee of the store underneath it.

**Implementation consideration — JSON with `Codable`.** Not a rejected alternative: nothing was built either way, and this was a choice made at the keyboard before the first line (round 10 asked, and there is no branch or commit to point at). All-or-nothing decoding sounds like the tighter answer, and what argued against it is that it introduces an encode-failure branch that cannot be reached, while every way of handling an unreachable branch produces a comment claiming more than the code does. The validation that actually matters — non-empty id, epoch in range, tag among the ones we ship — is unchanged either way, so the shape with no failure mode was the one written.

**The three old keys are ignored rather than adopted.** A triple written in three steps cannot be shown to have been committed as one, which is the defect itself, so it is not evidence of anything. Ignoring them lands on a state the design already defines: no readable snapshot, so the next publication mints a new identity, which the extension accepts unconditionally. They are deleted as well, and the deletion goes **first** — with the old state ignored, the new envelope carries a freshly minted identity, so an interruption between the two writes would leave two publications with different install ids, each accepted unconditionally, and two builds trading the language back and forth. Deleting first leaves nothing behind, which a mint recovers from.

## The Warp tab-config marker is a permanent machine protocol token

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** ledger D25, D38 and D66 in `docs/plans/i18n-five-locales.md`; `app/Sources/Core/WarpControl.swift:24` and `:63-73`, `uninstall.sh:69-70`
**Revisit when:** the tab-config file format changes, or Warp starts giving `#!` lines a meaning

The marker is `#!terminal-checkout/tab-config/v1`. `#` is a TOML comment, so Warp's parsing is unaffected; the `!`-and-path shape reads as a marker to a human; `v1` means a later format change does not reopen the language question; and it is all ASCII.

**Rejected alternative — keep the Korean header.** It leaves a Korean constant in an English tree, and worse, it leaves the token in a state that can change again for a reason that has nothing to do with the file format.

**Rejected alternative — translate it to English.** The same problem returns the next time the interface language changes.

**Collection is a pair.** Both the app and `uninstall.sh` keep recognizing the old Korean header. Teaching only one side the new token leaves files that nobody ever deletes.

**Why the match is on the whole line.** A prefix match would delete a user's file whose header merely starts with our string — `…/tab-config/v10` is enough. Splitting the human-readable explanation onto the following line is what made a whole-line match possible; the legacy Korean header keeps its prefix match because its explanation is on the same line.

**Residual, not a solved design.** Rollback is forward-only: an older binary cannot collect a file carrying the new token. The damage is a leftover file in `~/.warp/tab_configs/`, which is why this is accepted and written down rather than engineered around.
