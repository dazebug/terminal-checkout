import Foundation
import Darwin
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

        assertAppliedResult(result, backupSecured: true)
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

    /// H1 red reproduction: an existing same-second backup is a recovery artifact and must stay
    /// byte-identical while the V1 config is saved under another candidate name.
    func testItem22BackupNameCollisionPreservesExistingBackup() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        let sentinel = "sentinel"
        let now = Date(timeIntervalSince1970: 1_756_000_000)
        let timestamp = backupTimestamp(now)
        let existingBackupName = "cmux.json.\(timestamp).bak"
        let existingBackup = directory.appendingPathComponent(existingBackupName)
        try Data(original.utf8).write(to: config)
        try Data(sentinel.utf8).write(to: existingBackup)

        var result: CmuxAutomationWriteResult?
        var thrown: Error?
        do {
            result = try CmuxAutomation.writeAutomation(
                configURL: config,
                now: now,
                status: { .reachable },
                sleep: { _ in }
            )
        } catch {
            thrown = error
        }

        XCTAssertNil(thrown)
        guard let result else { return XCTFail("the write did not return a result") }
        assertAppliedResult(result, backupSecured: true)
        XCTAssertEqual(try String(contentsOf: existingBackup, encoding: .utf8), sentinel)
        XCTAssertTrue(
            try String(contentsOf: config, encoding: .utf8)
                .contains("\"socketControlMode\": \"automation\"")
        )

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "bak" && $0.path != existingBackup.path }
        XCTAssertTrue(
            try backups.contains { try String(contentsOf: $0, encoding: .utf8) == original },
            "the original config must survive in a differently named backup"
        )
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

    /// J1 red reproduction: a replacement may move the original into the named backup and then
    /// report an error. Path-only cleanup mistakes that real backup for our empty placeholder and
    /// deletes the only recovery copy.
    func testItem22ReplacementFailureKeepsBackupMovedBeforeThrow() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        try Data(original.utf8).write(to: config)
        var backupURL: URL?

        XCTAssertThrowsError(try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .reachable },
            sleep: { _ in },
            replaceItem: { originalURL, _, backupItemName in
                guard let backupItemName else {
                    throw NSError(domain: "CmuxAutomationTests", code: 3)
                }
                let destination = self.directory.appendingPathComponent(backupItemName)
                backupURL = destination
                try FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: originalURL, to: destination)
                throw NSError(domain: "CmuxAutomationTests", code: 4)
            }
        ))

        let backup = try XCTUnwrap(backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
        if FileManager.default.fileExists(atPath: config.path) {
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        }
    }

    /// J7 red reproduction: a dotfiles-style symlink must remain the live configuration path while
    /// the target directory receives the replacement and its recovery backup.
    func testItem22WriteThroughSymlinkPreservesLinkAndBacksUpTarget() throws {
        let targetDirectory = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appendingPathComponent("cmux.json")
        let link = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        try Data(original.utf8).write(to: target)
        XCTAssertEqual(symlink(target.path, link.path), 0)

        let result = try? CmuxAutomation.writeAutomation(
            configURL: link,
            status: { .reachable },
            sleep: { _ in }
        )

        guard let result else { return XCTFail("the write did not return a result") }
        assertAppliedResult(result, backupSecured: true)
        var info = stat()
        XCTAssertEqual(lstat(link.path, &info), 0, "the live symlink must remain")
        XCTAssertTrue((info.st_mode & S_IFMT) == S_IFLNK)
        XCTAssertTrue(
            try String(contentsOf: target, encoding: .utf8)
                .contains("\"socketControlMode\": \"automation\"")
        )
        let backups = try FileManager.default.contentsOfDirectory(
            at: targetDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "bak" }
        XCTAssertTrue(
            try backups.contains { try String(contentsOf: $0, encoding: .utf8) == original },
            "the target directory must hold the original bytes"
        )
    }

    func testItem22WriteCreatesDirectoriesAndReportsNotAppliedAfterBoundedPoll() throws {
        let config = directory.appendingPathComponent("nested/cmux.json")
        var sleeps = 0

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .notRunning },
            sleep: { _ in sleeps += 1 }
        )

        assertNotAppliedResult(result, backupSecured: true, requiresBackupPath: false)
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

        assertNotAppliedResult(denied, backupSecured: true, requiresBackupPath: false)
        XCTAssertEqual(deniedCalls, 1)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["cmux.json"])
    }

    /// H2 red reproduction: if narrowing the backup permissions fails after replacement, the
    /// config and backup already exist, so the result must come from the live status probe.
    func testItem22BackupPermissionFailureReportsLiveStatusAndUnsecuredBackup() throws {
        let scenarios: [(String, CmuxSocketStatus, Bool)] = [
            ("reachable", .reachable, true),
            ("not-running", .notRunning, false),
        ]

        for (name, liveStatus, shouldApply) in scenarios {
            let caseDirectory = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: caseDirectory, withIntermediateDirectories: true
            )
            let config = caseDirectory.appendingPathComponent("cmux.json")
            let original = #"{"schemaVersion":1}"#
            try Data(original.utf8).write(to: config)

            let fileManager = FileManagerThatRejectsBackupPermissions()
            var result: CmuxAutomationWriteResult?
            var thrown: Error?
            do {
                result = try CmuxAutomation.writeAutomation(
                    configURL: config,
                    fileManager: fileManager,
                    status: { liveStatus },
                    sleep: { _ in }
                )
            } catch {
                thrown = error
            }

            XCTAssertNil(thrown, name)
            guard let result else {
                return XCTFail("missing result for \(name)")
            }
            if shouldApply {
                assertAppliedResult(result, backupSecured: false)
            } else {
                assertNotAppliedResult(result, backupSecured: false)
            }
            XCTAssertTrue(
                try String(contentsOf: config, encoding: .utf8)
                    .contains("\"socketControlMode\": \"automation\""),
                name
            )
            let backups = try FileManager.default.contentsOfDirectory(
                at: caseDirectory, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "bak" }
            XCTAssertTrue(
                try backups.contains { try String(contentsOf: $0, encoding: .utf8) == original },
                name
            )
        }
    }

    /// I2 red reproduction: `isTaken` and replacement are separate operations. The green seam
    /// will reserve each candidate with an atomic create, skip an EEXIST candidate, and pass the
    /// placeholder name to replacement.
    func testItem22BackupReservationUsesAtomicCreateAndSkipsTakenCandidates() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        try Data(original.utf8).write(to: config)
        let now = Date(timeIntervalSince1970: 1_756_000_000)
        let timestamp = backupTimestamp(now)
        let first = "cmux.json.\(timestamp).bak"
        let second = "cmux.json.\(timestamp)-2.bak"
        var reservationAttempts: [String] = []
        var replacementBackupName: String?

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            now: now,
            status: { .reachable },
            sleep: { _ in },
            replaceItem: { originalURL, replacementURL, backupItemName in
                replacementBackupName = backupItemName
                let backupURL = self.directory.appendingPathComponent(backupItemName ?? "missing.bak")
                try Data(contentsOf: originalURL).write(to: backupURL, options: [])
                try Data(contentsOf: replacementURL).write(to: originalURL, options: [])
            },
            reserveBackup: { url in
                reservationAttempts.append(url.lastPathComponent)
                if url.lastPathComponent == first {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST))
                }
                try Data("placeholder".utf8).write(to: url, options: .withoutOverwriting)
                return self.reservedBackup(at: url)
            }
        )

        assertAppliedResult(result, backupSecured: true)
        XCTAssertEqual(reservationAttempts, [first, second])
        XCTAssertEqual(replacementBackupName, second)
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent(second), encoding: .utf8),
            original
        )
    }

    /// I2 red reproduction: a failed replacement must remove the placeholder reserved for the
    /// backup name, rather than leaving an empty artifact beside the untouched config.
    func testItem22BackupReservationPlaceholderIsRemovedWhenReplacementFails() throws {
        let config = directory.appendingPathComponent("cmux.json")
        try Data(#"{"schemaVersion":1}"#.utf8).write(to: config)
        var reservedURL: URL?

        XCTAssertThrowsError(try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .reachable },
            sleep: { _ in },
            replaceItem: { _, _, _ in
                throw NSError(domain: "CmuxAutomationTests", code: 2)
            },
            reserveBackup: { url in
                reservedURL = url
                try Data().write(to: url, options: .withoutOverwriting)
                return self.reservedBackup(at: url)
            }
        ))

        guard let reservedURL else {
            return XCTFail("the backup name was not atomically reserved")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservedURL.path))
    }

    /// I2 red reproduction: a successful replacement must turn the reserved placeholder into the
    /// bytes evicted from the config, not leave the placeholder as the backup content.
    func testItem22BackupReservationPreservesBytesInTheReservedBackup() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let original = #"{"schemaVersion":1}"#
        try Data(original.utf8).write(to: config)
        var reservedURL: URL?

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .reachable },
            sleep: { _ in },
            replaceItem: { originalURL, replacementURL, _ in
                guard let reservedURL else { return XCTFail("no reserved backup URL") }
                try Data(contentsOf: originalURL).write(to: reservedURL, options: [])
                try Data(contentsOf: replacementURL).write(to: originalURL, options: [])
            },
            reserveBackup: { url in
                reservedURL = url
                try Data("placeholder".utf8).write(to: url, options: .withoutOverwriting)
                return self.reservedBackup(at: url)
            }
        )

        assertAppliedResult(result, backupSecured: true)
        guard let reservedURL else {
            return XCTFail("the backup name was not atomically reserved")
        }
        XCTAssertEqual(try String(contentsOf: reservedURL, encoding: .utf8), original)
    }

    /// I6 contract: an existing whitespace-only file carries no content to preserve, so it takes
    /// the same minimal-config path as a missing file while still receiving the ordinary backup.
    func testItem22WriteTreatsWhitespaceOnlyExistingConfigAsEmptyAndBacksItUp() throws {
        let config = directory.appendingPathComponent("cmux.json")
        let whitespace = " \n\t"
        try Data(whitespace.utf8).write(to: config)

        let result = try CmuxAutomation.writeAutomation(
            configURL: config,
            status: { .reachable },
            sleep: { _ in }
        )

        assertAppliedResult(result, backupSecured: true)
        XCTAssertEqual(
            try String(contentsOf: config, encoding: .utf8),
            "{\n  \"automation\": {\n    \"socketControlMode\": \"automation\"\n  }\n}\n"
        )
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "bak" }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(backups.first), encoding: .utf8), whitespace)
    }

    private func assertAppliedResult(
        _ result: CmuxAutomationWriteResult, backupSecured: Bool
    ) {
        guard case .applied(let secured, let backupPath) = result else {
            return XCTFail("expected applied result, got \(result)")
        }
        XCTAssertEqual(secured, backupSecured)
        XCTAssertNotNil(backupPath)
    }

    private func assertNotAppliedResult(
        _ result: CmuxAutomationWriteResult, backupSecured: Bool,
        requiresBackupPath: Bool = true
    ) {
        guard case .notApplied(let secured, let backupPath) = result else {
            return XCTFail("expected not-applied result, got \(result)")
        }
        XCTAssertEqual(secured, backupSecured)
        if requiresBackupPath { XCTAssertNotNil(backupPath) }
    }

    private func reservedBackup(at url: URL) -> ReservedBackup {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) == 0 }) else {
            return ReservedBackup(url: url, inode: 0, device: 0)
        }
        return ReservedBackup(
            url: url, inode: UInt64(info.st_ino), device: Int32(info.st_dev)
        )
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue
    }

    private func backupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
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

private final class FileManagerThatRejectsBackupPermissions: FileManager {
    override func setAttributes(
        _ attributes: [FileAttributeKey: Any], ofItemAtPath path: String
    ) throws {
        if path.hasSuffix(".bak") {
            throw NSError(domain: "CmuxAutomationTests", code: 1)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}
