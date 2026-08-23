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
    /// **Empty, and emptying it was item 24's completion condition.** Every shipped locale is now
    /// held to the full key set, so the exemption branch below is unreachable and stays only as the
    /// shape a future partly-written catalogue would use.
    ///
    /// Why it had to empty *before* the translations landed rather than after: while it named the
    /// three locales nobody had filled, the key check *licensed* them — a catalogue with one key out
    /// of ninety-seven satisfied "a subset of English". The exemption was honest while the
    /// translations did not exist and became a hole the moment they did, and a gate written after
    /// the thing it guards cannot have caught it arriving.
    ///
    /// Being on the list would buy an exemption from the key-set check and nothing else: a key that
    /// *is* there still has to be a real one, with the same placeholders.
    private let incompleteLocales: Set<String> = []

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
    ///
    /// **Recursive, because a directory listing is not a source tree.** This read only the immediate
    /// children, so the first file put in a subdirectory of `Sources/App` would leave the gate
    /// green while asking for keys nobody checked — the gate would answer "no unreferenced keys"
    /// about a set it had never seen. Nothing is nested today; that is precisely why it had to be
    /// fixed now rather than when something is.
    private func sourceText() throws -> String {
        let files = try swiftFiles(under: Self.appSources)
        XCTAssertGreaterThan(files.count, 1, "the source scan found almost nothing — check the path")
        return try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    /// The walk itself, separated so that "does it descend" is a question a test can ask. Nothing is
    /// nested under `Sources/App` today, which is exactly why the recursion could not otherwise be
    /// asserted: a flat tree gives the same answer either way, and the gate would have gone on
    /// reporting "no unreferenced keys" about a set it had never seen.
    func swiftFiles(under root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not walk \(root.path)"
        )
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    /// **The scan descends.** A directory listing is not a source tree, and this read only the
    /// immediate children — so the first file anyone put in a subdirectory of `Sources/App` would
    /// have left every check here green while asking for keys nobody compared against the catalogue.
    func testTheSourceScanDescendsIntoSubdirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tc-scan-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Feature/Deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "// top".write(to: root.appendingPathComponent("Top.swift"), atomically: true, encoding: .utf8)
        try "// deep".write(to: nested.appendingPathComponent("Deep.swift"), atomically: true, encoding: .utf8)
        try "not swift".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let found = try swiftFiles(under: root).map { $0.lastPathComponent }
        XCTAssertEqual(found, ["Deep.swift", "Top.swift"], "the scan did not descend")
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
        // type, so the only callers meant to exist are the two shorthands in that same file.
        //
        // **It walks the same tree `sourceText()` does, through the same function.** This used to
        // call `contentsOfDirectory`, which does not descend — the exact defect that walk was
        // written to fix, left standing a few lines below three separate paragraphs explaining why a
        // directory listing is not a source tree. Measured: a caller placed in a subdirectory of
        // `Sources/App` passed unseen. Two walks is how one of them gets strengthened alone, so
        // there is one.
        for file in try swiftFiles(under: Self.appSources)
        where file.lastPathComponent != "Localization.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("AppLocalization.string("),
                "\(file.lastPathComponent) calls the lookup directly, which takes a String and skips the type"
            )
        }
    }

    /// **The oracle for a placeholder is the call site, not English.**
    ///
    /// `testEveryLocaleUsesTheSamePlaceholders` above compares every catalogue to English, so
    /// English is both a subject and the yardstick — measured, deleting `%@` from one key in **all
    /// five** catalogues passed, because they still agreed with each other. What actually decides
    /// whether a sentence needs a placeholder is how many arguments the code hands it, and that is
    /// written somewhere else: the call site.
    ///
    /// So the two directions are read off the source. A key called as `localized("k", x)` must carry
    /// a placeholder in **every** language, and one called as `localized("k")` must carry none — a
    /// stray `%@` there renders as the literal characters, since nothing is substituted.
    ///
    /// **Its limit**: a key nothing calls through `localized(` is skipped, which is why the count is
    /// asserted at the end. It reads the argument list only far enough to see whether one exists; it
    /// does not count arguments, so a sentence taking two placeholders while the call passes one is
    /// still only caught by the parity check against English.
    func testAPlaceholderIsRequiredByTheCallSiteRatherThanByEnglish() throws {
        let sources = try sourceText()
        var checked = 0
        for (key, _) in try catalogue(fallbackLocale) {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let called = try matches("localized\\(\\s*\"\(escaped)\"\\s*([,)])", in: sources)
            guard !called.isEmpty else { continue }
            checked += 1
            let takesArguments = called.contains(",")
            for tag in supportedLocales {
                let value = try XCTUnwrap(try catalogue(tag)[key])
                let hasPlaceholder = !(try placeholders(value).isEmpty)
                XCTAssertEqual(
                    hasPlaceholder, takesArguments,
                    takesArguments
                        ? "\(tag)/\(key) is called with an argument but has no placeholder to put it in"
                        : "\(tag)/\(key) carries a placeholder nothing substitutes — it draws as %@"
                )
            }
        }
        XCTAssertGreaterThan(checked, 50, "the call-site scan matched almost nothing — check the pattern")
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
