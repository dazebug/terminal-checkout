import Core
import XCTest
@testable import App

/// The four contracts round 1 asked for and round 5 pinned by name (D67), plus the two round 9
/// added: nothing a reader sees was ever half-written, and the three-key state an earlier build
/// left behind is not read.
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

    /// The envelope as it sits on disk, field by field, so that a malformed one can still be
    /// inspected — refusing those is what several of these cases are about.
    private func storedTriple() -> (String?, Any?, String?) {
        let envelope = defaults.dictionary(forKey: LocaleState.publicationKey)
        return (envelope?["installId"] as? String, envelope?["epoch"], envelope?["tag"] as? String)
    }

    /// Writes an envelope holding exactly the fields given; a nil argument leaves that field out,
    /// which is what a hand-edited or truncated one looks like. The field names are spelled here
    /// rather than imported from `LocaleState`, because they are the shape on disk: a rename is a
    /// new schema and should turn this red instead of following along.
    private func seed(installId: String?, epoch: Any?, tag: String?) {
        var envelope: [String: Any] = [:]
        if let installId { envelope["installId"] = installId }
        if let epoch { envelope["epoch"] = epoch }
        if let tag { envelope["tag"] = tag }
        defaults.set(envelope, forKey: LocaleState.publicationKey)
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
        seed(installId: fresh.installId, epoch: nil, tag: nil)
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

    /// **⑤ No reader ever observes a triple that was never published.**
    ///
    /// A single-writer rule does not make readers atomic (round 9 review). D49 removed the race
    /// between two *writers*; this is a *reader* seeing one writer's half-finished sequence, which
    /// is a different axis and was not covered by it.
    ///
    /// The reader here is the production one: `publish(role: .headless)` is what a second process
    /// hands the extension, and it reads the same domain the GUI writes. The interleaving is
    /// enumerated rather than raced — the hook reads after **every** write, so each intermediate
    /// state the writer leaves behind is inspected; a race that happened to pass would prove
    /// nothing. Nothing here names a storage key, so the case survives a change of schema.
    func testNoReaderObservesMixedSnapshot() throws {
        let watched = try XCTUnwrap(WriteObservingDefaults(suiteName: suiteName))
        let minted = try XCTUnwrap(
            LocaleState.publish(resolved: "ko", defaults: watched, role: .interactive)
        )

        var observed: [LocalePublication?] = []
        watched.afterWrite = { [unowned watched] in
            observed.append(LocaleState.publish(resolved: "ja", defaults: watched, role: .headless))
        }
        let advanced = try XCTUnwrap(
            LocaleState.publish(resolved: "ja", defaults: watched, role: .interactive)
        )
        watched.afterWrite = nil

        XCTAssertEqual(advanced.installId, minted.installId)
        XCTAssertEqual(advanced.snapshot, LocaleSnapshot(tag: "ja", epoch: 1))
        for (step, seen) in observed.enumerated() {
            XCTAssertTrue(
                seen == minted || seen == advanced,
                "after write \(step) a reader saw \(String(describing: seen)), which was never published"
            )
        }
        XCTAssertTrue(observed.contains(advanced), "no read ran at all — the write hook never fired")
    }

    /// **⑥ The three-key state an earlier build wrote is not a publication.**
    ///
    /// Nothing is migrated out of it: a triple written in three steps cannot be shown to have been
    /// committed as one, so reading it would mean trusting exactly the value this change exists to
    /// stop trusting. It is ignored, which lands on the state D51 already defines — no readable
    /// snapshot, so the next publication mints an identity, and the extension takes an unfamiliar
    /// `installId` unconditionally (D32) rather than comparing epochs with it. Until then the
    /// headless role publishes nothing at all, which is no input to the extension rather than a
    /// wrong one.
    ///
    /// "The next publication" is today the next language change: `LocaleState.publish` has one
    /// caller, `Settings.language`'s setter. Item 15 is what makes a launch publish.
    ///
    /// The deletion also has an order to it: at no point may the stale triple sit **next to** a new
    /// envelope. That pair is two builds each holding a publication the other's `installId` makes
    /// unfamiliar, and an unfamiliar one is accepted unconditionally (D32) — they would trade the
    /// language back and forth. Interrupted the other way there is nothing at all, which is the
    /// state a mint recovers from.
    func testAThreeKeySnapshotFromAnEarlierBuildIsNotAPublication() throws {
        let legacy = ["localeInstallId": "old-identity", "localeEpoch": 3, "localePublishedTag": "ko"] as [String: Any]
        let watched = try XCTUnwrap(WriteObservingDefaults(suiteName: suiteName))
        for (key, value) in legacy { watched.set(value, forKey: key) }

        XCTAssertNil(
            LocaleState.publish(resolved: "ko", defaults: watched, role: .headless),
            "the old three keys were read as something to republish"
        )

        var observations: [(envelope: Bool, stale: Bool)] = []
        watched.afterWrite = { [unowned watched] in
            observations.append((
                envelope: watched.dictionary(forKey: LocaleState.publicationKey) != nil,
                stale: LocaleState.legacyKeys.contains { watched.object(forKey: $0) != nil }
            ))
        }
        let minted = try XCTUnwrap(LocaleState.publish(resolved: "ja", defaults: watched, role: .interactive))
        watched.afterWrite = nil

        XCTAssertNotEqual(minted.installId, "old-identity")
        XCTAssertEqual(minted.snapshot, LocaleSnapshot(tag: "ja", epoch: 0))
        XCTAssertEqual(watched.dictionary(forKey: LocaleState.publicationKey)?["installId"] as? String, minted.installId)
        XCTAssertFalse(observations.isEmpty, "no write was observed at all — the hook never fired")
        XCTAssertNil(
            observations.firstIndex(where: { $0.envelope && $0.stale }),
            "a new envelope and the stale triple were on disk at the same time"
        )

        // And they are gone, so the build that still reads them cannot publish the stale triple
        for key in legacy.keys {
            XCTAssertNil(watched.object(forKey: key), key)
        }
        XCTAssertEqual(Set(LocaleState.legacyKeys), Set(legacy.keys), "the deleted set is not the old schema")
    }
}

/// A `UserDefaults` that lets a test look at the domain **between** a writer's steps.
///
/// Every override calls `super` first, so the closure runs once each write has landed and sees
/// exactly what another process reading at that moment would.
///
/// All three entry points carry the hook even though the measured routing has two of them landing
/// in the third: `set(_:forKey:)` for `Int` and `removeObject(forKey:)` both call the `Any?` form
/// underneath, so one write is observed twice and none is missed (`<scratchpad>/rA_spy_probe.swift`
/// and `rA_spy_dict_probe.swift` — one dictionary write is one call, one removal is two). Relying
/// on that routing would be relying on something whose failure mode is silence, so the hooks stay
/// on all three and the cases assert that a read happened at all.
private final class WriteObservingDefaults: UserDefaults {
    var afterWrite: (() -> Void)?

    override func set(_ value: Any?, forKey defaultName: String) {
        super.set(value, forKey: defaultName)
        afterWrite?()
    }

    override func set(_ value: Int, forKey defaultName: String) {
        super.set(value, forKey: defaultName)
        afterWrite?()
    }

    override func removeObject(forKey defaultName: String) {
        super.removeObject(forKey: defaultName)
        afterWrite?()
    }
}
