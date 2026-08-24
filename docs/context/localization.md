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
**Status:** superseded — see "Each surface follows its own platform" below
**Superseded by:** user decision, 2026-08-24; ledger D152 in `docs/plans/i18n-five-locales.md`
**Evidence:** confirmed
**Source:** issue #24; ledger D8, D9 and D17 in `docs/plans/i18n-five-locales.md`; the picker in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** the setup window stops being the first screen a user sees, or the extension gains a way to answer before the app can

The requirement is one language across the app and the extension, chosen by the user.

**Rejected alternative — each side follows its own platform locale** (`chrome.i18n` alone). Chrome's UI language is not macOS's and has no runtime switch, so a user on Japanese macOS with English Chrome would see two languages and have no single place to fix it.

**Rejected alternative — the extension is the source of truth.** The reason is ordering, not preference: the setup window is what a user sees *before* the extension is installed, so an extension-owned answer does not exist at the moment it is first needed. The app can always resolve its own language with no extension present.

**Cost, not hidden.** What this buys is eventual consistency, not simultaneity. A content script cannot reach the app directly — it goes through the service worker — so the first render happens before that round trip answers, and right after an app launch or while the app is down two languages can be on screen at once.

`chrome.i18n` still has exactly two keys to itself, `name` and `description` in `manifest.json`, because nothing else can localize those.

**State when this was reversed:** both halves shipped — the picker, the resolved locale and the published snapshot in the app, and the protocol that carried it plus the cache that consumed it in the extension. Eight rounds of review went into that machinery, including the fence and the single-writer envelope. It is being removed rather than fixed, and the entry below says why that is not a loss of the reasoning.

## Each surface follows its own platform: macOS answers for the app, Chrome for the extension

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured — `chrome.i18n` has no per-extension language setting; the display language is `chrome://settings/languages`, checked on Chrome 151.0.7922.172)
**Source:** user decision, 2026-08-24; ledger D152, D162, D163, D171, D172 in `docs/plans/i18n-five-locales.md`; `extension/i18n.js`, `extension/_locales/`
**Revisit when:** Chrome gains a per-extension language setting, or the product decides that one language across both surfaces is worth a synchronization protocol again

The extension asks `chrome.i18n` and the app asks macOS. Neither tells the other, and the two can differ — that is not a defect, it is what two platforms answer.

**What that costs, stated plainly:** a user on Japanese macOS with English Chrome sees the app in Japanese and the buttons in English, with no single place to change both. That is the exact cost the previous decision existed to avoid.

**What it buys** is the removal of the extension synchronization machinery the previous answer required: a locale query on the native socket, a cache with a generation and an install identity, a per-worker sequence fence, a serialized cache writer, and a redraw queue. The property that machinery could never quite reach — one language, always, on both surfaces — was eventually-consistent by construction, and the interval where the two disagreed was documented rather than eliminated. Two platform answers disagree in the same places, without the machinery.

**How the extension's own document language is decided.** Not by Chrome's configured UI language: Chrome may report a language we do not ship and then serve the English catalogue, and writing that language onto `<html lang>` declares English text as something else. Every catalogue carries one non-user-facing message whose value is its own tag, so the catalogue that answered names itself and `<html lang>` is that answer.

**The two Chrome-namespace keys are unchanged** — `name` and `description` in `manifest.json` still come from `_locales`, as they always had to.

## The boundary for `AppleLanguages` is the first localization lookup, not the existence of AppKit

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured with a windowless probe bundle)
**Source:** ledger D14, D22 and D79 in `docs/plans/i18n-five-locales.md`; `applyStoredLanguageToAppKit` in `app/Sources/App/main.swift`, `AppLocalization` in `app/Sources/App/Localization.swift`
**Revisit when:** AppKit starts honouring a language change mid-process, or the app gains a second entry point that draws UI

Measured with an `LSUIElement` probe bundle that writes only its own domain: written **after** AppKit has come up, the same process keeps its old language — `preferredLocalizations` does not move and an `NSAlert` button stays `확인`, while only the readback changes; left in place, the next launch picks it up; written **before** AppKit is touched, the same process picks it up immediately (`zh-Hant`, with `好` and `打開`). So the write lives in `main.swift` ahead of `NSApplication.shared`, and a language change during a session needs a restart for AppKit's own chrome. Our own strings do not go through this key at all — they are read with `Bundle(path:)` — which is why they redraw immediately and the chrome does not.

