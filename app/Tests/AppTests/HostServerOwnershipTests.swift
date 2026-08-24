import Core
import Darwin
import XCTest
@testable import App

/// **What a server instance owns, and for how long** (round 16 review).
///
/// These cases bind real sockets in a short-lived directory because pathname identity and teardown
/// ordering are socket properties. Locale publication is no longer part of this ownership contract.
final class HostServerOwnershipTests: XCTestCase {
    private var directory = ""
    private var path = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = "/tmp/tc-own-\(UUID().uuidString.prefix(8))"
        path = directory + "/s.sock"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func identity(_ path: String) -> (dev_t, ino_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    /// A listening socket at that path that is not the server's — what a second instance leaves
    /// behind when it takes the path over.
    private func bindAnotherSocket(at path: String) throws -> Int32 {
        var address = try XCTUnwrap(makeUnixSockaddr(path))
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0, "the replacement socket could not be bound")
        XCTAssertEqual(listen(fd, 4), 0)
        return fd
    }

    /// **Teardown deletes by identity, not by name.** A restarted instance can bind the path before
    /// the old one reaches cleanup; stopping the old instance must leave the new listener reachable.
    func testStopRemovesOnlyTheSocketItBound() throws {
        let server = HostServer(socketPath: path)
        try server.start()
        let ours = try XCTUnwrap(identity(path))

        let replacement = try bindAnotherSocket(at: path)
        defer { close(replacement) }
        let theirs = try XCTUnwrap(identity(path))
        XCTAssertNotEqual(ours.1, theirs.1, "the replacement reused the same file — the case proves nothing")

        server.stop()

        XCTAssertEqual(identity(path)?.1, theirs.1, "stopping deleted the replacement socket")
        let connection = try XCTUnwrap(connectToUnixSocket(path: path), "the surviving owner is unreachable")
        close(connection)
    }

    /// An instance that never bound owns nothing to take down. This is the path a second GUI
    /// instance walks: `start()` throws `alreadyRunning`, and its later stop must not remove the
    /// running instance's socket.
    func testAnInstanceThatLostTheBindRemovesNothing() throws {
        let owner = HostServer(socketPath: path)
        try owner.start()
        let ours = try XCTUnwrap(identity(path))

        let second = HostServer(socketPath: path)
        XCTAssertThrowsError(try second.start()) { error in
            guard case HostServer.ServerError.alreadyRunning = error else {
                return XCTFail("the second instance failed for another reason: \(error)")
            }
        }
        second.stop()

        XCTAssertEqual(identity(path)?.1, ours.1, "an instance that never bound deleted the owner's socket")
        let connection = try XCTUnwrap(connectToUnixSocket(path: path), "the owner is unreachable")
        close(connection)
        owner.stop()
        XCTAssertNil(identity(path), "the owner left its socket behind")
    }

    /// Startup and teardown are one lifecycle transition. The test pauses after binding but before
    /// arming accepts, then proves that `stop()` cannot close the descriptor or remove the path
    /// until startup releases the lifecycle lock.
    func testATeardownDuringAStartupWaitsForIt() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let atStop = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let server = HostServer(socketPath: path)
        server.beforeAccepting = {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }

        DispatchQueue.global().async {
            try? server.start()
            started.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 10), .success, "startup never reached its pause")
        XCTAssertNotNil(identity(path), "startup did not bind before the pause")

        DispatchQueue.global().async {
            atStop.signal()
            server.stop()
            stopped.signal()
        }
        XCTAssertEqual(atStop.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(
            stopped.wait(timeout: .now() + 0.5), .timedOut,
            "teardown ran while startup still held the lifecycle transition"
        )

        release.signal()
        XCTAssertEqual(started.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 10), .success)
        XCTAssertNil(identity(path), "the stopped server kept its socket")
    }
}
