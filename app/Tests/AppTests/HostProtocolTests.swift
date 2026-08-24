import Core
import XCTest
@testable import App

/// The request path has no protocol branch left between JSON decoding and Core's response.
final class HostProtocolTests: XCTestCase {
    /// `#filePath` and not `Bundle`: the sources are what this asserts about, and a bundle would
    /// answer with whatever the build happened to copy (D7).
    private var hostServerSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Sources/App/HostServer.swift")
            .path
    }

    /// The socket response is Core's response exactly. The source assertions pin the request-path
    /// shape — direct `handleRequest`, no decoded-payload inspection, and no request-shape branch —
    /// while the live socket assertion below compares the complete response, so a wrapper that adds
    /// a field fails even when it preserves the call spelling.
    /// The installation record is a separate invariant: it is stamped for every framed message
    /// before parsing, so malformed input counts too (CLAUDE.md:45).
    func testServeUsesHandleRequestOutputAndRecordsBeforeParsing() throws {
        let source = try String(contentsOfFile: hostServerSourcePath, encoding: .utf8)
        let requestPathStart = try XCTUnwrap(source.range(of: "let response = execQueue.sync {")).lowerBound
        let responseEncoding = try XCTUnwrap(source.range(of: "let payload =")).lowerBound
        let requestPath = String(source[requestPathStart..<responseEncoding])
        XCTAssertTrue(
            requestPath.contains("handleRequest(json: json, baseDirectory: Settings.baseDirectory"),
            "the socket path no longer returns handleRequest's response directly"
        )
        XCTAssertFalse(requestPath.contains("json["), "the socket path inspects a request field")
        XCTAssertFalse(requestPath.contains("query"), "the socket path special-cases a request shape")
        XCTAssertFalse(requestPath.contains("switch"), "the socket path branches on a request shape")

        let record = try XCTUnwrap(source.range(of: "Settings.recordRequestEvidence()")).lowerBound
        let parse = try XCTUnwrap(source.range(of: "let json = ((try? JSONSerialization.jsonObject")).lowerBound
        let recordOffset = source.distance(from: source.startIndex, to: record)
        let parseOffset = source.distance(from: source.startIndex, to: parse)
        XCTAssertLessThan(recordOffset, parseOffset, "the install record moved after JSON parsing")

        let expected = handleRequest(
            json: rejectedCommandProbe, baseDirectory: Settings.baseDirectory
        ) { _ in }
        let directory = "/tmp/tc-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        let server = HostServer(socketPath: path)
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(rejectedCommandProbe, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer, "the server did not answer the command")
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        XCTAssertEqual(
            actualBytes, expectedBytes,
            "the socket response differs from handleRequest's complete output"
        )
    }

    /// **The internal-error literal is the one response that stays bare, and not by omission.**
    ///
    /// `serve` builds it when `JSONSerialization` could not turn the Core response into bytes. The
    /// app emits it as a transport fallback, not as a second protocol response to decorate.
    ///
    /// The fallback has no locale claim — a response that could not be composed says nothing about
    /// the language.
    func testTheInternalErrorLiteralIsNotComposedAndCarriesNothing() throws {
        let literal = #"{"success":false,"error":"internal error"}"#
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [String: Any]
        )
        XCTAssertEqual(parsed.count, 2, "the internal-error literal grew a protocol field")
        XCTAssertEqual(parsed["success"] as? Bool, false)
        XCTAssertEqual(parsed["error"] as? String, "internal error")
        // and the source still emits exactly that literal — a lint, because the branch needs a
        // failed serialisation to reach
        let source = try String(contentsOfFile: hostServerSourcePath, encoding: .utf8)
        XCTAssertTrue(
            source.contains(#"Data(#"{"success":false,"error":"internal error"}"#),
            "the fallback literal moved; decide again whether it may claim a locale"
        )
    }

}
