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

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Short by hand — `sockaddr_un` holds 104 bytes and the runner's temporary directory is
        // most of that on its own
        directory = "/tmp/tc-own-\(UUID().uuidString.prefix(8))"
        path = directory + "/s.sock"
    }

    override func tearDown() {
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

        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.stop()
            stopped.signal()
        }
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

    /// **What a right can be minted from** — the discriminator, against real descriptors.
    ///
    /// `mint` is unreachable from here by design, so what is exercised is the check it consists of.
    /// Two other checks were measured and are not available on this platform: `SO_ACCEPTCONN` is
    /// `ENOPROTOOPT` for every socket, and a bound socket's `fstat` inode is synthetic
    /// (`<scratchpad>/r19_sockname_probe.swift`, `r19_ino_probe.swift`).
    func testOnlyASocketBoundToThatNameIdentifiesAsIt() throws {
        let server = HostServer(socketPath: path)
        try server.start(announcing: .nothing)
        defer { server.stop() }

        let elsewhere = directory + "/t.sock"
        let other = try bindAnotherSocket(at: elsewhere)
        defer { close(other) }
        XCTAssertTrue(unixSocketIsBound(other, to: elsewhere))
        XCTAssertFalse(unixSocketIsBound(other, to: path), "a socket bound elsewhere passed for ours")

        let fresh = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fresh) }
        XCTAssertFalse(unixSocketIsBound(fresh, to: path), "a socket that never bound passed")

        let client = try XCTUnwrap(connectToUnixSocket(path: path), "the owner is not reachable")
        defer { close(client) }
        XCTAssertFalse(unixSocketIsBound(client, to: path), "a connected client passed for the listener")

        let plain = open(directory + "/plain", O_CREAT | O_WRONLY, 0o600)
        defer { close(plain) }
        XCTAssertFalse(unixSocketIsBound(plain, to: path), "a regular file passed for a socket")
        XCTAssertFalse(unixSocketIsBound(-1, to: path), "a closed descriptor passed")
    }

    /// Two binds in one process is not a shape production has, but `mint` has to answer for it
    /// anyway: the second bind is the owner, and the first right stops being one. Ending the second
    /// must not resurrect the first, which is why the holder is cleared only when it is still that
    /// same right.
    func testAlaterBindSupersedesTheEarlierRight() throws {
        let first = HostServer(socketPath: path)
        let firstRight = try first.start(announcing: .nothing)
        let otherPath = directory + "/t.sock"
        let second = HostServer(socketPath: otherPath)
        let secondRight = try second.start(announcing: .nothing)

        XCTAssertFalse(firstRight.isHeld, "two rights were live at once")
        XCTAssertTrue(LocalePublicationRight.current === secondRight)

        first.stop()
        XCTAssertTrue(
            LocalePublicationRight.current === secondRight,
            "stopping the superseded server took the live right with it"
        )
        second.stop()
        XCTAssertNil(LocalePublicationRight.current)
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
