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
    /// Setting it is what makes this process a writer (D49): the picker lives in the setup window,
    /// so only the GUI reaches here. It publishes immediately, so the revision moves in the same
    /// process that took the click rather than on the next launch.
    static var language: String {
        get { (UserDefaults.standard.object(forKey: languagePreferenceKey) as? String) ?? automaticLocalePreference }
        set {
            UserDefaults.standard.set(newValue, forKey: languagePreferenceKey)
            LocaleState.publish(
                resolved: AppLocalization.resolvedTag(), role: .interactive
            )
            NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        }
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
/// **A seam, not an answer.** The condition itself is item 13's: a language restart must not run
/// while claude input is still being delivered, because that delivery is asynchronous and the Warp
/// injection helper's only defence is its lifetime — a restart that orphans it breaks the trust
/// boundary `CLAUDE.md` sets out. Until that lands this says yes, which is today's behaviour
/// unchanged; what the seam buys is that item 13 has exactly one place to fill and the picker
/// already asks.
enum LocaleRestartGate {
    /// Replaced by item 13. Left as a stored closure rather than a computed condition so the
    /// question and the answer stay separable — the picker calls it without knowing what it checks.
    static var isSafeNow: () -> Bool = { true }
}

// MARK: - The published locale snapshot

/// Which process is asking. **Only one may write** (D49): the GUI is the process that owns the
/// picker, so it is the only one with a reason to move the revision. `--headless-server` shares the
/// bundle id and therefore `UserDefaults.standard` with it, and two read-modify-writes against the
/// same key can publish **different locales under the same epoch** — after which the extension,
/// whose rule is "same install, accept only a strictly greater epoch", drops the newer of the two.
/// Making the second writer impossible removes the case rather than locking around it.
enum LocaleWriterRole {
    /// The GUI: has a picker, may mint an identity and advance the revision.
    case interactive
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
    /// The headless server never invents a revision. With a stored snapshot it repeats it verbatim,
    /// even when this launch resolves to a different locale: a system-language change seen only by
    /// a headless process arrives on the next GUI launch, which is the promise `auto` already
    /// makes. With nothing stored it publishes **nothing** (nil) — a response carrying no locale
    /// metadata, which the extension treats as no input rather than as a reason to change (D51).
    @discardableResult
    static func publish(
        resolved: String, defaults: UserDefaults = .standard, role: LocaleWriterRole
    ) -> LocalePublication? {
        guard let stored = stored(defaults) else {
            guard role == .interactive else { return nil }
            let minted = LocalePublication(
                installId: UUID().uuidString, snapshot: LocaleSnapshot(tag: resolved, epoch: 0)
            )
            write(minted, to: defaults)
            return minted
        }
        guard stored.snapshot.tag != resolved else { return stored }
        guard role == .interactive else { return stored }
        let advanced = LocalePublication(
            installId: stored.installId,
            snapshot: localeSnapshotToPublish(resolved: resolved, lastPublished: stored.snapshot)
        )
        write(advanced, to: defaults)
        return advanced
    }

    /// One `set`, because a publication is one fact. Three of them are what let a reader see a
    /// triple that was never published.
    ///
    /// The three-key state an earlier build wrote is **not read** — a triple written in three steps
    /// cannot be shown to have been committed as one, which is the defect itself, so it is not
    /// evidence of anything. Deleting it is the other half of that decision, and the reason is the
    /// build that *does* read it: nothing here has been released, so a copy holding those keys is a
    /// copy on our own machines, sharing the bundle id and therefore this domain, whose headless
    /// server would go on handing the extension a triple this build has already replaced. Measured
    /// while making this change: `defaults read com.dazebug.terminal-checkout` held no locale key
    /// at all, so what this covers is the state item 8's still-pending GUI checks would create, not
    /// one that has been seen. Deleting is a write and therefore reachable only from the
    /// interactive role, so the single writer stays single (D49).
    ///
    /// The deletion goes **first**, because the two states must not coexist: an envelope under a
    /// freshly minted identity *next to* the stale triple is the pair that lets two builds trade
    /// the language back and forth, since an unfamiliar `installId` is accepted unconditionally
    /// (D32). Interrupted the other way there is nothing at all, and the next publication mints —
    /// the state D51 already covers.
    private static func write(_ publication: LocalePublication, to defaults: UserDefaults) {
        for key in legacyKeys { defaults.removeObject(forKey: key) }
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
