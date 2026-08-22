import Core
import XCTest
@testable import App

/// The four contracts round 1 asked for and round 5 pinned by name (D67).
///
/// `localeSnapshotToPublish` is pure and stays that way: it assumes `resolved` came from
/// `resolveLocale` and that `lastPublished` is a **valid snapshot of the current install**, and it
/// cannot enforce either — `LocaleSnapshot` has no identity in it. Those assumptions belong to
/// storage and to the caller, so they are proved here rather than by making the function heavier.
///
/// Every case runs against a private suite. The subject is `UserDefaults` writes, and running them
/// against `.standard` would rewrite the language state of the app installed on this machine.
final class LocalePublicationTests: XCTestCase {
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

    private func storedTriple() -> (String?, Any?, String?) {
        (
            defaults.object(forKey: LocaleState.installIdKey) as? String,
            defaults.object(forKey: LocaleState.epochKey),
            defaults.object(forKey: LocaleState.publishedTagKey) as? String
        )
    }

    private func seed(installId: String, epoch: Any?, tag: String?) {
        defaults.set(installId, forKey: LocaleState.installIdKey)
        if let epoch { defaults.set(epoch, forKey: LocaleState.epochKey) }
        if let tag { defaults.set(tag, forKey: LocaleState.publishedTagKey) }
    }

    /// **① A missing last-published is only valid for a genuinely new install.**
    ///
    /// Nothing stored is the real thing: mint an identity and start at 0. But an identity that is
    /// already out there, with the rest of the snapshot gone, is *not* that state — republishing 0
    /// under it loses to whatever epoch the extension has cached, and the language never moves
    /// again. The identity has to change with it.
    func testANilLastPublishedIsOnlyValidForATrulyNewInstall() throws {
        let fresh = try XCTUnwrap(LocaleState.publish(resolved: "ko", defaults: defaults, role: .interactive))
        XCTAssertEqual(fresh.snapshot, LocaleSnapshot(tag: "ko", epoch: 0))
        XCTAssertFalse(fresh.installId.isEmpty)

        // The same starting point, except that an identity survived
        defaults.removeObject(forKey: LocaleState.epochKey)
        defaults.removeObject(forKey: LocaleState.publishedTagKey)
        let after = try XCTUnwrap(LocaleState.publish(resolved: "ko", defaults: defaults, role: .interactive))
        XCTAssertEqual(after.snapshot.epoch, 0)
        XCTAssertNotEqual(
            after.installId, fresh.installId,
            "epoch 0 was republished under the identity the extension already trusts"
        )
    }

    /// **② An install id with no epoch, or a malformed one, gets a new identity — never epoch 0
    /// under the old one.**
    ///
    /// `Int.max` counts as malformed: the next revision cannot be expressed, so staying under that
    /// identity would mean publishing changes the extension is obliged to ignore. A negative epoch
    /// and a non-integer are the shapes a hand-edited plist and a future build produce.
    func testAnInstallIdWithNoOrMalformedEpochGetsANewIdentityNotEpochZero() throws {
        let malformed: [(String, Any?)] = [
            ("missing", nil), ("string", "3"), ("negative", -1), ("max", Int.max), ("double", 2.5),
        ]
        for (label, epoch) in malformed {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            seed(installId: "old-identity", epoch: epoch, tag: "ko")
            let published = try XCTUnwrap(
                LocaleState.publish(resolved: "ja", defaults: defaults, role: .interactive), label
            )
            XCTAssertNotEqual(published.installId, "old-identity", label)
            XCTAssertEqual(published.snapshot, LocaleSnapshot(tag: "ja", epoch: 0), label)
            XCTAssertEqual(storedTriple().0, published.installId, label)
        }

        // A tag we do not ship is malformed too — it cannot be what we last published
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "old-identity", epoch: 4, tag: "fr")
        let published = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: defaults, role: .interactive))
        XCTAssertNotEqual(published.installId, "old-identity")
        XCTAssertEqual(published.snapshot.epoch, 0)
    }

    /// **③ Two writers cannot publish different locales at the same epoch** — because there is only
    /// one writer (D49). The headless server shares the bundle id, and therefore this whole domain,
    /// with the GUI; what keeps them from colliding is that it never writes and never invents a
    /// revision. It republishes what the GUI last wrote, even when this launch resolves elsewhere.
    func testTwoWritersCannotPublishDifferentLocalesAtTheSameEpoch() throws {
        seed(installId: "install-a", epoch: 3, tag: "ko")
        let before = storedTriple()

        let headless = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: defaults, role: .headless))
        XCTAssertEqual(headless.snapshot, LocaleSnapshot(tag: "ko", epoch: 3), "the headless server invented a revision")
        XCTAssertEqual(storedTriple().0, before.0)
        XCTAssertEqual(storedTriple().1 as? Int, before.1 as? Int)
        XCTAssertEqual(storedTriple().2, before.2, "the headless server wrote")

        let gui = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: defaults, role: .interactive))
        XCTAssertEqual(gui.snapshot, LocaleSnapshot(tag: "ja", epoch: 4))
        XCTAssertEqual(gui.installId, "install-a")
        // The pair the extension orders by: no epoch ever carries two different tags
        XCTAssertNotEqual(headless.snapshot.epoch, gui.snapshot.epoch)

        // And with nothing stored, the headless server publishes nothing at all rather than
        // minting an identity the GUI would then disagree with
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        XCTAssertNil(LocaleState.publish(resolved: "ja", defaults: defaults, role: .headless))
        XCTAssertNil(storedTriple().0)
    }

    /// **④ A corrupted epoch cannot trap, and cannot make publication non-monotonic.**
    ///
    /// `Int.max` is the trap: `epoch + 1` on it is a crash in Swift, not a wrap. The rest is the
    /// ordering promise — for one identity the epoch never goes down, whatever was in the plist.
    func testACorruptedEpochCannotTrapOrPublishNonMonotonically() throws {
        seed(installId: "install-a", epoch: Int.max, tag: "ko")
        let recovered = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: defaults, role: .interactive))
        XCTAssertEqual(recovered.snapshot.epoch, 0)
        XCTAssertNotEqual(recovered.installId, "install-a", "a revision that cannot advance kept its identity")

        // Monotonic under one identity: republishing the same locale stands still, a change moves
        // up by one, and returning to an earlier locale still moves up
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "install-b", epoch: 7, tag: "ko")
        var epochs: [Int] = []
        for resolved in ["ko", "ja", "ko", "zh-Hant"] {
            let published = try XCTUnwrap(
                LocaleState.publish(resolved: resolved, defaults: defaults, role: .interactive)
            )
            XCTAssertEqual(published.installId, "install-b")
            epochs.append(published.snapshot.epoch)
        }
        XCTAssertEqual(epochs, [7, 8, 9, 10])
        XCTAssertEqual(zip(epochs, epochs.dropFirst()).allSatisfy { $0 <= $1 }, true)
    }

    /// Republishing an unchanged locale does not move the revision — every launch publishes, and a
    /// number that moved each time would make every launch look like a language change.
    func testRepublishingTheSameLocaleStandsStill() throws {
        seed(installId: "install-a", epoch: 2, tag: "ja")
        let again = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: defaults, role: .interactive))
        XCTAssertEqual(again, LocalePublication(installId: "install-a", snapshot: LocaleSnapshot(tag: "ja", epoch: 2)))
    }
}
