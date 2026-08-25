import Darwin
import TestSupport
import XCTest
@testable import Core

/// **The admission has to cover the launch, not just the record**.
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

    /// The helper's source, by the path this test file sits at.
    private static func helperSource() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/WarpHelper/main.swift")
            .path
    }

    /// A Core source file, by the path this test file sits at.
    private static func coreSource(_ name: String) -> String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/CoreTests/<this file>
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Core/\(name)")
            .path
    }

    /// The file the app links from. Every case that takes an address back needs one, because
    /// `runInWarp` makes it beside the register entry — a case that skipped it would be measuring a
    /// state production does not have.
    @discardableResult
    private func pinned(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let path = advertised(name)
        XCTAssertTrue(createWarpHelperPin(forAdvertised: path), "the pin could not be made", file: file, line: line)
        return path
    }

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
    /// This is the dangerous interleaving: the record is in, the farewells have gone out, and
    /// only now does the pane come up. The helper must not end up listening where the app was
    /// looking — and it must find that out before the advertised name has ever referred to it, which
    /// is what makes the outcome "never existed" rather than "was not dismissed".
    func testAHelperBornAfterItsFarewellCannotTakeItsAddress() throws {
        let path = pinned("aaaaaaa1")
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
        let path = pinned("aaaaaaa2")
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
        let path = pinned("aaaaaaa4")
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

    /// **The withdrawal must survive the later sweep.** An aged advertised tombstone remains while
    /// its matching staging socket is listening, so a delayed helper cannot reclaim the address.
    func testAWithdrawalSurvivesTheSweepAndTheDelayedHelperStillCannotClaim() throws {
        let path = pinned("aaaaaaa5")
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

    /// **A withdrawal that did not happen is not a farewell address**.
    ///
    /// It used to answer `false` for `socket()` failing, for an unconstructible address and for
    /// every `bind` failure, and every false became something to say goodbye to. The comment
    /// defending that direction was right about two outcomes and there are three: nothing withdrawn,
    /// nobody holding the name, and a farewell that reaches nobody while the delayed helper's `link`
    /// still succeeds.
    ///
    /// The invariant: *a forced non-`EADDRINUSE` withdrawal failure with no
    /// advertised file must not allow a delayed helper to claim the address* — the half this process
    /// can keep is that it does not **claim** to have dismissed one.
    func testAFailedWithdrawalIsNotAnAddressToSayGoodbyeTo() throws {
        let locked = directory + "/locked"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        let path = locked + "/tcw-aaaaaaa7.sock"
        createWarpHelperPin(forAdvertised: path)
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

    /// The three answers, told apart. `.withdrawn` is this process's own act, `.occupied` is *the
    /// name is not free*, and `.failed` is neither — the distinction the `Bool` could not carry.
    func testTakingAnAddressBackHasThreeAnswers() throws {
        let path = pinned("aaaaaaa8")
        XCTAssertEqual(withdrawWarpHelperAddress(path), .withdrawn)
        XCTAssertEqual(withdrawWarpHelperAddress(path), .occupied, "the name it took reads as free")

        let taken = pinned("aaaaaaa9")
        let helper = try helperComingUp(at: taken)
        defer { close(helper.fd) }
        XCTAssertTrue(helper.claim())
        XCTAssertEqual(
            withdrawWarpHelperAddress(taken), .occupied,
            "a listening helper's address read as free"
        )

        let locked = directory + "/locked2"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        let lockedPath = locked + "/tcw-aaaaaab0.sock"
        createWarpHelperPin(forAdvertised: lockedPath)
        chmod(locked, 0o500)
        defer { chmod(locked, 0o700) }
        guard case .failed = withdrawWarpHelperAddress(lockedPath) else {
            return XCTFail("a take-back that could not act reported that it had")
        }
    }

    /// **`.occupied` says the name is taken and nothing about by what**.
    ///
    /// `EEXIST` comes back for a helper socket, for a leftover directory, for a regular file, for a
    /// symlink and for a dead socket alike, and the previous shape called all of them
    /// `.alreadyTaken` → `Departure.listening` → "a helper the app dismissed". The cost of the
    /// conflation is one refused connection; the reason to end it is that the name of a value is
    /// what the next reader builds on.
    func testOccupiedIsAboutTheNameAndNotAboutWhatIsAtIt() throws {
        let byDirectory = pinned("aaaaaab1")
        XCTAssertEqual(mkdir(byDirectory, 0o700), 0)
        XCTAssertEqual(withdrawWarpHelperAddress(byDirectory), .occupied)

        let byFile = pinned("aaaaaab2")
        let fd = open(byFile, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        close(fd)
        XCTAssertEqual(withdrawWarpHelperAddress(byFile), .occupied)

        let byLink = pinned("aaaaaab3")
        XCTAssertEqual(symlink("/nowhere", byLink), 0)
        XCTAssertEqual(withdrawWarpHelperAddress(byLink), .occupied)

        let byDeadSocket = pinned("aaaaaab4")
        let dead = try helperComingUp(at: byDeadSocket)
        XCTAssertTrue(dead.claim())
        close(dead.fd) // the helper is gone; the name it left is not
        XCTAssertNil(connectToUnixSocket(path: byDeadSocket), "the fixture is still answering")
        XCTAssertEqual(withdrawWarpHelperAddress(byDeadSocket), .occupied)

        // And the diagnostic the helper prints for the same errno says occupancy, not provenance
        let message = warpHelperClaimFailure(EEXIST)
        XCTAssertTrue(message.contains("occupied"))
        XCTAssertFalse(message.contains("withdrew"), "an errno was read as a decision the app made")
    }

    /// **A take-back that fails means the helper cannot claim either**.
    ///
    /// `mkdir` needed an inode and the helper's `link` reuses the socket's, so the code could answer
    /// `.failed` — no farewell — while the claim went through: the orphan again, by way of the branch
    /// written to be honest about not knowing. Documenting a sliver is not the same as it being safe.
    /// Both sides are `link` into the same parent now, so the failures are the same failures by
    /// construction rather than by an enumeration that can be incomplete.
    ///
    /// The invariant: *a staging socket is already listening, the take-back
    /// fails, and the delayed helper must still be unable to claim.*
    func testWhenTheTakeBackFailsTheHelperCannotClaimEither() throws {
        let locked = directory + "/locked3"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        let path = locked + "/tcw-aaaaaab5.sock"
        createWarpHelperPin(forAdvertised: path)

        // The helper is up and listening on its staging name, one syscall away from claiming
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }

        chmod(locked, 0o500)
        defer { chmod(locked, 0o700) }
        guard case .failed = withdrawWarpHelperAddress(path) else {
            return XCTFail("the fixture did not make the take-back fail")
        }
        XCTAssertFalse(
            helper.claim(),
            "the take-back failed and the helper claimed anyway — it outlives the app with nothing to dismiss it"
        )
        XCTAssertNil(connectToUnixSocket(path: path), "the advertised address answers")
    }

    /// **No pin, no launch.** A request whose pin cannot be made cannot safely launch its helper.
    ///
    /// Linking from a file the app already holds is what makes the take-back fail exactly when the
    /// claim would, but only while that file exists. A request whose pin could not be made is a
    /// request whose helper cannot be taken back is refused. The
    /// source-order half is a lint, not a runtime `runInWarp` proof; the writable-directory fixture
    /// below exercises the pin-creation failure itself.
    func testAWarpRequestIsRefusedWhenItsPinCannotBeMade() throws {
        let source = try auditSource(
            Self.coreSource("TerminalRunner.swift"), claim: .sourceOrder
        ).text
        let create = try XCTUnwrap(source.range(of: "guard createWarpHelperPin(forAdvertised: socketPath) else {"))
        let record = try XCTUnwrap(source.range(of: "try claudeInput.record(.warp(helperSocket: socketPath))"))
        XCTAssertLessThan(create.lowerBound, record.lowerBound, "the pin is made after the register entry")
        XCTAssertTrue(
            source[create.upperBound...].hasPrefix("\n            throw claudeInputRejection("),
            "a request whose pin could not be made is launched anyway"
        )

        // And the refusal is the same one every other unavailable-helper path raises, so it reaches
        // the window that explains it rather than a `{success:true}` with the input dropped
        let locked = directory + "/locked4"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        chmod(locked, 0o500)
        defer { chmod(locked, 0o700) }
        XCTAssertFalse(
            createWarpHelperPin(forAdvertised: locked + "/tcw-aaaaaab8.sock"),
            "the pin was made in a directory that cannot be written"
        )
    }

    /// **A finished delivery does not spend the pin**.
    ///
    /// One object had two lifetime rules: departure kept it — correctly, that is what takes the
    /// address back — and ordinary completion removed it. The difference was the defect. A helper
    /// listening only on its staging name, suspended before its `link`, while the delivery times
    /// out: the farewell reaches a path nothing is on, `end()` removed the pin, the helper resumes
    /// and claims, and nothing is left to dismiss it.
    ///
    /// A pin is spent when **no helper can still claim**, which is time's business and the sweep's.
    func testAFinishedDeliveryLeavesThePinForTheSweep() throws {
        let path = pinned("aaaaaab9")
        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        try admission.record(.warp(helperSocket: path))
        admission.end()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: warpHelperPinPath(advertised: path)),
            "finishing the delivery spent the pin, so a suspended helper could still claim"
        )
        // And the address can still be taken back afterwards, which is the whole point of keeping it
        XCTAssertEqual(withdrawWarpHelperAddress(path), .withdrawn)
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertFalse(helper.claim(), "the helper claimed after the delivery had ended")
    }

    /// **A registration that threw takes its pin with it.** The source-order half is a lint, while
    /// the runtime half exercises the cleanup. The pin is made before `record` on purpose — a
    /// registered address whose pin does not exist yet is an address that cannot be taken back — so
    /// the failing path is the one that has to clean up.
    func testAPinIsNotLeftBehindByARegistrationThatThrew() throws {
        let path = advertised("aaaaaaba")
        let source = try auditSource(
            Self.coreSource("TerminalRunner.swift"), claim: .sourceOrder
        ).text
        let create = try XCTUnwrap(source.range(of: "guard createWarpHelperPin(forAdvertised: socketPath) else {"))
        let record = try XCTUnwrap(source.range(of: "try claudeInput.record(.warp(helperSocket: socketPath))"))
        XCTAssertLessThan(create.lowerBound, record.lowerBound, "the pin is made after the address is registered")
        XCTAssertTrue(
            source.contains("removeWarpHelperPin(forAdvertised: socketPath)"),
            "a registration that throws leaves its pin behind"
        )

        // And the removal it uses is the verified one, not a raw unlink
        XCTAssertTrue(createWarpHelperPin(forAdvertised: path))
        removeWarpHelperPin(forAdvertised: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: warpHelperPinPath(advertised: path)))
    }

    /// **The claim is bounded from birth, by a deadline in the line the app writes.**
    ///
    /// The bound used to be derived from the Tab Config lifetime, `open`'s timeout and how long a
    /// pane takes to appear — and none of that bounds anything, because "the instruction after
    /// `listen`" is not a time and a suspended process can be anywhere. The
    /// helper's own caps start once it is serving, which is after the claim.
    func testTheLaunchLineCarriesTheDeadlineTheSweepIsDerivedFrom() throws {
        let line = warpHelperCommand(
            executable: "/x/helper", socketPath: "/tmp/tcw-ab12cd34.sock",
            deadline: Date(timeIntervalSince1970: 1_700_000_042)
        )
        XCTAssertTrue(line.hasSuffix(" 1700000042"), "the launch line carries no deadline")

        // The sweep's threshold is the number the helper enforces, not a derivation of its own
        XCTAssertGreaterThan(warpHelperOccupationLifetime, warpHelperClaimWindow)

        // And the helper reads it: the serve-path assertions below are a source lint, not a launched
        // helper proof. The path takes five words and treats an unreadable deadline as already past,
        // because an unbounded claim is the thing being removed.
        let helper = try auditSource(Self.helperSource(), claim: .sourceStructure).text
        XCTAssertTrue(helper.contains("arguments.count == 5, arguments[1] == serveFlag"))
        XCTAssertTrue(helper.contains("Double(arguments[4]) ?? 0"), "an unreadable deadline is not fail-closed")
        let deadlineCheck = try XCTUnwrap(helper.range(of: "Date().timeIntervalSince1970 <= claimDeadline"))
        let claim = try XCTUnwrap(helper.range(of: "guard claimWarpHelperAddress(from: stagingPath"))
        XCTAssertLessThan(deadlineCheck.lowerBound, claim.lowerBound, "the deadline is checked after the claim")
    }

    /// **The sweep takes our file and only our file.** The check was a prefix read, so a user file
    /// that merely *starts* with the marker was deleted. The fixture list is the
    /// specification.
    func testTheSweepTakesTheExactMarkerAndNothingElse() throws {
        let ours = directory + "/tcw-aaaaabb1.pin"
        XCTAssertTrue(createWarpHelperPin(forAdvertised: directory + "/tcw-aaaaabb1.sock"))

        let extra = directory + "/tcw-aaaaabb2.pin"
        try (warpHelperPinMarker + "and the user's own notes").write(
            toFile: extra, atomically: true, encoding: .utf8
        )
        let link = directory + "/tcw-aaaaabb3.pin"
        XCTAssertEqual(symlink("/etc/hosts", link), 0)

        reclaimStaleWarpHelperOccupations(in: directory, olderThan: -1)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ours), "our own pin survived the sweep")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: extra),
            "a file that only begins with our marker was deleted"
        )
        var info = stat()
        XCTAssertEqual(lstat(link, &info), 0, "a symlink with our name was deleted")
    }

    /// A pin whose marker could not be written is removed rather than left for a sweep that only
    /// takes whole ones — nothing would ever have collected it.
    func testAPinThatCouldNotBeWrittenIsNotLeftBehind() throws {
        let readOnly = directory + "/ro"
        try FileManager.default.createDirectory(atPath: readOnly, withIntermediateDirectories: true)
        chmod(readOnly, 0o500)
        defer { chmod(readOnly, 0o700) }
        XCTAssertFalse(createWarpHelperPin(forAdvertised: readOnly + "/tcw-aaaaabb4.sock"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: readOnly + "/tcw-aaaaabb4.pin"))
    }

    /// **What taking an address back leaves is bounded**.
    ///
    /// A tombstone older than any possible time-to-claim protects nothing. The bound is derived in
    /// `warpHelperOccupationLifetime`, and the sweep removes it only after that bound.
    func testWhatIsLeftBehindIsSweptOnceItCannotProtectAnything() throws {
        let path = pinned("aaaaaab6")
        XCTAssertEqual(withdrawWarpHelperAddress(path), .withdrawn)
        let pin = warpHelperPinPath(advertised: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pin), "the pin is not there to sweep")

        // Young: both stay, because a helper could still be coming
        reclaimStaleWarpHelperOccupations(in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "a fresh take-back was swept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pin))

        reclaimStaleWarpHelperOccupations(in: directory, olderThan: -1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "the leftover is unbounded")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pin), "the pin is unbounded")
    }

    /// And a live helper's address is never in that sweep's range: it is a socket, and the sweep
    /// only takes regular files.
    func testTheOccupationSweepNeverTakesALiveHelpersAddress() throws {
        let path = pinned("aaaaaab7")
        let helper = try helperComingUp(at: path)
        defer { close(helper.fd) }
        XCTAssertTrue(helper.claim())

        reclaimStaleWarpHelperOccupations(in: directory, olderThan: -1)
        let connection = try XCTUnwrap(
            connectToUnixSocket(path: path), "the sweep took a listening helper's address"
        )
        close(connection)
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

    /// **A refused claim says why it was refused, and `EEXIST` says only that the name is occupied.**
    ///
    /// `ENOENT` means the address was absent, while `EEXIST` means only that the name is occupied;
    /// neither errno identifies who owns it. The diagnostic must report that distinction.
    func testARefusedClaimNamesTheReasonItWasRefusedFor() {
        XCTAssertTrue(warpHelperClaimFailure(EEXIST).contains("occupied"))
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
