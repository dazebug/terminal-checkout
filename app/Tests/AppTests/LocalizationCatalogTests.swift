import Core
import XCTest
@testable import App

/// Item 12's gate: the five catalogues agree with each other and with the sources.
///
/// Everything here is read from the **source tree** through `#filePath` and parsed with
/// `PropertyListSerialization`. Not through `Bundle`: measured (D7), a bundle lookup resolves
/// through the host machine's language, so an oracle aimed at `en` answered with the Korean string
/// on a ko-KR Mac — it would pass here and fail in CI, or pass in both while testing nothing.
///
/// **What makes the two directions sound is a type, not this scan.** `localized(_:)` takes a
/// `StaticString`, so a key cannot be computed; the literals in the sources are therefore the whole
/// set of keys the app can ask for, and "every key exists" and "every key is used" are enumerations
/// rather than best guesses. `testAKeyCannotBeComputed` is what keeps that premise true.
final class LocalizationCatalogTests: XCTestCase {
    /// The catalogues item 24 has still to write. Being on this list buys an exemption from the
    /// key-set check and nothing else — a key that *is* there still has to be a real one, with the
    /// same placeholders.
    ///
    /// The list cannot quietly outlive its reason: a locale on it has to be **genuinely
    /// incomplete**, so the day item 24 fills one, this file turns red until the entry is removed.
    /// That is the completion condition item 24 carries.
    private let incompleteLocales: Set<String> = ["ja", "zh-Hans", "zh-Hant"]

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocalizationCatalogTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App")
    }

    private func catalogue(_ tag: String) throws -> [String: String] {
        let url = Self.appSources
            .appendingPathComponent("Resources/\(tag).lproj/Localizable.strings")
        let parsed = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil
        )
        return try XCTUnwrap(parsed as? [String: String], "\(tag) is not a dictionary of strings")
    }

    /// Every Swift file of the App target, concatenated. The subject is "what the app asks for", so
    /// tests are deliberately not part of it — a key only a test mentions is a key nothing draws.
    private func sourceText() throws -> String {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: Self.appSources.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertGreaterThan(names.count, 1, "the source scan found almost nothing — check the path")
        return try names
            .map { try String(contentsOf: Self.appSources.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func matches(_ pattern: String, in text: String, group: Int = 1) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    /// `%@`, `%d` and their positional forms, in the order they appear. Order matters: `%1$@ %2$@`
    /// and `%2$@ %1$@` carry the same set and mean different sentences, and a catalogue that
    /// disagrees with `en` about which argument goes where is the bug this looks for.
    private func placeholders(_ value: String) throws -> [String] {
        try matches("(%(?:\\d+\\$)?[@dsf])", in: value)
    }

    /// **Same keys in every catalogue.** A key missing from one of them is a raw key on that
    /// language's screen, which the fallback in `AppLocalization.string` only softens into English.
    func testEveryLocaleCarriesTheSameKeys() throws {
        let english = Set(try catalogue(fallbackLocale).keys)
        XCTAssertFalse(english.isEmpty)
        XCTAssertTrue(
            incompleteLocales.isSubset(of: Set(supportedLocales)),
            "the exemption list names a locale we do not ship"
        )
        XCTAssertFalse(
            incompleteLocales.contains(fallbackLocale), "English cannot be the incomplete one"
        )

        for tag in supportedLocales {
            let keys = Set(try catalogue(tag).keys)
            if incompleteLocales.contains(tag) {
                XCTAssertTrue(keys.isSubset(of: english), "\(tag) has keys en does not: \(keys.subtracting(english))")
                XCTAssertNotEqual(
                    keys, english,
                    "\(tag) is complete — take it out of `incompleteLocales`, which is item 24's completion condition"
                )
            } else {
                XCTAssertEqual(keys, english, "\(tag) differs from en: \(keys.symmetricDifference(english))")
            }
        }
    }

    /// **Same placeholders in every catalogue**, for every key a catalogue carries. A translation
    /// that drops a `%@` renders a sentence with a hole in it; one that adds a second `%@` reads an
    /// argument that was never passed, which is a crash rather than a typo.
    func testEveryLocaleUsesTheSamePlaceholders() throws {
        let english = try catalogue(fallbackLocale)
        for tag in supportedLocales where tag != fallbackLocale {
            let catalog = try catalogue(tag)
            for (key, value) in catalog {
                let expected = try placeholders(try XCTUnwrap(english[key], "\(tag) has an unknown key \(key)"))
                XCTAssertEqual(try placeholders(value), expected, "\(tag)/\(key)")
            }
        }
    }

    /// **Every key the sources ask for exists.** The keys are found as literals, which is only a
    /// complete answer because `localized(_:)` cannot take anything else.
    func testEveryKeyTheSourcesAskForExists() throws {
        let english = Set(try catalogue(fallbackLocale).keys)
        let referenced = Set(try matches("\"(app\\.[A-Za-z0-9._]+)\"", in: try sourceText()))
        XCTAssertFalse(referenced.isEmpty, "the literal scan found nothing — check the pattern")
        XCTAssertEqual(referenced.subtracting(english), [], "asked for but not in the catalogue")
    }

    /// **No key sits in the catalogue unused.** An unused key is a sentence nobody sees, and it is
    /// also five translations of it — the cost lands on item 24 and on every translator after.
    func testEveryCatalogueKeyIsAskedFor() throws {
        let english = Set(try catalogue(fallbackLocale).keys)
        let referenced = Set(try matches("\"(app\\.[A-Za-z0-9._]+)\"", in: try sourceText()))
        XCTAssertEqual(english.subtracting(referenced), [], "in the catalogue and never asked for")
    }

    /// **A key cannot be computed** — the premise the two directions above rest on.
    ///
    /// It is checked as source text because that is where the guarantee lives: the parameter type.
    /// A `String`-taking overload, or a call to the low-level lookup from somewhere else, would
    /// reopen the door without failing anything else in this file.
    func testAKeyCannotBeComputed() throws {
        let localization = try String(
            contentsOf: Self.appSources.appendingPathComponent("Localization.swift"), encoding: .utf8
        )
        XCTAssertTrue(
            localization.contains("func localized(_ key: StaticString) -> String"),
            "the shorthand no longer takes a StaticString, so a key can be computed again"
        )
        XCTAssertTrue(
            localization.contains("func localized(_ key: StaticString, _ arguments: CVarArg...) -> String"),
            "the formatting shorthand no longer takes a StaticString"
        )
        XCTAssertFalse(
            localization.contains("func localized(_ key: String"),
            "a String-taking overload puts the hole back"
        )

        // `AppLocalization.string` is the lookup underneath and does take a `String`, because tests
        // aim it at one catalogue at a time. Production reaching it directly would step around the
        // type, so the only callers allowed are the two shorthands in that same file.
        let names = try FileManager.default
            .contentsOfDirectory(atPath: Self.appSources.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Localization.swift" }
        for name in names {
            let text = try String(
                contentsOf: Self.appSources.appendingPathComponent(name), encoding: .utf8
            )
            XCTAssertFalse(
                text.contains("AppLocalization.string("),
                "\(name) calls the lookup directly, which takes a String and skips the type"
            )
        }
    }

    /// **A sentence that quotes a button names the button's key** (D28), and that key is real.
    ///
    /// The relation is what the gate checks, not the wording: a body carrying `[%@]` has to be
    /// called with a `localized("app.button…")` argument, so renaming or retranslating the button
    /// moves the sentence with it. Item 11 found the drift this prevents already in place — the
    /// Korean quoted `[권한 요청]` while the button read `iTerm2 권한 요청`.
    func testEverySentenceQuotingALabelNamesARealLabelKey() throws {
        let english = try catalogue(fallbackLocale)
        let sources = try sourceText()
        let quoting = english.filter { $0.value.contains("[%@]") }.keys.sorted()
        XCTAssertFalse(quoting.isEmpty, "no sentence quotes a label any more — has the convention changed?")

        for key in quoting {
            let pattern = "localized\\(\\s*\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*,"
                + "\\s*localized\\(\\s*\"([A-Za-z0-9._]+)\"\\s*\\)"
            let labelKeys = try matches(pattern, in: sources)
            XCTAssertFalse(
                labelKeys.isEmpty,
                "\(key) quotes a label but is not called with one — the label is hardcoded or the call was split"
            )
            for labelKey in labelKeys {
                XCTAssertNotNil(english[labelKey], "\(key) names \(labelKey), which is not in the catalogue")
                XCTAssertTrue(
                    labelKey.hasPrefix("app.button."),
                    "\(key) takes \(labelKey), which is not a button label"
                )
            }
        }
    }
}
