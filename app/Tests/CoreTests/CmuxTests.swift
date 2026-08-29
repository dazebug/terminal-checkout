import Foundation
import TestSupport
import XCTest
@testable import Core

final class CmuxTests: XCTestCase {
    func testCmuxCLICandidatePathsUseBundleLocationsBeforePATH() {
        let candidates = cmuxCLICandidatePaths(
            homeDirectory: "/Users/tester",
            path: "/custom/bin:/another/bin"
        )

        XCTAssertEqual(
            candidates,
            [
                "/Applications/cmux.app/Contents/Resources/bin/cmux",
                "/Users/tester/Applications/cmux.app/Contents/Resources/bin/cmux",
                "/opt/homebrew/bin/cmux",
                "/usr/local/bin/cmux",
                "/custom/bin/cmux",
                "/another/bin/cmux",
            ]
        )
    }

    func testFindCmuxCLIReturnsTheFirstExecutableCandidate() {
        let found = findCmuxCLI(
            homeDirectory: "/Users/tester",
            path: "/custom/bin",
            isExecutable: { path in path == "/custom/bin/cmux" }
        )

        XCTAssertEqual(found, "/custom/bin/cmux")
    }

    func testCmuxSocketPathOnlyReportsAnExistingSocket() {
        let expected = "/Users/tester/.local/state/cmux/cmux.sock"

        XCTAssertEqual(
            cmuxSocketPath(homeDirectory: "/Users/tester", fileExists: { $0 == expected }),
            expected
        )
        XCTAssertNil(cmuxSocketPath(homeDirectory: "/Users/tester", fileExists: { _ in false }))
    }

    /// J2 red reproduction: retry is safe only when the first request demonstrably never reached
    /// the server. A timeout or invalid JSON can follow a server-side workspace creation, so the
    /// implementation must rethrow those uncertain outcomes instead of creating a duplicate.
    func testCmuxRecoveryActionRetriesOnlyATypedReachabilityFailure() {
        let measuredErrors = [
            "Error: Failed to connect to socket at /tmp/…/dead.sock (Connection refused, errno 61)",
            "Error: Socket not found at /tmp/…/nonexistent.sock"
        ]
        for measuredError in measuredErrors {
            let classified = classifyCmuxCLIFailure(measuredError)
            guard case .cmuxNotReachable = classified else {
                XCTFail("the measured connection error was not typed as unreachable")
                continue
            }
            XCTAssertEqual(
                cmuxRecoveryAction(
                    afterFirstFailure: classified, launchAttempted: false
                ),
                .launchAndRetry
            )
            XCTAssertEqual(
                cmuxRecoveryAction(
                    afterFirstFailure: classified, launchAttempted: true
                ),
                .rethrow
            )
        }

        XCTAssertEqual(
            cmuxRecoveryAction(
                afterFirstFailure: .cmuxSocketDenied, launchAttempted: false
            ),
            .rethrow
        )
        XCTAssertEqual(
            cmuxRecoveryAction(
                afterFirstFailure: .timeout("cmux socket"), launchAttempted: false
            ),
            .rethrow
        )
        XCTAssertEqual(
            cmuxRecoveryAction(
                afterFirstFailure: .cmuxRPCFailed(
                    "workspace.create: invalid JSON response"
                ), launchAttempted: false
            ),
            .rethrow
        )
    }

    /// Both forms are driver measurements from 2026-08-27, and the `Error: ` prefix is part of
    /// the cmux CLI's stderr output. The earlier no-prefix test passed while blocking the real
    /// auto-launch path, so both measured inputs must remain anchored here.
    func testCmuxCLIFailureClassifierUsesMeasuredStaleAndMissingSocketErrors() {
        let measuredErrors = [
            "Error: Failed to connect to socket at /tmp/…/dead.sock (Connection refused, errno 61)",
            "Error: Socket not found at /tmp/…/nonexistent.sock"
        ]
        for measuredError in measuredErrors {
            let classified = classifyCmuxCLIFailure(measuredError)
            guard case .cmuxNotReachable(let detail) = classified else {
                XCTFail("the measured CLI error was not typed as unreachable")
                continue
            }
            XCTAssertEqual(detail, measuredError)
        }
    }

