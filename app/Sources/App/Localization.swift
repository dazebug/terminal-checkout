import Core
import Foundation

/// The app's half of localization: which catalog to read, reading it, and telling AppKit which
/// language its own chrome should be in. The verdict itself — which of the five tags a stored
/// preference and a system list come out as — lives in Core (`resolveLocale`), where it can be
/// tested against inputs instead of against this machine.
///
/// **Catalogs are read with `Bundle(path:)`, not with SwiftPM `resources:` and `Bundle.module`.**
/// Measured: the generated accessor looks in `Bundle.main.bundleURL/<Name>.bundle` and in an
/// absolute `.build` path baked into the binary, and calls `fatalError` when neither is there — so
/// on the machine that compiled it, a catalog missing from the app bundle still resolves, and the
/// failure only appears on someone else's Mac. Reading `Contents/Resources/<tag>.lproj` directly
/// fails in the same place for everyone, and the bundle gate compares the built bundle against these
/// sources so "someone else's Mac" stops being where it is discovered.
///
/// **A tag is always injectable.** Nothing here asks the process what language it is in: a lookup
/// that consulted `Bundle.main`'s own localization would answer differently on a ko-KR laptop than
/// on an `en` CI runner, which is the same trap machine-dependent test oracles create.
///
/// In particular, `Bundle.preferredLocalizations(from:)` — the overload that takes no preferences —
/// is not a function of its argument. Measured on a host whose `AppleLanguages` is `["ko-KR"]`,
/// against the five tags this app ships: the no-preferences form answered `["en"]` while
/// `preferredLocalizations(from:forPreferences: ["ko-KR"])` answered `["ko"]`, and the built app
/// bundle's own `preferredLocalizations` answered `["en"]` too. Whatever process state it is
/// reading, it is not the list we resolved, so the app's choice goes through `resolveLocale` and
/// the catalog is addressed by path.

/// The `UserDefaults` key holding the language the user picked, or `auto`. The picker that writes
/// it is the picker; this file only reads it, and reads it as an **object** so a value that is not a
/// string reaches `resolveLocale` intact rather than being quietly turned into "follow the system".
let languagePreferenceKey = "language"

/// AppKit's own key for the language its chrome is drawn in.
private let appleLanguagesKey = "AppleLanguages"

/// The app-local companion record for the exact `AppleLanguages` value this process last wrote. It
/// is provenance, not another language preference: automatic mode may remove the system key only
/// while the current value still matches this record.
let appleLanguagesProvenanceKey = "TerminalCheckoutAppleLanguagesProvenance"

/// Returned when a key is missing, so a lookup can tell "no such key" from a value that happens to
/// equal the key. It cannot occur in a catalog: `PropertyListSerialization` would reject the file.
private let missingValueSentinel = "\u{0}tc-missing"

enum AppLocalization {
    /// Where catalogues are read from. The app leaves it at its own bundle; `swift test` has no app
    /// bundle at all, so a test that wants the window to draw **sentences instead of raw keys** has
    /// to say where they live. Without this the layout tests would be measuring the width of
    /// `app.card.baseDir.help` — a string that is shorter than every sentence it stands for, which
    /// is the one direction a layout test must not be wrong in.
    static var resourcesPath: String? = Bundle.main.resourcePath

    /// A locale a test can force, so the window can be drawn in each one without touching the
    /// user's stored preference. nil in production, and the only writer is a test.
    static var tagOverrideForTesting: String?

    /// The tag this launch renders in.
    static func resolvedTag(
        defaults: UserDefaults = .standard,
        systemPreferred: [String]? = nil
    ) -> String {
        if let tagOverrideForTesting { return tagOverrideForTesting }
        let systemPreferred = systemPreferred ?? externalSystemPreferred(in: defaults)
        return resolveLocale(
            preference: defaults.object(forKey: languagePreferenceKey),
            systemPreferred: systemPreferred
        )
    }

