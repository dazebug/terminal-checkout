import Core
import Foundation

/// The settings the app owns as their single source. Which terminal to use is decided here and not
/// by the extension.
enum Settings {
    static var terminal: Terminal {
        get {
            if let value = UserDefaults.standard.string(forKey: "terminal") {
                return Terminal(storedValue: value)
            }
            // The default detects what is installed. The order is how long each has been supported
            // and worn in by real use — Warp is last because it has no official way to address a
            // pane and needs a helper process in between
            if PermissionChecker.isITermInstalled { return .iterm }
            if PermissionChecker.isWezTermInstalled { return .wezterm }
            if PermissionChecker.isWarpInstalled { return .warp }
            return .iterm
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal") }
    }

    /// The top-level folder repositories are cloned into — where a command moves when `z` fails.
    /// This only **stores the string**; validation, normalization, and fragment assembly all live
    /// in Core (`normalizedBaseDirectory`, `repoEntryCommand`). The extension neither knows nor
    /// sends this value: paths differ per machine while extension settings ride storage.sync
    /// across an account.
    ///
    /// A stored value that isn't a string (a hand-edited plist, some future build writing another
    /// type) must not read as "not configured" — that is exactly the silent fold decision 4 rules
    /// out. It is handed on as text instead, so `normalizedBaseDirectory` rejects it and the button
    /// fails carrying the reason. `string(forKey:)` cannot express that: it returns nil for both
    /// "absent" and "present but another type".
    static var baseDirectory: String {
        get {
            guard let stored = UserDefaults.standard.object(forKey: "baseDirectory") else { return "" }
            return stored as? String ?? String(describing: stored)
        }
        set { UserDefaults.standard.set(newValue, forKey: "baseDirectory") }
    }

    /// The language the user picked, or `auto`. Stored as text and handed to `resolveLocale` as the
    /// **object** it came back as — a value that is not a string must not read as "follow the
    /// system", which is the same fold `baseDirectory` refuses just above.
    ///
    /// Setting it is what makes this process a writer (D49). It publishes immediately, so the
    /// revision moves in the same process that took the click rather than on the next launch.
    ///
    /// **Only if this process owns the socket.** The comment here used to read "the picker lives in
    /// the setup window, so only the GUI reaches here", which is true and answers a different
    /// question — a *second* GUI instance has a setup window too, and it reached this line and
    /// published (round 15 review). The window that cannot publish is disabled and says so, but the
    /// enforcement is that publishing takes a right only the bind can produce: a guard on a control
    /// is a guard on one caller, and a guard on a boolean is a guard the next caller forgets.
    ///
    /// The preference itself is still written: it is an ordinary user setting in a shared domain,
    /// last writer wins, and the owner reads it on its next launch. What must not happen without
    /// ownership is the **publication**, because that carries a generation the extension orders by.
    static var language: String {
        get { languagePreference(in: .standard) }
        set { _ = setLanguage(newValue) }
    }

    /// The setter's body, with its store and its right as arguments — so the rule can be exercised
    /// against the real code rather than a stand-in, and without writing into the domain the
    /// installed app is using. Returns whether it published.
    ///
    /// `right` defaults to whatever this process holds, and that default is not a way around the
    /// rule: nothing outside `HostServer.swift` can produce one, so a caller can pass the right this
    /// process was given or nothing at all.
    @discardableResult
    static func setLanguage(
        _ newValue: String,
        defaults: UserDefaults = .standard,
        right: LocalePublicationRight? = LocalePublicationRight.current,
        systemPreferred: [String] = Locale.preferredLanguages
    ) -> Bool {
        defaults.set(newValue, forKey: languagePreferenceKey)
        defer { NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil) }
        return publishInteractively(
            AppLocalization.resolvedLocale(defaults: defaults, systemPreferred: systemPreferred),
            as: right, to: defaults
        ) != nil
    }

