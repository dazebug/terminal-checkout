import Core
import Darwin
import TestSupport
import XCTest
@testable import App

/// The two steps a launch takes — reserve the slot, then write into it the address of the helper it
/// is about to create — for the cases that are about what happens *after* that. A case about the
/// refusal itself calls `record` directly; here a refusal throws out of the helper, so a case can
/// never run on against an empty register.
/// A place for the addresses these cases register.
///
/// They have to be **unique per run and cleaned up**, because a registered address is no longer only
/// a string: shutting the gate withdraws it by binding it, so a fixed name in `/tmp` survives the
/// process and the next run finds its own leftover already there — which flips the withdrawal's
/// answer and makes a case pass for a reason that has nothing to do with what it asserts (observed
/// while writing the fix: `testTerminationClosesTheGateBeforeSayingGoodbye` went green
/// against a socket file the previous run had left).
final class SocketFixtures {
    let directory = "/tmp/tc-fix-" + String(UUID().uuidString.prefix(8))
    private var listeners: [Int32] = []

    init() {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    deinit {
        for fd in listeners { close(fd) }
        try? FileManager.default.removeItem(atPath: directory)
    }

    func path(_ name: String) -> String { directory + "/" + name + ".sock" }

    /// A helper that has come up in its pane and **taken** its address, through the same production
    /// function the helper binary calls.
    ///
    /// A registered address used to be only a string, so a case could assert that termination said
    /// goodbye to a socket nobody was ever on — which is the defect those cases were meant to be
    /// about. Now the two are told apart by whether anything is listening, so a case that wants the
    /// farewell has to put something there.
    func liveHelper(
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        let advertised = path(name)
        // `runInWarp` makes this beside the register entry, and the app links from it to take an
        // address back — a fixture without one would be measuring a state production does not have
        XCTAssertTrue(
            createWarpHelperPin(forAdvertised: advertised), "the pin could not be made",
            file: file, line: line
        )
        let staging = warpHelperStagingPath(advertised: advertised)
        guard var address = makeUnixSockaddr(staging) else {
            XCTFail("the staging path does not fit sun_path", file: file, line: line)
            return advertised
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0, "the fixture helper could not bind", file: file, line: line)
        XCTAssertEqual(listen(fd, 4), 0, file: file, line: line)
        XCTAssertTrue(
            claimWarpHelperAddress(from: staging, as: advertised),
            "the fixture helper could not take its address", file: file, line: line
        )
        listeners.append(fd)
        return advertised
    }
}

private func admitted(
    _ handle: TerminalSessionHandle, file: StaticString = #filePath, line: UInt = #line
) throws -> ClaudeDelivery.Admission {
    let admission = try XCTUnwrap(
        ClaudeDelivery.admit(), "the gate refused a reservation", file: file, line: line
    )
    try admission.record(handle)
    return admission
}

/// **A language restart must not cut a claude delivery in half.**
///
/// The delivery is asynchronous — `HostServer` answers Chrome as soon as the tab exists and watches
/// the typing on a background queue, because waiting for claude to come up and retrying each input
/// can take minutes. A restart in that window leaves the Warp injection helper running in the user's
/// pane with nobody left to say goodbye to it, and that helper's **only** defence is its lifetime
/// (`CLAUDE.md`): while it lives, any process with the same uid can inject into that pane. Every
/// residual this project accepted about the same-uid boundary is standing on "it dies when the
/// delivery ends".
///
/// **What can and cannot be driven from here.** Standing up a real delivery would need a terminal, a
/// claude process and a helper, so what is tested is the shape items 15 and 16 used for the same
/// problem: the verdict is a pure function of a registry, the registry is exercised directly, and
/// the one line that consumes the verdict is pinned by reading it. The socket farewell itself is the
/// piece no test here takes — it needs a helper on the other end.
final class LocaleRestartTests: XCTestCase {
    private var sockets = SocketFixtures()
    private var restoredAdmit: (() -> Bool)!
    private var restoredWithdraw: (() -> Void)!

    override func setUp() {
        super.setUp()
        sockets = SocketFixtures()
        restoredAdmit = LocaleRestartGate.admitRestart
        restoredWithdraw = LocaleRestartGate.withdrawAdmission
        // No draining here, and the first version of this file pretended otherwise: `endEveryHelper`
        // dismisses helpers, it does not empty the register, so the line that called it "cleanup"
        // was a comment describing something the code does not do — the class keeps
        // sweeping for, committed in its own test. Each test balances its own tokens with `defer`
        // instead, and the assertion below is the canary for one that did not.
    }

