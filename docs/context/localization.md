# Localization

How the app decides which language it renders in, where the catalogues live, and who owns the answer. The mechanisms and the invariants live in `CLAUDE.md`. This file holds the forks — what was chosen over what, and why; it is meant to be readable without any other document. The migration's own promotion ledger and audit tables were a working record and are not part of the repository, so nothing here cites them.

## Catalogues live in `Contents/Resources/<tag>.lproj` and are read with `Bundle(path:)`

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured)
**Source:** issue #24, which prescribed the opposite; PR #41; `app/Sources/App/Localization.swift`, `app/Package.swift:15-21`, `app/verify-bundle.sh`
**Revisit when:** the `.app` stops being assembled by hand in `build.sh`, or SwiftPM's generated accessor stops falling back to a build-machine path

Issue #24 prescribed SwiftPM `resources:` with `Bundle.module`. That was rejected on measurement, not on taste: the generated accessor looks in exactly two places — `Bundle.main.bundleURL/<Name>.bundle`, which is the top of the `.app` and not `Contents/Resources`, and an absolute `.build` path baked into the binary — and calls `fatalError` when neither is there. The consequence is the dangerous one: on the machine that compiled it, a catalogue that was never copied into the bundle still resolves through `.build`, so the missing copy is invisible locally and the crash happens only on someone else's Mac. Reading `Contents/Resources/<tag>.lproj` by path fails in the same place for everybody.

That choice forces `exclude: ["Resources"]` in `Package.swift`. SwiftPM demands a `defaultLocalization` as soon as it notices a `.lproj` under a target, and supplying one starts the machinery this entry rejected.

**Residual, and the device that closes it.** The silent failure does not disappear; it moves to `build.sh`, which assembles the bundle by hand. `app/verify-bundle.sh` closes it by comparing the source `.lproj` files against the built ones byte for byte, comparing the directory sets, requiring regular files, checking `CFBundleDevelopmentRegion`, and running `plutil -lint` on each catalogue. It is a build script rather than a test on purpose: `swift test` runs with no `.app` present at all, so a test would have to skip — and a gate that is green because it did not run has the same shape as the defect the gate exists to catch.

## The app owns the language, and it flows one way to the extension

**Type:** decision
**Status:** superseded — see "Each surface follows its own platform" below
**Superseded by:** user decision, 2026-08-24; PR #41
**Evidence:** confirmed
**Source:** issue #24; PR #41; the picker in `app/Sources/App/SetupWindowController.swift`
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
**Source:** user decision, 2026-08-24; PR #41; `extension/i18n.js`, `extension/_locales/`
**Revisit when:** Chrome gains a per-extension language setting, or the product decides that one language across both surfaces is worth a synchronization protocol again

The extension asks `chrome.i18n` and the app asks macOS. Neither tells the other, and the two can differ — that is not a defect, it is what two platforms answer.

**What that costs, stated plainly:** a user on Japanese macOS with English Chrome sees the app in Japanese and the buttons in English, with no single place to change both. That is the exact cost the previous decision existed to avoid.

**What it buys** is the removal of the extension synchronization machinery the previous answer required: a locale query on the native socket, a cache with a generation and an install identity, a per-worker sequence fence, a serialized cache writer, and a redraw queue. The property that machinery could never quite reach — one language, always, on both surfaces — was eventually-consistent by construction, and the interval where the two disagreed was documented rather than eliminated. Two platform answers disagree in the same places, without the machinery.

**How the extension's own document language is decided.** Not by Chrome's configured UI language: Chrome may report a language we do not ship and then serve the English catalogue, and writing that language onto `<html lang>` declares English text as something else. Every catalogue carries one non-user-facing message whose value is its own tag, so the catalogue that answered names itself and `<html lang>` is that answer.

**The two Chrome-namespace keys are unchanged** — `name` and `description` in `manifest.json` still come from `_locales`, as they always had to.

## The compatibility passenger protected a state Chrome refuses to construct

**Type:** incident
**Type:** decision
**Status:** active
**Evidence:** confirmed — Chrome refused to load the unpacked extension with "Cannot load extension with file or directory name _i18n. Filenames starting with \"_\" are reserved for use by the system", on the first real load after PR #41 shipped
**Source:** issue #45; `tests/i18n.test.js` (the extension-root reserved-name gate); PR #41 for what was retired
**Revisit when:** a future release removes or renames a file that the previous release's manifest or `importScripts` list names

