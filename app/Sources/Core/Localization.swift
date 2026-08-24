import Foundation

/// Which language the app renders in — the verdict only, never the rendering.
///
/// The two questions here are "given what the user stored and what the system prefers, which of
/// the bundled catalogs answers" and "is that a different answer from a prior resolved snapshot
/// in the retained migration-era pure model". Both are pure: every input arrives as an argument,
/// so a test can state the case it means instead of the case the machine it runs on happens to be
/// in. Reading `Locale.preferredLanguages` or the bundle in here would put the host machine's
/// language into the answer — measured (D7): a `Bundle(url:)` lookup for `en` resolves through the
/// host language and returns the ko-KR string on a ko-KR machine.
///
/// It lives in Core rather than in App for the same reason `BaseDirectory` does: the App target's
/// only tests drive AppKit windows and save and restore the user's live settings, so asserting on
/// a verdict placed there would mean asserting through a window server and the real defaults. The
/// The snapshot helpers below are retained as a pure migration-era model for focused Core tests;
/// no current app path persists or sends one to the extension. Keeping the resolver in Core still
/// prevents a second copy from drifting from the verdict the window renders.

/// The tags the app ships a catalog for. This is the whole list — `zh-Hant` covers Hong Kong and
/// Macau as well, which is what macOS itself does with them (D12).
public let supportedLocales: [String] = ["en", "ko", "ja", "zh-Hans", "zh-Hant"]

/// The stored preference that means "follow the system". Our own token, not a language tag, so it
/// is compared exactly: `AUTO` or `auto ` is a value we did not write, and guessing that someone
/// meant this one would blur the line the corrupt case is defined by.
public let automaticLocalePreference = "auto"

/// Where every question we cannot answer lands. Folding an unshipped language to English rather
/// than to whatever the machine happens to prefer is a decision, not a property of the bundle.
public let fallbackLocale = "en"

/// A tag we actually ship a catalogue for.
///
/// It keeps the pure model from carrying an unshipped tag. The migration-era writer used to accept
/// any string, so a value such as `"fr"` could be persisted even though no shipped catalog could
/// render it; the type moves that check to the moment the value is made and asks the compiler
/// instead of a reviewer. That is the same move `ShellPayload` makes in the App target, one
/// direction over: there a computed value must not reach a shell, here an unshipped tag must not
/// reach the model.
///
/// The only way to build one without asking is `fallback`, which is `fallbackLocale` — a member of
/// `supportedLocales` by construction, and `testTheFallbackIsALocaleWeShip` keeps that true.
public struct SupportedLocale: Equatable {
    public let tag: String

    private init(unchecked tag: String) {
        self.tag = tag
    }

    public init?(_ tag: String) {
        guard supportedLocales.contains(tag) else { return nil }
        self.init(unchecked: tag)
    }

    /// The answer for a question we could not answer — English, for the reason `fallbackLocale`
    /// gives.
    public static let fallback = SupportedLocale(unchecked: fallbackLocale)
}

/// The catalog to render in.
///
/// `preference` is the **stored object**, not a decoded string — `UserDefaults.object(forKey:)`
/// hands back whatever is in the plist, and a hand-edited or future-build value that is not a
/// string is precisely the case that must not be mistaken for a choice. Pass it through as it
/// came: substituting a default for a value that failed to decode (`string(forKey:) ?? "auto"`)
/// would fold a corrupt byte into "follow the system" silently, and `Settings.baseDirectory`
/// already refuses that same fold for the same reason. Absence — the key was never written — is
/// the only other thing that means `auto`.
///
/// An explicit tag and a system-list entry go through one matcher, so `zh-HK` names Traditional
/// Chinese wherever it was read from. What an explicit choice does **not** do is fall through to
/// the system list when we cannot honour it: the user named a language, and answering with a
/// third one they never mentioned would be a guess dressed as a preference.
///
/// The result is an element of `available` by identity whenever that list is non-empty, which is
/// what lets a caller spell `<result>.lproj` and find a directory. An empty list has no answer to
/// give and yields `en`.
public func resolveLocale(
    preference: Any?,
    systemPreferred: [String],
    available: [String] = supportedLocales
) -> String {
    let lastResort = available.contains(fallbackLocale) ? fallbackLocale : (available.first ?? fallbackLocale)

    if let stored = preference {
        guard let text = stored as? String else { return lastResort }
        if text != automaticLocalePreference {
            return matchingLocale(for: text, in: available) ?? lastResort
        }
    }

    // `auto`: the system's own order decides, so the first entry we can answer wins. Scanning
    // `available` instead would answer in our order and hand a user whose list reads
    // [ja, ko] the Korean catalog.
    for tag in systemPreferred {
        if let match = matchingLocale(for: tag, in: available) { return match }
    }
    return lastResort
}

/// A retained migration-era snapshot model and the revision of its resolved tag.
///
/// `epoch` is the revision of **this snapshot**, not of the preference (D48). The preference can
/// sit at `auto` for years while the resolved tag changes underneath it. A counter that moved only
/// when the preference was edited would leave the pure model on the old language.
///
/// No current app path persists this value or sends it over the socket; the focused Core tests
/// retain the migration-era revision contract.
public struct LocaleSnapshot: Equatable {
    public let tag: String
    public let epoch: Int

    public init(tag: String, epoch: Int) {
        self.tag = tag
        self.epoch = epoch
    }
}

