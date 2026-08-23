import Core
import XCTest
@testable import App

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
    private var restored: (() -> Bool)!

    override func setUp() {
        super.setUp()
        restored = LocaleRestartGate.isSafeNow
        // No draining here, and the first version of this file pretended otherwise: `endEveryHelper`
        // dismisses helpers, it does not empty the register, so the line that called it "cleanup"
        // was a comment describing something the code does not do — the class this work keeps
        // sweeping for, committed in its own test. Each test balances its own tokens with `defer`
        // instead, and the assertion below is the canary for one that did not.
    }

    override func tearDown() {
        LocaleRestartGate.isSafeNow = restored
        super.tearDown()
    }

    /// The truth table, enumerated: idle, in flight, and finished.
    func testRestartIsRefusedOnlyWhileADeliveryIsInFlight() {
        XCTAssertFalse(ClaudeDelivery.isInFlight, "a previous test left a delivery registered")
        XCTAssertTrue(LocaleRestartGate.isSafeNow(), "idle should allow a restart")

        let token = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-a.sock"))
        defer { ClaudeDelivery.end(token) }
        XCTAssertTrue(ClaudeDelivery.isInFlight)
        XCTAssertFalse(LocaleRestartGate.isSafeNow(), "a restart was allowed during a delivery")

        ClaudeDelivery.end(token)
        XCTAssertFalse(ClaudeDelivery.isInFlight)
        XCTAssertTrue(LocaleRestartGate.isSafeNow(), "the barrier stayed down after the delivery ended")
    }

    /// Two deliveries can overlap — a second button pressed while the first is still typing — so the
    /// barrier has to count rather than latch. A boolean flag here would be lowered by whichever
    /// delivery finished first.
    func testASecondDeliveryKeepsTheBarrierUpUntilBothFinish() {
        let first = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-a.sock"))
        let second = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-b.sock"))
        defer { ClaudeDelivery.end(first); ClaudeDelivery.end(second) }
        ClaudeDelivery.end(first)
        XCTAssertTrue(ClaudeDelivery.isInFlight, "the barrier fell while a delivery was still running")
        XCTAssertFalse(LocaleRestartGate.isSafeNow())
        ClaudeDelivery.end(second)
        XCTAssertFalse(ClaudeDelivery.isInFlight)
    }

    /// Ending a token twice is the `defer`'s prerogative — it must never have to know whether it
    /// already ran — and it must not disturb another delivery.
    func testEndingTheSameDeliveryTwiceIsHarmless() {
        let token = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-a.sock"))
        let other = ClaudeDelivery.begin(.iterm(sessionID: "s1", tty: "/dev/ttys001"))
        defer { ClaudeDelivery.end(token); ClaudeDelivery.end(other) }
        ClaudeDelivery.end(token)
        ClaudeDelivery.end(token)
        XCTAssertTrue(ClaudeDelivery.isInFlight, "a repeated end took another delivery with it")
        ClaudeDelivery.end(other)
        XCTAssertFalse(ClaudeDelivery.isInFlight)
    }

    /// Termination has to reach the helpers, and only the helpers: a session with no helper has
    /// nothing to say goodbye to.
    func testTerminationSaysGoodbyeToEveryLiveHelperAndNothingElse() {
        let warpA = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-a.sock"))
        let warpB = ClaudeDelivery.begin(.warp(helperSocket: "/tmp/tc-test-b.sock"))
        let iterm = ClaudeDelivery.begin(.iterm(sessionID: "s7", tty: "/dev/ttys002"))
        defer { ClaudeDelivery.end(warpA); ClaudeDelivery.end(warpB); ClaudeDelivery.end(iterm) }

        var farewells: [String] = []
        ClaudeDelivery.endEveryHelper(farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, ["/tmp/tc-test-a.sock", "/tmp/tc-test-b.sock"])

        ClaudeDelivery.end(warpA)
        ClaudeDelivery.end(warpB)
        ClaudeDelivery.end(iterm)

        farewells = []
        ClaudeDelivery.endEveryHelper(farewell: { farewells.append($0) })
        XCTAssertEqual(farewells, [], "a finished delivery still had a helper to dismiss")
    }

    /// **The ordering inside the delivery's `defer` is the invariant, not an implementation detail.**
    ///
    /// The farewell goes out before the register is cleared, so that a reader who sees "nothing in
    /// flight" may conclude "no helper of ours is still alive on that account". The reverse order
    /// leaves a window where the barrier is down and a helper is up, which is exactly what the
    /// lifetime defence cannot afford. It is read from the source because reaching that `defer`
    /// means running a real delivery.
    func testTheHelperIsDismissedBeforeTheRegisterIsCleared() throws {
        let source = try String(contentsOfFile: Self.coreSource("ClaudeInjector.swift"), encoding: .utf8)
        let farewell = source.range(of: "if case .warp(let socket) = handle { _ = warpHelperRequest(.bye, socket: socket) }")
        let clear = source.range(of: "ClaudeDelivery.end(deliveryToken)")
        let begin = source.range(of: "let deliveryToken = ClaudeDelivery.begin(handle)")
        XCTAssertNotNil(begin, "the delivery no longer registers itself")
        let farewellStart = try XCTUnwrap(farewell?.lowerBound, "the helper is no longer dismissed")
        let clearStart = try XCTUnwrap(clear?.lowerBound, "the register is no longer cleared")
        XCTAssertLessThan(
            farewellStart, clearStart,
            "the register is cleared before the helper is dismissed, which opens the window this closes"
        )
    }

    /// The one line that consumes the verdict. Reading it is the honest option: the branch that
    /// follows calls `NSApp.terminate`, so a test that took it would end the test run.
    func testThePickerAsksBeforeItRestarts() throws {
        let source = try String(
            contentsOfFile: Self.appSource("SetupWindowController.swift"), encoding: .utf8
        )
        let function = try XCTUnwrap(source.range(of: "@objc private func restartForLanguage() {"))
        let body = source[function.upperBound...]
        let guardIndex = try XCTUnwrap(
            body.range(of: "guard LocaleRestartGate.isSafeNow() else {"),
            "the picker restarts without asking whether it is safe"
        ).lowerBound
        let terminate = try XCTUnwrap(body.range(of: "NSApp.terminate(nil)")).lowerBound
        XCTAssertLessThan(guardIndex, terminate, "the app is terminated before the gate is consulted")
    }

    /// And termination dismisses the helpers before it stops our own socket server: one of those is
    /// a process on the user's machine and the other is ours to lose.
    func testTerminationDismissesHelpersBeforeStoppingOurOwnServer() throws {
        let source = try String(contentsOfFile: Self.appSource("AppDelegate.swift"), encoding: .utf8)
        let function = try XCTUnwrap(source.range(of: "func applicationWillTerminate("))
        let body = source[function.upperBound...]
        let helpers = try XCTUnwrap(
            body.range(of: "ClaudeDelivery.endEveryHelper()"), "termination no longer dismisses helpers"
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
