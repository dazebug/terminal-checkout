import Foundation
import XCTest
@testable import Core

// MARK: - Legacy response-byte corpus

final class LegacyRequestByteCorpusTests: XCTestCase {
    private struct Fixture {
        let name: String
        let requestJSON: String
        let responseJSON: String
    }

    private let fixtures = [
        Fixture(
            name: "success",
            requestJSON: #"{"command_template":"z {repo}","variables":{"repo":"remy"}}"#,
            responseJSON: #"{"success":true}"#
        ),
        Fixture(
            name: "unknown variable",
            requestJSON: #"{"command_template":"z {repo}","variables":{"evil":"x"}}"#,
            responseJSON: #"{"error":"Unknown variable: {evil}","success":false}"#
        ),
        Fixture(
            name: "invalid characters",
            requestJSON: #"{"command_template":"z {repo}","variables":{"repo":"a;rm -rf /"}}"#,
            responseJSON: #"{"error":"Invalid characters in input: a;rm -rf \/","success":false}"#
        ),
        Fixture(
            name: "missing command_template",
            requestJSON: #"{"unrelated":1}"#,
            responseJSON: #"{"error":"command_template is required","success":false}"#
        ),
        Fixture(
            name: "unprovided template variable",
            requestJSON: #"{"command_template":"git checkout {main}","variables":{"repo":"r"}}"#,
            responseJSON: #"{"error":"Variable {main} not provided","success":false}"#
        ),
        Fixture(
            name: "claude_inputs must be array",
            requestJSON: #"{"command_template":"z {repo}","variables":{"repo":"r"},"claude_inputs":"x"}"#,
            responseJSON: #"{"error":"claude_inputs must be an array of strings","success":false}"#
        ),
    ]

    func testLegacyRequestResponseBytesStayAtTheCapturedBaseline() throws {
        for fixture in fixtures {
            let request = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(fixture.requestJSON.utf8)) as? [String: Any],
                fixture.name
            )
            let response = handleRequest(json: request) { _ in }
            let actual = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
            XCTAssertEqual(
                actual,
                Data(fixture.responseJSON.utf8),
                "legacy response bytes changed for fixture \(fixture.name)"
            )
        }
    }
}

// MARK: - Batch request contract

