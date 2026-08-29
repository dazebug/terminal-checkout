import Core
import Darwin
import TestSupport
import XCTest
@testable import App

let rejectedCommandProbe: [String: Any] = [
    "command_template": "z {repo}", "variables": ["evil": "x"],
]

/// What the retained response oracle does: keep trying the path until something is there, send one
/// request, and wait for the answer. Its two facts are read from the test's thread under a lock.
final class RelayAtTheDoor {
    private let lock = NSLock()
    private var asked_ = false
    private var answer_: [String: Any]?

    var asked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return asked_
    }

    var answer: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return answer_
    }

    func connectAndAsk(_ request: [String: Any], at path: String, givingUp seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        Thread.detachNewThread { [self] in
            var connection: Int32?
            while connection == nil, Date() < deadline {
                connection = connectToUnixSocket(path: path)
                if connection == nil { usleep(2_000) }
            }
            guard let connection else { return }
            defer { close(connection) }
            guard let payload = try? JSONSerialization.data(withJSONObject: request),
                  writeFramedMessage(payload, toFD: connection)
            else { return }
            lock.lock()
            asked_ = true
            lock.unlock()

            guard let data = readFramedMessage(fromFD: connection),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return }
            lock.lock()
            answer_ = json
            lock.unlock()
        }
    }
}