    /// **The one door an interactive publication goes through**, so that "may this process move the
    /// generation the extension orders by" is settled in one place by both writers rather than
    /// beside each of them.
    ///
    /// It used to *ask* — `right.isHeld` here, and `role.mayWrite` again inside the write — and both
    /// answers could be stale by the time anything was written. `LocaleState.commit` now runs the
    /// write inside the right's own lock and hands back what it wrote, so what comes back here is
    /// not permission but **the publication that exists**. nil is a right that was not held, or was
    /// given up before the write could happen; either way nothing was written and this instance is
    /// no longer the one the relay can reach.
    ///
    /// **And it no longer asks, which it was still doing when that was written** (round 22 review):
    /// a `right.isHeld` stood here after `mayWrite` had been deleted on the reasoning that the write
    /// path does not ask. Removing it changes no outcome — `commit` refuses the same cases — and it
    /// makes the sentence above true rather than nearly true.
    ///
    /// **D112 was re-measured before removing it.** That guard was also documented as load-bearing
    /// for the release compiler: on Swift 6.3.3 a function taking this class and only *forwarding* it
    /// into an inlined callee crashed `CopyPropagation`. `build.sh` is green without it in this
    /// shape, so the note is a fact about that shape and not about this line. If the crash comes
    /// back, the fix is the one that worked before — give the forwarding function something to read —
    /// and the reason to write it down is that a debug build and `swift test` will both be green.
    private static func publishInteractively(
        _ resolved: SupportedLocale, as right: LocalePublicationRight?, to defaults: UserDefaults
    ) -> LocalePublication? {
        guard let right,
              let committed = LocaleState.commit(resolved: resolved, defaults: defaults, right: right)
        else {
            checkoutLog("this instance does not own the socket, so no locale was published")
            return nil
        }
        return committed
    }

    /// Publishes the locale this launch resolved to — the GUI's other writer, beside the picker.
    ///
    /// It exists because `auto` is a promise about the **system's** language, and the system's
    /// language can change while this app is not running: without a publication at launch, an
    /// `auto` user's extension would keep the tag from whenever they last touched the picker (D48).
    ///
    /// What it publishes is `AppLocalization.resolvedLocale()` and **not** `Settings.language`. The
    /// two disagree on exactly one input and it matters here: a stored preference that is not a
    /// string reads as a third state from the setting, while the resolver folds it to English —
    /// which is what the window is drawing. Publishing the preference would tell the extension a
    /// language nothing is rendering in (round 10 review).
    ///
    /// The headless server never calls this. It has no picker, draws nothing, and inventing a
    /// revision there is what D49 rules out.
    /// `resolved` is passed in rather than computed here, and that is what lets the publication
    /// move later without moving the moment the language is decided. `main.swift` resolves once,
    /// immediately after pointing AppKit at the same answer; this runs after the socket has been
    /// bound. Resolving again at that point would ask a second time — and `Locale.preferredLanguages`
    /// can differ between the two — which is the divergence the original placement was avoiding.
    ///
    /// **`right` is what makes "after the bind" a fact of this signature rather than of where the
    /// call happens.** Round 14 moved this call behind `HostServer.start()` and round 15 wrote that
    /// both writers ask one type — but this one still published whatever it was handed, and only the
    /// order of two lines in `AppDelegate` said otherwise (round 16 review). Item 39 of this work's
    /// own plan says it: a rule kept by convention at each call site is broken by the next call site.
    /// A caller that does not own the socket now has nothing to pass.
    ///
    /// **And it reports.** It used to answer `Void`, so `HostServer.start` armed the accept loop
    /// whether or not anything had been published — the invariant the code held was "a publication
    /// was attempted" while the one written above it was "the publication is committed before
    /// anything is answered" (round 18 review). Nil is that gap made visible: the right was given up
    /// between the bind and the write, nothing is on disk for this launch, and the caller has to
    /// decide rather than assume. It is deliberately not `@discardableResult`.
    static func publishLocaleAtLaunch(
        resolved: SupportedLocale,
        right: LocalePublicationRight,
        defaults: UserDefaults = .standard
    ) -> LocalePublication? {
        publishInteractively(resolved, as: right, to: defaults)
    }

    /// What a stored preference reads as.
    ///
    /// The doc above says a value that is not a string must not read as "follow the system", and
    /// the getter used to do exactly that (round 8 review): `as? String ?? auto` folded a
    /// hand-edited plist into a choice the user never made, while `AppLocalization.resolvedTag()`,
    /// looking at the same object, resolved it to English — the picker said one thing while the
    /// window drew another. Handed on as text it stays a **third state**: neither `auto` nor a tag
    /// we ship, which leaves the window to decide what to show for it (it shows the language it is
    /// actually drawing in). `string(forKey:)` cannot express that state at all, answering nil for
    /// "absent" and for "present but another type" alike.
    ///
    /// It takes its store as an argument so the third state can be exercised without writing into
    /// the domain the installed app is using.
    static func languagePreference(in defaults: UserDefaults) -> String {
        guard let stored = defaults.object(forKey: languagePreferenceKey) else {
            return automaticLocalePreference
        }
        return stored as? String ?? String(describing: stored)
    }