    /// The catalog for one tag, or nil when the bundle does not carry it. `resources` is a
    /// parameter so a test can point at the source tree; production passes the app bundle.
    static func catalog(
        forTag tag: String, resources: String? = AppLocalization.resourcesPath
    ) -> Bundle? {
        guard let resources else { return nil }
        return Bundle(path: (resources as NSString).appendingPathComponent("\(tag).lproj"))
    }

    /// The one lookup every user-facing string in the app goes through.
    ///
    /// A key the chosen catalog does not carry falls back to English and then to the key itself.
    /// The fallback is a floor, not a feature — the catalogue gate makes a missing key a red build, and
    /// a raw key on screen is what that gate exists to prevent.
    static func string(
        _ key: String,
        tag: String? = nil,
        resources: String? = AppLocalization.resourcesPath
    ) -> String {
        let tag = tag ?? resolvedTag()
        for candidate in [tag, fallbackLocale] {
            guard let catalog = catalog(forTag: candidate, resources: resources) else { continue }
            let value = catalog.localizedString(
                forKey: key, value: missingValueSentinel, table: nil
            )
            if value != missingValueSentinel { return value }
        }
        return key
    }

    /// Points AppKit's own chrome — `NSAlert` buttons, `NSOpenPanel`, the menu bar's standard
    /// items — at the language we render in.
    ///
    /// **The boundary is the first localization lookup in the process, not the existence of
    /// AppKit.** Measured: written after AppKit had come up, the same process kept its old
    /// language (`preferredLocalizations` stayed `["ko"]`, an `NSAlert` button stayed `확인`) and
    /// only the readback changed; written before, the same process picked it up (`zh-Hant`, `好`).
    /// That is why the call site is `main.swift`, ahead of `NSApplication.shared`.
    ///
    /// **`auto` never writes the resolved tag**. Writing it would turn "follow the system"
    /// into a permanent app-level override: the user changes the macOS language afterwards and
    /// every app follows except this one, with nothing on screen to say why. It removes an existing
    /// `AppleLanguages` value only when the app-local provenance record proves that this app wrote
    /// the same value; a value with no record, or one changed since our write, belongs to somebody
    /// else and is left alone. Everything that is not `auto` — including a stored value we cannot
    /// read — is written, because our own strings resolve such a value to English and chrome that
    /// disagreed with them would split the app's own language from its chrome.
    ///
    /// Our own strings do not go through this key at all: they are read with `Bundle(path:)`, so
    /// they change on the next redraw while AppKit's chrome changes on the next launch.
    @discardableResult
    static func applyStoredLanguageToAppKit(
        defaults: UserDefaults = .standard,
        systemPreferred: [String]? = nil
    ) -> String? {
        let stored = defaults.object(forKey: languagePreferenceKey)
        let isAutomatic = stored == nil || (stored as? String) == automaticLocalePreference
        guard !isAutomatic else {
            let current = defaults.array(forKey: appleLanguagesKey) as? [String]
            let recorded = defaults.array(forKey: appleLanguagesProvenanceKey) as? [String]
            if let current, let recorded, current == recorded {
                defaults.removeObject(forKey: appleLanguagesKey)
            }
            defaults.removeObject(forKey: appleLanguagesProvenanceKey)
            return nil
        }
        let systemPreferred = systemPreferred ?? externalSystemPreferred(in: defaults)
        let tag = resolveLocale(preference: stored, systemPreferred: systemPreferred)
        let value = [tag]
        defaults.set(value, forKey: appleLanguagesKey)
        defaults.set(value, forKey: appleLanguagesProvenanceKey)
        return tag
    }