PR #41 shipped `extension/_i18n/*.js` pinned byte-for-byte as a compatibility passenger, so that a service worker of the adjacent generation — the one whose `importScripts` names those files — would survive a folder swap. Every VM-based gate loaded that folder happily. Chrome's real loader refused the entire folder: any extension-root name starting with `_` is reserved for the system (`_locales`, `_metadata`), and only the real loader enforces this. The failure surfaced on a user machine at first load, exactly the class PR #41's "needs a device" list existed for.

**The refusal falsified the passenger's premise.** The only generation whose consumers import `_i18n` files also *contains* `_i18n` at its root — so Chrome never loaded it, on any machine, at any point. A service worker that was never resident cannot be aborted by a missing import. The retirement precondition issue #45 asked for ("no installed profile can still be loading the old generation") was answered by the refusal itself, and stronger than any version floor could: the profile in question cannot exist.

**So the retirement is a delete, not a deployment.** The passenger files, their load entries in `manifest.json`, `background.js` and `options.html`, the extension-side locale cache and its per-worker fence, the renderer and requester compositions kept as adjacent-generation ABI, the mixed-generation execution matrix and its pinned baseline fixture all lost their subject at once — each existed only to keep that unloadable generation alive. `_locales/en` replaced `_i18n` as the argument-identity source for the other four locales; `en` itself has no external oracle and is reviewed through its byte pin.

**What survives the retirement, because it is not about `_i18n`:**

- The mixed-read window is real (measured, one in ∼10,200 — see "What the atomic extension-folder swap does not buy"). What was wrong was pairing it with a generation that could not be resident. The forward rule the window still imposes: **a release may not remove or rename a file that the previous release's manifest or import list names**, or a worker that loads across the swap aborts once. This release removes `_i18n` files that no previous *loaded* release names, which is why it may.
- The loader's reserved-name rule now has a gate (`tests/i18n.test.js`): no extension-root name may start with `_` unless Chrome owns it. It is a lint for a rule only the real loader enforces — the one kind of contract the VM gates structurally cannot see, which is the same class as the device gates in #46/#49/#50.

## Three stores, three verdicts

> Superseded 2026-08-25: the compatibility passenger was retired — Chrome refuses any extension root name starting with `_` other than its own, so no Chrome ever loaded a generation containing `_i18n` and the passenger protected a state that cannot exist. See "The compatibility passenger protected a state Chrome refuses to construct" below. Two stores remain: `.lproj` for the app, `_locales` for the extension, with `en` the argument-identity source for the other locales.

**Type:** decision
**Status:** superseded
**Evidence:** confirmed — the ownership gate checks the app catalogues, the live Chrome catalogues and the compatibility passengers separately; the live argument-identity gate reads `_locales` itself
**Source:** PR #41; `app/Tests/AppTests/CatalogueOwnershipTests.swift`, `tools/check-locales.js`, `extension/_locales/`
**Revisit when:** —

The app `.lproj` catalogues are canonical for AppKit, `_locales` is canonical for the extension and is the store Chrome reads, and `_i18n` is a non-canonical compatibility artifact retained for adjacent-generation consumers. `_i18n` is pinned to the migration baseline; it is not a second live catalogue that must track every reviewed translation edit in `_locales`.

The checks therefore have separate subjects. Ownership asks whether each store has exactly the entries it owns. The compatibility pin asks whether the passenger still has its baseline bytes. The live argument-identity check reads `_locales` entries and compares placeholder positions and sentinel projections with the source, because a byte pin can report only that a reviewed edit happened and cannot distinguish a translation change from structural corruption.

An intentional `_locales` translation edit keeps the compatibility checker green and requires a reviewed baseline update; an edit that changes a placeholder binding must fail the semantic gate before anyone updates that pin.

## The boundary for `AppleLanguages` is the first localization lookup, not the existence of AppKit

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured with a windowless probe bundle)
**Source:** PR #41 (ledger D301–D309); `applyStoredLanguageToAppKit` in `app/Sources/App/main.swift`, `AppLocalization` in `app/Sources/App/Localization.swift`
**Revisit when:** AppKit starts honouring a language change mid-process, or the app gains a second entry point that draws UI

