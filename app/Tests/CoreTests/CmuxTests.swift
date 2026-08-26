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

    func testCmuxRPCMethodNamesAreTheFiveSupportedMethods() {
        XCTAssertEqual(cmuxWorkspaceCreateMethod, "workspace.create")
        XCTAssertEqual(cmuxSurfaceSendTextMethod, "surface.send_text")
        XCTAssertEqual(cmuxSurfaceSendKeyMethod, "surface.send_key")
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

    func testItem10CmuxClearInputUsesCtrlUThenBackspace() {
        XCTAssertEqual(
            cmuxSendOperations(surfaceID: "surface-1", text: claudeClearInputKey),
            [
                CmuxRPCOperation(
                    method: cmuxSurfaceSendKeyMethod,
                    params: ["surface_id": "surface-1", "key": "ctrl+u"]
                ),
                CmuxRPCOperation(
                    method: cmuxSurfaceSendKeyMethod,
                    params: ["surface_id": "surface-1", "key": "backspace"]
                ),
            ]
        )
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
}
