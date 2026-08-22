import Core
import XCTest
@testable import App

/// The bundle skeleton: five catalogs that each answer in their own language, and the one write
/// that points AppKit's chrome at the same language.
///
/// Every lookup here names its `.lproj` **directly**. Measured (D7): `Bundle(url:)` on the folder
/// holding them resolves through the *host machine's* language, so a lookup aimed at `en` returned
/// the Korean string on a ko-KR Mac — an oracle that would pass here and fail in CI, or worse,
/// pass in both while testing nothing. `Bundle(path: <…>/<tag>.lproj)` is the only form that
/// answers the same way everywhere.
///
/// The subject is the **source** tree, not the built app. Whether `build.sh` copied it is item 7's
/// question, and `swift test` runs with no app bundle in sight.
final class LocalizationBundleTests: XCTestCase {
    private var resources: String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocalizationBundleTests.swift
            .deletingLastPathComponent() // AppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // app
            .appendingPathComponent("Sources/App/Resources")
            .path
    }

    /// The key every catalogue carries. It was a skeleton probe (`app.setup.window.title`) until
    /// item 10 moved the window's strings in and the window title got its real key; the other four
    /// catalogues still hold only this one, because their bodies are item 24's.
    private let probeKey = "app.window.title"

    func testEachBundledCatalogAnswersInItsOwnLanguage() throws {
        var answers: [String: String] = [:]
        for tag in supportedLocales {
            let catalog = try XCTUnwrap(
                AppLocalization.catalog(forTag: tag, resources: resources),
                "\(tag).lproj is missing from the sources"
            )
            let value = catalog.localizedString(forKey: probeKey, value: "", table: nil)
            XCTAssertFalse(value.isEmpty, "\(tag) has no value for \(probeKey)")
            XCTAssertNotEqual(value, probeKey, "\(tag) returned the raw key")
            answers[tag] = value
        }
        XCTAssertEqual(answers.count, 5)
        // Distinct values are what proves the lookup reached five different files. With two
        // catalogs sharing a wording this assertion has to be relaxed to name the pair — silently
        // dropping it would let a single catalog answer for all five and still pass.
        XCTAssertEqual(
            Set(answers.values).count, 5, "two catalogs answered identically: \(answers)"
        )
        XCTAssertEqual(answers["en"], "Terminal Checkout Setup")
        XCTAssertEqual(answers["ko"], "Terminal Checkout 설정")
    }

    /// The lookup asks the requested catalog, then English, then gives back the key. The last step
    /// is a floor and not a feature: item 12's gate turns a missing key into a red build, and a raw
    /// key on screen is the failure that gate exists to prevent.
    func testAMissingKeyFallsBackToEnglishAndThenToTheKey() {
        XCTAssertEqual(
            AppLocalization.string(probeKey, tag: "ja", resources: resources),
            "Terminal Checkout セットアップ"
        )
        XCTAssertEqual(
            AppLocalization.string("app.no.such.key", tag: "ja", resources: resources),
            "app.no.such.key"
        )
        // A tag with no catalog at all falls to English rather than to the key
        XCTAssertEqual(
            AppLocalization.string(probeKey, tag: "fr", resources: resources),
            "Terminal Checkout Setup"
        )
    }

    /// The `auto` probe D22 asked for, and the reason item 8 can build on it: an automatic
    /// preference leaves **no** `AppleLanguages` entry behind, so the system language keeps
    /// deciding. Writing the resolved tag there instead would freeze the app at today's system
    /// language — every other app would follow a later change and this one would not.
    ///
    /// A private suite is used because the subject is a `UserDefaults` write: running this against
    /// `.standard` would rewrite the language of the app installed on this machine.
    ///
    /// **Absence is asserted on our own domain, not through `object(forKey:)`.** Measured while
    /// writing this: after the key is removed, reading it back still answers `["ko-KR"]`, because
    /// `AppleLanguages` also lives in `NSGlobalDomain` and the search list falls through to it.
    /// That fall-through is not in the way of the test — it **is** the mechanism: removing our copy
    /// is what puts the system's list back in charge, which is what `auto` means.
    func testAnAutomaticPreferenceLeavesNoAppleLanguagesOverride() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        func ourOwnCopy() -> Any? {
            UserDefaults.standard.persistentDomain(forName: suiteName)?["AppleLanguages"]
        }

        // An override left by an earlier explicit choice has to be taken away, not merely skipped
        defaults.set(["ja"], forKey: "AppleLanguages")
        defaults.set("auto", forKey: languagePreferenceKey)
        XCTAssertNotNil(ourOwnCopy(), "the fixture did not take — the removal below proves nothing")
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))
        XCTAssertNil(ourOwnCopy())

        // Absent means automatic too — the key is never written before the picker exists
        defaults.removeObject(forKey: languagePreferenceKey)
        defaults.set(["ja"], forKey: "AppleLanguages")
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))
        XCTAssertNil(ourOwnCopy())
    }

    /// **The value that answers afterwards is the one that answered before** (round 7 review).
    ///
    /// The test above proves our own copy of the key is gone, which is not the same claim: a
    /// removal that also lost whatever the domain below was saying would satisfy it just as well.
    /// What `auto` promises is that the system's list decides again, so the assertion is a
    /// before/after comparison of the **effective** value — read through the search list rather
    /// than out of our own domain.
    ///
    /// It also fixes the boundary of that promise. `auto` removes the **app-owned** override and
    /// nothing else: an `-AppleLanguages` argument on the command line, or any domain with higher
    /// precedence, still wins, and no amount of removing our key changes that. Users need to know
    /// it (item 25 lists it in the README), and a future reader needs to know this test does not
    /// claim otherwise.
    func testAutomaticRestoresTheEffectiveValueItFound() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // What the search list answers with no override of ours in the way. It comes from a domain
        // this suite does not own, which is exactly why the comparison is worth making
        let before = defaults.array(forKey: "AppleLanguages") as? [String]
        XCTAssertNotNil(before, "no effective AppleLanguages to restore — the comparison would be vacuous")

        defaults.set("ja", forKey: languagePreferenceKey)
        XCTAssertEqual(
            AppLocalization.applyStoredLanguageToAppKit(defaults: defaults, systemPreferred: ["ko-KR"]),
            "ja"
        )
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["ja"], "the override did not take")

        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))

        let after = defaults.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(after, before, "auto removed our override but did not give the previous answer back")
        XCTAssertNil(
            UserDefaults.standard.persistentDomain(forName: suiteName)?["AppleLanguages"],
            "our own copy is still there, so `after` may only be echoing it"
        )
    }

    /// The other half of the same rule: an explicit choice **is** written, and so is a stored value
    /// we cannot read — our own strings resolve that one to English, and chrome that disagreed with
    /// them would be exactly the split-language window D14 rules out.
    func testAnExplicitChoiceIsWrittenAndSoIsAValueWeCannotRead() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set("ja", forKey: languagePreferenceKey)
        XCTAssertEqual(
            AppLocalization.applyStoredLanguageToAppKit(defaults: defaults, systemPreferred: ["ko-KR"]),
            "ja"
        )
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["ja"])

        defaults.set(42, forKey: languagePreferenceKey)
        XCTAssertEqual(
            AppLocalization.applyStoredLanguageToAppKit(defaults: defaults, systemPreferred: ["ko-KR"]),
            "en"
        )
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["en"])
        XCTAssertEqual(
            AppLocalization.resolvedTag(defaults: defaults, systemPreferred: ["ko-KR"]), "en",
            "the strings we draw and the chrome AppKit draws have to land on the same language"
        )
    }

    /// The bundle gate hardcodes the development region it expects, because a shell script cannot
    /// read a Swift constant. That is the same drift `UninstallScriptSyncTests` guards for the
    /// uninstall markers, so it is guarded the same way: change `fallbackLocale` alone and this
    /// fails, rather than the gate quietly enforcing last year's answer.
    func testTheBundleGateExpectsTheSameRegionWeFallBackTo() throws {
        let script = try repoFile("app/verify-bundle.sh")
        XCTAssertTrue(
            script.contains("CFBundleDevelopmentRegion"),
            "verify-bundle.sh no longer checks the development region at all"
        )
        XCTAssertTrue(
            script.contains("\"$REGION\" != \"\(fallbackLocale)\""),
            "verify-bundle.sh expects a different region than fallbackLocale (\(fallbackLocale))"
        )
    }

    /// `CFBundleDevelopmentRegion` is what macOS answers with when it can match nothing else.
    /// Measured (D2): with the region at `ko`, a process asking for `fr` resolved to `["ko"]`; with
    /// it at `en`, to `["en"]`. Leaving it at `ko` would put a French user in Korean while our own
    /// strings gave them English.
    func testTheDevelopmentRegionIsTheLanguageWeFallBackTo() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Info.plist")
        let parsed = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plist), format: nil
        ) as? [String: Any]
        XCTAssertEqual(parsed?["CFBundleDevelopmentRegion"] as? String, fallbackLocale)
    }
}

private func repoFile(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocalizationBundleTests.swift
        .deletingLastPathComponent() // AppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // app
        .deletingLastPathComponent() // the repository root
    return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
}