`auto` **removes** the key instead of writing the resolved tag. Writing it would turn "follow the system" into a permanent app-level override: the user changes the macOS language afterwards and every app follows except this one, with nothing on screen to say why.

**Trap worth the next person's time (measured).** After removing the key, `object(forKey:)` still returns a value, because the search list falls through to `NSGlobalDomain` — and that fallthrough is *how `auto` works*, not an obstacle to it. Absence has to be asserted against `persistentDomain(forName:)`, and the useful assertion is that the effective value before a temporary override equals the effective value after removing it.

**Boundary.** `auto` removes only the app-owned override. An `-AppleLanguages` argument on the command line, or a domain of higher priority, still wins.

**Unmeasured.** Whether the TCC permission prompt follows the chosen language is not known. The prompt is drawn by tccd, and measuring it would mean resetting the user's live Automation grant.

## Retired: the published locale was one value under one key

**Type:** decision
**Status:** superseded by A6 — the app-to-extension publication protocol was removed; this entry records the retired design
**Evidence:** confirmed at the API level — the torn read was reproduced as a failing test before the change; the cross-process and crash behaviour underneath it was not measured
**Source:** round 9 review; ledger D80 and item 34 in `docs/plans/i18n-five-locales.md`; the pre-A6 `LocaleState` implementation and its focused tests
**Disposition:** A6 removed the compatibility publication protocol after current extension consumers stopped reading it; `LocaleRestartGate` remains because it protects delivery lifetime, not publication

Before A6, the app composed three compatibility values — an install id, an epoch, and a tag — and an adjacent old extension accepted a snapshot from the same install only when the epoch was strictly greater. A4's current consumers already ignored them; A5/A6 then removed the protocol. The three values were once three `UserDefaults` keys, written one after another.

**A single-writer rule does not make readers atomic.** The rule that only the GUI may write removed the race between two *writers*; it says nothing about a *reader*, which could observe the writer's half-finished sequence: between the epoch write and the tag write, the new epoch carrying the old tag — a pair that was never published. An adjacent old extension accepts that pair, and then turns down the correct publication behind it for carrying an epoch it already holds, so its language stays wrong for good. The two failures are different axes, and several rounds of designing this contract asked only what to publish, never how to commit it.

In the retired design, one key held one dictionary, and what that bought had two halves worth keeping apart.

**At the API level**, a publication was one `set` of one value, so there was no moment when the writer had stored part of it — the observing `UserDefaults` subclass in the pre-A6 `LocalePublicationTests` read after every write and saw only the complete old triple or the complete new one.

**Below that level, this is inference and not measurement.** The subclass proves there is no intermediate callback **inside one process**; it says nothing about what a second process sees through `cfprefsd`, and nothing about what survives a crash between the write and the flush. Neither was measured — no two-process run was made — so the claim stops at "a single value has no parts for a reader to mix", which is a property of the API's shape rather than an observed guarantee of the store underneath it.

**Implementation consideration — JSON with `Codable`.** Not a rejected alternative: nothing was built either way, and this was a choice made at the keyboard before the first line (round 10 asked, and there is no branch or commit to point at). All-or-nothing decoding sounds like the tighter answer, and what argued against it is that it introduces an encode-failure branch that cannot be reached, while every way of handling an unreachable branch produces a comment claiming more than the code does. The validation that actually matters — non-empty id, epoch in range, tag among the ones we ship — is unchanged either way, so the shape with no failure mode was the one written.

**The three old keys were ignored rather than adopted.** A triple written in three steps could not be shown to have been committed as one, which was the defect itself, so it was not evidence of anything. Ignoring them landed on a state the design already defined: no readable snapshot, so the next publication minted a new identity, which the extension accepted unconditionally. They were deleted as well, and the deletion went **first** — with the old state ignored, the new envelope carried a freshly minted identity, so an interruption between the two writes would have left two publications with different install ids, each accepted unconditionally, and two builds trading the language back and forth. Deleting first left nothing behind, which a mint recovered from.

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