Measured with an `LSUIElement` probe bundle that writes only its own domain: written **after** AppKit has come up, the same process keeps its old language — `preferredLocalizations` does not move and an `NSAlert` button stays `확인`, while only the readback changes; left in place, the next launch picks it up; written **before** AppKit is touched, the same process picks it up immediately (`zh-Hant`, with `好` and `打開`). So the write lives in `main.swift` ahead of `NSApplication.shared`, and a language change during a session needs a restart for AppKit's own chrome. Our own strings do not go through this key at all — they are read with `Bundle(path:)` — which is why they redraw immediately and the chrome does not.

`auto` **never writes** the resolved tag. An explicit choice writes `[tag]` to `AppleLanguages` and records that exact value in the app-local `TerminalCheckoutAppleLanguagesProvenance` companion key. Automatic mode removes the language key only when its current value still equals that record, then removes the record; an unrecorded value or a value changed by System Settings or another writer is left alone. This is provenance, not a comparison against the value the app would have written, because a user's own single-language choice can happen to be identical.

**Trap worth the next person's time (measured).** After removing the key, `object(forKey:)` still returns a value, because the search list falls through to `NSGlobalDomain` — and that fallthrough is *how `auto` works*, not an obstacle to it. Absence has to be asserted against `persistentDomain(forName:)`, and the useful assertion is that the effective value before a temporary override equals the effective value after removing it.

**Boundary.** Automatic resolution first honors an effective `AppleLanguages` value that does not match the app's provenance record, which includes a System Settings per-app choice. When the effective value matches the app's record, it reads the argument domain and then the global domain instead of feeding the app's own value back into `Locale.preferredLanguages`. An `-AppleLanguages` argument or a higher-priority external value therefore still wins.

The unit test stages the production `persistentDomain(forName: UserDefaults.globalDomain)` call through an isolated `UserDefaults` subclass because writing `NSGlobalDomain` would mutate the test runner's real defaults; the actual System Settings domain and AppKit's first lookup remain device-only evidence. The measured host has no `AppleLanguages` in its global volatile domain, so that branch is not part of the production order.

**Device release gate — ownership.** On a real Mac, with the app preference at `auto`, assign Terminal Checkout a per-app language in System Settings, quit and relaunch, and verify that the System Settings entry remains and both the setup window and AppKit chrome use that language. Then choose an explicit language in the app, relaunch, choose `auto`, and verify that only the value the app recorded is removed; an external per-app or global choice remains. Also compare the app's chosen language with what another ordinary app displays, and record both `defaults read -g AppleLanguages` and the app's effective `array(forKey: "AppleLanguages")`; if they agree on the device, record that and close the remaining domain-order question.

**Device release gate — first lookup.** Launch the built app once for each of an explicit language, `auto` with a global language order, and `auto` with a per-app System Settings choice. Verify the first AppKit menu, alert and file-panel labels against the app's own strings. The unit tests inject language lists and cannot establish AppKit's first-lookup boundary or the language of macOS's own permission prompt.

**Unmeasured.** Whether the TCC permission prompt follows the chosen language is not known. The prompt is drawn by tccd, and measuring it would mean resetting the user's live Automation grant.

**Residual — same-value provenance collision (suspicion).** If the app writes and records `["ja"]`, then System Settings later writes the byte-identical value into the same application domain, a later switch to `auto` cannot distinguish the second writer and may remove the user's setting. The trigger is an explicit app choice, an identical subsequent System Settings value, and then `auto`; whether System Settings writes exactly that one-element array or a longer list is unmeasured. “Never remove” was rejected because it would leave the app's own override in place permanently, so the ownership device gate must measure this collision rather than narrow the provenance rule pre-emptively.

## Retired: the published locale was one value under one key

**Type:** decision
**Status:** superseded by A6 — the app-to-extension publication protocol was removed; this entry records the retired design
**Evidence:** confirmed at the API level — the torn read was reproduced as a failing test before the change; the cross-process and crash behaviour underneath it was not measured
**Source:** round 9 review; PR #41; the pre-A6 `LocaleState` implementation and its focused tests
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
**Source:** PR #41; `app/Sources/Core/WarpControl.swift:24` and `:63-73`, `uninstall.sh:69-70`
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
**Source:** PR #41; `runAppleScript` in `app/Sources/Core/AppleScriptSupport.swift`, `wezTermFallbackArguments` in `app/Sources/Core/TerminalRunner.swift`
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
**Source:** PR #41; `ShellPayload` and `localized` in `app/Sources/App/Localization.swift`, `testCommand` in `app/Sources/App/SetupWindowController.swift:177`, `renderCommand` in `app/Sources/Core/CommandRenderer.swift`
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
**Source:** PR #41; `LocaleRestartGate` in `app/Sources/App/Settings.swift`, `restartForLanguage` in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** claude input delivery gains a bounded worst case, or the restart stops being user-initiated