    override func tearDown() {
        LocaleRestartGate.admitRestart = restoredAdmit
        LocaleRestartGate.withdrawAdmission = restoredWithdraw
        // Admission latches, so a case that granted one and did not give it back would refuse every
        // delivery in every case after it — the cross-test leak this file's own canary looks for
        ClaudeDelivery.withdrawRestartAdmission()
        super.tearDown()
    }

    /// The truth table, enumerated: idle, in flight, and finished.
    ///
    /// Granting is separated from asking on purpose. `isInFlight` is the question and may be asked
    /// as often as one likes; `admitRestart` **latches**, so each grant below is withdrawn before
    /// the next assertion — a test that treated the latching operation as a query would be testing
    /// its own leftovers.
    func testRestartIsRefusedOnlyWhileADeliveryIsInFlight() throws {
        XCTAssertFalse(ClaudeDelivery.isInFlight, "a previous test left a delivery registered")
        XCTAssertTrue(ClaudeDelivery.admitRestart(), "idle should admit a restart")
        ClaudeDelivery.withdrawRestartAdmission()

        let token = try admitted(.warp(helperSocket: sockets.path("test-a")))
        defer { token.end() }
        XCTAssertTrue(ClaudeDelivery.isInFlight)
        XCTAssertFalse(ClaudeDelivery.admitRestart(), "a restart was admitted during a delivery")

        token.end()
        XCTAssertFalse(ClaudeDelivery.isInFlight)
        XCTAssertTrue(ClaudeDelivery.admitRestart(), "the barrier stayed up after the delivery ended")
        ClaudeDelivery.withdrawRestartAdmission()
    }

    /// **The race this protocol exists for.**
    ///
    /// The old gate answered "is a delivery running" and closed nothing behind itself. A request
    /// already on its way could pass `runInWarp`, write its Tab Config and **launch a helper** after
    /// the picker had decided — and the app would terminate believing nothing was in flight, leaving
    /// a same-uid injection socket alive in the user's pane. That is the boundary `CLAUDE.md` says
    /// the helper's only defence is.
    ///
    /// So admission is one-way while it holds: after it is granted, a delivery cannot be admitted at
    /// all. It is refusal and not queueing, because the process is about to go away — the request
    /// fails with `TerminalError.goingAway` and the user presses again.
    func testNoDeliveryCanBeginAfterRestartAdmission() {
        XCTAssertFalse(ClaudeDelivery.isInFlight, "a previous test left a delivery registered")
        XCTAssertTrue(ClaudeDelivery.admitRestart(), "idle should admit a restart")
        defer { ClaudeDelivery.withdrawRestartAdmission() }

        XCTAssertNil(
            ClaudeDelivery.admit(),
            "a delivery was admitted after the restart was — the helper it launches outlives the app"
        )
        XCTAssertFalse(ClaudeDelivery.isInFlight, "a refused delivery still left something registered")
    }

    /// Withdrawing puts it back, and that path is not decoration: the picker's relaunch can fail to
    /// spawn, and an admission nobody lifts would refuse every claude input for the rest of the
    /// process's life — a worse outcome than the restart not happening.
    func testAWithdrawnAdmissionLetsDeliveriesStartAgain() throws {
        XCTAssertTrue(ClaudeDelivery.admitRestart())
        XCTAssertNil(ClaudeDelivery.admit())
        ClaudeDelivery.withdrawRestartAdmission()
        let token = try XCTUnwrap(ClaudeDelivery.admit(), "withdrawing did not reopen admission")
        token.end()
    }

    /// A slot reserved before the launch has decided on an address carries no handle yet. It still
    /// has to hold the barrier down — that interval is the one in which a helper is about to be
    /// asked for and its address is not yet known to anybody.
    func testAReservedSlotWithNoHandleStillRefusesARestart() throws {
        let token = try XCTUnwrap(ClaudeDelivery.admit())
        defer { token.end() }
        XCTAssertTrue(ClaudeDelivery.isInFlight, "a reservation without a handle left the register empty")
        XCTAssertFalse(ClaudeDelivery.admitRestart(), "a restart was admitted while a helper was being launched")
        XCTAssertEqual(ClaudeDelivery.liveWarpSockets, [], "a slot with no handle offered a socket")

        try token.record(.warp(helperSocket: sockets.path("test-late")))
        XCTAssertEqual(ClaudeDelivery.liveWarpSockets, [sockets.path("test-late")])
    }

