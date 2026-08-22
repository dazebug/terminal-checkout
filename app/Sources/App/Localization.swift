import Core
import Foundation

/// The app's half of localization: which catalog to read, reading it, and telling AppKit which
/// language its own chrome should be in. The verdict itself — which of the five tags a stored
/// preference and a system list come out as — lives in Core (`resolveLocale`), where it can be
/// tested against inputs instead of against this machine.
///
/// **Catalogs are read with `Bundle(path:)`, not with SwiftPM `resources:` and `Bundle.module`.**
/// Measured (D1): the generated accessor looks in `Bundle.main.bundleURL/<Name>.bundle` and in an
/// absolute `.build` path baked into the binary, and calls `fatalError` when neither is there — so
/// on the machine that compiled it, a catalog missing from the app bundle still resolves, and the
/// failure only appears on someone else's Mac. Reading `Contents/Resources/<tag>.lproj` directly
/// fails in the same place for everyone, and item 7's gate compares the built bundle against these
/// sources so "someone else's Mac" stops being where it is discovered.
///
/// **A tag is always injectable.** Nothing here asks the process what language it is in: a lookup
/// that consulted `Bundle.main`'s own localization would answer differently on a ko-KR laptop than
/// on an `en` CI runner, which is the same trap D7 recorded for test oracles.
///
/// In particular, `Bundle.preferredLocalizations(from:)` — the overload that takes no preferences —
/// is not a function of its argument. Measured on a host whose `AppleLanguages` is `["ko-KR"]`,
/// against the five tags this app ships: the no-preferences form answered `["en"]` while
/// `preferredLocalizations(from:forPreferences: ["ko-KR"])` answered `["ko"]`, and the built app
/// bundle's own `preferredLocalizations` answered `["en"]` too. Whatever process state it is
/// reading, it is not the list we resolved, so the app's choice goes through `resolveLocale` and
/// the catalog is addressed by path.

/// The `UserDefaults` key holding the language the user picked, or `auto`. The picker that writes
/// it is item 8; this file only reads it, and reads it as an **object** so a value that is not a
/// string reaches `resolveLocale` intact rather than being quietly turned into "follow the system".
let languagePreferenceKey = "language"

/// AppKit's own key for the language its chrome is drawn in.
private let appleLanguagesKey = "AppleLanguages"

/// Returned when a key is missing, so a lookup can tell "no such key" from a value that happens to
/// equal the key. It cannot occur in a catalog: `PropertyListSerialization` would reject the file.
private let missingValueSentinel = "\u{0}tc-missing"

enum AppLocalization {
    /// The tag this launch renders in.
    static func resolvedTag(
        defaults: UserDefaults = .standard,
        systemPreferred: [String] = Locale.preferredLanguages
    ) -> String {
        resolveLocale(
            preference: defaults.object(forKey: languagePreferenceKey),
            systemPreferred: systemPreferred
        )
    }

    /// The catalog for one tag, or nil when the bundle does not carry it. `resources` is a
    /// parameter so a test can point at the source tree; production passes the app bundle.
    static func catalog(
        forTag tag: String, resources: String? = Bundle.main.resourcePath
    ) -> Bundle? {
        guard let resources else { return nil }
        return Bundle(path: (resources as NSString).appendingPathComponent("\(tag).lproj"))
    }

    /// The one lookup every user-facing string in the app goes through.
    ///
    /// A key the chosen catalog does not carry falls back to English and then to the key itself.
    /// The fallback is a floor, not a feature — item 12's gate makes a missing key a red build, and
    /// a raw key on screen is what that gate exists to prevent.
    static func string(
        _ key: String,
        tag: String? = nil,
        resources: String? = Bundle.main.resourcePath
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
    /// AppKit.** Measured (D14): written after AppKit had come up, the same process kept its old
    /// language (`preferredLocalizations` stayed `["ko"]`, an `NSAlert` button stayed `확인`) and
    /// only the readback changed; written before, the same process picked it up (`zh-Hant`, `好`).
    /// That is why the call site is `main.swift`, ahead of `NSApplication.shared`.
    ///
    /// **`auto` removes the key instead of writing the resolved tag** (D22). Writing it would turn
    /// "follow the system" into a permanent app-level override: the user changes the macOS
    /// language afterwards and every app follows except this one, with nothing on screen to say
    /// why. Everything that is not `auto` — including a stored value we cannot read — is written,
    /// because our own strings resolve such a value to English and chrome that disagreed with them
    /// would be the split D14 rules out.
    ///
    /// Our own strings do not go through this key at all: they are read with `Bundle(path:)`, so
    /// they change on the next redraw while AppKit's chrome changes on the next launch. Item 8
    /// owns saying that difference out loud.
    @discardableResult
    static func applyStoredLanguageToAppKit(
        defaults: UserDefaults = .standard,
        systemPreferred: [String] = Locale.preferredLanguages
    ) -> String? {
        let stored = defaults.object(forKey: languagePreferenceKey)
        let isAutomatic = stored == nil || (stored as? String) == automaticLocalePreference
        guard !isAutomatic else {
            defaults.removeObject(forKey: appleLanguagesKey)
            return nil
        }
        let tag = resolveLocale(preference: stored, systemPreferred: systemPreferred)
        defaults.set([tag], forKey: appleLanguagesKey)
        return tag
    }
}
