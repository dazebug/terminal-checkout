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

    /// The socket response is Core's response exactly. This is a shape contract, not a list
    /// of locale fields that happens not to be appended: the request path must call `handleRequest`
    /// directly and must not inspect the decoded payload or compose a protocol answer around it.
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

    /// **The socket server does not publish a locale.** The GUI owns publication; this request path
    /// must not become a second writer or compose a generation into a command response.
    ///
    /// This is a **lint**, not a proof — it reads the source rather than the behaviour, and a
    /// different spelling of the same mistake would slip past it. Publication's own writer tests
    /// live with the publication machinery and are not this request-path contract.
    /// **The subject is `serve`, not the file.** It used to read the whole of `HostServer.swift`,
    /// and since round 17 that file also holds the launch publication — so "this file does not
    /// publish" became false about the file while staying true about the request path, which is the
    /// thing the claim was ever about (round 18, while narrowing the same contract).
    func testTheServerPublishesAsAReaderOnly() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/App/HostServer.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(
            source.range(of: "private func serve(fd: Int32) {"),
            "the request path is no longer where this lint reads it from"
        ).upperBound
        let serve = String(source[start...])
        XCTAssertFalse(
            serve.contains("LocaleState.publish("),
            "the socket server publishes a locale instead of returning Core's response"
        )
    }
}