    /// N2 red reproduction: the CLI's `Error: ` prefix is part of the measured connection
    /// evidence. A prefixless message is not an anchor; if cmux changes its output, retry must
    /// close conservatively rather than claim that the request never reached the server.
    func testCmuxCLIFailureClassifierRequiresTheMeasuredErrorPrefix() {
        let unprefixedErrors = [
            "Failed to connect to socket at /tmp/x",
            "Socket not found at /tmp/x",
        ]
        for message in unprefixedErrors {
            let classified = classifyCmuxCLIFailure(message)
            guard case .cmuxRPCFailed = classified else {
                XCTFail("an unmeasured prefixless error authorized a retry")
                continue
            }
        }
    }

    /// L2: a post-create hook can contain the same filesystem words after the server already made
    /// a workspace, so it must remain an ordinary RPC failure and never authorize a retry.
    func testCmuxCLIFailureDoesNotTreatPostCreateHookFailureAsConnectionLoss() {
        let message = "workspace.create: post-create hook: no such file or directory"
        let classified = classifyCmuxCLIFailure(message)
        guard case .cmuxRPCFailed = classified else {
            return XCTFail("post-create failure was unexpectedly typed as unreachable")
        }
        XCTAssertEqual(
            cmuxRecoveryAction(afterFirstFailure: classified, launchAttempted: false),
            .rethrow
        )
    }

    /// J5 red reproduction: readiness must come from a lightweight RPC response, with denial as
    /// an immediate terminal outcome rather than another poll. The current socket-file stub cannot
    /// distinguish either response yet.
    func testCmuxReadinessOutcomeStopsPollingOnDenied() {
        XCTAssertEqual(cmuxReadinessOutcome(from: nil), .ready)
        XCTAssertEqual(
            cmuxReadinessOutcome(from: .cmuxSocketDenied), .denied
        )
        XCTAssertEqual(
            cmuxReadinessOutcome(from: .timeout("debug.terminals")), .notReady
        )
    }

    /// L7: launch status and the last non-denial readiness error survive a bounded poll instead of
    /// collapsing into the generic timeout sentence.
    func testCmuxReadinessTimeoutDescriptionKeepsLaunchAndLastError() {
        let description = cmuxReadinessTimeoutDescription(
            launchExitStatus: 1, lastError: .cmuxRPCFailed("bundle not found")
        )
        XCTAssertTrue(description.contains("1"), description)
        XCTAssertTrue(description.contains("bundle not found"), description)
        XCTAssertEqual(
            cmuxReadinessTimeoutDescription(launchExitStatus: nil, lastError: nil),
            "cmux readiness"
        )
    }