    /// Two deliveries can overlap — a second button pressed while the first is still typing — so the
    /// barrier has to count rather than latch. A boolean flag here would be lowered by whichever
    /// delivery finished first.
    func testASecondDeliveryKeepsTheBarrierUpUntilBothFinish() throws {
        let first = try admitted(.warp(helperSocket: sockets.path("test-a")))
        let second = try admitted(.warp(helperSocket: sockets.path("test-b")))
        defer { first.end(); second.end() }
        first.end()
        XCTAssertTrue(ClaudeDelivery.isInFlight, "the barrier fell while a delivery was still running")
        XCTAssertFalse(ClaudeDelivery.admitRestart())
        second.end()
        XCTAssertFalse(ClaudeDelivery.isInFlight)
    }

    /// Ending a token twice is the `defer`'s prerogative — it must never have to know whether it
    /// already ran — and it must not disturb another delivery.
    func testEndingTheSameDeliveryTwiceIsHarmless() throws {
        let token = try admitted(.warp(helperSocket: sockets.path("test-a")))
        let other = try admitted(.iterm(sessionID: "s1", tty: "/dev/ttys001"))
        defer { token.end(); other.end() }
        token.end()
        token.end()
        XCTAssertTrue(ClaudeDelivery.isInFlight, "a repeated end took another delivery with it")
        other.end()
        XCTAssertFalse(ClaudeDelivery.isInFlight)
    }

    /// Termination has to reach the helpers, and only the helpers: a session with no helper has
    /// nothing to say goodbye to.
    func testTerminationSaysGoodbyeToEveryLiveHelperAndNothingElse() throws {
        let warpA = try admitted(.warp(helperSocket: sockets.liveHelper("test-a")))
        let warpB = try admitted(.warp(helperSocket: sockets.liveHelper("test-b")))
        let iterm = try admitted(.iterm(sessionID: "s7", tty: "/dev/ttys002"))
        defer { warpA.end(); warpB.end(); iterm.end() }

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [sockets.path("test-a"), sockets.path("test-b")])

        warpA.end()
        warpB.end()
        iterm.end()

        farewells = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [], "a finished delivery still had a helper to dismiss")
    }

    /// **The ordering inside the delivery's `defer` is the invariant, not an implementation detail.**
    ///
    /// The farewell goes out before the register is cleared, so that a reader who sees "nothing in
    /// flight" may conclude "no helper of ours is still alive on that account". The reverse order
    /// leaves a window where the barrier is down and a helper is up, which is exactly what the
    /// lifetime defence cannot afford. This is a source-order lint, not a runtime delivery proof:
    /// reaching that `defer` would require running a real delivery.
    func testTheHelperIsDismissedBeforeTheRegisterIsCleared() throws {
        let source = try auditSource(
            Self.coreSource("ClaudeInjector.swift"), claim: .sourceOrder
        ).text
        let farewell = source.range(of: "if case .warp(let socket) = handle { _ = warpHelperRequest(.bye, socket: socket) }")
        let clear = source.range(of: "admission.end()")
        XCTAssertTrue(
            source.contains("admission: ClaudeDelivery.Admission\n"),
            "the delivery no longer takes the slot its launch passed through"
        )
        let farewellStart = try XCTUnwrap(farewell?.lowerBound, "the helper is no longer dismissed")
        let clearStart = try XCTUnwrap(clear?.lowerBound, "the register is no longer cleared")
        XCTAssertLessThan(
            farewellStart, clearStart,
            "the register is cleared before the helper is dismissed, which opens the window this closes"
        )
    }

    /// The one line that consumes the verdict. This is a source-order lint, not a runtime restart
    /// proof: the branch that follows calls `NSApp.terminate`, so a test that took it would end the
    /// test run.
    func testThePickerAsksBeforeItRestarts() throws {
        let source = try auditSource(
            Self.appSource("SetupWindowController.swift"), claim: .sourceOrder
        ).text
        let function = try XCTUnwrap(source.range(of: "@objc private func restartForLanguage() {"))
        let body = source[function.upperBound...]
        let guardIndex = try XCTUnwrap(
            body.range(of: "guard LocaleRestartGate.admitRestart() else {"),
            "the picker restarts without taking an admission"
        ).lowerBound
        let terminate = try XCTUnwrap(body.range(of: "NSApp.terminate(nil)")).lowerBound
        XCTAssertLessThan(guardIndex, terminate, "the app is terminated before the gate is consulted")
    }

    /// **A non-owning window still reaches the delivery gate.** Socket ownership used to be the
    /// transport for this policy; it is gone, while refusing a restart during delivery remains the
    /// policy that prevents termination from cutting off a live helper.
    ///
    /// It is driven through the selector because the method is private, and the gate is left
    /// refusing so the case proves that the action reaches the refusal path. It cannot observe
    /// `NSApp.terminate` itself: letting that branch run would terminate the test process. The
    /// source-order case above proves only that the gate is consulted before termination; whether
    /// the false branch returns without terminating is a human-review boundary, recorded in the
    /// plan rather than disguised as this case's runtime oracle.
    func testTheRestartActionReachesDeliveryGateWithoutSocketOwnership() throws {
        var asked = 0
        LocaleRestartGate.admitRestart = { asked += 1; return false }

        let controller = SetupWindowController()
        _ = controller.window
        controller.perform(NSSelectorFromString("restartForLanguage"))
        XCTAssertEqual(asked, 1, "a non-owning window bypassed LocaleRestartGate")
    }

    /// And termination dismisses the helpers before it stops our own socket server: one of those is
    /// a process on the user's machine and the other is ours to lose. This is a source-order lint,
    /// not a runtime termination proof, because invoking the path would stop the test process.
    func testTerminationDismissesHelpersBeforeStoppingOurOwnServer() throws {
        let source = try auditSource(
            Self.appSource("AppDelegate.swift"), claim: .sourceOrder
        ).text
        let function = try XCTUnwrap(source.range(of: "func applicationWillTerminate("))
        let body = source[function.upperBound...]
        let helpers = try XCTUnwrap(
            body.range(of: "ClaudeDelivery.endEveryHelper(departure)"),
            "termination no longer dismisses helpers"
        ).lowerBound
        let stop = try XCTUnwrap(body.range(of: "server?.stop()")).lowerBound
        XCTAssertLessThan(helpers, stop)
    }

    // MARK: - Paths

    private static func source(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocaleRestartTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
            .path
    }

    private static func appSource(_ name: String) -> String { source("Sources/App/\(name)") }
    private static func coreSource(_ name: String) -> String { source("Sources/Core/\(name)") }
}

