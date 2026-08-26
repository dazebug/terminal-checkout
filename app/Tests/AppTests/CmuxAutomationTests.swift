import Foundation
import XCTest
@testable import App
@testable import Core

final class CmuxAutomationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-automation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testItem22WriteBacksUpBeforeReplacingAndConfirmsReachable() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = """
        {
          "$schema": "https://example.test/cmux.json",
          "schemaVersion": 1,
          // preserve this comment
        }
        """
        try Data(original.utf8).write(to: config)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: config.path
        )

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            now: Date(timeIntervalSince1970: 1_756_000_000),
            status: { .reachable },
            sleep: { _ in }
        )

        XCTAssertEqual(result, .applied)
        let updated = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(updated.contains("\"socketControlMode\": \"automation\""))
        XCTAssertTrue(updated.contains("// preserve this comment"))

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("cmux.json.") && $0.pathExtension == "bak" }
        let backup = try XCTUnwrap(backups.single)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
        XCTAssertEqual(try permissions(of: config), 0o600)
        XCTAssertEqual(try permissions(of: backup), 0o600)
    }

    func testItem22WriteCreatesDirectoriesAndReportsNotAppliedAfterBoundedPoll() throws {
        let config = directory.appendingPathComponent("nested/cmux.json")
        var sleeps = 0

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .notRunning },
            sleep: { _ in sleeps += 1 }
        )

        XCTAssertEqual(result, .notApplied)
        XCTAssertEqual(sleeps, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path + ".bak"))
        XCTAssertEqual(try permissions(of: config), 0o600)
    }

    func testItem22WriteDoesNotTouchAnAlreadyEnabledConfig() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"automation":{"socketControlMode":"automation"},"other":1}"#
        try Data(original.utf8).write(to: config)

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { XCTFail("an unchanged config must not be probed"); return .reachable },
            sleep: { _ in }
        )

        XCTAssertEqual(result, .alreadyEnabled)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["cmux.json"])
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue
    }
}

private extension Array where Element == URL {
    var single: Element? { count == 1 ? first : nil }
}