    /// When the last request arrived on the socket — the only evidence that the extension really is
    /// loaded in Chrome and connected. A prepared folder cannot tell you whether Chrome loaded it.
    static var lastRequestAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastRequestAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRequestAt") }
    }

    static func recordRequestEvidence() {
        lastRequestAt = Date()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .terminalCheckoutRequestHandled, object: nil)
        }
    }

    /// The last answer about the tools a command calls (z/gh/claude). Asking takes time — it opens a
    /// login shell — so the previous answer is kept for the window to draw the moment it opens. Nil
    /// before the first check.
    static var toolAvailability: [String: Bool]? {
        get { UserDefaults.standard.dictionary(forKey: "toolAvailability") as? [String: Bool] }
        set { UserDefaults.standard.set(newValue, forKey: "toolAvailability") }
    }

    /// A different fact from the same check: does that name resolve to an **executable**. The merge
    /// path calls it as `command claude`, so an installation that is only a function or an alias
    /// cannot take that path.
    static var toolExecutables: [String: Bool]? {
        get { UserDefaults.standard.dictionary(forKey: "toolExecutables") as? [String: Bool] }
        set { UserDefaults.standard.set(newValue, forKey: "toolExecutables") }
    }

    /// Taken as true **before** the check has run. Turning the merge off in the moment right after
    /// launch, when the login shell has not been asked yet, would slow the presets down for the
    /// common installation (an executable) and on Warp would go as far as refusing without the
    /// permission. A wrong answer in the other direction shows up as one `command not found` line
    /// in the pane and is corrected by the next check.
    static var claudeIsExecutable: Bool { toolExecutables?["claude"] ?? true }

    /// Asked again on every launch — the user may have installed something since. When no answer
    /// comes back the previous one is left as it is.
    static func refreshToolAvailability() {
        DispatchQueue.global(qos: .utility).async {
            guard let result = checkTools() else {
                // `checkTools` returns nil when **no** login-shell form produced output we could
                // parse (`ToolChecker.checkTools`): a shell that never answered is one way in, and
                // a timeout, output without the completion marker, and a parse failure all arrive
                // at the same place. Naming only the shell would promote one cause over the rest
                checkoutLog("tool check failed — no login-shell form returned an answer we could parse")
                return
            }
            toolAvailability = result.available
            toolExecutables = result.executable
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .terminalCheckoutToolsChecked, object: nil)
            }
        }
    }
}

extension Notification.Name {
    /// Posted when a socket request is handled — the setup window, if open, updates its state live
    static let terminalCheckoutRequestHandled = Notification.Name("TerminalCheckoutRequestHandled")
    /// Posted when the tool check finishes — it runs in the background, so the window can be up first
    static let terminalCheckoutToolsChecked = Notification.Name("TerminalCheckoutToolsChecked")
    /// Posted after the language choice changes — our own strings redraw immediately, with no restart (D14)
    static let terminalCheckoutLanguageChanged = Notification.Name("TerminalCheckoutLanguageChanged")
}

/// Whether restarting right now would cut something off.
///
/// A language restart must not run while claude input is still being delivered: that delivery is
/// asynchronous, and the Warp injection helper's **only** defence is its lifetime — a restart that
/// orphans it breaks the trust boundary `CLAUDE.md` sets out, and every residual that leans on the
/// same-uid boundary is standing on that lifetime.
///
/// The answer comes from `ClaudeDelivery`, which is kept by the delivery itself rather than by
/// whoever starts one: a flag maintained outside the interval it describes is a second state, and
/// two states drift.
///
/// **Refused, not deferred, and the app already said so.** The note the picker shows reads "the app
/// is not restarting right now. Press again once the delivery has finished." — a refusal with an
/// instruction, written long before this gate had a condition behind it. Making the restart happen
/// automatically later would contradict a sentence three more languages are about to be translated
/// from, and it would need its own lifetime tie: something to fire it, something to cancel it if the
/// user picks another language, something to decide what happens if a delivery never ends. That is
/// the very class of defect this item exists to close, so the user keeps the trigger.
enum LocaleRestartGate {
    /// **Admission, not a question.** This used to be `isSafeNow`, a read of the register — which
    /// answers for the instant it was asked and closes nothing behind itself, so a request already
    /// on its way could still launch a helper before the process died (round 14, P0). Granting now
    /// latches: every later `ClaudeDelivery.admit()` is refused until it is withdrawn.
    ///
    /// Injectable so a test can drive the consumer's branches without a delivery running; the
    /// default is the real operation, so nothing has to remember to wire it up at launch. A gate
    /// that opens when nobody connects it is the shape this item was fixing.
    static var admitRestart: () -> Bool = { ClaudeDelivery.admitRestart() }
    /// Given back when the restart it was granted for did not happen.
    static var withdrawAdmission: () -> Void = { ClaudeDelivery.withdrawRestartAdmission() }
}

