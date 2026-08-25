import Core
import XCTest
@testable import App

/// Test-only ownership of the socket-path override. The remaining locale tests are pure settings
/// and picker contracts, but other AppTests still use this helper for their socket cases.
final class CanonicalSocketOverride {
    private let previous: String?

    init(_ path: String) {
        previous = ProcessInfo.processInfo.environment["TERMINAL_CHECKOUT_SOCKET"]
        setenv("TERMINAL_CHECKOUT_SOCKET", path, 1)
    }

    deinit {
        if let previous { setenv("TERMINAL_CHECKOUT_SOCKET", previous, 1) } else {
            unsetenv("TERMINAL_CHECKOUT_SOCKET")
        }
    }
}

final class LocalizationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The invariant `SupportedLocale.fallback` is built on: the language every unanswerable
    /// question lands in is one we actually ship. Without this the type could hand out a tag with
    /// no catalogue behind it, which is the defect it exists to prevent.
    func testTheFallbackIsALocaleWeShip() {
        XCTAssertTrue(supportedLocales.contains(fallbackLocale))
        XCTAssertEqual(SupportedLocale.fallback.tag, fallbackLocale)
        XCTAssertEqual(SupportedLocale(fallbackLocale), SupportedLocale.fallback)
    }

    /// **A preference that is not a string reads as itself, not as `auto`**.
    ///
    /// The two sides have to agree about what an unreadable value means: the picker asks
    /// `Settings.languagePreference`, the window draws what `resolveLocale` says, and folding the
    /// value in one of them and not the other is how the picker ended up claiming a choice the
    /// window was not honouring.
    func testACorruptPreferenceIsNeitherAutoNorAChoice() {
        defaults.set(42, forKey: languagePreferenceKey)
        let corrupt = Settings.languagePreference(in: defaults)
        XCTAssertNotEqual(corrupt, automaticLocalePreference, "a corrupt value folded into a choice")
        XCTAssertFalse(supportedLocales.contains(corrupt), "a corrupt value read as a language we ship")
        XCTAssertEqual(
            AppLocalization.resolvedTag(defaults: defaults, systemPreferred: ["ko-KR"]), fallbackLocale,
            "the window and the picker disagree about what this value means"
        )

        defaults.removeObject(forKey: languagePreferenceKey)
        XCTAssertEqual(Settings.languagePreference(in: defaults), automaticLocalePreference)
        defaults.set("ja", forKey: languagePreferenceKey)
        XCTAssertEqual(Settings.languagePreference(in: defaults), "ja")
    }

    /// The picker has one entry for each stored choice and points at the language actually drawn
    /// when the stored value is automatic, corrupt, or otherwise not among the entries.
    func testThePickerPointsAtTheLanguageBeingDrawn() {
        let entries: [String?] = [automaticLocalePreference] + supportedLocales

        XCTAssertEqual(languagePickerIndex(stored: "ja", drawn: "ja", entries: entries),
                       entries.firstIndex(of: "ja"))
        XCTAssertEqual(languagePickerIndex(stored: automaticLocalePreference, drawn: "ko", entries: entries), 0)
        XCTAssertEqual(languagePickerIndex(stored: "42", drawn: fallbackLocale, entries: entries),
                       entries.firstIndex(of: fallbackLocale))
        XCTAssertEqual(languagePickerIndex(stored: "42", drawn: "fr", entries: entries), 0)
    }
}
