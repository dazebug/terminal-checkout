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

    /// Existing user-owned config permissions stay unchanged; only the backup and newly created
    /// config are ours to constrain to 0600.
    func testItem22WriteNarrowsBackupPermissionsTo0600AndConfirmsReachable() throws {
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
            [.posixPermissions: 0o644], ofItemAtPath: config.path
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
        XCTAssertEqual(try permissions(of: config), 0o644)
        XCTAssertEqual(try permissions(of: backup), 0o600)
    }

    /// F2 reproduction: V1 is read, the backup target is prepared, and another editor writes V2
    /// before the atomic replacement. The write must reject the stale V1 operation and leave V2 intact.
    func testItem22WriteRejectsAConfigChangedAfterBackup() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        let replacement = #"{"schemaVersion":2,"editedBy":"another-process"}"#
        try Data(original.utf8).write(to: config)

        let fileManager = FileManagerThatEditsConfigAfterBackup(
            configURL: config, replacement: Data(replacement.utf8)
        )
        XCTAssertThrowsError(try CmuxAutomation.writeAutomation(
            configURL: config,
            fileManager: fileManager,
            status: { .reachable },
            sleep: { _ in }
        ))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), replacement)
    }

    /// G1 reproduction: a third editor can save after the compare but before replace. The
    /// replacement operation must preserve the bytes it evicts, not just the earlier V1 backup.
    func testItem22ReplacementRacePreservesTheBytesEvictedAtReplaceTime() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        let replacement = #"{"schemaVersion":3,"editedBy":"replace-race"}"#
        try Data(original.utf8).write(to: config)

        _ = try? CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .reachable },
            sleep: { _ in },
            replaceItem: { original, replacementURL, backupItemName in
                try Data(replacement.utf8).write(to: original, options: [])
                _ = try FileManager.default.replaceItemAt(
                    original,
                    withItemAt: replacementURL,
                    backupItemName: backupItemName,
                    options: [.withoutDeletingBackupItem]
                )
            }
        )

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "bak" }
        let backupContents = try backups.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertTrue(backupContents.contains(replacement), "the bytes evicted at replace were lost")
        XCTAssertTrue(
            try String(contentsOf: config, encoding: .utf8)
                .contains("\"socketControlMode\": \"automation\"")
        )
        for backup in backups {
            XCTAssertEqual(try permissions(of: backup), 0o600)
        }
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

    /// F5: unchanged configuration is not proof that the live cmux accepts the socket. It still
    /// gets one probe: reachable is alreadyEnabled, while denied is notApplied, with no write.
    func testItem22WriteChecksReachabilityOnceForAlreadyEnabledConfig() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"automation":{"socketControlMode":"automation"},"other":1}"#
        try Data(original.utf8).write(to: config)

        var reachableCalls = 0
        let reachable = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { reachableCalls += 1; return .reachable },
            sleep: { _ in }
        )

        XCTAssertEqual(reachable, .alreadyEnabled)
        XCTAssertEqual(reachableCalls, 1)

        var deniedCalls = 0
        let denied = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { deniedCalls += 1; return .denied },
            sleep: { _ in }
        )

        XCTAssertEqual(denied, .notApplied)
        XCTAssertEqual(deniedCalls, 1)
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

private final class FileManagerThatEditsConfigAfterBackup: FileManager {
    private let configURL: URL
    private let replacement: Data

    init(configURL: URL, replacement: Data) {
        self.configURL = configURL
        self.replacement = replacement
        super.init()
    }

    override func setAttributes(
        _ attributes: [FileAttributeKey: Any], ofItemAtPath path: String
    ) throws {
        try super.setAttributes(attributes, ofItemAtPath: path)
        guard path != configURL.path else { return }
        try replacement.write(to: configURL, options: [])
    }
}