// MARK: - The published locale snapshot

/// Which process is asking. **Only one may write** (D49): the GUI is the process that owns the
/// picker, so it is the only one with a reason to move the revision. `--headless-server` shares the
/// bundle id and therefore `UserDefaults.standard` with it, and two read-modify-writes against the
/// same key can publish **different locales under the same epoch** — after which the extension,
/// whose rule is "same install, accept only a strictly greater epoch", drops the newer of the two.
/// Making the second writer impossible removes the case rather than locking around it.
///
/// **Which process may is not a question this asks — it is a value this carries.** Ownership is
/// decided exactly once, by the bind: `HostServer.start()` throws `alreadyRunning` when
/// another instance answers on the path, and that is the only singleton test this app has — an
/// `NSLock` is process-local and cannot see a second process at all. The interactive case therefore
/// **carries** the right that bind produced, so every publication in the program has to have come
/// from one; see `LocalePublicationRight`.
enum LocaleWriterRole {
    /// The GUI holding the socket: has a picker, may mint an identity and advance the revision.
    case interactive(LocalePublicationRight)
    /// The headless server: publishes what the GUI last wrote, and writes nothing.
    case headless
}

/// What goes out to the extension: which locale, and how the extension is to order it.
struct LocalePublication: Equatable {
    /// Identity of the app's data. A different one means "this is a different install" and the
    /// extension accepts unconditionally — which is what makes a reset distinguishable from a stale
    /// message, something a single integer cannot express (D32).
    let installId: String
    let snapshot: LocaleSnapshot
}

/// Reading, minting and advancing the published snapshot.
///
/// The verdict itself is pure and lives in Core (`localeSnapshotToPublish`). What lives here is
/// everything that function deliberately does not know: where the snapshot is kept, what a
/// half-written one means, and who may write. Those are invariants of the caller and of storage,
/// not of the function, which is why they are proved here instead of by widening it (D67).
enum LocaleState {
    /// The whole publication, under **one** key.
    ///
    /// It used to be three, and three keys cannot be read as one fact: between the epoch write and
    /// the tag write, a reader gets the epoch of the `ja` publication carrying the tag of the `ko`
    /// one — a pair this app never published (round 9 review, reproduced by
    /// `testNoReaderObservesMixedSnapshot`). The extension's rule is "same install, accept only a
    /// strictly greater epoch" (D32), so it would take that pair and then turn down the correct
    /// `(…, 4, ja)` for carrying an epoch it already holds, and the language would stay wrong.
    /// **A single-writer rule does not make readers atomic** (the review's sentence): D49 removed
    /// the race between two writers, and this is a reader seeing one writer's half-finished
    /// sequence — a different axis, and the one this key closes. One value is replaced as a whole,
    /// so a read lands on the complete old triple or the complete new one.
    static let publicationKey = "localePublication"

    /// The keys the three-key schema wrote, kept only to be deleted (see `write`).
    static let legacyKeys = ["localeInstallId", "localeEpoch", "localePublishedTag"]

    /// The names inside the envelope. They are the persisted schema, not an implementation detail:
    /// a rename is a new shape on disk, which is why the tests spell them out rather than import
    /// them from here.
    private enum Field {
        static let installId = "installId"
        static let epoch = "epoch"
        static let tag = "tag"
    }

