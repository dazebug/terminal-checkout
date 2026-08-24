import Core
import TestSupport
import XCTest
@testable import App

/// Stages the two global-domain APIs without mutating the test runner's real defaults. Production
/// reads the persistent global domain here; the volatile value is deliberately different so a
/// test cannot pass while consulting the branch that does not exist on the measured host.
private final class StagedGlobalDefaults: UserDefaults {
    private let stagedVolatileGlobal: [String: Any]
    private let stagedPersistentGlobal: [String: Any]

    init(
        suiteName: String,
        volatileGlobal: [String: Any],
        persistentGlobal: [String: Any]
    ) {
        stagedVolatileGlobal = volatileGlobal
        stagedPersistentGlobal = persistentGlobal
        super.init(suiteName: suiteName)!
    }

    override func volatileDomain(forName domainName: String) -> [String: Any] {
        if domainName == UserDefaults.globalDomain { return stagedVolatileGlobal }
        return super.volatileDomain(forName: domainName)
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        if domainName == UserDefaults.globalDomain { return stagedPersistentGlobal }
        return super.persistentDomain(forName: domainName)
    }
}

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

    /// The key this file probes with. It was a skeleton key (`app.setup.window.title`) until item 10
    /// moved the window's strings in and the window title got its real one. All five catalogues are
    /// full now, so it is a probe by choice rather than by necessity: one key every catalogue is
    /// certain to carry, which is all these cases need to tell five files apart.
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

    /// `auto` may remove only the `AppleLanguages` value this app can prove it wrote. A value that
    /// arrived from System Settings, another domain or an older build is not ours to delete, even
    /// when it has the same shape as the value we would have written.
    ///
    /// A private suite is used because the subject is a `UserDefaults` write: running this against
    /// `.standard` would rewrite the language of the app installed on this machine.
    ///
    /// **Absence is asserted on our own domain, not through `object(forKey:)`.** Reading the
    /// effective value after removal can still answer a global-domain value, so the test must
    /// distinguish our copy from the value the system supplies below it.
    func testAutomaticRemovesOnlyItsRecordedAppleLanguagesValue() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        func ourOwnCopy() -> Any? {
            UserDefaults.standard.persistentDomain(forName: suiteName)?["AppleLanguages"]
        }
        func ourRecord() -> Any? {
            UserDefaults.standard.persistentDomain(forName: suiteName)?["TerminalCheckoutAppleLanguagesProvenance"]
        }

        // A value with no record is not ours, even if it is exactly the value an explicit choice
        // would write.
        defaults.set(["ja"], forKey: "AppleLanguages")
        defaults.set("auto", forKey: languagePreferenceKey)
        XCTAssertNotNil(ourOwnCopy(), "the fixture did not take — the removal below proves nothing")
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))
        XCTAssertEqual(ourOwnCopy() as? [String], ["ja"], "auto removed a value with no provenance record")
        XCTAssertNil(ourRecord())

        // An explicit choice records the exact value it wrote, and `auto` may then remove that
        // value together with the record.
        defaults.set("ja", forKey: languagePreferenceKey)
        XCTAssertEqual(
            AppLocalization.applyStoredLanguageToAppKit(defaults: defaults, systemPreferred: ["ko-KR"]),
            "ja"
        )
        XCTAssertEqual(ourRecord() as? [String], ["ja"])
        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)
        defaults.set(["ja"], forKey: "AppleLanguages")
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))
        XCTAssertNil(ourOwnCopy())
        XCTAssertNil(ourRecord())
    }

    /// Provenance is a comparison against the value we wrote, not a permanent right to erase the
    /// key. If another writer changes the value before the user chooses `auto`, it stays and the
    /// stale record is discarded.
    func testAutomaticLeavesAChangedAppleLanguagesValueForItsWriter() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set("ja", forKey: languagePreferenceKey)
        XCTAssertEqual(
            AppLocalization.applyStoredLanguageToAppKit(defaults: defaults, systemPreferred: ["ko-KR"]),
            "ja"
        )
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["ja"], "the override did not take")
        XCTAssertEqual(
            defaults.array(forKey: "TerminalCheckoutAppleLanguagesProvenance") as? [String], ["ja"]
        )

        // Simulate System Settings or another writer changing the app-domain value after our write.
        defaults.set(["ko"], forKey: "AppleLanguages")
        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)
        XCTAssertNil(AppLocalization.applyStoredLanguageToAppKit(
            defaults: defaults, systemPreferred: ["ko-KR"]
        ))

        XCTAssertEqual(
            defaults.array(forKey: "AppleLanguages") as? [String], ["ko"],
            "auto removed a value that no longer matched our provenance record"
        )
        XCTAssertNil(defaults.object(forKey: "TerminalCheckoutAppleLanguagesProvenance"))
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
        // this suite does not own, which is exactly why the comparison is worth making.
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

    /// The process's `Locale.preferredLanguages` includes the app-domain override after an
    /// explicit choice. `auto` must instead read the argument/global system domains. This fixture
    /// stages the production `persistentDomain(forName:)` call through an isolated `UserDefaults`
    /// double because writing `NSGlobalDomain` would mutate the test runner's real defaults. The
    /// actual System Settings domain and AppKit's first lookup remain device-gate questions.
    func testAutomaticResolutionUsesTheExternalSystemLanguageOrder() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let defaults = StagedGlobalDefaults(
            suiteName: suiteName,
            volatileGlobal: ["AppleLanguages": ["en-US"]],
            persistentGlobal: ["AppleLanguages": ["zh-TW"]]
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set(["ja"], forKey: "AppleLanguages")
        XCTAssertEqual(
            AppLocalization.resolvedTag(defaults: defaults), "ja",
            "an unowned per-app AppleLanguages choice must remain the system answer"
        )
        defaults.set(["ja"], forKey: "TerminalCheckoutAppleLanguagesProvenance")
        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)

        XCTAssertEqual(
            AppLocalization.resolvedTag(defaults: defaults), "zh-Hant",
            "auto resolved from the app's AppleLanguages value instead of the external system order"
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
    /// The bundle gate spells the shipped languages out, because a shell script cannot read
    /// `supportedLocales`. Same arrangement as the development region below, and the same reason:
    /// change the constant alone and this fails, rather than the gate quietly admitting a language
    /// the app does not ship or rejecting one it does.
    func testTheBundleGateKnowsExactlyTheLanguagesWeShip() throws {
        let script = try repoFile("app/verify-bundle.sh")
        let line = try XCTUnwrap(
            script.split(separator: "\n").first { $0.hasPrefix("SUPPORTED_LPROJ=") },
            "verify-bundle.sh no longer closes the catalogue set"
        )
        let listed = String(line)
            .replacingOccurrences(of: "SUPPORTED_LPROJ=", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .split(separator: " ").map(String.init)
        XCTAssertEqual(
            listed.sorted(), supportedLocales.sorted(),
            "verify-bundle.sh and supportedLocales disagree about which languages ship"
        )
    }

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
    return try auditSource(root.appendingPathComponent(name).path, claim: .sourceStructure).text
}
