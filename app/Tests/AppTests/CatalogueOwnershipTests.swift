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
///   * `ext.…`                      → `extension/_i18n/<tag>.js`
///   * `extName` / `extDescription` → `extension/_locales/<chrome tag>/messages.json`
///
/// A key's name says where it lives; a file's location says what it may hold. Both directions are
/// asserted, because either one alone permits a key to exist in two places at once.
///
/// **What has to be data, and why it cannot be derived.** Two keys holding the same sentence are
/// indistinguishable, to any rule, from a copy-paste mistake — "these two mean different things in
/// different places" is a judgement about meaning, and no file records it. Those judgements are the
/// exception tables below, and each one carries its reason. There are four.
///
/// This gate lives on the Swift side because it is the only side that can already read all three
/// stores: `PropertyListSerialization` parses `.strings`, and the extension's dictionaries are a
/// JSON object literal that can be read directly (pinned from the JavaScript side, which owns those
/// files, by `tests/i18n.test.js`).
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

    /// The extension's dictionary for one tag.
    ///
    /// The file is a classic browser script that assigns one object literal, and the literal's body
    /// is JSON apart from a trailing comma — which is exactly what makes it readable from here
    /// without running JavaScript. Both halves of that assumption are asserted: that the region was
    /// found, and that it parsed. A reader that quietly returns nothing would make every check below
    /// pass over an empty set, which is the way this kind of gate usually fails.
    private func extensionDictionary(_ tag: String) throws -> [String: String] {
        let url = Self.repositoryRoot.appendingPathComponent("extension/_i18n/\(tag).js")
        let source = try String(contentsOf: url, encoding: .utf8)
        let opening = try XCTUnwrap(source.range(of: "] = {"), "\(tag).js does not assign a dictionary")
        let closing = try XCTUnwrap(source.range(of: "};", options: .backwards), "\(tag).js has no end")
        var body = String(source[source.index(before: opening.upperBound)..<closing.lowerBound])
        body += "}"
        // The trailing comma the generator leaves after the last entry
        if let comma = body.range(of: ",", options: .backwards),
           body[comma.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines) == "}" {
            body.replaceSubrange(comma, with: "")
        }
        let parsed = try JSONSerialization.jsonObject(with: Data(body.utf8))
        return try XCTUnwrap(parsed as? [String: String], "\(tag).js is not a dictionary of strings")
    }

    private func chromeMessages(_ tag: String) throws -> [String: Any] {
        let url = Self.repositoryRoot
            .appendingPathComponent("extension/_locales/\(tag)/messages.json")
        let parsed = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try XCTUnwrap(parsed as? [String: Any], "\(tag)/messages.json is not an object")
    }

    /// The locales both catalogues have actually been filled for. Derived rather than listed: `ja`
    /// and the two Chinese catalogues are item 24's, and a hardcoded list here would be a second
    /// copy of item 12's `incompleteLocales` — two lists that can disagree about the same fact.
    private func filledLocales() throws -> [String] {
        try ["en", "ko", "ja", "zh-Hans", "zh-Hant"].filter { locale in
            try !appCatalogue(locale).isEmpty && !extensionDictionary(locale).isEmpty
        }
    }

    // MARK: - The rules

    func testEveryKeyLivesWhereItsNameSaysItDoes() throws {
        var checked = 0
        for locale in try filledLocales() {
            for key in try appCatalogue(locale).keys {
                XCTAssertTrue(key.hasPrefix("app."), "\(locale): the app catalogue holds \(key)")
                checked += 1
            }
            for key in try extensionDictionary(locale).keys {
                XCTAssertTrue(key.hasPrefix("ext."), "\(locale): the extension dictionary holds \(key)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 300, "the scan compared almost nothing — check the paths")

        // The other direction: a name that belongs to one store may not appear in another. Without
        // this, both stores could hold `app.x` and each would still satisfy its own rule.
        for locale in try filledLocales() {
            let app = Set(try appCatalogue(locale).keys)
            let ext = Set(try extensionDictionary(locale).keys)
            XCTAssertEqual(app.intersection(ext), [], "\(locale): a key lives in two catalogues")
        }

        // Chrome's own namespace holds those two names and nothing from ours. The *count* is item
        // 17's assertion, on the side that owns the file; what is checked here is ownership.
        for tag in ["en", "ko"] {
            for key in try chromeMessages(tag).keys {
                XCTAssertTrue(
                    ["extName", "extDescription"].contains(key),
                    "_locales/\(tag) holds \(key), which belongs to another store"
                )
            }
        }
    }

    /// **No sentence has two homes.** A message that reads the same in two catalogues is one message
    /// that two places will translate separately, and they will drift — that is the whole reason
    /// this gate exists rather than a naming convention alone.
    func testNoValueHasTwoHomes() throws {
        for locale in try filledLocales() {
            let app = try appCatalogue(locale)
            let ext = try extensionDictionary(locale)
            let shared = Set(app.values).intersection(Set(ext.values))
            XCTAssertEqual(
                shared.sorted(), [],
                "\(locale): the app and the extension both own \(shared.sorted())"
            )
        }
    }

    /// Two keys in one catalogue holding the same sentence. Each pair is a judgement — the same
    /// words, deliberately, in two places that mean different things — so each is listed with the
    /// reason it is not a duplicate to remove.
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
        ["ext.section.main.title", "ext.table.mainBranch"]:
            "a section heading and a table column that happen to name the same thing",
        // **Found by this gate when Japanese landed, and kept rather than worked around.** English
        // distinguishes removing a row ("Remove") from deleting a button ("Delete"); Japanese uses
        // 削除 for both, and Korean and both Chinese catalogues keep them apart. Inventing a second
        // Japanese word to satisfy a check would make that screen read worse than it does now — the
        // gate's job here was to make the collapse visible, and it is.
        ["ext.button.remove", "ext.card.delete"]:
            "Japanese uses one word where English has two, and a second one would be worse UI",
    ]

    func testDuplicateValuesWithinAStoreAreDeclared() throws {
        var seen: Set<[String]> = []
        for locale in try filledLocales() {
            for (store, table) in [("app", try appCatalogue(locale)), ("ext", try extensionDictionary(locale))] {
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
    /// — the shape the plan recorded as a known limit (D37) and that item 21 found an instance of by
    /// hand — so it is made here, with its two present cases judged.
    private let declaredContainment: [String: String] = [
        // Item 21 split one status message into two complete ones so that neither had a clause
        // substituted into it (D31a/D46). The shorter is necessarily a prefix of the longer; that is
        // the shape of the fix, not a duplicate.
        "ext.status.imported": "the two-message split that replaced a substituted clause",
        // **Recorded as debt, not as correct.** The z advice spells the base-directory card's title
        // out — `“Repository base folder”` — instead of receiving it as a `%@` the way the other
        // eight quotations do (D28). It was missed because that convention was found by looking for
        // square brackets and this one uses typographic quotes. Changing a string value is outside
        // the item that found it; the follow-up is to make it a quotation like the rest.
        "app.card.baseDir.title": "a label quotation still spelled out — known debt, see the plan",
    ]

    func testOneValueInsideAnotherIsDeclared() throws {
        var seen: Set<String> = []
        for locale in try filledLocales() {
            var everything: [(String, String)] = []
            for (key, value) in try appCatalogue(locale) { everything.append((key, value)) }
            for (key, value) in try extensionDictionary(locale) { everything.append((key, value)) }

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
    /// mode item 7 named for the bundle check, in a different file.
    func testTheStoresAreActuallyBeingRead() throws {
        XCTAssertEqual(
            try filledLocales(), ["en", "ko", "ja", "zh-Hans", "zh-Hant"],
            "a catalogue emptied out — every check in this file silently skips a locale it cannot read"
        )
        XCTAssertGreaterThan(try appCatalogue("en").count, 90)
        XCTAssertGreaterThan(try extensionDictionary("en").count, 110)
        for tag in try filledLocales() {
            XCTAssertEqual(
                try appCatalogue(tag).count, try appCatalogue("en").count,
                "the app catalogues disagree on size at \(tag)"
            )
            XCTAssertEqual(
                try extensionDictionary(tag).count, try extensionDictionary("en").count,
                "the extension dictionaries disagree on size at \(tag)"
            )
        }
    }
}