## The bytes a user typed are carried, not normalized

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured); the last hop into the terminal is unmeasured and marked so below
**Source:** ledger D73 and D100, item 31 in `docs/plans/i18n-five-locales.md`; commit `682b6c7`; `runAppleScript` in `app/Sources/Core/AppleScriptSupport.swift`, `wezTermFallbackArguments` in `app/Sources/Core/TerminalRunner.swift`
**Revisit when:** a value that is not a path has to cross `Process.arguments` or the environment, or Foundation stops re-encoding them

Shipping five languages means users write to claude in Korean, Japanese and Chinese, and text handed to a subprocess in `Process.arguments` arrives **decomposed** — Foundation re-encodes it to NFD on Darwin. On the iTerm2 branch the message is embedded in an AppleScript that used to go out as `osascript -e`, so what reached claude was not what was typed; when the input is a `!` one, the decomposed bytes reach the **shell**, where a byte-literal tool like `grep` stops matching.

**Composing to NFC was rejected, and this is the fork worth keeping.** Read as an encoding bug, normalization looks like the answer. Read as *whose bytes are preserved*, it is the same defect from the other side: someone who typed NFD would have their bytes rewritten just as surely. So the carrier changed instead — the script is delivered on stdin, measured to preserve the bytes, with a script file measured equivalent but rejected because that path runs several times per input and a file adds a lifetime to reclaim.

**The class is wider than it looked.** `Process.environment` decomposes exactly like `Process.arguments` (measured), which is why the WezTerm fallback — the no-mux launch, where the command has no stdin and no file to ride on — makes its argument **pure ASCII** rather than moving it to an environment variable. Pipes, file contents, unix sockets and JSON decoding were measured to preserve bytes, which is why Warp's tab-config file and WezTerm's normal `send-text` path were never affected.

**What the paths that remain rest on.** Everything else crossing that boundary is a *path*, and those survive because the filesystem resolves NFC and NFD to the same node (measured on APFS, including a socket bound one way and connected the other) — not because the value is unchanged. On a normalization-sensitive volume that stops being true.

**Unmeasured.** Whether iTerm2's `write text` puts those bytes on the tty unchanged needs iTerm2 running and was not measured; what is established is that they leave AppleScript itself intact, through two independent sinks.

## A localized string may never become machine input, and the type says so

**Type:** constraint
**Status:** active
**Evidence:** confirmed
**Source:** ledger D29 and D34 in `docs/plans/i18n-five-locales.md`; `ShellPayload` and `localized` in `app/Sources/App/Localization.swift`, `testCommand` in `app/Sources/App/SetupWindowController.swift:177`, `renderCommand` in `app/Sources/Core/CommandRenderer.swift`
**Revisit when:** a string has to be both translated and executed, or a second value earns the whitelist exemption

`testCommand` is shown on screen *and* run in the user's terminal. Translate it and an apostrophe in the new language breaks the `echo '…'` quoting, so the test button reports a shell error — a translator, working only in the catalogue, would have no way to see that coming.

The rule that came out of it is that a localized catalogue value never reaches a shell, AppleScript, a TOML file or a terminal's input. **It is carried by types rather than by memory**, in both directions: `localized(…)` takes a `StaticString`, so a key cannot be computed and the catalogue gates can enumerate rather than estimate; `ShellPayload` also takes only a `StaticString`, so a value can be written as a literal in the source and cannot be built from a `String` — and since `localized(…)` returns a `String`, a translated value does not compile in that position.

**Where a type cannot reach, the module boundary does.** The one value exempt from the character whitelist is `{cd}`, because its value *is* shell syntax. What earns the exemption is that the app assembled it out of already-validated ingredients — and since a plain `[String: String]` cannot express "assembled by us", the exemption lives on a non-public overload of `renderCommand` whose only caller builds the dictionary from `repoEntryCommand`. The guarantee is "no request-supplied text can appear in this dictionary", and it holds by there being one caller, not by the type.