/// **Going away is one decision, and both ways of going away take it**.
///
/// Normal termination — the user quitting, or
/// macOS shutting the app down — called `endEveryHelper` and stopped the listener with the gate
/// still open, so a request already accepted on the socket queue could reach `runInTerminal` and
/// launch a Warp helper *after* the farewells had gone out. That helper would outlive the app with
/// nothing left to dismiss it, which is the boundary `CLAUDE.md` says its lifetime is the only
/// defence of.
///
/// The two paths differ in one thing only, and it is the difference between asking and being told: a
/// restart may be refused, a termination may not.
final class AppTerminationAdmissionTests: XCTestCase {
    private var sockets = SocketFixtures()

    override func setUp() {
        super.setUp()
        sockets = SocketFixtures()
    }

    override func tearDown() {
        ClaudeDelivery.withdrawRestartAdmission()
        super.tearDown()
    }

    /// Termination closes the gate **even though something is in flight** — refusing would not stop
    /// it — and after it no delivery can be admitted.
    func testTerminationClosesAdmissionEvenWithADeliveryInFlight() throws {
        let token = try admitted(.warp(helperSocket: sockets.path("term-a")))
        defer { token.end() }

        XCTAssertFalse(ClaudeDelivery.admitRestart(), "a restart should be refused while delivering")
        // Nothing can refuse a termination, which is why this hands back a `Departure` rather than
        // an answer — there is no state in which it fails
        _ = ClaudeDelivery.depart()
        XCTAssertNil(
            ClaudeDelivery.admit(),
            "a delivery was admitted after termination began — its helper would outlive the app"
        )
        XCTAssertEqual(
            ClaudeDelivery.liveWarpSockets, [sockets.path("term-a")],
            "closing the gate lost the helper that still has to be dismissed"
        )
    }

    /// And the restart half of the same function still refuses, so sharing it did not widen it.
    func testTheRestartHalfStillRefusesWhileSomethingIsRegistered() throws {
        let token = try XCTUnwrap(ClaudeDelivery.admit())
        defer { token.end() }
        XCTAssertFalse(ClaudeDelivery.admitRestart())
        let after = try XCTUnwrap(ClaudeDelivery.admit(), "a refused close left the gate shut anyway")
        after.end()
    }

