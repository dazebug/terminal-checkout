import Darwin
import XCTest
@testable import Core

/// **The admission has to cover the launch, not just the record** (round 17 review, P0).
///
/// `record` succeeds under the admission lock and returns; the lock is released, and only then does
/// `runInWarp` create a directory, write the Tab Config and call `open` with a fifteen-second
/// timeout. Warp brings the pane up 0.5∼0.7s after that returns. So this order stood:
///
///     record → the gate closes → the farewells go out → the file is written → open → the helper is born
///
/// The helper was born after its own farewell, and nothing was left to dismiss it: it lived to its
/// own idle cap (180s) and lifetime cap (900s), listening on a socket any same-uid process can
/// reach. Two shapes were already measured and closed — dismissing at attach time reaches a socket
/// nobody is listening on, and holding the launch inside the farewell phase does not fit the
/// termination budget — so what is left is that a helper learns **at birth** whether it is wanted.
///
/// These cases bind real sockets, because the thing being tested is which of two processes the
/// kernel lets have a name. A stand-in for the filesystem would be a stand-in for the answer.
final class ClaudeDeliveryLaunchAdmissionTests: XCTestCase {
    private var directory = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Short by hand — `sockaddr_un` holds 104 bytes
        directory = "/tmp/tc-adm-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // The gate is process-global, so a case that shut it would shut it for every case after
        ClaudeDelivery.withdrawRestartAdmission()
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func advertised(_ name: String) -> String { directory + "/tcw-\(name).sock" }