    /// A stored snapshot counts only when **all three** parts are there and readable. A partial one
    /// is not "epoch 0 of this install": republishing 0 under an identity the extension already
    /// holds would lose to its cached higher epoch, and the app would look stuck in the old
    /// language forever. It counts as no identity at all, and a new one is minted (D51). Our writer
    /// puts all three in at once, so an envelope missing one of them was edited by hand or written
    /// by something else — the required set is checked here rather than assumed from the shape.
    ///
    /// `Int.max` is malformed for the same reason absence is — the next revision cannot be
    /// expressed, so staying under this identity would mean publishing changes the extension is
    /// required to ignore.
    private static func stored(_ defaults: UserDefaults) -> LocalePublication? {
        guard let envelope = defaults.dictionary(forKey: publicationKey),
              let installId = envelope[Field.installId] as? String, !installId.isEmpty,
              let epoch = envelope[Field.epoch] as? Int, epoch >= 0, epoch < Int.max,
              let tag = envelope[Field.tag] as? String,
              supportedLocales.contains(tag)
        else { return nil }
        return LocalePublication(
            installId: installId, snapshot: LocaleSnapshot(tag: tag, epoch: epoch)
        )
    }

    /// What this process should publish for `resolved`, and — for the one writer — the persistence
    /// that makes it true for the next one.
    ///
    /// `resolved` is a `SupportedLocale` and not a string: the mint path used to write whatever it
    /// was handed, so a tag we ship no catalogue for could be persisted and was only caught by the
    /// next read, which then discarded the identity to recover (round 10 review). The type asks the
    /// question where the value is made instead.
    ///
    /// The headless server never invents a revision. With a stored snapshot it repeats it verbatim,
    /// even when this launch resolves to a different locale: a system-language change seen only by
    /// a headless process arrives on the next GUI launch, which is the promise `auto` already
    /// makes. With nothing stored it publishes **nothing** (nil) — a response carrying no locale
    /// metadata, which the extension treats as no input rather than as a reason to change (D51).
    /// Held across the read-modify-write of an `.interactive` publication.
    ///
    /// The single-writer rule used to be **an enum argument and nothing else** (round 10 review),
    /// which orders nothing: two `.interactive` callers could read epoch 3 and both write epoch 4
    /// with different tags, and the extension — whose rule is "same install, accept only a strictly
    /// greater epoch" — would keep whichever arrived first and drop the other for good. Item 15 is
    /// where that stopped being hypothetical, because a launch publisher stands beside the picker.
    /// Both of them run on the main queue today, which is a second reason they cannot interleave;
    /// the lock is here because that is a fact about AppKit rather than about this contract.
    ///
    /// **It orders callers inside one process and cannot see another** — `UserDefaults` is shared by
    /// every instance, and a second GUI one is `open -n` away (which is how the language restart
    /// relaunches). What carries that half is not this lock but *who publishes at all*: only a caller
    /// holding the right `HostServer.start()` hands back does, because that is the instance the
    /// extension is talking to. Round 14's review found this half missing; round 16's found that it
    /// was still a rule about where the call sat rather than about what the caller had.
    private static let writeLock = NSLock()

    /// **The write, taken inside the lock that decides whether it may happen.**
    ///
    /// It used to be two locks: `role.mayWrite` (the right's) answered, `writeLock` was taken, and
    /// the write followed — with `HostServer.stop()` free to relinquish in between. The comment here
    /// called that narrowed rather than closed and gave as its reason that merging them "would mean
    /// teardown taking the publication lock". **That reason did not survive being tried**: teardown
    /// takes only the right's lock, and this is the one path that holds both, always in the order
    /// writeLock → the right's. One order is no inversion (`LocalePublicationRight.whileHeld`).
    ///
    /// Nil means **nothing was written**, and it is the only thing nil can mean here — which is what
    /// makes this, rather than `publish`, the function a launch can ask "did it happen".
    static func commit(
        resolved: SupportedLocale, defaults: UserDefaults = .standard, right: LocalePublicationRight
    ) -> LocalePublication? {
        writeLock.lock()
        defer { writeLock.unlock() }
        return right.whileHeld {
            published(resolved: resolved, mayWrite: true, defaults: defaults)
        } ?? nil
    }

