import Core
import Foundation

/// The settings the app owns as their single source. Which terminal to use is decided here and not
/// by the extension.
enum Settings {
    /// Chooses the first installed terminal in the supported priority order. Keeping the decision
    /// pure makes the order testable without consulting this Mac's applications or UserDefaults.
    static func terminalForInstalledTerminals(
        iterm: Bool, wezterm: Bool, warp: Bool, cmux: Bool, cmuxNightly: Bool
    ) -> Terminal {
        if iterm { return .iterm }
        if wezterm { return .wezterm }
        if warp { return .warp }
        if cmux { return .cmux }
        if cmuxNightly { return .cmuxNightly }
        return .iterm
    }

    static var terminal: Terminal {
        get {
            if let value = UserDefaults.standard.string(forKey: "terminal") {
                return Terminal(storedValue: value)
            }
            // The default detects what is installed. The order is how long each has been supported
            // and worn in by real use — cmux is last because it is the newest integration and
            // needs its user's socket automation setting in addition to the installed CLI, and
            // its NIGHTLY channel follows stable so someone with both installed defaults to the
            // release build
            return terminalForInstalledTerminals(
                iterm: PermissionChecker.isITermInstalled,
                wezterm: PermissionChecker.isWezTermInstalled,
                warp: PermissionChecker.isWarpInstalled,
                cmux: PermissionChecker.isCmuxInstalled(channel: .stable),
                cmuxNightly: PermissionChecker.isCmuxInstalled(channel: .nightly)
            )
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal") }
    }

    /// The top-level folder repositories are cloned into — where a command moves when `z` fails.
    /// This only **stores the string**; validation, normalization, and fragment assembly all live
    /// in Core (`normalizedBaseDirectory`, `repoEntryCommand`). The extension neither knows nor
    /// sends this value: paths differ per machine while extension settings ride storage.sync
    /// across an account.
    ///
    /// A stored value that isn't a string must not read as "not configured". It is handed on as
    /// text so `normalizedBaseDirectory` rejects it and the button fails carrying the reason.
    static var baseDirectory: String {
        get {
            guard let stored = UserDefaults.standard.object(forKey: "baseDirectory") else { return "" }
            return stored as? String ?? String(describing: stored)
        }
        set { UserDefaults.standard.set(newValue, forKey: "baseDirectory") }
    }

    /// Raw cmux placement values are app-owned machine-local strings. Their meaning, including
    /// defaults and invalid-value handling, belongs to Core's one `CmuxPlacementPreset.parse` seam;
    /// this layer only preserves what UserDefaults contains and gives non-string values a textual
    /// form instead of silently treating them as absent.
    static var cmuxPlacementIdentityMode: String {
        get { rawString(forKey: CmuxPlacementStorageKey.identityMode) }
        set { UserDefaults.standard.set(newValue, forKey: CmuxPlacementStorageKey.identityMode) }
    }

    static var cmuxPlacementFixedName: String {
        get { rawString(forKey: CmuxPlacementStorageKey.fixedName) }
        set { UserDefaults.standard.set(newValue, forKey: CmuxPlacementStorageKey.fixedName) }
    }

    static var cmuxPlacementArrangement: String {
        get { rawString(forKey: CmuxPlacementStorageKey.arrangement) }
        set { UserDefaults.standard.set(newValue, forKey: CmuxPlacementStorageKey.arrangement) }
    }

    private static func rawString(forKey key: String) -> String {
        guard let stored = UserDefaults.standard.object(forKey: key) else { return "" }
        return stored as? String ?? String(describing: stored)
    }

    /// The language the user picked, or `auto`. A preference is app-local state: our own strings
    /// redraw after the notification, while AppKit chrome follows on the restart action because
    /// AppKit reads its language before the process creates `NSApplication`. In automatic mode the
    /// resolver reads macOS's argument/global language domains, not the app override it wrote.
    static var language: String {
        get { languagePreference(in: .standard) }
        set {
            UserDefaults.standard.set(newValue, forKey: languagePreferenceKey)
            NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        }
    }

    /// What a stored preference reads as. A value that is not a string remains a third state rather
    /// than silently becoming `auto`, so the picker and the resolver cannot claim different choices.
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

    /// Taken as true **before** the check has run. A wrong answer in the other direction shows up as
    /// one `command not found` line in the pane and is corrected by the next check.
    static var claudeIsExecutable: Bool { toolExecutables?["claude"] ?? true }

    /// Asked again on every launch — the user may have installed something since. When no answer
    /// comes back the previous one is left as it is.
    static func refreshToolAvailability() {
        DispatchQueue.global(qos: .utility).async {
            guard let result = checkTools() else {
                // `checkTools` returns nil when no login-shell form returned an answer we could parse.
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
    /// Posted after the language choice changes — our own strings redraw immediately, with no restart
    static let terminalCheckoutLanguageChanged = Notification.Name("TerminalCheckoutLanguageChanged")
}

/// Whether restarting right now would cut something off.
///
/// A language restart must not run while claude input is still being delivered: that delivery is
/// asynchronous, and the Warp injection helper's **only** defence is its lifetime — a restart that
/// orphans it breaks the trust boundary `CLAUDE.md` sets out.
///
/// The answer comes from `ClaudeDelivery`, which is kept by the delivery itself rather than by
/// whoever starts one: a flag maintained outside the interval it describes is a second state, and
/// two states drift.
enum LocaleRestartGate {
    /// **Admission, not a question.** Granting now latches: every later `ClaudeDelivery.admit()` is
    /// refused until it is withdrawn.
    ///
    /// Injectable so a test can drive the consumer's branches without a delivery running; the
    /// default is the real operation, so nothing has to remember to wire it up at launch.
    static var admitRestart: () -> Bool = { ClaudeDelivery.admitRestart() }
    /// Given back when the restart it was granted for did not happen.
    static var withdrawAdmission: () -> Void = { ClaudeDelivery.withdrawRestartAdmission() }
}
