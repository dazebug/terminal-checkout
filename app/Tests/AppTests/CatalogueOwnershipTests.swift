import Core
import XCTest
@testable import App

/// **Which catalogue owns a message, and the rule that nobody has to maintain.**
///
/// The obvious way to build this was a file listing every message id against its home. That file
/// would be the third source of truth in a plan whose first invariant is that i18n does not create a
/// second one — it would drift the moment a catalogue gained a key, and the drift would be silent
/// because nothing else reads it.
///
/// So ownership is **derived from facts that already exist**, and this gate checks the derivation
/// rather than a list:
///
///   * `app.…`                      → `app/Sources/App/Resources/<locale>.lproj/Localizable.strings`
///   * extension messages           → `extension/_locales/<chrome tag>/messages.json`
///
/// A key's name says where it lives; a file's location says what it may hold. Both directions are
/// asserted, because either one alone permits a key to exist in two places at once.
///
/// **What has to be data, and why it cannot be derived.** Two keys holding the same sentence are
/// indistinguishable, to any rule, from a copy-paste mistake — "these two mean different things in
/// different places" is a judgement about meaning, and no file records it. Those judgements are the
/// exception tables below, and each one carries its reason. There are three.
///
/// This gate lives on the Swift side because it is the only side that can already read both
/// stores: `PropertyListSerialization` parses `.strings`, and the live Chrome entries are JSON
/// objects. The JavaScript side owns the live catalogues' structure and argument identity; this
/// gate owns cross-store ownership.
final class CatalogueOwnershipTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/CatalogueOwnershipTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: - Reading the three stores

    private func appCatalogue(_ locale: String) throws -> [String: String] {
        let url = Self.repositoryRoot
            .appendingPathComponent("app/Sources/App/Resources/\(locale).lproj/Localizable.strings")
        let parsed = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil
        )
        return try XCTUnwrap(parsed as? [String: String], "\(locale) is not a dictionary of strings")
    }

    private func chromeMessages(_ tag: String) throws -> [String: Any] {
        let url = Self.repositoryRoot
            .appendingPathComponent("extension/_locales/\(tag)/messages.json")
        let parsed = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try XCTUnwrap(parsed as? [String: Any], "\(tag)/messages.json is not an object")
    }

    /// The message text in the live store Chrome actually reads. Its physical names are retained so
    /// duplicate and containment judgements cannot silently fall back to the frozen passenger.
    private func chromeMessageValues(_ tag: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in try chromeMessages(tag) {
            if let message = (value as? [String: Any])?["message"] as? String {
                values[key] = message
            }
        }
        return values
    }

    /// The locales both catalogues have actually been filled for — **derived from
    /// `supportedLocales`, not a second copy of it**.
    ///
    /// It used to spell the five out, which is exactly the shape this comment claimed to avoid, and
    /// it was a narrowing rather than a false answer: measured, a sixth tag added to
    /// `supportedLocales` was simply never visited, so every ownership rule below passed without
    /// having seen it. `testTheStoresAreActuallyBeingRead` compared against the same literal, so it
    /// did not notice either — that comparison is now against the constant, which turns "a shipped
    /// locale we cannot read" into a failure instead of a shorter loop.
    private func filledLocales() throws -> [String] {
        try supportedLocales.filter { locale in
            let chromeTag = try XCTUnwrap(chromeLocaleDirectories[locale], "no _locales directory is declared for \(locale)")
            return try !appCatalogue(locale).isEmpty && !chromeMessageValues(chromeTag).isEmpty
        }
    }

    /// Our tag to Chrome's directory name. Chrome's namespace is its own and `extension/i18n.js`
    /// deliberately keeps no mapping table in shipping code, so the correspondence is policy and is
    /// declared where the gate that needs it can be read beside it.
    private let chromeLocaleDirectories: [String: String] = [
        "en": "en", "ko": "ko", "ja": "ja", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW",
    ]

    /// The `_locales/` directories, read rather than listed. A hardcoded pair is what let three of
    /// them go unchecked when the supported set grew from two locales to five.
    private func chromeLocaleTags() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: Self.repositoryRoot.appendingPathComponent("extension/_locales").path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    // MARK: - The rules

    func testEveryKeyLivesWhereItsNameSaysItDoes() throws {
        var checked = 0
        for locale in try filledLocales() {
            for key in try appCatalogue(locale).keys {
                XCTAssertTrue(key.hasPrefix("app."), "\(locale): the app catalogue holds \(key)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 300, "the scan compared almost nothing — check the paths")

        // Chrome's own namespace holds those two names and nothing from ours. The count is checked
        // on the side that owns the file; what is checked here is ownership.
        //
        // **Every directory that is there, not a pair named here.** This visits every directory;
        // the supported set grew to five and the
        // loop did not follow, so a foreign key in `ja`, `zh_CN` or `zh_TW` passed unseen
        // (measured). Reading the directory means the next one is covered by existing.
        // **The mapping, not the count**. Comparing sizes says five directories
        // exist; it does not say they are the five that answer for the languages we ship, so
        // renaming `zh_TW` to `zh_HK` — which Chrome would then not use for our Traditional
        // Chinese — kept the arithmetic true and the extension's name untranslated.
        let chromeTags = try chromeLocaleTags()
        let expected = try supportedLocales.map {
            try XCTUnwrap(chromeLocaleDirectories[$0], "no _locales directory is declared for \($0)")
        }
        XCTAssertEqual(
            chromeTags.sorted(), expected.sorted(),
            "_locales holds \(chromeTags), and the languages we ship map to \(expected.sorted())"
        )
        // **`_locales` holds two namespaces, and that is the boundary conversion's doing rather
        // than a leak.** It carries the two manifest keys, plus one converted name per extension
        // message: the conversion writes `ext.header.options` there as `ext_header_options`,
        // because a `_locales` name cannot contain a dot. An `app.` key or a name outside those
        // namespaces is foreign.
        //
        // **The physical-name conversion is not repeated here.** The JavaScript ownership gate and
        // the read-only checker share `chromeMessageId`; this Swift gate owns only the namespace
        // boundary. Repeating `.`→`_` here would create a second converter that could drift while
        // both tests stayed green. The independent check below therefore asks whether every Chrome
        // name belongs to the extension namespace, while the JavaScript gate checks exact identity.
        for tag in chromeTags {
            for key in try chromeMessages(tag).keys {
                XCTAssertTrue(
                    ["extName", "extDescription"].contains(key) || key.hasPrefix("ext_"),
                    "_locales/\(tag) holds \(key), which belongs to another store"
                )
            }
        }
    }

    /// **No sentence has two homes.** A message that reads the same in two catalogues is one message
    /// that two places will translate separately, and they will drift — that is the whole reason
    /// this gate exists rather than a naming convention alone.
    /// **The catalogue set is closed, not merely consistent.**
    ///
    /// Everything else here compares the stores to each other, which says nothing about a language
    /// we do not ship: an `fr.lproj` dropped into the sources was copied into the bundle, matched
    /// byte for byte and parsed, and every check stayed green while macOS advertised a localization
    /// the app cannot resolve to. The same rule is enforced on the built bundle by
    /// `verify-bundle.sh`; this is the source side, where it is cheaper to notice.
    func testNoCatalogueExistsForALanguageWeDoNotShip() throws {
        let resources = Self.repositoryRoot.appendingPathComponent("app/Sources/App/Resources")
        let found = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
        XCTAssertEqual(
            found, supportedLocales.sorted(),
            "the catalogues on disk are not the languages we ship"
        )
    }

    func testNoValueHasTwoHomes() throws {
        for locale in try filledLocales() {
            let app = try appCatalogue(locale)
            let chrome = try chromeMessages(chromeLocaleDirectories[locale] ?? locale)
                .compactMap { value in
                    (value as? [String: Any])?["message"] as? String
                }
            let shared = Set(app.values).intersection(chrome)
            XCTAssertEqual(
                shared.sorted(), [],
                "\(locale): the app and the extension both own \(shared.sorted())"
            )
        }
    }

    /// Two keys in one catalogue holding the same sentence. Each pair is a judgement — the same
    /// words, deliberately, in two places that mean different things — so each is listed with the
    /// reason it is not a duplicate to remove. There are three such judgements.
    ///
    /// **Keyed by the pair of keys, not by the sentence.** The first version of this table was keyed
    /// by the English text, and the gate caught it on its first run: the same two pairs share a
    /// sentence in Korean too, so a value-keyed table needs one entry per language and grows another
    /// row every time a locale is filled. Which two keys may legitimately agree is a fact about the
    /// keys; it is the same fact in every language.
    private let declaredSameValue: [[String]: String] = [
        // Two permission rows on the setup card, each reporting its own grant: Accessibility (used
        // for typing into Warp) and Apple Events (used to drive iTerm2). They are separate
        // permissions with separate outcomes, and one shared row would make one look like the other.
        ["app.automation.granted", "app.status.accessibility.granted"]:
            "two independent permission rows report their own state",
        // The section heading `❯ main branch` and the column header of the override table under it.
        // Merging them would tie a heading's wording to a table column's.
        ["ext_section_main_title", "ext_table_mainBranch"]:
            "a section heading and a table column that happen to name the same thing",
        // English distinguishes removing a row ("Remove") from deleting a button ("Delete"); Japanese uses
        // 削除 for both, and Korean and both Chinese catalogues keep them apart. Inventing a second
        // Japanese word to satisfy a check would make that screen read worse than it does now — the
        // gate's job here was to make the collapse visible, and it is.
        ["ext_button_remove", "ext_card_delete"]:
            "Japanese uses one word where English has two, and a second one would be worse UI",
    ]

    func testDuplicateValuesWithinAStoreAreDeclared() throws {
        var seen: Set<[String]> = []
        for locale in try filledLocales() {
            let stores: [(String, [String: String])] = [
                ("app", try appCatalogue(locale)),
                ("live extension", try chromeMessageValues(try XCTUnwrap(
                    chromeLocaleDirectories[locale], "no _locales directory is declared for \(locale)"
                ))),
            ]
            for (store, table) in stores {
                var byValue: [String: [String]] = [:]
                for (key, value) in table { byValue[value, default: []].append(key) }
                for (value, keys) in byValue where keys.count > 1 {
                    let pair = keys.sorted()
                    seen.insert(pair)
                    XCTAssertNotNil(
                        declaredSameValue[pair],
                        "\(locale) \(store): \(pair) share \"\(value)\" with no reason recorded"
                    )
                }
            }
        }
        // ...and a declaration that has stopped being true has to go, or the list becomes a place
        // where old judgements accumulate unread.
        //
        // **What this does not catch, deliberately:** a pair that has stopped agreeing in one
        // language while still agreeing in another. The declaration is still doing work for the
        // language where the two agree, so it is still true — it dies only when no filled locale
        // has the pair sharing a value. A stricter rule would demand that translations agree with
        // each other about which sentences coincide, which is not a property translations have.
        for declared in declaredSameValue.keys {
            XCTAssertTrue(seen.contains(declared), "\(declared) is declared but no longer shares a value")
        }
    }

    /// One message contained whole inside another. This is the check that exact matching cannot make
    /// — a known limit — so it is made here, with its two present cases judged.
    private let declaredContainment: [String: String] = [
        // The status message was split into two complete ones so that neither had a clause
        // substituted into it. The shorter is necessarily a prefix of the longer; that is
        // the shape of the fix, not a duplicate.
        "ext_status_imported": "the two-message split that replaced a substituted clause",
        // **Recorded as debt, not as correct.** The z advice spells the base-directory card's title
        // out — `“Repository base folder”` — instead of receiving it as a `%@` the way the other
        // eight quotations do. The typographic quotes are not covered by the square-bracket
        // convention. Changing a string value is outside this gate; the follow-up is to make it a
        // quotation like the rest.
        "app.card.baseDir.title": "a label quotation still spelled out — known debt, see the plan",
    ]

    func testOneValueInsideAnotherIsDeclared() throws {
        var seen: Set<String> = []
        for locale in try filledLocales() {
            var everything: [(String, String)] = []
            for (key, value) in try appCatalogue(locale) { everything.append((key, value)) }
            let chromeTag = try XCTUnwrap(
                chromeLocaleDirectories[locale], "no _locales directory is declared for \(locale)"
            )
            for (key, value) in try chromeMessageValues(chromeTag) { everything.append((key, value)) }

            for (shortKey, shortValue) in everything where shortValue.count >= 20 {
                for (longKey, longValue) in everything where longKey != shortKey {
                    guard longValue.count > shortValue.count, longValue.contains(shortValue) else { continue }
                    seen.insert(shortKey)
                    XCTAssertNotNil(
                        declaredContainment[shortKey],
                        "\(locale): \(shortKey) is contained in \(longKey) with no reason recorded"
                    )
                }
            }
        }
        for declared in declaredContainment.keys {
            XCTAssertTrue(seen.contains(declared), "\(declared) is declared but is no longer contained anywhere")
        }
    }

    /// The reader itself, because a gate that reads nothing passes everything. This is the failure
    /// mode the bundle check uses in a different file.
    func testTheStoresAreActuallyBeingRead() throws {
        // Against the constant, not against a literal: with a literal on both sides this compared a
        // list to itself and a shipped locale missing a catalogue produced a shorter loop rather
        // than a failure
        XCTAssertEqual(
            try filledLocales(), supportedLocales,
            "a shipped locale has an unreadable or empty catalogue — every check in this file skips it"
        )
        XCTAssertGreaterThan(try appCatalogue("en").count, 90)
        XCTAssertGreaterThan(
            try chromeMessageValues(try XCTUnwrap(chromeLocaleDirectories["en"])).count, 110
        )
        for tag in try filledLocales() {
            XCTAssertEqual(
                try appCatalogue(tag).count, try appCatalogue("en").count,
                "the app catalogues disagree on size at \(tag)"
            )
            let chromeTag = try XCTUnwrap(
                chromeLocaleDirectories[tag], "no _locales directory is declared for \(tag)"
            )
            XCTAssertEqual(
                try chromeMessageValues(chromeTag).count,
                try chromeMessageValues(try XCTUnwrap(chromeLocaleDirectories["en"])).count,
                "the live extension catalogues disagree on size at \(tag)"
            )
        }
    }
}
