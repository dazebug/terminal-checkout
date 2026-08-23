import Core
import Darwin
import XCTest
@testable import App

/// **What a server instance owns, and for how long** (round 16 review).
///
/// The socket path is a name, and a name can come to mean something else. Two facts were hanging off
/// it: teardown deleted whatever the name pointed at, and the right to publish a locale was a
/// process-global boolean that outlived the socket it stood for. Together they produce a process that
/// believes it owns this machine while the relay is reaching a different one — the extension takes
/// the generation that process publishes, and the app answering the button never sees it.
///
/// These cases bind real sockets in a short-lived directory, because that is the only way to have the
/// thing being tested: the identity of a file and a right that only a successful `bind` produces.
final class HostServerOwnershipTests: XCTestCase {
    private var directory = ""
    private var path = ""
    private var canonical: CanonicalSocketOverride?

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Short by hand — `sockaddr_un` holds 104 bytes and the runner's temporary directory is
        // most of that on its own
        directory = "/tmp/tc-own-\(UUID().uuidString.prefix(8))"
        path = directory + "/s.sock"
        // What `current` answers and what may publish are both about **the** socket now, so the one
        // these cases bind has to be it
        canonical = nil
        canonical = CanonicalSocketOverride(path)
    }

    override func tearDown() {
        canonical = nil
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    /// Which file the name points at, so a case can say "still the same one" rather than "still
    /// something".
    private func identity(_ path: String) -> (dev_t, ino_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    /// A listening socket at that path that is **not** the server's — what a second instance leaves
    /// behind when it takes the path over.
    private func bindAnotherSocket(at path: String) throws -> Int32 {
        var address = try XCTUnwrap(makeUnixSockaddr(path))
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        unlink(path)
        // `Darwin.bind`, spelled out: unqualified, Swift finds `XCTestCase`'s own `bind` method
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0, "the replacement socket could not be bound")
        XCTAssertEqual(listen(fd, 4), 0)
        return fd
    }

    /// **Teardown deletes by identity, not by name.**
    ///
    /// The order is one a language restart can produce: this instance stops listening, the instance
    /// it relaunched binds the same path, and only then does the first one get to its cleanup. Going
    /// by the name deletes the socket the relay is now talking to — the new process keeps running,
    /// keeps believing it owns the machine, and every button press fails to connect.
    func testStopRemovesOnlyTheSocketItBound() throws {
        let server = HostServer(socketPath: path)
        try server.start(announcing: .nothing)
        let ours = try XCTUnwrap(identity(path))

        let replacement = try bindAnotherSocket(at: path)
        defer { close(replacement) }
        let theirs = try XCTUnwrap(identity(path))
        XCTAssertNotEqual(ours.1, theirs.1, "the replacement reused the same file — the case proves nothing")

        server.stop()

        XCTAssertEqual(
            identity(path)?.1, theirs.1,
            "stopping deleted the socket another instance had bound in the meantime"
        )
        let connection = try XCTUnwrap(
            connectToUnixSocket(path: path), "the surviving owner is no longer reachable"
        )
        close(connection)
    }

    /// And an instance that never bound owns nothing to take down. This is the one a second GUI
    /// instance really walks: `start()` throws `alreadyRunning`, the window stays up, the user quits
    /// it — and its teardown used to remove the running instance's socket by name.
    func testAnInstanceThatLostTheBindRemovesNothing() throws {
        let owner = HostServer(socketPath: path)
        try owner.start(announcing: .nothing)
        let ours = try XCTUnwrap(identity(path))

        let second = HostServer(socketPath: path)
        XCTAssertThrowsError(try second.start(announcing: .nothing)) { error in
            guard case HostServer.ServerError.alreadyRunning = error else {
                return XCTFail("the second instance failed for another reason: \(error)")
            }
        }
        second.stop()

        XCTAssertEqual(identity(path)?.1, ours.1, "an instance that never bound deleted the owner's socket")
        let connection = try XCTUnwrap(connectToUnixSocket(path: path), "the owner is no longer reachable")
        close(connection)
        owner.stop()
        XCTAssertNil(identity(path), "the owner left its socket behind")
    }

    /// **The right to publish lasts exactly as long as the socket.** It used to be a process-global
    /// boolean, so a process that had stopped listening went on believing it could move the
    /// generation the extension orders by.
    func testThePublicationRightIsGivenUpWithTheSocket() throws {
        let server = HostServer(socketPath: path)
        let right = try server.start(announcing: .nothing)
        XCTAssertTrue(right.isHeld)
        XCTAssertTrue(LocalePublicationRight.current === right, "the bind did not record what it produced")

        server.stop()
        XCTAssertFalse(right.isHeld, "the right outlived its socket")
        XCTAssertNil(LocalePublicationRight.current)
        // What used to be asserted here was `mayWrite` — a *question*, which is the shape round 18
        // took away. The thing that decides is that the body does not run
        var ran = false
        XCTAssertNil(right.whileHeld { ran = true }, "a right that has been given up still runs a write")
        XCTAssertFalse(ran, "the body ran under a right that had been given up")
    }

    /// **A publication cannot land after the socket is gone** (round 18 review, item 50a).
    ///
    /// The check and the write used to be under different locks — `role.mayWrite` asked the right's,
    /// the write took its own — so `stop()` could relinquish in between and the write would land
    /// afterwards. That is not "one stale write": the publication is a read-modify-write against a
    /// shared `UserDefaults`, and the process that loses the socket in a language restart is exactly
    /// the process that can still be inside it, so the value lands at the **new** owner's epoch
    /// carrying the **old** owner's language, and the extension is then required to ignore every
    /// later correction under that identity.
    ///
    /// The case holds the write open and asks whether a teardown can get through it. It cannot:
    /// giving the right up waits for the write to finish, which is what "one critical section"
    /// means. Under the old shape `isHeld` goes false while the write is still in flight.
    func testATeardownCannotGetBetweenTheCheckAndTheWrite() throws {
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let store = try XCTUnwrap(WriteHoldingDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let server = HostServer(socketPath: path)
        let right = try server.start(announcing: .nothing)

        let writing = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        store.beforeWritingThePublication = {
            writing.signal()
            release.wait()
        }
        let published = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = Settings.publishLocaleAtLaunch(
                resolved: .fallback, right: right, defaults: store
            )
            published.signal()
        }
        XCTAssertEqual(writing.wait(timeout: .now() + 10), .success, "the publication never reached its write")

        let atStop = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            atStop.signal()
            server.stop()
            stopped.signal()
        }
        // **The teardown thread is shown to have reached the call before its silence is read as the
        // lock** (round 20 review): without this, a scheduler that had not run the thread yet looks
        // exactly like an implementation that blocked, and the case would pass on an old one.
        XCTAssertEqual(atStop.wait(timeout: .now() + 10), .success, "the teardown thread never started")
        // Long enough for a teardown that *could* get through to have got through. **This, and not
        // `isHeld`, is the observation available here**: asking would take the same lock the write is
        // holding, so the question deadlocks — which is itself the property under test, seen from the
        // other side. Under the old two-lock shape `stop()` returns while the write is still in
        // flight, and this line goes red
        XCTAssertEqual(stopped.wait(timeout: .now() + 0.5), .timedOut, "the socket was given up mid-publication")

        store.beforeWritingThePublication = nil
        release.signal()
        XCTAssertEqual(published.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 10), .success)
        XCTAssertFalse(right.isHeld, "the teardown never completed")
        XCTAssertEqual(
            store.dictionary(forKey: LocaleState.publicationKey)?["tag"] as? String, fallbackLocale,
            "the publication that held the right did not land"
        )
    }

    /// **A superseded right never still reports held** (round 20 review).
    ///
    /// `mint` used to assign the new right, unlock, and only then give the previous one up — with a
    /// comment directly above saying the previous one was given up *first*. It never was, and in
    /// that interval the old right could enter `whileHeld` and write.
    ///
    /// **What this case is and is not.** The interval is a few instructions inside a function
    /// nothing outside can step into, so a spinner does not reliably land in it: run against the old
    /// ordering unchanged it stays green (measured). Widen that window and it goes red, which is how
    /// the case is shown to detect the state at all rather than to be watching nothing. So it is a
    /// **regression guard**, and the proof of the fix is that the handover happens inside one
    /// acquisition — the plan file records both, because a toggle that catches nothing has to say so.
    ///
    /// The question is asked in one acquisition of the type's lock. Asking "who holds it" and "is
    /// this one still held" separately takes it twice, and a legitimate handover between them looks
    /// exactly like the violation.
    func testASupersededRightNeverStillReportsHeld() throws {
        let first = HostServer(socketPath: path)
        let firstRight = try first.start(announcing: .nothing)
        defer { first.stop() }

        let violations = ViolationFlag()
        let stop = ViolationFlag()
        Thread.detachNewThread {
            while !stop.isSet {
                if LocalePublicationRight.supersededButStillHeld(firstRight) { violations.set() }
            }
        }
        defer { stop.set() }

        for index in 0..<200 {
            let server = HostServer(socketPath: directory + "/r\(index).sock")
            _ = try server.start(announcing: .nothing)
            server.stop()
        }
        // The loop ends with nothing holding the position, and the invariant is the same there: a
        // superseded right that is still live would write through `whileHeld` whether or not anybody
        // replaced it. The predicate asks only that, since round 22 — it also required a successor,
        // which is a narrower question than the one being posed. **No toggle reddens this line**: the
        // state it newly covers cannot be built from outside the type, so what changed is what the
        // predicate means rather than what it currently catches
        XCTAssertFalse(
            LocalePublicationRight.supersededButStillHeld(firstRight),
            "a superseded right is still live after the last holder went"
        )
        XCTAssertFalse(
            violations.isSet,
            "a superseded right and its successor both reported held — the old right can still write"
        )
    }

    /// **A teardown arriving during a startup waits for it** (round 20 review).
    ///
    /// `serverFD` and the right were assigned six lines apart, so a `stop()` in between relinquished
    /// nothing and closed the socket — and `start` went on to publish as the owner and arm an accept
    /// loop on a closed descriptor. The two are one transition now, and the observation available is
    /// the same one the publication seam has: the teardown cannot complete while the startup is in
    /// it.
    func testATeardownDuringAStartupWaitsForIt() throws {
        // **The publication goes to this case's own store.** It went to `.standard` — the runner's
        // own settings, reachable by every case after it — in the round after the injection was
        // added to stop exactly that (round 22 review). The argument existed; this went around it
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let store = try XCTUnwrap(WriteHoldingDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // The hold goes through the store, which is injectable — the publisher closure that used to
        // do it was a production capability and is gone (round 24 review)
        let inPublication = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        store.beforeWritingThePublication = {
            inPublication.signal()
            release.wait()
        }
        let server = HostServer(socketPath: path, defaults: store)
        let started = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? server.start(announcing: .publish(.fallback))
            started.signal()
        }
        XCTAssertEqual(inPublication.wait(timeout: .now() + 10), .success, "the startup never got that far")

        let atStop = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            atStop.signal()
            server.stop()
            stopped.signal()
        }
        // The teardown thread is at the call, so a timeout below is the lock and not the scheduler
        XCTAssertEqual(atStop.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(
            stopped.wait(timeout: .now() + 0.5), .timedOut,
            "the socket was torn down while the startup was still deciding whether it owned it"
        )

        store.beforeWritingThePublication = nil
        release.signal()
        XCTAssertEqual(started.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 10), .success)
        XCTAssertNil(LocalePublicationRight.current, "the torn-down instance kept the right")
        XCTAssertNil(identity(path), "the torn-down instance kept its socket")
        XCTAssertNotNil(
            store.dictionary(forKey: LocaleState.publicationKey),
            "the publication went somewhere other than this case's store"
        )
        XCTAssertNil(
            UserDefaults.standard.dictionary(forKey: LocaleState.publicationKey),
            "the runner's own settings were written"
        )
    }

    /// **Binding another name does not unseat the one that counts** (round 24 review).
    ///
    /// A single holder meant that any bind at all replaced whoever held the canonical socket, so any
    /// file in the module could take a temporary name and leave the process the relay reaches unable
    /// to publish — a denial dressed as a handover. Two binds of different paths are not two answers
    /// to one question, and `bind` is exclusive, so the same path cannot be held twice at once. What
    /// a right is *for* is the thing that decides.
    func testBindingAnotherNameDoesNotUnseatTheCanonicalRight() throws {
        let owner = HostServer(socketPath: path)
        let ownersRight = try owner.start(announcing: .nothing)
        XCTAssertTrue(LocalePublicationRight.current === ownersRight)

        let elsewhere = HostServer(socketPath: directory + "/t.sock")
        let strayRight = try elsewhere.start(announcing: .nothing)

        XCTAssertTrue(ownersRight.isHeld, "a bind of another name gave up the canonical right")
        XCTAssertTrue(
            LocalePublicationRight.current === ownersRight,
            "a bind of another name became what the picker reads"
        )
        XCTAssertTrue(strayRight.isHeld, "the stray right is still a real right to a real bind")
        XCTAssertNotEqual(strayRight.path, defaultSocketPath(), "the fixture proves nothing")

        // And it publishes nothing, which is the half that makes the rest safe
        let suiteName = "com.dazebug.terminal-checkout.tests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        XCTAssertNil(
            Settings.publishLocaleAtLaunch(resolved: .fallback, right: strayRight, defaults: store),
            "a right for another name published"
        )
        XCTAssertNil(store.dictionary(forKey: LocaleState.publicationKey), "it wrote anyway")

        elsewhere.stop()
        XCTAssertTrue(
            LocalePublicationRight.current === ownersRight,
            "stopping the stray server took the canonical right with it"
        )
        owner.stop()
        XCTAssertNil(LocalePublicationRight.current)
    }
}

/// A flag two threads share. `NSLock` rather than an atomic because the subject is not the flag.
private final class ViolationFlag {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// A store that can be stopped in the middle of committing a publication, so that "can anything get
/// between the check and the write" is a question with an answer rather than a race nobody can see.
private final class WriteHoldingDefaults: UserDefaults {
    var beforeWritingThePublication: (() -> Void)?

    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName == LocaleState.publicationKey { beforeWritingThePublication?() }
        super.set(value, forKey: defaultName)
    }
}