A language change moves AppKit's own chrome only on the next launch, so the card offers a restart. Restarting through an in-flight claude input delivery would cut it off and orphan a Warp injection helper whose only defence is its lifetime, so the gate answers "not now".

**Rejected alternative — defer the restart until the delivery finishes.** Two reasons. The window already says "not restarting right now, press again when the delivery has finished", and a queue that fired by itself would contradict a sentence about to exist in five languages. More fundamentally, deferring needs the deferral to outlive whatever it waits for — including a delivery that never ends — which is the same self-lifetime problem the gate exists to avoid. The user keeps the trigger.

## Restart notes use a closed state

**Type:** constraint
**Status:** active
**Evidence:** confirmed by the implementation
**Source:** PR #41 (closing change); `LanguageNoteState` and `languageNote` in `app/Sources/App/SetupWindowController.swift`
**Revisit when:** the language card gains another mutually exclusive restart outcome

The language card has three outcomes: the ordinary note, a restart blocked because delivery is in flight, and a relaunch that failed to start. They are represented by `LanguageNoteState`, not by two independent booleans, so the impossible combination “blocked and failed” cannot be passed to the formatter. The failed-launch path therefore keeps its own message instead of borrowing the explanation for a delivery refusal.

## Residual: the compatibility cache's fence is per worker, not per account

> Superseded 2026-08-25: the cache and its fence were removed with the compatibility passenger — the adjacent generation that would have called the preserved writer was never loadable by Chrome (see the incident entry above), so the residual left with its subject.

**Type:** constraint
**Status:** superseded
**Evidence:** unknown — the interleaving is a reviewer's scenario and was not reproduced
**Source:** PR #41
**Revisit when:** —

**What this limits is the retained compatibility implementation, not the current consumer path.** A4 removed cache reads and writes from current consumers, but an adjacent old service worker can still open the new `i18n.js` after a folder swap and call its preserved writer. Removing that implementation now would abort the old worker; generation-consistent deployment is the point at which this residual can leave with its passenger.

For such an adjacent consumer, the cache is fenced against stale writes inside one service-worker realm. A realm that keeps running after a new one has started is outside that fence: the two have different scopes, so the fence does not see them as competing, and because the ordering rule accepts a different `installId` unconditionally, an old realm's write can land on top of a new one.

It is written down rather than fixed because it cannot be observed from where we stand — nothing in the extension can ask "is another realm of me still alive", and the scenario has never been reproduced. In the compatibility window the damage is bounded to an old consumer rendering the wrong language until another publication; current consumers follow Chrome and never read this cache.

## What the atomic extension-folder swap does not buy

**Type:** constraint
**Status:** active
**Evidence:** confirmed (measured — one mixed read in roughly 10,200)
**Source:** PR #41 (measured replacement probe); `app/Sources/App/Installer.swift`
**Revisit when:** Chrome gains a way to snapshot an unpacked extension folder, or the folder stops being read file by file

Adding locale files meant the extension copy had to be replaced rather than edited in place, and the replacement is atomic: the folder is built complete beside the old one and swapped, so it is never observed missing or half-built (measured, zero occurrences in roughly 10,200 reads; `rename(2)` cannot be used because it refuses a non-empty directory, so it is `replaceItemAt`).

**Atomic does not mean a reader sees one generation.** Measured once in that same run: a reader opened `manifest.json` before the swap and a nested file after it, and mixed two generations. There is no filesystem primitive that protects a reader opening several files in sequence — the reader has to take a snapshot, and ours is Chrome, which we do not control. The `try?` that used to swallow the failure is gone, so a swap that fails is reported instead of leaving a half-state, but this residual is not closed by that.

## Closure follow-up seeds

The seeds carried out of PR #41 are filed as issues **#42–#52** and are no longer listed here; each issue states the sequence that produces the wrong outcome, which a summary line cannot.

Two things about that list are worth keeping, because the issues themselves cannot say them:

**It closed at eleven, not at the seven the loop had reached.** Four arrived after the implementation rounds were over — three from reviews with no history of the change (#42's sibling residuals, the `AppleLanguages` collision, the effective-versus-global order) and one from comparing two independently kept lists of what was outstanding. A seed that exists in only one participant's notes dies with those notes, which is why the lists were compared rather than merged on trust.

**Two of them are device-only** (#46, #50) and cannot become tests. They are release gates. A gate that no suite can execute has to be written where a release is prepared, not where tests live, or it is not a gate at all.

## Closure dispositions preserved from PR #41

Numbered as in `testing.md`, and self-contained for the same reason: the earlier rows of the working ledger were not carried over, so nothing here cites a row that is not present.

- **D291:** `languageNote(restartBlocked: Bool, restartFailed: Bool)` made a mutually exclusive three-state UI represent an impossible combined state; `LanguageNoteState` makes that state unrepresentable.
- **D293:** Q12 stays on the device release-gate list with the “do not fight the prompt” decision recorded above and an open pre-statement choice (now #46); Q13 becomes a follow-up for the installed-settings side effect after A5 removed the locale-query aggravation (now #47); Q14 becomes a follow-up for missing progress feedback while the already-shipped deferred-restart explanation remains deliberate (now #48).
- **D301:** `AppleLanguages` is shared with System Settings, so automatic mode records the exact array this app writes and removes it only while the effective value still matches that record; unconditional removal and comparison with a value the app merely intended to write were rejected because neither proves ownership.
- **D302:** automatic app strings resolve from an effective unowned `AppleLanguages` value or from the external argument/global domains when the value matches this app's record; clearing the key during a switch and hoping `Locale.preferredLanguages` refreshes was rejected because the process may retain the old answer.
- **D303:** the `Locale.preferredLanguages` default argument became an optional injected test value, with the production path reading the external source inside the function before any explicit write; the unit suite cannot observe AppKit's first-lookup consequence, so the device release gate remains required.
- **D304:** the shared-domain write sweep found only `AppleLanguages` in the app's product sources; `terminal`, `baseDirectory`, `language`, `lastRequestAt`, `toolAvailability` and `toolExecutables` are app-owned keys, while private-suite cleanup in tests is not product behavior.
- **D305:** the host measurement found no keys in `volatileDomain(forName: UserDefaults.globalDomain)` and `AppleLanguages` in the persistent global domain, so the unused volatile-global branch was removed; the unit test overrides both accessors with conflicting values to prove it reads the production persistent branch without mutating the host, while actual System Settings precedence remains a device gate.
- **D306:** the effective-value-before-and-after contract was restored as `testAutomaticRestoresTheEffectiveValueItFound`; it is not subsumed by the provenance tests because those prove ownership of the app copy, not restoration of the answer below it.
- **D307:** provenance cannot distinguish a later System Settings write that is byte-identical to the app's recorded value; this remains a suspicion with the explicit-choice → identical per-app value → `auto` trigger, and “never remove” was rejected because it would preserve the app's override indefinitely.
- **D308:** the ownership device gate must compare the app's automatic language with another app's displayed language and record both `defaults read -g AppleLanguages` and the app's effective `AppleLanguages` array; the current process probe had no bundle identifier, so it cannot settle the field behavior.
- **D309:** the staging sweep found one corrected mismatch — the external-language test staged a global volatile domain that production does not populate — while private suites, injected resolver lists, source-resource paths, tag overrides, socket environment overrides and temporary filesystem fixtures all exercise the same API seams for isolation or pure contracts rather than pretending to be field-produced language inputs.
- **D316:** the current-prose sweep corrected the remaining `#24` language claim, Korean code comments, the live-pin ownership attribution, the absolute live-failure count and the promise that saved labels always follow Chrome; the old `LocalePublicationTests` wording in the retired-publication history remains because it names evidence from that design rather than a live test.
- **D317:** `LocalePublicationTests.swift` and its class became `LocalizationTests` because the three surviving cases cover fallback, corrupt preferences and picker state, not publication; the historical `LocalePublicationTests` reference remains explicitly scoped to the pre-A6 publication record.
- **D318:** the adding-language instructions now name the app list, extension list, both catalogue stores, both compatibility load lists and checker mapping/hash metadata; the supported-only toggle showed that none of the independent extension declarations can be inferred from `supportedLocales`.
- **D319:** a live-catalogue diagnostic states only that bytes differ and asks for review before a pin moves; it does not assert that the edit is benign, and its test compares the exact edited failure set instead of an absolute count.