/// The request path has no protocol branch left between JSON decoding and Core's response.
final class HostProtocolTests: XCTestCase {
    /// `#filePath` and not `Bundle`: the sources are what this asserts about, and a bundle would
    /// answer with whatever the build happened to copy.
    private var hostServerSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Sources/App/HostServer.swift")
            .path
    }

    private var previousTerminal: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousTerminal = UserDefaults.standard.string(forKey: "terminal")
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        if let previousTerminal {
            UserDefaults.standard.set(previousTerminal, forKey: "terminal")
        } else {
            UserDefaults.standard.removeObject(forKey: "terminal")
        }
    }

    /// The socket response is Core's response exactly. The source assertions pin the request-path
    /// shape — direct `handleRequest`, no decoded-payload inspection, and no request-shape branch —
    /// while the live socket assertion below compares the complete response, so a wrapper that adds
    /// a field fails even when it preserves the call spelling.
    /// The installation record is a separate invariant: it is stamped for every framed message
    /// before parsing, so malformed input counts too (CLAUDE.md:45).
    func testServeUsesHandleRequestOutputAndRecordsBeforeParsing() throws {
        let source = try auditSource(hostServerSourcePath, claim: .sourceStructure).text
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
        let source = try auditSource(hostServerSourcePath, claim: .sourceLiteral).text
        XCTAssertTrue(
            source.contains(#"Data(#"{"success":false,"error":"internal error"}"#),
            "the fallback literal moved; decide again whether it may claim a locale"
        )
    }

    /// A legacy request snapshots the settings terminal only after it reaches the serial launch queue.
    func testLegacyTerminalSnapshotOccursAfterExecQueueAdmission() throws {
        let request: [String: Any] = ["command_template": "echo terminal-snapshot"]
        let directory = "/tmp/tc-terminal-snapshot-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        let firstRunnerEntered = DispatchSemaphore(value: 0)
        let releaseFirstRunner = DispatchSemaphore(value: 0)
        let secondBeforeQueue = DispatchSemaphore(value: 0)
        let releaseSecondBeforeQueue = DispatchSemaphore(value: 0)
        let admissionLock = NSLock()
        var admissionCount = 0
        let lock = NSLock()
        var terminals: [Terminal] = []
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, terminal, _ in
                lock.lock()
                let index = terminals.count
                terminals.append(terminal)
                lock.unlock()
                if index == 0 {
                    firstRunnerEntered.signal()
                    releaseFirstRunner.wait()
                }
                return .none
            },
            beforeExecQueueAdmission: {
                admissionLock.lock()
                admissionCount += 1
                let index = admissionCount
                admissionLock.unlock()
                if index == 2 {
                    secondBeforeQueue.signal()
                    releaseSecondBeforeQueue.wait()
                }
            }
        )
        try server.start()
        defer {
            releaseFirstRunner.signal()
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let first = RelayAtTheDoor()
        first.connectAndAsk(request, at: path, givingUp: 10)
        XCTAssertEqual(
            firstRunnerEntered.wait(timeout: .now() + 2), .success,
            "the first request did not reach the injected runner"
        )

        let second = RelayAtTheDoor()
        second.connectAndAsk(request, at: path, givingUp: 10)
        XCTAssertEqual(
            secondBeforeQueue.wait(timeout: .now() + 2), .success,
            "the server did not hold the second request before queue admission"
        )

        UserDefaults.standard.set(Terminal.warp.rawValue, forKey: "terminal")
        releaseSecondBeforeQueue.signal()
        releaseFirstRunner.signal()

        let answerDeadline = Date().addingTimeInterval(10)
        while (first.answer == nil || second.answer == nil), Date() < answerDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        lock.lock()
        let observed = terminals
        lock.unlock()
        XCTAssertEqual(observed, [.iterm, .warp])
    }

    /// A batch stops launching at the response budget and marks the remaining items as unlaunched.
    func testBatchLaunchesStopBeforeResponseDeadline() throws {
        let request: [String: Any] = [
            "command": "echo deadline",
            "items": (1...8).map { ["variables": ["repo": "repo\($0)"]] },
        ]
        let directory = "/tmp/tc-batch-deadline-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        let clockLock = NSLock()
        var fakeNow = Date(timeIntervalSince1970: 0)
        var fakeMonotonicNow: TimeInterval = 0
        var launches = 0
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                clockLock.lock()
                launches += 1
                fakeNow = fakeNow.addingTimeInterval(30)
                fakeMonotonicNow += 30
                clockLock.unlock()
                return .none
            },
            now: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeNow
            },
            monotonicNow: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeMonotonicNow
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        XCTAssertEqual(actual["success"] as? Bool, false)
        XCTAssertEqual(actual["error"] as? String, "3 of 8 items failed")

        let results = try XCTUnwrap(actual["items"] as? [[String: Any]])
        XCTAssertEqual(results.count, 8)
        clockLock.lock()
        let observedLaunches = launches
        clockLock.unlock()
        XCTAssertEqual(observedLaunches, 5, "the sixth item reaches the 150-second budget and is not launched")
        for result in results.prefix(5) {
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result["success"] as? Bool, true)
        }
        for result in results.suffix(3) {
            XCTAssertEqual(result["success"] as? Bool, false)
            XCTAssertEqual(
                result["error"] as? String,
                "not launched — response deadline exceeded"
            )
        }
    }

    /// The response budget uses monotonic elapsed time even when the wall clock moves backward.
    func testBatchLaunchBudgetUsesMonotonicElapsedTimeWhenWallClockMovesBackward() throws {
        let request: [String: Any] = [
            "command": "echo monotonic-deadline",
            "items": (1...8).map { ["variables": ["repo": "repo\($0)"]] },
        ]
        let directory = "/tmp/tc-batch-monotonic-deadline-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        let clockLock = NSLock()
        var fakeWallClock = Date(timeIntervalSince1970: 0)
        var fakeMonotonicNow: TimeInterval = 0
        var launches = 0
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                clockLock.lock()
                launches += 1
                fakeMonotonicNow += 40
                if launches == 1 {
                    fakeWallClock = fakeWallClock.addingTimeInterval(-3600)
                }
                clockLock.unlock()
                return .none
            },
            now: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeWallClock
            },
            monotonicNow: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeMonotonicNow
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        XCTAssertEqual(actual["success"] as? Bool, false)
        XCTAssertEqual(actual["error"] as? String, "4 of 8 items failed")

        let results = try XCTUnwrap(actual["items"] as? [[String: Any]])
        XCTAssertEqual(results.count, 8)
        clockLock.lock()
        let observedLaunches = launches
        clockLock.unlock()
        XCTAssertEqual(observedLaunches, 4, "the fifth item reaches 160 monotonic seconds")
        for result in results.prefix(4) {
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result["success"] as? Bool, true)
        }
        for result in results.suffix(4) {
            XCTAssertEqual(result["success"] as? Bool, false)
            XCTAssertEqual(
                result["error"] as? String,
                "not launched — response deadline exceeded"
            )
        }
    }

    /// A one-item typed batch still emits the batch-level Warp warning exactly once.
    func testServeLogsOneWarpWarningForOneItemTypedBatch() throws {
        let request: [String: Any] = [
            "command": "claude",
            "claude_inputs": ["/review"],
            "items": [["variables": [String: Any]()]],
        ]
        let warningNeedle =
            "a Warp batch of 1 item(s) schedules typed claude input (first at item 1) — delivery needs the Accessibility permission and each tab watched"

        let directory = "/tmp/tc-batch-warp-one-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )
        let logsLock = NSLock()
        var logs: [String] = []
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in .none },
            log: { message in
                logsLock.lock()
                logs.append(message)
                logsLock.unlock()
            }
        )
        try server.start()
        let previousToolExecutables = Settings.toolExecutables
        Settings.toolExecutables = ["claude": true]
        defer {
            Settings.toolExecutables = previousToolExecutables
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.warp.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        _ = try XCTUnwrap(relay.answer)

        logsLock.lock()
        let warnings = logs.filter { $0.contains(warningNeedle) }
        logsLock.unlock()
        XCTAssertEqual(warnings.count, 1, "one-item typed batches should emit one Warp warning")
    }

    /// A typed item cut by the response budget must not emit a Warp warning before it is prepared.
    func testServeDoesNotWarnForTypedItemCutByResponseDeadline() throws {
        let request: [String: Any] = [
            "command": "claude",
            "claude_inputs": ["{number}"],
            "items": [
                ["variables": ["number": "plain"]],
                ["variables": ["number": "/review"]],
            ],
        ]
        let warningNeedle =
            "a Warp batch of 2 item(s) schedules typed claude input (first at item 2) — delivery needs the Accessibility permission and each tab watched"

        let directory = "/tmp/tc-batch-warp-deadline-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )
        let clockLock = NSLock()
        var fakeNow = Date(timeIntervalSince1970: 0)
        var fakeMonotonicNow: TimeInterval = 0
        let logsLock = NSLock()
        var logs: [String] = []
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                clockLock.lock()
                fakeNow = fakeNow.addingTimeInterval(150)
                fakeMonotonicNow += 150
                clockLock.unlock()
                return .none
            },
            log: { message in
                logsLock.lock()
                logs.append(message)
                logsLock.unlock()
            },
            now: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeNow
            },
            monotonicNow: {
                clockLock.lock()
                defer { clockLock.unlock() }
                return fakeMonotonicNow
            }
        )
        try server.start()
        let previousToolExecutables = Settings.toolExecutables
        Settings.toolExecutables = ["claude": true]
        defer {
            Settings.toolExecutables = previousToolExecutables
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.warp.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        XCTAssertEqual(actual["success"] as? Bool, false)

        logsLock.lock()
        let warnings = logs.filter { $0.contains(warningNeedle) }
        logsLock.unlock()
        XCTAssertEqual(warnings.count, 0, "a deadline-cut typed item must not warn")
    }

    /// Each transport item gets its own timeline label on every emitted stage, including follow-ups.
    func testServeWritesOneTimelinePerBatchItem() throws {
        let request: [String: Any] = [
            "command": "echo item-metrics",
            "items": [
                ["variables": ["repo": "one"]],
                ["variables": ["repo": "two"]],
            ],
        ]
        let expected = handleRequest(json: request) { _ in }
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        var linesByItem: [String: [String]] = [:]
        let lock = NSLock()
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in .none },
            timelineFactory: { _, label in
                let itemLabel = label ?? "legacy"
                lock.lock()
                linesByItem[itemLabel] = []
                lock.unlock()
                return DeliveryTimeline(
                    emit: { message in
                        lock.lock()
                        linesByItem[itemLabel, default: []].append(message)
                        lock.unlock()
                    },
                    label: label
                )
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        XCTAssertEqual(
            actualBytes, expectedBytes,
            "batch transport still has to serialize as Core's handleRequest output"
        )

        lock.lock()
        let firstItemLines = linesByItem["item 1/2"] ?? []
        let secondItemLines = linesByItem["item 2/2"] ?? []
        lock.unlock()
        XCTAssertEqual(firstItemLines.count, 2, "the first item emits two launch-path timeline stages")
        XCTAssertEqual(secondItemLines.count, 2, "the second item emits two launch-path timeline stages")
        XCTAssertTrue(
            firstItemLines.allSatisfy { $0.hasPrefix("[item 1/2] ") },
            "every first-item timeline stage must carry its own label"
        )
        XCTAssertTrue(
            secondItemLines.allSatisfy { $0.hasPrefix("[item 2/2] ") },
            "every second-item timeline stage must carry its own label"
        )
    }

    /// The second item keeps the request-arrival stopwatch, so the first item's launch time remains in its total.
    func testServeSecondItemTimelineTotalIncludesFirstLaunchTime() throws {
        let request: [String: Any] = [
            "command": "echo anchored-timeline",
            "items": [
                ["variables": ["repo": "one"]],
                ["variables": ["repo": "two"]],
            ],
        ]

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        let clockLock = NSLock()
        var fakeNow: Date?
        let linesLock = NSLock()
        var lines: [String] = []
        var anchors: [Date] = []
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                clockLock.lock()
                fakeNow = fakeNow?.addingTimeInterval(2)
                clockLock.unlock()
                return .none
            },
            timelineFactory: { arrival, label in
                clockLock.lock()
                if fakeNow == nil { fakeNow = arrival }
                clockLock.unlock()

                anchors.append(arrival)
                return DeliveryTimeline(
                    now: {
                        clockLock.lock()
                        defer { clockLock.unlock() }
                        return fakeNow ?? arrival
                    },
                    emit: { message in
                        linesLock.lock()
                        lines.append(message)
                        linesLock.unlock()
                    },
                    startedAt: arrival,
                    label: label
                )
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        _ = try XCTUnwrap(relay.answer)

        linesLock.lock()
        let captured = lines
        linesLock.unlock()
        XCTAssertTrue(
            captured.contains { $0.contains("item 2/2") && $0.contains("total 2.0s") },
            "item 2's total must include the first launch's two fake seconds"
        )
        XCTAssertEqual(anchors.count, 2, "each batch item should create one anchored timeline")
        if anchors.count == 2 {
            XCTAssertEqual(anchors[0], anchors[1], "all item timelines must share request arrival")
        }
    }

    /// Batch launches stay serial because `handleRequest` runs inside the HostServer `execQueue` for each frame.
    func testServeExecutesBatchLaunchesSequentially() throws {
        let request: [String: Any] = [
            "command": "echo serial-order",
            "items": [
                ["variables": ["repo": "one"]],
                ["variables": ["repo": "two"]],
                ["variables": ["repo": "three"]],
            ],
        ]
        _ = handleRequest(json: request) { _ in }

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        var launches = 0
        var active = 0
        var maximumActive = 0
        let lock = NSLock()
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                lock.lock()
                active += 1
                maximumActive = max(maximumActive, active)
                launches += 1
                lock.unlock()

                Thread.sleep(forTimeInterval: 0.05)

                lock.lock()
                active -= 1
                lock.unlock()
                return .none
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        _ = try XCTUnwrap(relay.answer)

        lock.lock()
        let observedLaunches = launches
        let observedMaxActive = maximumActive
        lock.unlock()
        XCTAssertEqual(observedLaunches, 3, "every batch item should launch exactly once")
        XCTAssertLessThanOrEqual(
            observedMaxActive, 1,
            "batch launches should not overlap because `execQueue` wraps the request path"
        )
    }

    /// Warp batch warnings are logged once for a qualifying batch and never for the same batch on non-Warp.
    func testServeLogsOneWarpBatchWarningOnlyWhenApplicable() throws {
        let request: [String: Any] = [
            "command": "claude",
            "claude_inputs": ["{number}"],
            "items": [
                ["variables": ["number": "/review"]],
                ["variables": ["number": "plain"]],
            ],
        ]
        let expected = handleRequest(json: request) { _ in }
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        let warningNeedle =
            "a Warp batch of 2 item(s) schedules typed claude input (first at item 1) — delivery needs the Accessibility permission and each tab watched"

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )
        var logs: [String] = []
        let logsLock = NSLock()
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in .none },
            log: { message in
                logsLock.lock()
                logs.append(message)
                logsLock.unlock()
            }
        )
        try server.start()
        let previousToolExecutables = Settings.toolExecutables
        Settings.toolExecutables = ["claude": true]
        defer {
            Settings.toolExecutables = previousToolExecutables
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        let relayIterm = RelayAtTheDoor()
        relayIterm.connectAndAsk(request, at: path, givingUp: 10)
        let deadlineIterm = Date().addingTimeInterval(10)
        while relayIterm.answer == nil, Date() < deadlineIterm {
            Thread.sleep(forTimeInterval: 0.01)
        }
        _ = try XCTUnwrap(relayIterm.answer)

        logsLock.lock()
        let preWarpWarnings = logs.filter { $0.contains(warningNeedle) }
        logsLock.unlock()
        XCTAssertEqual(preWarpWarnings.count, 0, "non-Warp batches should not emit this warning")

        logsLock.lock()
        logs.removeAll()
        logsLock.unlock()
        UserDefaults.standard.set(Terminal.warp.rawValue, forKey: "terminal")
        let relayWarp = RelayAtTheDoor()
        relayWarp.connectAndAsk(request, at: path, givingUp: 10)
        let deadlineWarp = Date().addingTimeInterval(10)
        while relayWarp.answer == nil, Date() < deadlineWarp {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relayWarp.answer)
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        XCTAssertEqual(
            actualBytes, expectedBytes,
            "batch transport response should match Core on the same request"
        )

        logsLock.lock()
        let warpWarnings = logs.filter { $0.contains(warningNeedle) }
        logsLock.unlock()
        XCTAssertEqual(warpWarnings.count, 1, "Warp batch warning should be emitted once")
    }

    /// A request that fails structural validation must return the Core response and never call the
    /// terminal runner.
    func testServeReturnsBatchValidationFailureBeforeLaunch() throws {
        let request: [String: Any] = [
            "command": "echo bad",
            "items": ["not an item"],
        ]
        let expected = handleRequest(json: request) { _ in
            XCTFail("run must not be called on validation failure")
        }
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        var runInvocations = 0
        let runLock = NSLock()
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                runLock.lock()
                runInvocations += 1
                runLock.unlock()
                return .none
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        XCTAssertEqual(
            actualBytes, expectedBytes,
            "validation failure must match Core's non-launch response"
        )

        runLock.lock()
        let invocations = runInvocations
        runLock.unlock()
        XCTAssertEqual(invocations, 0, "validation failure must not launch anything")
    }

    /// A size violation is rejected before any launch with the batch shared failure response.
    func testServeReturnsCapExceededFailureBeforeLaunch() throws {
        let request: [String: Any] = [
            "command": "echo cap",
            "items": (1...9).map { ["variables": ["repo": "repo\($0)"]] },
        ]
        let expected = handleRequest(json: request) { _ in
            XCTFail("run must not be called on cap failure")
        }
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])

        let directory = "/tmp/tc-batch-protocol-\(UUID().uuidString.prefix(8))"
        let path = directory + "/s.sock"
        let canonical = CanonicalSocketOverride(path)
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: nil
        )

        var runInvocations = 0
        let runLock = NSLock()
        let server = HostServer(
            socketPath: path,
            runInTerminal: { _, _, _ in
                runLock.lock()
                runInvocations += 1
                runLock.unlock()
                return .none
            }
        )
        try server.start()
        defer {
            server.stop()
            _ = canonical
            try? FileManager.default.removeItem(atPath: directory)
        }

        let relay = RelayAtTheDoor()
        relay.connectAndAsk(request, at: path, givingUp: 10)
        let deadline = Date().addingTimeInterval(10)
        while relay.answer == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let actual = try XCTUnwrap(relay.answer)
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        XCTAssertEqual(
            actualBytes, expectedBytes,
            "cap rejection must be serialized from Core before launch"
        )

        runLock.lock()
        let invocations = runInvocations
        runLock.unlock()
        XCTAssertEqual(invocations, 0, "cap rejection must not launch anything")
    }

}
