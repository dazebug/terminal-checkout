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

    /// `SupportedLocale` has no literal form — that is the whole point of the type — so a case that
    /// means "publish Korean" says it once here instead of unwrapping in every line.
    private func locale(
        _ tag: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> SupportedLocale {
        try XCTUnwrap(SupportedLocale(tag), "\(tag) is not a locale we ship", file: file, line: line)
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
        let fresh = try XCTUnwrap(LocaleState.publish(resolved: try locale("ko"), defaults: defaults, role: .interactive))
        XCTAssertEqual(fresh.snapshot, LocaleSnapshot(tag: "ko", epoch: 0))
        XCTAssertFalse(fresh.installId.isEmpty)

        // The same starting point, except that an identity survived
        seed(installId: fresh.installId, epoch: nil, tag: nil)
        let after = try XCTUnwrap(LocaleState.publish(resolved: try locale("ko"), defaults: defaults, role: .interactive))
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
                LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive), label
            )
            XCTAssertNotEqual(published.installId, "old-identity", label)
            XCTAssertEqual(published.snapshot, LocaleSnapshot(tag: "ja", epoch: 0), label)
            XCTAssertEqual(storedTriple().0, published.installId, label)
        }

        // A tag we do not ship is malformed too — it cannot be what we last published
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "old-identity", epoch: 4, tag: "fr")
        let published = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive))
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

        let headless = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .headless))
        XCTAssertEqual(headless.snapshot, LocaleSnapshot(tag: "ko", epoch: 3), "the headless server invented a revision")
        XCTAssertEqual(storedTriple().0, before.0)
        XCTAssertEqual(storedTriple().1 as? Int, before.1 as? Int)
        XCTAssertEqual(storedTriple().2, before.2, "the headless server wrote")

        let gui = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive))
        XCTAssertEqual(gui.snapshot, LocaleSnapshot(tag: "ja", epoch: 4))
        XCTAssertEqual(gui.installId, "install-a")
        // The pair the extension orders by: no epoch ever carries two different tags
        XCTAssertNotEqual(headless.snapshot.epoch, gui.snapshot.epoch)

        // And with nothing stored, the headless server publishes nothing at all rather than
        // minting an identity the GUI would then disagree with
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        XCTAssertNil(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .headless))
        XCTAssertNil(storedTriple().0)
    }

    /// **④ A corrupted epoch cannot trap, and cannot make publication non-monotonic.**
    ///
    /// `Int.max` is the trap: `epoch + 1` on it is a crash in Swift, not a wrap. The rest is the
    /// ordering promise — for one identity the epoch never goes down, whatever was in the plist.
    func testACorruptedEpochCannotTrapOrPublishNonMonotonically() throws {
        seed(installId: "install-a", epoch: Int.max, tag: "ko")
        let recovered = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive))
        XCTAssertEqual(recovered.snapshot.epoch, 0)
        XCTAssertNotEqual(recovered.installId, "install-a", "a revision that cannot advance kept its identity")

        // Monotonic under one identity: republishing the same locale stands still, a change moves
        // up by one, and returning to an earlier locale still moves up
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "install-b", epoch: 7, tag: "ko")
        var epochs: [Int] = []
        for resolved in ["ko", "ja", "ko", "zh-Hant"] {
            let published = try XCTUnwrap(
                LocaleState.publish(resolved: try locale(resolved), defaults: defaults, role: .interactive)
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
        let again = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive))
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
            LocaleState.publish(resolved: try locale("ko"), defaults: watched, role: .interactive)
        )

        var observed: [LocalePublication?] = []
        let japanese = try locale("ja")
        watched.afterWrite = { [unowned watched] in
            observed.append(LocaleState.publish(resolved: japanese, defaults: watched, role: .headless))
        }
        let advanced = try XCTUnwrap(
            LocaleState.publish(resolved: try locale("ja"), defaults: watched, role: .interactive)
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
            LocaleState.publish(resolved: try locale("ko"), defaults: watched, role: .headless),
            "the old three keys were read as something to republish"
        )

        var observations: [(envelope: Bool, stale: Bool)] = []
        watched.afterWrite = { [unowned watched] in
            observations.append((
                envelope: watched.dictionary(forKey: LocaleState.publicationKey) != nil,
                stale: LocaleState.legacyKeys.contains { watched.object(forKey: $0) != nil }
            ))
        }
        let minted = try XCTUnwrap(LocaleState.publish(resolved: try locale("ja"), defaults: watched, role: .interactive))
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

    /// **⑦ A tag we do not ship cannot be published** (round 10 review).
    ///
    /// The mint path used to persist whatever string it was handed, so `publish(resolved: "fr", …)`
    /// wrote a tag nothing can render, and the mistake surfaced only on the next read — which then
    /// threw the identity away to recover from a value we had written ourselves. The check now
    /// happens where the value is made: `SupportedLocale` has no other way in.
    ///
    /// The case cannot pass an unsupported tag to `publish` at all — that is the point — so what it
    /// proves is the two halves that remain provable: the type refuses, and the value production
    /// path in front of it (`resolvedLocale`) answers with a shipped tag even when the stored
    /// preference is a corrupt one.
    func testPublishRejectsUnsupportedResolvedTag() throws {
        XCTAssertNil(SupportedLocale("fr"), "a tag we ship no catalogue for was accepted")
        XCTAssertNil(SupportedLocale(""))
        XCTAssertNil(SupportedLocale(automaticLocalePreference), "`auto` is a preference, not a tag")
        XCTAssertEqual(SupportedLocale("zh-Hant")?.tag, "zh-Hant")

        defaults.set(42, forKey: languagePreferenceKey)
        let resolved = AppLocalization.resolvedLocale(defaults: defaults, systemPreferred: ["fr-CA"])
        XCTAssertTrue(supportedLocales.contains(resolved.tag), "the resolver produced \(resolved.tag)")

        let published = try XCTUnwrap(
            LocaleState.publish(resolved: resolved, defaults: defaults, role: .interactive)
        )
        XCTAssertTrue(supportedLocales.contains(published.snapshot.tag))
        XCTAssertEqual(storedTriple().2, published.snapshot.tag, "what was stored is not what was returned")
    }

    /// **⑧ An identity one step from `Int.max` rotates instead of publishing it.**
    ///
    /// `stored` accepts `Int.max - 1`, and advancing it produced `Int.max` — a snapshot the very
    /// next read calls malformed (round 10 review). Writing it and then refusing to read it is the
    /// worst of both: the extension is handed an epoch, and the app has thrown the identity away by
    /// the time anyone looks. The rotation happens before that value exists.
    func testEpochAtMaxMinusOneCannotPublishIntMax() throws {
        seed(installId: "install-a", epoch: Int.max - 1, tag: "ko")
        let rotated = try XCTUnwrap(
            LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive)
        )
        XCTAssertNotEqual(rotated.installId, "install-a", "the exhausted identity was kept")
        XCTAssertEqual(rotated.snapshot, LocaleSnapshot(tag: "ja", epoch: 0))
        XCTAssertEqual(storedTriple().1 as? Int, 0, "an epoch was stored that cannot be read back")

        // One below that still advances normally — the rotation is a boundary, not a ceiling that
        // swallowed the last usable revision
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "install-b", epoch: Int.max - 2, tag: "ko")
        let advanced = try XCTUnwrap(
            LocaleState.publish(resolved: try locale("ja"), defaults: defaults, role: .interactive)
        )
        XCTAssertEqual(advanced.installId, "install-b")
        XCTAssertEqual(advanced.snapshot.epoch, Int.max - 1)
    }

    /// **⑨ A valid envelope beside stale legacy keys still loses the legacy keys.**
    ///
    /// The cleanup used to live in `write`, which never runs in this state: the envelope is valid,
    /// so a republication of the same tag returns it unchanged and writes nothing — and the old
    /// keys stayed for good (round 10 review). Case ⑥ covers the legacy-only state and would have
    /// gone on passing.
    func testValidEnvelopeAlsoRemovesLegacyKeys() throws {
        seed(installId: "install-a", epoch: 3, tag: "ko")
        for (key, value) in ["localeInstallId": "old", "localeEpoch": 1, "localePublishedTag": "ja"] as [String: Any] {
            defaults.set(value, forKey: key)
        }

        let republished = try XCTUnwrap(
            LocaleState.publish(resolved: try locale("ko"), defaults: defaults, role: .interactive)
        )
        XCTAssertEqual(republished.snapshot, LocaleSnapshot(tag: "ko", epoch: 3), "the envelope moved")
        for key in LocaleState.legacyKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }

        // The headless role does not clean, for the same reason it does not write (D49)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        seed(installId: "install-a", epoch: 3, tag: "ko")
        defaults.set("old", forKey: "localeInstallId")
        XCTAssertNotNil(LocaleState.publish(resolved: try locale("ko"), defaults: defaults, role: .headless))
        XCTAssertNotNil(defaults.object(forKey: "localeInstallId"), "the headless role wrote")
    }

    /// The invariant `SupportedLocale.fallback` is built on: the language every unanswerable
    /// question lands in is one we actually ship. Without this the type could hand out a tag with
    /// no catalogue behind it, which is the defect it exists to prevent.
    func testTheFallbackIsALocaleWeShip() {
        XCTAssertTrue(supportedLocales.contains(fallbackLocale))
        XCTAssertEqual(SupportedLocale.fallback.tag, fallbackLocale)
        XCTAssertEqual(SupportedLocale(fallbackLocale), SupportedLocale.fallback)
    }

    /// **A preference that is not a string reads as itself, not as `auto`** (round 8 review).
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

    /// **⑩ Two interactive writers cannot publish different tags at the same epoch** — and this
    /// time by construction rather than by an enum argument (round 10 review).
    ///
    /// Item 15 is where the second writer arrives: a launch publisher stands beside the picker. Two
    /// callers reading epoch 3 and both writing epoch 4 with different tags is a state the extension
    /// cannot recover from — its rule is "same install, accept only a strictly greater epoch", so it
    /// keeps whichever landed first and drops the other for good.
    ///
    /// Both production writers are on the main queue, which is a second reason they cannot
    /// interleave; the case drives them concurrently on purpose, because that fact belongs to AppKit
    /// and not to this contract.
    ///
    /// **The interleaving is arranged, not hoped for.** Simply running two writers concurrently
    /// proved nothing — measured: with the lock removed, four concurrent writers still produced four
    /// distinct epochs on three runs out of three, because the read-modify-write is microseconds
    /// long and nothing made the threads meet inside it. So the store holds the first reader at the
    /// exact moment that matters, until the second has read the same epoch or half a second passes.
    /// Without the lock that produces the collision every time; with it, the second reader cannot
    /// even start, the wait times out, and the two publications come out one after the other.
    func testTwoInteractiveWritersCannotPublishDifferentTagsAtTheSameEpoch() throws {
        let coordinating = try XCTUnwrap(ReadCoordinatingDefaults(suiteName: suiteName))
        seed(installId: "install-a", epoch: 3, tag: "en")
        let tags = try ["ko", "ja"].map { try locale($0) }
        let box = NSLock()
        var published: [LocalePublication] = []
        coordinating.coordinateReads = true

        DispatchQueue.concurrentPerform(iterations: tags.count) { index in
            if let result = LocaleState.publish(
                resolved: tags[index], defaults: coordinating, role: .interactive
            ) {
                box.lock()
                published.append(result)
                box.unlock()
            }
        }
        coordinating.coordinateReads = false

        XCTAssertEqual(published.count, tags.count)
        XCTAssertEqual(Set(published.map(\.installId)), ["install-a"], "an identity was minted")
        // The contract itself: an epoch identifies one tag. Distinct epochs are how it is kept here,
        // but the sentence the extension depends on is this one.
        let tagsByEpoch = Dictionary(grouping: published, by: { $0.snapshot.epoch })
            .mapValues { Set($0.map(\.snapshot.tag)) }
        for (epoch, tagsAtEpoch) in tagsByEpoch {
            XCTAssertEqual(tagsAtEpoch.count, 1, "epoch \(epoch) carries \(tagsAtEpoch)")
        }
        XCTAssertEqual(Set(published.map(\.snapshot.epoch)), [4, 5])

        // What is on disk is the last of them, whichever order they ran in
        let last = try XCTUnwrap(published.max(by: { $0.snapshot.epoch < $1.snapshot.epoch }))
        XCTAssertEqual(storedTriple().1 as? Int, last.snapshot.epoch)
        XCTAssertEqual(storedTriple().2, last.snapshot.tag)
    }

    /// **The launch publisher publishes what the window draws, not what is stored.** The two answers
    /// differ on exactly one input — a preference that is not a string — and publishing the stored
    /// one would tell the extension a language nothing renders in (round 10 review).
    ///
    /// The resolution moved to the caller in round 14 so that publishing could wait for the socket
    /// (see the lint below), so these cases resolve the way `main.swift` does and hand the answer
    /// over. What is still being pinned is the pair: resolved, not stored.
    func testTheLaunchPublisherPublishesTheResolvedLocale() throws {
        func launch(_ system: [String]) {
            Settings.publishLocaleAtLaunch(
                resolved: AppLocalization.resolvedLocale(defaults: defaults, systemPreferred: system),
                defaults: defaults
            )
        }
        defaults.set(42, forKey: languagePreferenceKey)
        launch(["ko-KR"])

        XCTAssertEqual(storedTriple().2, fallbackLocale, "the launch publisher stored the preference itself")
        XCTAssertNotEqual(Settings.languagePreference(in: defaults), fallbackLocale, "the fixture proves nothing")

        // An `auto` user whose system language moved while the app was not running: the launch
        // publisher is what makes that reach the extension at all (D48)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)
        launch(["ko-KR"])
        XCTAssertEqual(storedTriple().2, "ko")
        launch(["ja-JP"])
        XCTAssertEqual(storedTriple().2, "ja")
        XCTAssertEqual(storedTriple().1 as? Int, 1, "the revision did not move with the system language")
    }

    /// **Only the instance that owns the socket publishes** (round 14 review, P1).
    ///
    /// The single-writer rule was enforced with an `NSLock`, which is process-local and cannot see a
    /// second process at all — and `main.swift` published *before* `HostServer.start()` decided who
    /// owns the path. Two GUI instances are not hypothetical: the language restart relaunches with
    /// `open -n`. Both would publish under the same install id and epoch with different tags, and
    /// the extension's rule ("same install, strictly greater epoch") cannot order that pair.
    ///
    /// Read from the source because the alternative is standing up two GUI processes: what is pinned
    /// is that the publication sits inside the `do` that follows a successful `start()`, and that
    /// `main.swift` resolves without publishing.
    func testOnlyTheInstanceThatOwnsTheSocketPublishes() throws {
        let main = try String(contentsOfFile: Self.appSource("main.swift"), encoding: .utf8)
        XCTAssertFalse(
            main.contains("Settings.publishLocaleAtLaunch("),
            "main.swift publishes again — a second instance reaches that line before the bind decides"
        )
        XCTAssertTrue(
            main.contains("let launchLocale = AppLocalization.resolvedLocale()"),
            "main.swift no longer resolves the launch language next to the AppleLanguages write"
        )

        let delegate = try String(contentsOfFile: Self.appSource("AppDelegate.swift"), encoding: .utf8)
        let start = try XCTUnwrap(delegate.range(of: "try server.start()")).upperBound
        let publish = try XCTUnwrap(
            delegate.range(of: "Settings.publishLocaleAtLaunch(resolved: launchLocale)"),
            "the delegate no longer publishes the launch locale"
        ).lowerBound
        XCTAssertLessThan(start, publish, "the locale is published before the socket is bound")
        let catchStart = try XCTUnwrap(delegate.range(of: "} catch {", range: start..<delegate.endIndex)).lowerBound
        XCTAssertLessThan(publish, catchStart, "the publication is outside the branch that owns the socket")
    }

    /// **A window that does not own the socket must not publish** (round 15 review, P0).
    ///
    /// Round 14 bound the launch publisher to the bind and left the picker unbound, while the
    /// comment on `startServer` declared the rule for both. A second GUI instance has a setup window
    /// too — that is what `open -n` gives you, and the language restart uses it — so a picker there
    /// moved the shared publication while the owner's window and the extension stayed where they
    /// were.
    ///
    /// The preference itself is still written: it is an ordinary shared user setting, last writer
    /// wins. What must not move without ownership is the generation the extension orders by.
    func testOnlyTheSocketOwnerPublishesALanguageChange() throws {
        defaults.set(automaticLocalePreference, forKey: languagePreferenceKey)
        XCTAssertTrue(
            Settings.setLanguage("ja", defaults: defaults, mayPublish: true, systemPreferred: ["ko-KR"]),
            "the owner did not publish"
        )
        let owned = storedTriple()
        XCTAssertEqual(owned.2, "ja")

        XCTAssertFalse(
            Settings.setLanguage("ko", defaults: defaults, mayPublish: false, systemPreferred: ["ko-KR"]),
            "a non-owner published a language change"
        )
        XCTAssertEqual(storedTriple().2, owned.2, "a non-owner moved the published locale")
        XCTAssertEqual(storedTriple().1 as? Int, owned.1 as? Int, "a non-owner moved the generation")
        XCTAssertEqual(
            Settings.languagePreference(in: defaults), "ko",
            "the preference is a shared user setting and should still have been written"
        )
    }

    /// Both writers ask the same question, and the window that cannot publish says so rather than
    /// offering a control that does nothing. Read from the source: the picker's branch ends in
    /// `NSApp.terminate` and a second instance needs a second process.
    func testBothWritersAskTheSameQuestionAndTheWindowSaysSo() throws {
        let settings = try String(contentsOfFile: Self.appSource("Settings.swift"), encoding: .utf8)
        XCTAssertTrue(
            settings.contains("guard mayPublish else {"),
            "the picker's writer no longer asks whether it may publish"
        )
        let delegate = try String(contentsOfFile: Self.appSource("AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(
            delegate.contains("LocalePublicationRight.recordSocketOwnership()"),
            "nothing records who owns the socket"
        )
        let window = try String(contentsOfFile: Self.appSource("SetupWindowController.swift"), encoding: .utf8)
        XCTAssertTrue(
            window.contains("languagePopUp.isEnabled = mayPublish"),
            "a window that cannot publish still offers the picker"
        )
        XCTAssertTrue(
            window.contains("localized(\"app.language.notOwner\")"),
            "a window that cannot publish does not say why"
        )
    }

    private static func appSource(_ name: String) -> String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocalePublicationTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/\(name)")
            .path
    }

    /// And what the picker does with that third state. All three rows are enumerated here rather
    /// than driven through the window, which would mean writing the preference into the domain the
    /// installed app uses.
    func testThePickerPointsAtTheLanguageBeingDrawn() {
        let entries: [String?] = [automaticLocalePreference] + supportedLocales

        XCTAssertEqual(languagePickerIndex(stored: "ja", drawn: "ja", entries: entries),
                       entries.firstIndex(of: "ja"))
        XCTAssertEqual(languagePickerIndex(stored: automaticLocalePreference, drawn: "ko", entries: entries), 0)
        // The third state: nothing matches the stored value, so the picker shows what is on screen
        XCTAssertEqual(languagePickerIndex(stored: "42", drawn: fallbackLocale, entries: entries),
                       entries.firstIndex(of: fallbackLocale))
        // And when even that is unknown there is nowhere else to point
        XCTAssertEqual(languagePickerIndex(stored: "42", drawn: "fr", entries: entries), 0)
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
/// A `UserDefaults` that holds the **first** reader inside the read, until a second one has read the
/// same value or half a second has passed.
///
/// It exists because the race it arranges cannot be reached by asking for it: four writers running
/// concurrently against an unlocked publish produced four distinct epochs on every attempt, since
/// the window between the read and the write is microseconds wide. Holding the first reader open is
/// what makes "both saw epoch 3" a fact of the test rather than a hope.
///
/// The wait has a timeout because the correct implementation is the one where the second reader
/// **never arrives** — it is still waiting for the write lock — and a test that deadlocked on
/// correct code would be worse than one that proves nothing.
private final class ReadCoordinatingDefaults: UserDefaults {
    var coordinateReads = false
    private let bookkeeping = NSLock()
    private var readers = 0
    private let secondReaderArrived = DispatchSemaphore(value: 0)

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        let value = super.dictionary(forKey: defaultName)
        guard coordinateReads else { return value }
        bookkeeping.lock()
        readers += 1
        let order = readers
        bookkeeping.unlock()
        if order == 1 {
            _ = secondReaderArrived.wait(timeout: .now() + 0.5)
        } else if order == 2 {
            secondReaderArrived.signal()
        }
        return value
    }
}

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