    /// A helper coming up in its pane, at the point it has bound and listened and is about to take
    /// the advertised name. It goes through the production function, so what the case observes is
    /// the same operation the helper binary performs rather than a re-statement of it.
    private func helperComingUp(
        at advertised: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> (fd: Int32, claim: () -> Bool) {
        let staging = warpHelperStagingPath(advertised: advertised)
        var address = try XCTUnwrap(makeUnixSockaddr(staging), file: file, line: line)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0, file: file, line: line)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0, "the helper could not bind its staging name", file: file, line: line)
        XCTAssertEqual(listen(fd, 4), 0, file: file, line: line)
        return (fd, { claimWarpHelperAddress(from: staging, as: advertised) })
    }

    /// **A helper admitted before the gate shut cannot take its address afterwards.**
    ///
    /// This is the interleaving the review named: the record is in, the farewells have gone out, and
    /// only now does the pane come up. The helper must not end up listening where the app was
    /// looking — and it must find that out before the advertised name has ever referred to it, which
    /// is what makes the outcome "never existed" rather than "was not dismissed".
    func testAHelperBornAfterItsFarewellCannotTakeItsAddress() throws {
        let path = advertised("aaaaaaa1")
        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        defer { admission.end() }
        try admission.record(.warp(helperSocket: path))

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [], "a helper that does not exist yet was sent a farewell")

        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertFalse(
            helper.claim(),
            "a helper born after its own farewell took the address anyway — nothing is left to dismiss it"
        )
        XCTAssertNil(
            connectToUnixSocket(path: path),
            "the advertised address answers, so that helper is serving in the user's pane"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: warpHelperStagingPath(advertised: path)),
            "the refused helper left its staging socket behind"
        )
    }

    /// **And a helper that got there first is dismissed rather than orphaned.**
    ///
    /// The withdrawal must not be able to take an address that is already answering: it would leave
    /// the live helper unreachable *and* remove it from the list of things to say goodbye to, which
    /// is the same failure with the blame moved.
    func testAHelperThatAlreadyTookItsAddressIsFarewelledAndKeepsIt() throws {
        let path = advertised("aaaaaaa2")
        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        defer { admission.end() }
        try admission.record(.warp(helperSocket: path))

        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertTrue(helper.claim(), "the helper could not take an address nobody had withdrawn")

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [path], "a listening helper was not told to go")
        let connection = try XCTUnwrap(
            connectToUnixSocket(path: path),
            "the withdrawal took the address of a helper that was already listening"
        )
        close(connection)
    }

    /// **The address answers only once the helper is listening**, which is what makes the farewell
    /// in the case above land rather than race. Before the claim the advertised name does not exist
    /// at all, so there is no interval in which it names a socket that would refuse a connection.
    func testTheAdvertisedNameNeverExistsBeforeItAnswers() throws {
        let path = advertised("aaaaaaa3")
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path),
            "the advertised name existed while the helper was still coming up"
        )
        XCTAssertTrue(helper.claim())
        let connection = try XCTUnwrap(connectToUnixSocket(path: path))
        close(connection)
    }

    /// A reservation with no address, and one whose terminal has no helper process at all, are both
    /// nothing to withdraw and nothing to dismiss. `.none` is the interval between `admit` and
    /// `record`; iTerm2 and WezTerm are typed into by this process itself.
    func testOnlyAWarpHelperHasAnAddressToWithdraw() throws {
        let reserved = try XCTUnwrap(ClaudeDelivery.admit())
        defer { reserved.end() }
        let iterm = try XCTUnwrap(ClaudeDelivery.admit())
        defer { iterm.end() }
        try iterm.record(.iterm(sessionID: "w0t0p0", tty: "/dev/ttys001"))

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [], "a session with no helper process was sent a farewell")
    }

    /// **A refused restart withdraws nothing.** It is the same function with one argument different,
    /// and the argument that makes it refusable must not also make it act: a restart that was turned
    /// down leaves the delivery it was turned down for exactly as it was.
    func testARefusedRestartLeavesTheHelperItRefusedFor() throws {
        let path = advertised("aaaaaaa4")
        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        defer { admission.end() }
        try admission.record(.warp(helperSocket: path))

        XCTAssertFalse(ClaudeDelivery.admitRestart(), "a restart was admitted while delivering")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path),
            "a refused restart withdrew the address of the delivery it was refused for"
        )
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertTrue(helper.claim(), "the helper of an ongoing delivery could not take its address")
    }

    /// **The withdrawal must survive the sweep that used to be its virtue** (round 19 review).
    ///
    /// `d4f76a1` presented the leftover as a merit: a dead socket file is exactly what
    /// `reclaimDeadWarpHelperSockets` removes, and the terminating process has no later moment of
    /// its own to clean up in. That is the hole. A later run's sweep deleting it while the delayed
    /// helper is still alive on its staging name puts the address back within reach and the `link`
    /// succeeds — the P0 again, by way of the tidying. The withdrawal is a directory now, which no
    /// sweep here touches, so nothing had to be taught a rule about pairs.
    ///
    /// The invariant, in the reviewer's words: *an aged advertised tombstone must remain while its
    /// matching staging socket is listening; otherwise the delayed helper must still be unable to
    /// claim.*
    func testAWithdrawalSurvivesTheSweepAndTheDelayedHelperStillCannotClaim() throws {
        let path = advertised("aaaaaaa5")
        XCTAssertEqual(withdrawWarpHelperAddress(path), .withdrawn)
        XCTAssertNil(connectToUnixSocket(path: path), "the withdrawal left something that answers")
        // The name is still one the sweep considers ours — what saves it is the shape, not the name
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: (path as NSString).lastPathComponent))

        // The delayed helper is alive on its staging name, which is the case the sweep could not see
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        reclaimDeadWarpHelperSockets(in: [directory], youngerThan: -1)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path),
            "the sweep removed the only cancellation state while its helper was still coming up"
        )
        XCTAssertFalse(helper.claim(), "the delayed helper claimed the address after the sweep ran")
        XCTAssertNil(connectToUnixSocket(path: path), "the address answers, so that helper is serving")
    }

    /// **A withdrawal that did not happen is not a farewell address** (round 19 review, P0).
    ///
    /// It used to answer `false` for `socket()` failing, for an unconstructible address and for
    /// every `bind` failure, and every false became something to say goodbye to. The comment
    /// defending that direction was right about two outcomes and there are three: nothing withdrawn,
    /// nobody holding the name, and a farewell that reaches nobody while the delayed helper's `link`
    /// still succeeds.
    ///
    /// The invariant, in the reviewer's words: *a forced non-`EADDRINUSE` withdrawal failure with no
    /// advertised file must not allow a delayed helper to claim the address* — the half this process
    /// can keep is that it does not **claim** to have dismissed one.
    func testAFailedWithdrawalIsNotAnAddressToSayGoodbyeTo() throws {
        let locked = directory + "/locked"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        let path = locked + "/tcw-aaaaaaa7.sock"
        chmod(locked, 0o500)
        defer { chmod(locked, 0o700) }

        guard case .failed = withdrawWarpHelperAddress(path) else {
            return XCTFail("the fixture did not make the withdrawal fail")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "something was withdrawn after all")

        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        defer { admission.end() }
        try admission.record(.warp(helperSocket: path))

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(
            farewells, [],
            "an address the app could not take back was reported as a helper it had dismissed"
        )
    }

    /// The three answers, told apart. `.withdrawn` is this process's own act, `.alreadyTaken` is
    /// somebody else's, and `.failed` is neither — the distinction the `Bool` could not carry.
    func testTheWithdrawalHasThreeAnswers() throws {
        let path = advertised("aaaaaaa8")
        XCTAssertEqual(withdrawWarpHelperAddress(path), .withdrawn)
        XCTAssertEqual(withdrawWarpHelperAddress(path), .alreadyTaken, "the name it took reads as free")

        let taken = advertised("aaaaaaa9")
        let helper = try helperComingUp(at: taken)
        defer { close(helper.fd) }
        XCTAssertTrue(helper.claim())
        XCTAssertEqual(
            withdrawWarpHelperAddress(taken), .alreadyTaken,
            "a listening helper's address read as free"
        )

        let locked = directory + "/locked2"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        chmod(locked, 0o500)
        defer { chmod(locked, 0o700) }
        guard case .failed = withdrawWarpHelperAddress(locked + "/tcw-aaaaaab0.sock") else {
            return XCTFail("a withdrawal that could not act reported that it had")
        }
    }

    /// And the staging name is reclaimed too — a helper killed between `listen` and the claim leaves
    /// one, and a sweep that only knew the advertised suffix would leave it in `/tmp` for good.
    func testAStagingSocketLeftByAKilledHelperIsReclaimed() throws {
        let path = advertised("aaaaaaa6")
        let helper = try helperComingUp(at: path)
        close(helper.fd) // SIGKILL: no claim, no cleanup
        let staging = warpHelperStagingPath(advertised: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging), "the fixture proves nothing")

        reclaimDeadWarpHelperSockets(in: [directory], youngerThan: -1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging), "a staging socket was left behind")
    }

    /// **A refused claim says why it was refused, and only `EEXIST` is the withdrawal.**
    ///
    /// The helper printed the withdrawal's name for every errno, so `ENOENT` reported a decision the
    /// app never made. That is a diagnostic contradicted by the code around it — the class this work
    /// has swept since round 1, introduced by the round that swept it. The message is a function of
    /// the code now, which is the only reason a case can hold it at all.
    func testARefusedClaimNamesTheReasonItWasRefusedFor() {
        // "withdr" and not one spelling of it: the sentence being kept out is the *attribution*,
        // and the previous one reached it through "withdrawing"
        XCTAssertTrue(warpHelperClaimFailure(EEXIST).contains("withdr"))
        XCTAssertTrue(warpHelperClaimFailure(EEXIST).contains("File exists"))
        for code in [ENOENT, EACCES, ENOSPC, EPERM] {
            let message = warpHelperClaimFailure(code)
            XCTAssertFalse(
                message.contains("withdr"),
                "\(String(cString: strerror(code))) was reported as a decision the app made"
            )
            XCTAssertTrue(
                message.contains(String(cString: strerror(code))), "the reason is not in the message"
            )
        }
    }

    /// The staging name is shorter than the advertised one, so the length check on the advertised
    /// path answers for both — a helper cannot fail to bind for a reason the app could not have seen.
    func testAStagingNameFitsWhereverTheAdvertisedOneDoes() throws {
        let path = try XCTUnwrap(warpHelperSocketPath(token: "0123abcd", directories: ["/tmp"]))
        let staging = warpHelperStagingPath(advertised: path)
        XCTAssertLessThan(staging.utf8.count, path.utf8.count)
        XCTAssertNotNil(makeUnixSockaddr(staging))
        XCTAssertTrue(staging.hasSuffix(warpHelperStagingSuffix))
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: (staging as NSString).lastPathComponent))
        // The token rule is the same one on both suffixes — widening the sweep must not widen what
        // counts as ours
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-0123ABCD.pre"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-0123abc.pre"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "other-0123abcd.pre"))
    }
}