final class BatchRequestTests: XCTestCase {
    private func itemResults(_ response: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> [[String: Any]] {
        let raw = try XCTUnwrap(response["items"] as? [Any], file: file, line: line)
        return try raw.enumerated().map { index, value in
            try XCTUnwrap(value as? [String: Any], "item \(index) is not an object", file: file, line: line)
        }
    }

    private func batchRequest(
        command: String = "z {repo}",
        claudeInputs: [String] = [],
        items: Any
    ) -> [String: Any] {
        [
            "command": command,
            "claude_inputs": claudeInputs,
            "items": items,
        ]
    }

    func testBatchItemsUseTheSharedTemplatesAndCanonicalResolverPerItem() throws {
        let request = batchRequest(
            command: "z {repo} && git checkout {branch}",
            claudeInputs: ["PR {number}"],
            items: [
                ["variables": ["repo": "remy", "branch": "fix/one", "number": "1438"]],
                ["variables": ["repo": "worker", "branch": "fix/two", "number": "1439"]],
            ]
        )
        var resolved: [ResolvedRequest] = []
        let response = handleRequest(json: request) { resolved.append($0) }

        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(resolved.map(\.command), [
            "z remy && git checkout fix/one",
            "z worker && git checkout fix/two",
        ])
        XCTAssertEqual(resolved.map(\.claudeInputs), [["PR 1438"], ["PR 1439"]])
        let results = try itemResults(response)
        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result["success"] as? Bool, true)
        }
    }

    func testItemsPresenceSelectsBatchAndCommandTemplateCoexistenceIsAmbiguous() {
        var runCount = 0
        let response = handleRequest(
            json: [
                "command": "z {repo}",
                "command_template": "legacy",
                "items": [["variables": ["repo": "remy"]]],
            ],
            run: { _ in runCount += 1 }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("ambiguous"))
        XCTAssertEqual(runCount, 0)
    }

    func testBatchShapeDoesNotFallThroughToThePre66MissingTemplateResponse() throws {
        let response = handleRequest(
            json: batchRequest(items: [["variables": ["repo": "remy"]]]),
            run: { _ in }
        )
        let actual = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        let pre66 = Data(#"{"error":"command_template is required","success":false}"#.utf8)

        XCTAssertNotEqual(actual, pre66)
        XCTAssertEqual(response["success"] as? Bool, true)
    }

    func testBatchRejectsItemsThatAreNotAnArrayBeforeRunning() {
        var runCount = 0
        let response = handleRequest(
            json: batchRequest(items: "not an array"),
            run: { _ in runCount += 1 }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("items"))
        XCTAssertEqual(runCount, 0)
    }

    func testBatchRejectsAnEmptyItemsArrayBeforeRunning() {
        var runCount = 0
        let response = handleRequest(
            json: batchRequest(items: []),
            run: { _ in runCount += 1 }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("empty"))
        XCTAssertEqual(runCount, 0)
    }

    func testBatchRejectsAnItemThatIsNotAnObjectBeforeRunning() {
        var runCount = 0
        let response = handleRequest(
            json: batchRequest(items: ["not an object"]),
            run: { _ in runCount += 1 }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("object"))
        XCTAssertEqual(runCount, 0)
    }

    func testBatchRejectsMissingOrMalformedVariablesAsTopLevelStructureErrors() {
        let malformedItems: [Any] = [
            ["repo": "remy"],
            ["variables": "not an object"],
            ["variables": ["repo": 1]],
        ]

        for malformed in malformedItems {
            var runCount = 0
            let response = handleRequest(
                json: batchRequest(items: [malformed]),
                run: { _ in runCount += 1 }
            )

            XCTAssertEqual(response["success"] as? Bool, false)
            XCTAssertTrue(
                (response["error"] as? String ?? "").contains("variables"),
                "unexpected response for \(malformed): \(response)"
            )
            XCTAssertNil(response["items"])
            XCTAssertEqual(runCount, 0)
        }
    }

    func testBatchItemLimitIsEightAndExcessIsRejectedBeforeRunning() {
        XCTAssertEqual(batchItemLimit, 25)
        let items = (0...batchItemLimit).map { ["variables": ["repo": "repo\($0)"]] }
        var runCount = 0
        let response = handleRequest(
            json: batchRequest(items: items),
            run: { _ in runCount += 1 }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("8"))
        XCTAssertEqual(runCount, 0)
    }

    func testBatchContentValidationPreflightsEveryItemAndLaunchesNone() throws {
        let response = handleRequest(
            json: batchRequest(items: [
                ["variables": ["repo": "first"]],
                ["variables": [:]],
                ["variables": ["repo": "bad value"]],
                ["variables": ["repo": "last"]],
            ]),
            run: { _ in XCTFail("content validation failure must launch zero items") }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Variable {repo} not provided")
        let results = try itemResults(response)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(
            results[0]["error"] as? String,
            "not launched — batch rejected during validation"
        )
        XCTAssertEqual(results[1]["error"] as? String, "Variable {repo} not provided")
        XCTAssertEqual(results[2]["error"] as? String, "Invalid characters in input: bad value")
        XCTAssertEqual(
            results[3]["error"] as? String,
            "not launched — batch rejected during validation"
        )
        for result in results {
            XCTAssertEqual(result["success"] as? Bool, false)
        }
    }

    func testBatchClaudeInputValidationUsesTheCanonicalResolverForEveryItem() throws {
        let response = handleRequest(
            json: batchRequest(
                claudeInputs: ["!echo ready\n"],
                items: [
                    ["variables": ["repo": "first"]],
                    ["variables": ["repo": "second"]],
                ]
            ),
            run: { _ in XCTFail("Claude-input validation failure must launch zero items") }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String ?? "").contains("claude_inputs"))
        let results = try itemResults(response)
        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertEqual(result["success"] as? Bool, false)
            XCTAssertTrue((result["error"] as? String ?? "").contains("claude_inputs"))
        }
    }

    func testBatchCommandNULRejectionNamesTheCommandWireKey() {
        let response = handleRequest(
            json: batchRequest(
                command: "echo \u{0} unsafe",
                items: [["variables": ["repo": "first"]]]
            ),
            run: { _ in XCTFail("NUL validation must launch zero items") }
        )

        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "command must not contain NUL")
    }

    func testBatchLaunchFailureReturnsOrderedItemResultsAndContinues() throws {
        struct LaunchFailure: Error, CustomStringConvertible {
            var description: String { "launch failed" }
        }

        var commands: [String] = []
        let response = handleRequest(
            json: batchRequest(items: [
                ["variables": ["repo": "first"]],
                ["variables": ["repo": "second"]],
                ["variables": ["repo": "last"]],
            ]),
            run: { resolved in
                commands.append(resolved.command)
                if resolved.command.contains("second") { throw LaunchFailure() }
            }
        )

        XCTAssertEqual(commands, ["z first", "z second", "z last"])
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "1 of 3 items failed")
        let results = try itemResults(response)
        XCTAssertEqual(results[0].count, 1)
        XCTAssertEqual(results[0]["success"] as? Bool, true)
        XCTAssertEqual(results[1]["success"] as? Bool, false)
        XCTAssertEqual(results[1]["error"] as? String, "launch failed")
        XCTAssertEqual(results[2].count, 1)
        XCTAssertEqual(results[2]["success"] as? Bool, true)
    }
}