/// The next revision in the retained migration-era snapshot model for a freshly resolved tag.
///
/// An unchanged tag returns the snapshot it was given, epoch and all: resolving happens on every
/// launch, and a number that moved each time would make every launch look like a language change in
/// the old protocol. A changed tag takes the next revision — including a change back to a tag that
/// appeared earlier, which is a new revision and not the old number again.
///
/// There is no current persistence or socket publication caller; this pure function remains for
/// the focused migration-era contract tests.
public func localeSnapshotToPublish(resolved: String, lastPublished: LocaleSnapshot?) -> LocaleSnapshot {
    guard let last = lastPublished else { return LocaleSnapshot(tag: resolved, epoch: 0) }
    guard last.tag != resolved else { return last }
    return LocaleSnapshot(tag: resolved, epoch: last.epoch + 1)
}

/// Whether this retained snapshot identity has a next revision left to give.
///
/// `Int.max` is malformed for the retained model because it cannot express its own successor, so an
/// identity sitting at `Int.max - 1` is one advance away from a snapshot the old reader would refuse.
/// The migration-era caller had to mint a fresh identity at that point rather than advance, which
/// is the same answer D51 gives from the other end: an epoch that cannot move means the identity has
/// to.
///
/// It is a question rather than a clamp because the recovery is minting, and only the caller has an
/// identity to mint.
public func localeIdentityIsExhausted(_ snapshot: LocaleSnapshot) -> Bool {
    snapshot.epoch >= Int.max - 1
}

/// Case and `_` are levelled so that `zh_TW` and `ZH-Hant` are read as the tags they name.
/// Nothing else is trimmed — a value with spaces around it is not a tag we wrote.
///
/// The fold is the stdlib's, which is the same fold everywhere: measured under
/// `-AppleLanguages '(tr)'`, `"I".lowercased()` is `i` while Foundation's locale-aware
/// `lowercased(with: Locale("tr"))` is `ı`. Swapping in the locale-aware one would make `zh-HANT`
/// stop matching on a Turkish machine and nowhere else.
private func normalizedTag(_ tag: String) -> String {
    tag.replacingOccurrences(of: "_", with: "-").lowercased()
}

/// The language subtag of an already-normalized tag, or nil when the string is not a tag.
///
/// **Every** subtag is checked, not just the first one. Reading only the first answered Korean for
/// `ko--KR`: the walk stopped at the leading `-`, found `ko`, and never looked at the rest — and
/// `ko-`, `zh--Hant`, `ko-💩` and `zh-Hant foo` went the same way (round 5 review). The round
/// before had switched the split to keep empty subtags, which closed the **leading**-empty shape
/// alone; a rule that holds for one shape of malformed input is not the rule this is supposed to
/// be. Nothing here is a full BCP-47 validator: a subtag is 1–8 ASCII alphanumerics, the first is
/// 2–8 ASCII letters, and anything else is a string nobody who meant a language wrote.
private func languageSubtag(_ normalized: String) -> String? {
    let subtags = normalized.split(separator: "-", omittingEmptySubsequences: false)
    guard let first = subtags.first else { return nil }
    for subtag in subtags {
        guard (1...8).contains(subtag.count),
              subtag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
    }
    let language = String(first)
    guard (2...8).contains(language.count), language.allSatisfy({ $0.isASCII && $0.isLetter })
    else { return nil }
    return language
}

/// Which Chinese script an already-normalized `zh…` tag is written in.
///
/// A script subtag answers directly. Without one the region does, and the split is measured (D12,
/// against five real `.lproj` bundles): `zh-HK`, `zh-MO` and `zh-TW` resolved to `zh-Hant`, while
/// `zh` and `zh-SG` resolved to `zh-Hans`. Regions outside that measurement follow the same rule
/// rather than a second one — that is generalization, not measurement.
private func chineseScript(_ normalized: String) -> String {
    let parts = normalized.split(separator: "-").map(String.init)
    if parts.contains("hant") { return "hant" }
    if parts.contains("hans") { return "hans" }
    let traditionalRegions: Set<String> = ["hk", "mo", "tw"]
    return parts.dropFirst().contains(where: { traditionalRegions.contains($0) }) ? "hant" : "hans"
}

/// The bundled tag that answers `tag`, or nil when nothing we ship speaks its language.
///
/// The returned string is taken from `available`, never assembled here, so the caller gets back
/// the exact spelling it declared.
private func matchingLocale(for tag: String, in available: [String]) -> String? {
    let wanted = normalizedTag(tag)
    // The check runs **before** the exact match. Behind it, a malformed value could still be
    // answered by an entry of `available` spelled the same way — the one path that skipped
    // validation altogether (round 5 review).
    guard let language = languageSubtag(wanted) else { return nil }
    if let exact = available.first(where: { normalizedTag($0) == wanted }) { return exact }

    let sameLanguage = available.filter { languageSubtag(normalizedTag($0)) == language }
    guard !sameLanguage.isEmpty else { return nil }

    if language == "zh" {
        let script = chineseScript(wanted)
        if let byScript = sameLanguage.first(where: { chineseScript(normalizedTag($0)) == script }) {
            return byScript
        }
        // The script we wanted is not bundled. Falling through to the other Chinese catalog is
        // inference — with both `zh-Hans` and `zh-Hant` shipped there is no input that reaches it.
    }
    return sameLanguage.first(where: { normalizedTag($0) == language }) ?? sameLanguage.first
}