    /// What this process should say, writing it first if it is entitled to. The two nils it can
    /// return are not the same fact, which is why the writer's half is `commit` and this composes
    /// it: a refused write falls through to reading, and a reader with nothing stored answers
    /// nothing at all (D51).
    @discardableResult
    static func publish(
        resolved: SupportedLocale, defaults: UserDefaults = .standard, role: LocaleWriterRole
    ) -> LocalePublication? {
        guard case .interactive(let right) = role else {
            return published(resolved: resolved, mayWrite: false, defaults: defaults)
        }
        return commit(resolved: resolved, defaults: defaults, right: right)
            ?? published(resolved: resolved, mayWrite: false, defaults: defaults)
    }

    /// `mayWrite` and not the role, because the role is a question that has already been answered by
    /// the time this runs — carrying it further would mean asking it again in five branches, each of
    /// which could ask it differently.
    private static func published(
        resolved: SupportedLocale, mayWrite: Bool, defaults: UserDefaults
    ) -> LocalePublication? {
        // The one writer is also the one cleaner. Removing the earlier schema's keys used to happen
        // inside `write`, which never runs when a valid envelope is already there — so an envelope
        // beside stale keys kept them for good (round 10 review). Doing it on the way in covers that
        // state and keeps the ordering rule below: the deletion still precedes any envelope write.
        if mayWrite { forgetLegacySchema(defaults) }

        guard let stored = stored(defaults) else {
            guard mayWrite else { return nil }
            return mint(resolved, to: defaults)
        }
        guard stored.snapshot.tag != resolved.tag else { return stored }
        guard mayWrite else { return stored }
        guard !localeIdentityIsExhausted(stored.snapshot) else {
            // One more revision would be `Int.max`, which storage refuses to read back — so the
            // identity is rotated *before* that value exists rather than after it has been written
            // and then judged malformed. The extension takes an unfamiliar `installId`
            // unconditionally (D32), so the language still moves.
            return mint(resolved, to: defaults)
        }
        let advanced = LocalePublication(
            installId: stored.installId,
            snapshot: localeSnapshotToPublish(resolved: resolved.tag, lastPublished: stored.snapshot)
        )
        write(advanced, to: defaults)
        return advanced
    }

    /// A new identity at revision 0 — the recovery for every state that has no usable snapshot,
    /// whether nothing was stored, what was stored could not be read, or the identity ran out of
    /// revisions.
    private static func mint(_ resolved: SupportedLocale, to defaults: UserDefaults) -> LocalePublication {
        let minted = LocalePublication(
            installId: UUID().uuidString, snapshot: LocaleSnapshot(tag: resolved.tag, epoch: 0)
        )
        write(minted, to: defaults)
        return minted
    }

    /// The three-key state an earlier build wrote is **not read** — a triple written in three steps
    /// cannot be shown to have been committed as one, which is the defect itself, so it is not
    /// evidence of anything. Deleting it is the other half of that decision, and the reason is the
    /// build that *does* read it: nothing here has been released, so a copy holding those keys is a
    /// copy on our own machines, sharing the bundle id and therefore this domain, whose headless
    /// server would go on handing the extension a triple this build has already replaced. Measured
    /// when the envelope was introduced: `defaults read com.dazebug.terminal-checkout` held no
    /// locale key at all, so what this covers is the state item 8's still-pending GUI checks would
    /// create, not one that has been seen.
    ///
    /// It runs from `publish` rather than from `write`, and that is the fix for the state where a
    /// valid envelope and stale keys sat side by side: nothing writes in that state, so a cleanup
    /// living in `write` never ran and the old keys stayed for good. Deleting is a write and so it
    /// is still reachable only from a caller holding the publication right — the single writer stays
    /// single (D49).
    private static func forgetLegacySchema(_ defaults: UserDefaults) {
        for key in legacyKeys { defaults.removeObject(forKey: key) }
    }

    /// One `set`, because a publication is one fact. Three of them are what let a reader see a
    /// triple that was never published.
    ///
    /// The legacy keys are already gone by the time this runs (`publish` clears them on the way
    /// in), which is what keeps the two states from coexisting: an envelope under a freshly minted
    /// identity *next to* the stale triple is the pair that lets two builds trade the language back
    /// and forth, since an unfamiliar `installId` is accepted unconditionally (D32).
    private static func write(_ publication: LocalePublication, to defaults: UserDefaults) {
        defaults.set(
            [
                Field.installId: publication.installId,
                Field.epoch: publication.snapshot.epoch,
                Field.tag: publication.snapshot.tag,
            ],
            forKey: publicationKey
        )
    }
}