    /// **A reservation made before the gate closed must not become a helper after it.**
    ///
    /// Closing the gate against *new* admissions while leaving existing reservations
    /// untouched, so this order stood: a request reserves its slot, the user quits, the farewells go
    /// out and find a slot with no address in it, and only then does the launch produce one. The app
    /// leaves; the helper is still listening in the pane, reachable by anything with the same uid.
    ///
    /// The register cannot dismiss a helper it has no address for, and by then the process is going,
    /// so the answer is that the address is written **before** the helper is created and the write is
    /// refused once the gate is shut. Here that refusal is the whole assertion; what `runInWarp` does
    /// with it — throw before writing the Tab Config — is pinned by the case below.
    func testTerminationDoesNotMissAHelperAttachedAfterFarewell() throws {
        let token = try XCTUnwrap(ClaudeDelivery.admit())
        defer { token.end() }

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(ClaudeDelivery.depart(), farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [], "a reservation with no address had something to dismiss")

        XCTAssertThrowsError(
            try token.record(.warp(helperSocket: sockets.path("term-late"))),
            "a helper was recorded after the farewells had gone out — nothing is left to dismiss it"
        ) { error in
            guard case TerminalError.goingAway = error else {
                return XCTFail("the register refused for another reason: \(error)")
            }
        }
        XCTAssertEqual(
            ClaudeDelivery.liveWarpSockets, [],
            "the refused address went into the register anyway"
        )
    }

    /// And the one place that brings a helper into existence writes the address first, so a refusal
    /// reaches it while nothing has been created — after the Tab Config is written there is no way to
    /// recall the launch. This is a source-order lint, not a runtime launch proof: the passing branch
    /// of `runInWarp` opens a real tab.
    func testNoHelperIsLaunchedAfterTheGateCloses() throws {
        let source = try auditSource(
            Self.coreSource("TerminalRunner.swift"), claim: .sourceOrder
        ).text
        let function = try XCTUnwrap(source.range(of: "public func runInWarp(")).upperBound
        let body = source[function...]
        let record = try XCTUnwrap(
            body.range(of: "try claudeInput.record(.warp(helperSocket: socketPath))"),
            "the launch no longer registers the address it is about to create"
        ).lowerBound
        let write = try XCTUnwrap(body.range(of: "try writeNewFile(path: path")).lowerBound
        let open = try XCTUnwrap(body.range(of: #"try runProcess("/usr/bin/open""#)).lowerBound
        XCTAssertLessThan(record, write, "the Tab Config is written before the register is asked")
        XCTAssertLessThan(record, open, "the tab is opened before the register is asked")
    }

    /// **The order is the invariant**, and it is carried by a value rather than by two adjacent
    /// lines: the farewells take a `Departure`, and the only thing that produces one is shutting the
    /// gate. This case exercises the pair the app terminates with — after it, nothing can be
    /// admitted, and what was registered before is exactly what gets dismissed.
    func testTerminationClosesTheGateBeforeSayingGoodbye() throws {
        let token = try admitted(.warp(helperSocket: sockets.liveHelper("term-order")))
        defer { token.end() }

        let departure = ClaudeDelivery.depart()
        XCTAssertNil(ClaudeDelivery.admit(), "the gate was still open when the farewells could go out")

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(departure, farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [sockets.path("term-order")])
    }

    /// Both ways of leaving reach the same decision, so a third one has to find it too. The two
    /// entries differ by the one argument that says whether they may be refused.
    ///
    /// Read as a **count** rather than as two lines of source. The source-count half is a lint, not
    /// a runtime proof of every termination route. The lines were pinned verbatim and went red the
    /// moment the decision grew a second job: shutting the gate also withdraws the
    /// addresses of helpers that are not there yet) — a gate that fails when the thing it guards is
    /// improved is a gate people delete. What has to stay true is that there is one place, and that
    /// both ways of leaving arrive at it.
    func testRestartAndTerminationShareOneDecision() throws {
        let core = try auditSource(
            Self.coreSource("ClaudeInjector.swift"), claim: .sourceStructure
        ).text
        XCTAssertEqual(
            core.components(separatedBy: "admissionClosed = true").count - 1, 1,
            "the gate is shut in more than one place, so a third way of leaving can shut it differently"
        )

        XCTAssertTrue(ClaudeDelivery.admitRestart(), "the restart path does not reach the decision")
        XCTAssertNil(ClaudeDelivery.admit(), "an admitted restart left the gate open")
        ClaudeDelivery.withdrawRestartAdmission()

        _ = ClaudeDelivery.depart()
        XCTAssertNil(ClaudeDelivery.admit(), "termination left the gate open")
    }

    private static func source(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/LocaleRestartTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
            .path
    }

    private static func appSource(_ name: String) -> String { source("Sources/App/\(name)") }
    private static func coreSource(_ name: String) -> String { source("Sources/Core/\(name)") }
}
