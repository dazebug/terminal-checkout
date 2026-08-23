import Core
import Darwin
import XCTest
@testable import App

/// **The door opens after the answer exists** (round 17 review).
///
/// `start` used to arm the accept loop on its way out and hand the caller a right to publish with;
/// the caller published afterwards. Between those two points the server was answering, and what it
/// answered with was whatever this machine published the last time it ran — so an `auto` user whose
/// system language changed while the app was down got the *old* language in the extension's opening
/// question, cached it, and had nothing to make them ask again. The window is not a rare
/// interleaving: the relay launches the app when nothing answers on the path and then retries the
/// connection, so it is standing at the socket waiting for that `listen`.
///
/// **Why the case has to hold the publication open.** The two statements were microseconds apart, so
/// a case that merely raced them would pass under the defect nearly always and prove nothing either
/// way. Holding the write is the only way to make the question — *can anything be answered while the
/// launch has not said what the language is* — answerable at all. The hold is on the store, not on
/// the server: the same `UserDefaults` subclass trick `LocalePublicationTests` uses to enumerate what
/// a reader can see mid-write, one step earlier.
final class HostServerStartupPublicationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: HoldingDefaults!
    private var directory = ""
    private var path = ""
    private var server: HostServer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(HoldingDefaults(suiteName: suiteName))
        // Short by hand: `sockaddr_un` holds 104 bytes and the runner's temporary directory spends
        // most of them on its own
        directory = "/tmp/tc-boot-\(UUID().uuidString.prefix(8))"
        path = directory + "/s.sock"
        server = HostServer(socketPath: path, defaults: defaults)
    }

    override func tearDown() {
        defaults.beforeWritingThePublication = nil
        server.stop()
        try? FileManager.default.removeItem(atPath: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Polls rather than sleeps a fixed amount, so a slow machine costs time instead of a failure.
    private func waits(for condition: () -> Bool, upTo seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    /// **Nothing is answered before this launch has said what the language is.**
    ///
    /// The store already holds the previous launch's publication, in a different language. If a
    /// request can be answered while the new one is still being written, the extension caches `ko`
    /// with an epoch it will then refuse to move for — which is this feature failing in the exact
    /// scenario it was built for.
    func testNoRequestIsAnsweredBeforeTheLaunchPublicationIsCommitted() throws {
        defaults.set(
            ["installId": "install-before", "epoch": 3, "tag": "ko"],
            forKey: LocaleState.publicationKey
        )

        let writing = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defaults.beforeWritingThePublication = {
            writing.signal()
            release.wait()
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(["query": localeQueryName], at: path, givingUp: 10)

        let japanese = try XCTUnwrap(SupportedLocale("ja"))
        let bound = DispatchSemaphore(value: 0)
        let start = ThrownError()
        DispatchQueue.global().async { [server] in
            do { try server?.start(announcing: .publish(japanese)) } catch { start.record(error) }
            bound.signal()
        }

        XCTAssertEqual(
            writing.wait(timeout: .now() + 10), .success,
            "the launch never got as far as writing a publication"
        )
        // Checked rather than assumed: with nobody through the door the case would pass for the
        // wrong reason. The socket is listening by now, so the relay is connected and its request
        // is written — the only thing still undecided is what this launch publishes
        XCTAssertTrue(
            waits(for: { relay.asked }, upTo: 5),
            "the relay never reached the socket, so nothing was on offer to answer"
        )
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNil(
            relay.answer,
            "a request was answered while the launch publication was still being written"
        )

        release.signal()
        XCTAssertEqual(bound.wait(timeout: .now() + 10), .success, "start never returned")
        XCTAssertNil(start.error)

        XCTAssertTrue(waits(for: { relay.answer != nil }, upTo: 10), "the request was never answered")
        let answer = try XCTUnwrap(relay.answer)
        XCTAssertEqual(answer["success"] as? Bool, true)
        XCTAssertEqual(
            answer[localeResponseKey] as? String, "ja",
            "the first answer carried the language of the launch before this one"
        )
        XCTAssertEqual(answer[localeEpochResponseKey] as? Int, 4, "the generation the extension orders by did not move")
        XCTAssertEqual(answer[localeInstallIdResponseKey] as? String, "install-before")
        XCTAssertEqual(
            defaults.dictionary(forKey: LocaleState.publicationKey)?["tag"] as? String, "ja",
            "the answer was not the thing that was committed"
        )
    }

    /// **The headless server answers too, and announcing nothing is how it says what it is.**
    ///
    /// It draws nothing and has no picker, so inventing a revision there is what D49 rules out — but
    /// it still has to serve, which is the constraint any arming mechanism has to satisfy. What it
    /// hands back is the GUI's last publication, unchanged, and the store is left as it was found.
    func testTheHeadlessServerAnswersAndPublishesNothing() throws {
        defaults.set(
            ["installId": "install-before", "epoch": 3, "tag": "ko"],
            forKey: LocaleState.publicationKey
        )
        defaults.beforeWritingThePublication = {
            XCTFail("the headless announcement wrote a publication")
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(["query": localeQueryName], at: path, givingUp: 10)
        try server.start(announcing: .nothing)

        XCTAssertTrue(waits(for: { relay.answer != nil }, upTo: 10), "the headless server answered nothing")
        let answer = try XCTUnwrap(relay.answer)
        XCTAssertEqual(answer[localeResponseKey] as? String, "ko")
        XCTAssertEqual(answer[localeEpochResponseKey] as? Int, 3, "the headless server moved the generation")
        XCTAssertEqual(answer[localeInstallIdResponseKey] as? String, "install-before")
    }
}

/// A store that can be stopped in the middle of committing a publication.
///
/// The pause is **before** `super.set`, so while it is held the new envelope is provably not on
/// disk — pausing after the write would leave the value already committed and the case would be
/// asking a question that had already been answered.
private final class HoldingDefaults: UserDefaults {
    var beforeWritingThePublication: (() -> Void)?

    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName == LocaleState.publicationKey { beforeWritingThePublication?() }
        super.set(value, forKey: defaultName)
    }
}

/// What the relay does: keep trying the path until something is there, send one request, and wait
/// for the answer. Its two facts are read from the test's thread, so they are taken under a lock —
/// "no answer yet" is an assertion here, and an assertion on a value nothing orders proves nothing.
private final class RelayAtTheDoor {
    private let lock = NSLock()
    private var asked_ = false
    private var answer_: [String: Any]?

    var asked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return asked_
    }

    var answer: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return answer_
    }

    func connectAndAsk(_ request: [String: Any], at path: String, givingUp seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        Thread.detachNewThread { [self] in
            var connection: Int32?
            while connection == nil, Date() < deadline {
                connection = connectToUnixSocket(path: path)
                if connection == nil { usleep(2_000) }
            }
            guard let connection else { return }
            defer { close(connection) }
            guard let payload = try? JSONSerialization.data(withJSONObject: request),
                  writeFramedMessage(payload, toFD: connection)
            else { return }
            lock.lock()
            asked_ = true
            lock.unlock()

            guard let data = readFramedMessage(fromFD: connection),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return }
            lock.lock()
            answer_ = json
            lock.unlock()
        }
    }
}

/// An error thrown on another thread, read on this one.
private final class ThrownError {
    private let lock = NSLock()
    private var value: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record(_ error: Error) {
        lock.lock()
        value = error
        lock.unlock()
    }
}