    /// The language order that belongs to macOS rather than to an override this app wrote. An
    /// effective `AppleLanguages` value that does not match our provenance record is somebody
    /// else's answer — including a per-app choice made in System Settings — and must win so our
    /// catalogues agree with AppKit. When the value matches our record, the argument domain has
    /// higher precedence than the global domain, just as it does in the defaults search list.
    /// `Locale.preferredLanguages` is the fallback only when neither external domain exposes the
    /// key and no provenance record exists. If a record exists but no external domain answers, the
    /// empty list is deliberate: falling back to English is safer than feeding our own value back
    /// through a system API whose domain ordering is not observable here.
    private static func externalSystemPreferred(in defaults: UserDefaults) -> [String] {
        let current = defaults.array(forKey: appleLanguagesKey) as? [String]
        let recorded = defaults.array(forKey: appleLanguagesProvenanceKey) as? [String]
        if let current, current != recorded { return current }

        let argument = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        if let languages = argument[appleLanguagesKey] as? [String] { return languages }

        let persistentGlobal = defaults.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        if let languages = persistentGlobal[appleLanguagesKey] as? [String] { return languages }

        if recorded != nil { return [] }
        return Locale.preferredLanguages
    }
}


/// The shorthand every user-facing string in the app goes through.
///
/// A free function rather than a method so that a call site reads as the sentence it produces, and
/// so that **nothing can hold the result**: `localized` is called where the string is used, which is
/// what makes a language change take effect on the next redraw rather than on the next launch.
///
/// **The key is a `StaticString`, so it cannot be computed.** That is not a style rule: the catalogue
/// gate answers "is every catalogue key referenced" and "is every referenced key in the catalogue"
/// by reading the sources for literals, and both answers are only as good as the guarantee that a
/// key never arrives from a variable. The type gives that guarantee — a concatenation, an
/// interpolation, and a `String` variable all fail to compile here — which turns the scan from a
/// best effort into an enumeration. It is the same move `ShellPayload` makes below for the opposite
/// direction: there a literal is required so a computed value cannot reach a shell, here so a
/// computed value cannot reach a catalogue lookup.
///
/// Picking between two keys stays possible and is written as a choice between two calls
/// (`flag ? localized("a") : localized("b")`), which means callers choose a finished
/// message, never assemble one.
func localized(_ key: StaticString) -> String {
    AppLocalization.string(key.description)
}

/// The same lookup with arguments substituted.
///
/// Formatting happens **here and only here**, because the alternative is building a sentence out of
/// pieces at the call site — the one thing a catalogue cannot survive. A translator can move
/// `%1$@` and `%2$@` around each other; they cannot reorder two strings a `+` glued together.
///
/// No locale is passed to `String(format:)` on purpose: every placeholder we use is `%@` or a
/// positional form of it, and a locale-aware format would put grouping separators into numbers that
/// are not numbers to us.
func localized(_ key: StaticString, _ arguments: CVarArg...) -> String {
    String(format: AppLocalization.string(key.description), arguments: arguments)
}

/// Core keeps its stable English descriptions for diagnostics and for callers that do not have an
/// app bundle. The socket response is user-facing, so the App boundary localizes the three cmux
/// failures while leaving every existing terminal message byte-for-byte unchanged.
func localizedErrorMessage(_ error: Error) -> String {
    guard let terminalError = error as? TerminalError else { return errorMessage(error) }
    switch terminalError {
    case .cmuxNotFound:
        return localized("app.error.cmux.notInstalled")
    case .cmuxSocketDenied:
        return localized("app.error.cmux.socketDenied")
    case .cmuxRPCFailed(let message):
        return localized("app.error.cmux.rpcFailed", message)
    default:
        return errorMessage(error)
    }
}

/// Text that is **shell syntax**, not a message.
///
/// The distinction is load-bearing rather than tidy: `testCommand` is shown on screen *and* run in
/// the user's terminal, so a translated apostrophe would break the `echo '…'` quoting and the test
/// button would report a shell error. The invariant that came out of that — a localized
/// catalogue value never reaches a shell, AppleScript, a TOML file or a terminal's input — is the
/// same class as `{cd}` being exempt from the character whitelist.
///
/// It is enforced by the type rather than by remembering: the only initialiser takes a
/// `StaticString`, so a value can be written as a literal in this source and **cannot** be built
/// from a `String` computed at runtime. `localized(…)` returns a `String`, so it does not compile
/// here, so the compiler enforces the boundary.
struct ShellPayload: ExpressibleByStringLiteral, CustomStringConvertible {
    let command: String

    init(stringLiteral value: StaticString) {
        command = value.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    }

    var description: String { command }
}