    func testCmuxRPCFailureLogSuppressesRepeatedSameSurfaceMessage() {
        CmuxRPCFailureLog.reset()
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
        XCTAssertFalse(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
    }

    /// G4: a successful read must reopen logging for that surface, rather than letting a stale
    /// process-wide message suppress a later failure.
    func testCmuxRPCFailureLogResetsAfterScreenReadSuccess() {
        CmuxRPCFailureLog.reset()
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
        CmuxRPCFailureLog.recordScreenReadSuccess(surface: "surface-a")
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
    }

    /// G4: the same error text from another surface must not be swallowed by the first surface's
    /// suppression state.
    func testCmuxRPCFailureLogSeparatesSurfaces() {
        CmuxRPCFailureLog.reset()
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-b", message: "surface.read_text failed"
            )
        )
    }

    /// H5 red reproduction: a delivery that ends in failure must forget its surface so the next
    /// attempt can report the same RPC error again.
    func testCmuxRPCFailureLogForgetsFailuresAtDeliveryEnd() {
        CmuxRPCFailureLog.reset()
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
        CmuxRPCFailureLog.forgetScreenReadFailures(surface: "surface-a")
        XCTAssertTrue(
            CmuxRPCFailureLog.shouldLogScreenReadFailure(
                surface: "surface-a", message: "surface.read_text failed"
            )
        )
    }

    /// H5 red reproduction: a stream of failed surfaces must not grow the process-lifetime map
    /// without bound; 32 entries is the chosen backstop for the green implementation.
    func testCmuxRPCFailureLogHasBoundedFailureSurfaceState() {
        CmuxRPCFailureLog.reset()
        for index in 0..<40 {
            XCTAssertTrue(
                CmuxRPCFailureLog.shouldLogScreenReadFailure(
                    surface: "surface-\(index)", message: "surface.read_text failed"
                )
            )
        }
        XCTAssertLessThanOrEqual(CmuxRPCFailureLog.testOnlyScreenReadFailureCount(), 32)
    }

    func testCmuxRPCMethodNamesAreTheFourSupportedMethods() {
        XCTAssertEqual(cmuxWorkspaceCreateMethod, "workspace.create")
        XCTAssertEqual(cmuxSurfaceSendTextMethod, "surface.send_text")
        XCTAssertEqual(cmuxSurfaceReadTextMethod, "surface.read_text")
        XCTAssertEqual(cmuxDebugTerminalsMethod, "debug.terminals")
    }

    func testCmuxRPCArgumentsAreASCIIAndPreserveJSONValues() throws {
        let params: [String: Any] = [
            "literal": "\\n",
            "carriageReturn": "\r",
            "message": "한글",
            "longValue": String(repeating: "x", count: 513),
        ]

        let arguments = try cmuxRPCArguments(method: cmuxSurfaceSendTextMethod, params: params)

        XCTAssertEqual(arguments.count, 3)
        XCTAssertEqual(arguments[0], "rpc")
        XCTAssertEqual(arguments[1], cmuxSurfaceSendTextMethod)
        XCTAssertTrue(arguments.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })

        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(arguments[2].utf8)) as? [String: Any]
        )
        XCTAssertEqual(decoded["literal"] as? String, "\\n")
        XCTAssertEqual(decoded["carriageReturn"] as? String, "\r")
        XCTAssertEqual(decoded["message"] as? String, "한글")
        XCTAssertEqual(Array((decoded["message"] as? String ?? "").utf8), Array("한글".utf8))
        XCTAssertEqual((decoded["longValue"] as? String)?.utf8.count, 513)
    }

    func testCmuxRPCResponseParsesWorkspaceIdentifiers() throws {
        let response = try cmuxRPCResponse(
            Data(
                """
                {"workspace_id":"workspace-1","surface_id":"surface-1","window_id":"window-1","workspace_ref":"workspace-ref","surface_ref":"surface-ref","window_ref":"window-ref","group_id":"group-1","group_ref":"group-ref"}
                """.utf8
            )
        )

        XCTAssertEqual(response["workspace_id"] as? String, "workspace-1")
        XCTAssertEqual(response["surface_id"] as? String, "surface-1")
        XCTAssertEqual(response["window_id"] as? String, "window-1")
        XCTAssertEqual(response["workspace_ref"] as? String, "workspace-ref")
        XCTAssertEqual(response["surface_ref"] as? String, "surface-ref")
        XCTAssertEqual(response["window_ref"] as? String, "window-ref")
        XCTAssertEqual(response["group_id"] as? String, "group-1")
        XCTAssertEqual(response["group_ref"] as? String, "group-ref")
    }

    func testCmuxRPCResponseParsesQueuedAndText() throws {
        let sendResponse = try cmuxRPCResponse(Data("{\"queued\":true}".utf8))
        XCTAssertEqual(sendResponse["queued"] as? Bool, true)

        let readResponse = try cmuxRPCResponse(Data("{\"text\":\"한글\\r\\n\"}".utf8))
        XCTAssertEqual(readResponse["text"] as? String, "한글\r\n")
    }

    func testCmuxRPCFailuresDistinguishSocketDenialAndMethod() {
        switch cmuxRPCFailure(method: cmuxSurfaceReadTextMethod, status: 1, stderr: "Access denied") {
        case .cmuxSocketDenied:
            break
        default:
            XCTFail("Access denied must be classified as a socket denial")
        }

        switch cmuxRPCFailure(method: cmuxSurfaceReadTextMethod, status: 1, stderr: "unknown method") {
        case .cmuxRPCFailed(let message):
            XCTAssertTrue(message.contains(cmuxSurfaceReadTextMethod))
        default:
            XCTFail("A non-access RPC failure must include its method")
        }
    }

    func testItem5CmuxRunParametersUseFocusOnlyAndPreserveCommandCR() {
        let workspace = cmuxWorkspaceCreateParameters()
        XCTAssertEqual(workspace["focus"] as? Bool, true)
        XCTAssertNil(workspace["window_id"])
        XCTAssertNil(workspace["cwd"])

        let command = cmuxSurfaceSendTextParameters(
            surfaceID: "surface-1", text: "echo 한글\r"
        )
        XCTAssertEqual(command["surface_id"] as? String, "surface-1")
        XCTAssertEqual(command["text"] as? String, "echo 한글\r")
    }

    func testItem5CmuxWorkspaceIdentifiersRequireWorkspaceAndSurface() {
        let identifiers = cmuxWorkspaceIdentifiers(from: [
            "workspace_id": "workspace-1",
            "surface_id": "surface-1",
        ])
        XCTAssertEqual(identifiers?.workspaceID, "workspace-1")
        XCTAssertEqual(identifiers?.surfaceID, "surface-1")

        XCTAssertNil(cmuxWorkspaceIdentifiers(from: ["workspace_id": "workspace-1"]))
        XCTAssertNil(cmuxWorkspaceIdentifiers(from: ["surface_id": "surface-1"]))
    }

    func testItem9CmuxTTYNameParsesTheMatchingSurface() {
        let json = Data(
            """
            {"terminals":[{"surface_id":"surface-other","tty":"ttys019"},{"surface_id":"surface-1","tty":"ttys020"}]}
            """.utf8
        )

        XCTAssertEqual(cmuxTTYName(debugTerminalsJSON: json, surfaceID: "surface-1"), "/dev/ttys020")
    }

    func testItem9CmuxTTYNameReturnsNilForNullTTY() {
        let json = Data(
            #"{"terminals":[{"surface_id":"surface-1","tty":null}]}"#.utf8
        )

        XCTAssertNil(cmuxTTYName(debugTerminalsJSON: json, surfaceID: "surface-1"))
    }

    func testItem9CmuxTTYNameReturnsNilForMissingSurface() {
        let json = Data(
            #"{"terminals":[{"surface_id":"surface-other","tty":"ttys020"}]}"#.utf8
        )

        XCTAssertNil(cmuxTTYName(debugTerminalsJSON: json, surfaceID: "surface-1"))
    }

    func testItem9CmuxTTYNameReturnsNilForInvalidJSON() {
        XCTAssertNil(cmuxTTYName(debugTerminalsJSON: Data("not json".utf8), surfaceID: "surface-1"))
    }

    /// **R1-j reproduction:** under Claude's Kitty keyboard protocol flag 1,
    /// cmux's key-event path for `ctrl+u` is ineffective; a separate `surface.send_text`
    /// call carrying 0x15 clears the text. A separate 0x7F call then removes the `!` shell-mode
    /// prefix. Sending both bytes in one text call leaves `!`, while two calls in order empty it.
    func testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace() {
        XCTAssertEqual(
            cmuxSendOperations(surfaceID: "surface-1", text: claudeClearInputKey),
            [
                CmuxRPCOperation(
                    method: cmuxSurfaceSendTextMethod,
                    params: ["surface_id": "surface-1", "text": "\u{15}"]
                ),
                CmuxRPCOperation(
                    method: cmuxSurfaceSendTextMethod,
                    params: ["surface_id": "surface-1", "text": "\u{7F}"]
                ),
            ]
        )
    }

    /// D8 routes the marker, both clear bytes, body, and CR through the same raw text carrier.
    /// The clear key is deliberately two operations so cmux cannot reorder the buffered bytes.
    func testItem10EveryCmuxByteGoesThroughSendText() {
        let inputs = ["tcabcdefghij", claudeClearInputKey, "!echo x", claudeSubmitKey]
        let operations = inputs.flatMap {
            cmuxSendOperations(surfaceID: "surface-1", text: $0)
        }

        XCTAssertEqual(operations.count, 5)
        XCTAssertTrue(operations.allSatisfy { $0.method == cmuxSurfaceSendTextMethod })
    }

    /// F3 reproduction: `send(_:io:)` checks the session once, then the cmux branch emits the
    /// two clear RPCs below it. CLAUDE.md requires every byte-emitting site to pass through that
    /// gate and re-check session identity; if the first check passes and the second fails, only
    /// the first operation may be sent.
    func testItem10CmuxOperationsRecheckSessionBeforeEveryRPC() {
        let operations = cmuxSendOperations(surfaceID: "surface-1", text: claudeClearInputKey)
        var sessionChecks = 0
        var sent: [CmuxRPCOperation] = []

        let result = runCmuxOperations(
            operations,
            sessionIsUnchanged: {
                sessionChecks += 1
                return sessionChecks == 1
            },
            send: { operation in
                sent.append(operation)
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(sent, Array(operations.prefix(1)))
        XCTAssertEqual(sessionChecks, 2)
    }

    func testItem10CmuxBodyUsesSurfaceSendTextWithoutChangingIt() {
        XCTAssertEqual(
            cmuxSendOperations(surfaceID: "surface-1", text: "한글"),
            [
                CmuxRPCOperation(
                    method: cmuxSurfaceSendTextMethod,
                    params: ["surface_id": "surface-1", "text": "한글"]
                )
            ]
        )
    }

    func testItem10CmuxCRUsesOneSurfaceSendTextCR() {
        XCTAssertEqual(
            cmuxSendOperations(surfaceID: "surface-1", text: claudeSubmitKey),
            [
                CmuxRPCOperation(
                    method: cmuxSurfaceSendTextMethod,
                    params: ["surface_id": "surface-1", "text": "\r"]
                )
            ]
        )
    }

    func testItem11CmuxScreenTextRequiresTheTextField() {
        let parameters = cmuxSurfaceReadTextParameters(surfaceID: "surface-1")
        XCTAssertEqual(parameters["surface_id"] as? String, "surface-1")
        XCTAssertEqual(cmuxScreenText(from: ["text": "screen"]), "screen")
        XCTAssertNil(cmuxScreenText(from: ["error": "internal_error"]))
    }

    func testItem13CmuxSocketStatusIncludesNotInstalledState() {
        guard case .notInstalled = CmuxSocketStatus.notInstalled else {
            XCTFail("cmux status must distinguish an absent CLI")
            return
        }
    }

    func testItem13CmuxPingResultOverridesMissingDefaultSocket() {
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: false, pingStatus: 0, stdout: "PONG\n", stderr: ""
            ),
            .reachable
        )
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: false, pingStatus: 1, stdout: "not running", stderr: ""
            ),
            .notRunning
        )
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: false, pingStatus: 1, stdout: "", stderr: "Access denied"
            ),
            .denied
        )
    }

    func testItem13CmuxSocketStatusClassifiesAccessDenied() {
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: true, pingStatus: 1, stdout: "", stderr: "ACCESS DENIED"
            ),
            .denied
        )
    }

    func testItem13CmuxSocketStatusClassifiesSuccessfulPong() {
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: true, pingStatus: 0, stdout: "PONG\n", stderr: ""
            ),
            .reachable
        )
    }

    func testItem13CmuxSocketStatusPreservesFailureSummary() {
        XCTAssertEqual(
            classifyCmuxSocketStatus(
                socketExists: true, pingStatus: 2, stdout: "unexpected reply\n", stderr: ""
            ),
            .failed("unexpected reply")
        )
    }

    // MARK: - Canonical-limit send gate

    // Measured on Darwin 25.4.0 (pty probe, master draining echo like a terminal emulator):
    // a canonical-mode tty keeps exactly 1024 bytes of an unread line and silently discards the
    // rest, CR included — the writer sees every byte accepted. 1023 bytes + CR survive whole.
    func testCanonicalLineLimitIsTheMeasured1024() {
        XCTAssertEqual(darwinCanonicalLineLimit, 1024)
    }

    func testCommandSendGateSendsOnlyWhenTheShellIsReading() {
        XCTAssertEqual(
            cmuxCommandSendGate(rawModeObserved: true, deadlineExpired: false, payloadByteCount: 5000),
            .send
        )
        XCTAssertEqual(
            cmuxCommandSendGate(rawModeObserved: true, deadlineExpired: true, payloadByteCount: 5000),
            .send
        )
        XCTAssertEqual(
            cmuxCommandSendGate(rawModeObserved: false, deadlineExpired: false, payloadByteCount: 10),
            .waitLonger
        )
        // "Cannot tell" is not "raw" — the same rule as the claude session gate.
        XCTAssertEqual(
            cmuxCommandSendGate(rawModeObserved: nil, deadlineExpired: false, payloadByteCount: 10),
            .waitLonger
        )
    }

    func testCommandSendGateFallsBackBySizeAtTheDeadline() {
        XCTAssertEqual(
            cmuxCommandSendGate(
                rawModeObserved: nil, deadlineExpired: true,
                payloadByteCount: darwinCanonicalLineLimit
            ),
            .sendDespiteCanonical
        )
        XCTAssertEqual(
            cmuxCommandSendGate(
                rawModeObserved: false, deadlineExpired: true,
                payloadByteCount: darwinCanonicalLineLimit + 1
            ),
            .refuseTooLong
        )
    }

    // MARK: - Channels

    func testCmuxChannelsCarryTheirOwnBundleAndSocketPointer() {
        XCTAssertEqual(CmuxChannel.stable.bundleID, "com.cmuxterm.app")
        XCTAssertEqual(CmuxChannel.nightly.bundleID, "com.cmuxterm.app.nightly")
        XCTAssertEqual(CmuxChannel.stable.lastSocketPathFileName, "last-socket-path")
        XCTAssertEqual(CmuxChannel.nightly.lastSocketPathFileName, "nightly-last-socket-path")
    }

    func testCmuxNightlyCLICandidatesAreTheBundlePathsOnly() {
        // A bare `cmux` on PATH cannot testify to its channel, so nightly searches only the
        // bundle installations.
        XCTAssertEqual(
            cmuxCLICandidatePaths(channel: .nightly, homeDirectory: "/Users/u", path: "/opt/x:/usr/bin"),
            [
                "/Applications/cmux NIGHTLY.app/Contents/Resources/bin/cmux",
                "/Users/u/Applications/cmux NIGHTLY.app/Contents/Resources/bin/cmux",
            ]
        )
    }

    func testCmuxStableCLICandidatesAreUnchangedByTheChannelParameter() {
        XCTAssertEqual(
            cmuxCLICandidatePaths(homeDirectory: "/Users/u", path: nil),
            [
                "/Applications/cmux.app/Contents/Resources/bin/cmux",
                "/Users/u/Applications/cmux.app/Contents/Resources/bin/cmux",
                "/opt/homebrew/bin/cmux",
                "/usr/local/bin/cmux",
            ]
        )
    }

    func testCmuxResolvedSocketPathRequiresALivePointerTarget() {
        XCTAssertEqual(
            cmuxResolvedSocketPath(pointerContents: "/tmp/a.sock\n", fileExists: { $0 == "/tmp/a.sock" }),
            "/tmp/a.sock"
        )
        XCTAssertNil(cmuxResolvedSocketPath(pointerContents: "/tmp/a.sock\n", fileExists: { _ in false }))
        XCTAssertNil(cmuxResolvedSocketPath(pointerContents: "   \n", fileExists: { _ in true }))
        XCTAssertNil(cmuxResolvedSocketPath(pointerContents: nil, fileExists: { _ in true }))
    }

    func testCmuxRPCEnvironmentPinsTheSocketAndKeepsTheInheritedEnvironment() {
        XCTAssertNil(cmuxRPCEnvironment(socketPath: nil, base: ["PATH": "/usr/bin"]))
        XCTAssertEqual(
            cmuxRPCEnvironment(socketPath: "/tmp/a.sock", base: ["PATH": "/usr/bin"]),
            ["PATH": "/usr/bin", "CMUX_SOCKET_PATH": "/tmp/a.sock"]
        )
    }

    func testTerminalStoresCmuxNightlyAsItsOwnIdentifier() {
        XCTAssertEqual(Terminal(storedValue: "cmux-nightly"), .cmuxNightly)
        XCTAssertEqual(Terminal.cmuxNightly.rawValue, "cmux-nightly")
        XCTAssertEqual(Terminal.cmuxNightly.cmuxChannel, .nightly)
        XCTAssertEqual(Terminal.cmux.cmuxChannel, .stable)
        XCTAssertNil(Terminal.warp.cmuxChannel)
    }

}