## The installer scripts stay English

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `install.sh:117-120`, `uninstall.sh:122-125`; issue #24's checklist item on removing the transitional label glosses
**Revisit when:** the app gains a way to be configured before its first launch, or installation stops going through a shell script

`install.sh` and `uninstall.sh` print in English and are not localized. Two reasons, and the first one is enough on its own: **at install time there is no language yet.** The preference is stored by the app's own picker, so the first run of `install.sh` happens before any language could have been chosen, and reading a preference that cannot exist would only produce a wrong guess. The second is that a shell script cannot reach the catalogues — they are `.lproj` bundles read through `Bundle(path:)`, and teaching a script to parse them would create a second reader of the same files that could drift from the first.

The transitional Korean glosses these scripts and `README.md` carried while the app was Korean-only are gone now that the `en` catalogue ships, which is what issue #24 asked for.

## Rejected: deferring a language restart instead of refusing it

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** ledger D92 in `docs/plans/i18n-five-locales.md`; `LocaleRestartGate` in `app/Sources/App/Settings.swift`, `restartForLanguage` in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** claude input delivery gains a bounded worst case, or the restart stops being user-initiated

A language change moves AppKit's own chrome only on the next launch, so the card offers a restart. Restarting through an in-flight claude input delivery would cut it off and orphan a Warp injection helper whose only defence is its lifetime, so the gate answers "not now".

**Rejected alternative — defer the restart until the delivery finishes.** Two reasons. The window already says "not restarting right now, press again when the delivery has finished", and a queue that fired by itself would contradict a sentence about to exist in five languages. More fundamentally, deferring needs the deferral to outlive whatever it waits for — including a delivery that never ends — which is the same self-lifetime problem the gate exists to avoid. The user keeps the trigger.

## Residual: the compatibility cache's fence is per worker, not per account

**Type:** constraint
**Status:** active
**Evidence:** unknown — the interleaving is a reviewer's scenario and was not reproduced
**Source:** ledger D90 in `docs/plans/i18n-five-locales.md`
**Revisit when:** generation-consistent deployment lets the adjacent-generation cache ABI be removed, a browser API can prove at most one service-worker realm writes it, or the cache moves somewhere with a compare-and-set

**What this limits is the retained compatibility implementation, not the current consumer path.** A4 removed cache reads and writes from current consumers, but an adjacent old service worker can still open the new `i18n.js` after a folder swap and call its preserved writer. Removing that implementation now would abort the old worker; generation-consistent deployment is the point at which this residual can leave with its passenger.

For such an adjacent consumer, the cache is fenced against stale writes inside one service-worker realm. A realm that keeps running after a new one has started is outside that fence: the two have different scopes, so the fence does not see them as competing, and because the ordering rule accepts a different `installId` unconditionally, an old realm's write can land on top of a new one.

It is written down rather than fixed because it cannot be observed from where we stand — nothing in the extension can ask "is another realm of me still alive", and the scenario has never been reproduced. In the compatibility window the damage is bounded to an old consumer rendering the wrong language until another publication; current consumers follow Chrome and never read this cache.

## What the atomic extension-folder swap does not buy

**Type:** constraint
**Status:** active
**Evidence:** confirmed (measured — one mixed read in roughly 10,200)
**Source:** ledger D19, D98 and D99 in `docs/plans/i18n-five-locales.md`; `<scratchpad>/probe_replace.swift`; `Installer.swift`
**Revisit when:** Chrome gains a way to snapshot an unpacked extension folder, or the folder stops being read file by file

Adding locale files meant the extension copy had to be replaced rather than edited in place, and the replacement is atomic: the folder is built complete beside the old one and swapped, so it is never observed missing or half-built (measured, zero occurrences in roughly 10,200 reads; `rename(2)` cannot be used because it refuses a non-empty directory, so it is `replaceItemAt`).

**Atomic does not mean a reader sees one generation.** Measured once in that same run: a reader opened `manifest.json` before the swap and a nested file after it, and mixed two generations. There is no filesystem primitive that protects a reader opening several files in sequence — the reader has to take a snapshot, and ours is Chrome, which we do not control. The `try?` that used to swallow the failure is gone, so a swap that fails is reported instead of leaving a half-state, but this residual is not closed by that.
