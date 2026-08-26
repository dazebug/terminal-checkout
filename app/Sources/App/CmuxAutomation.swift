import Core
import Darwin
import Foundation

enum CmuxAutomationWriteResult: Equatable {
    case alreadyEnabled
    case applied(backupSecured: Bool, backupPath: String?)
    case notApplied(backupSecured: Bool, backupPath: String?)
}

/// The reservation identity that the green implementation will use to distinguish its empty
/// placeholder from a real backup left behind by a partially completed replacement.
struct ReservedBackup {
    let url: URL
    let inode: UInt64
    let device: Int32
}

enum CmuxConfigurationError: Error, CustomStringConvertible {
    case readFailed(String)
    case invalidUTF8
    case editFailed(String)
    case backupFailed(String)
    case directoryFailed(String)
    case writeFailed(String)
    case writeFailedWithUnsecuredBackup(String, path: String)

    var description: String {
        switch self {
        case .readFailed(let detail): return "read failed: \(detail)"
        case .invalidUTF8: return "the configuration is not UTF-8"
        case .editFailed(let detail): return "configuration edit failed: \(detail)"
        case .backupFailed(let detail): return "backup failed: \(detail)"
        case .directoryFailed(let detail): return "directory creation failed: \(detail)"
        case .writeFailed(let detail): return "atomic write failed: \(detail)"
        case .writeFailedWithUnsecuredBackup(let detail, let path):
            return "atomic write failed: \(detail) (unsecured backup: \(path))"
        }
    }
}

enum CmuxAutomation {
    private static let backupNameAttemptLimit = 1000
    private static let symlinkResolutionLimit = 32

    private static func backupCandidateName(
        timestamp: String, randomToken: String, suffix: Int
    ) -> String {
        let collisionSuffix = suffix == 1 ? "" : "-\(suffix)"
        return "cmux.json.\(timestamp).\(randomToken)\(collisionSuffix).bak"
    }

    private static func errorIsFileExists(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EEXIST)
    }

    /// Read identity from the open descriptor before close; the close∼lstat window is not
    /// reproduced in tests because fstat removes that window rather than racing around it.
    private static func reservationIdentity(for descriptor: Int32, at url: URL) -> ReservedBackup {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            return ReservedBackup(url: url, inode: 0, device: 0)
        }
        return ReservedBackup(
            url: url, inode: UInt64(info.st_ino), device: Int32(info.st_dev)
        )
    }

    private static func reserveBackupPlaceholder(at url: URL) throws -> ReservedBackup {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let reservation = reservationIdentity(for: descriptor, at: url)
        guard reservation.inode != 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            removeReservedPlaceholder(reservation)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            removeReservedPlaceholder(reservation)
            _ = Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard Darwin.close(descriptor) == 0 else {
            let code = errno
            removeReservedPlaceholder(reservation)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return reservation
    }

    /// `backupItemName` removes an existing item with that name during replacement, so checking
    /// then using a path leaves a TOCTOU window. O_EXCL reservation makes the placeholder ours;
    /// Foundation replaces that placeholder with the bytes it evicts, and failures remove it only
    /// while its recorded inode/device and zero size still prove that it is ours. Swift's Darwin
    /// module exposes no `funlinkat` (`import Darwin; _ = funlinkat` fails to compile), so the
    /// reservation name also carries eight random hex digits. A path that cannot be predicted can
    /// only have been moved there deliberately by a same-uid actor; identity checking remains a
    /// defense-in-depth guard, and the unlink primitive can be revisited if Swift exposes it.
    private static func reserveBackupURL(
        timestamp: String, directory: URL, reserve: (URL) throws -> ReservedBackup
    ) throws -> ReservedBackup {
        let randomToken = String(
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        ).lowercased()
        for suffix in 1...backupNameAttemptLimit {
            let name = backupCandidateName(
                timestamp: timestamp, randomToken: randomToken, suffix: suffix
            )
            let url = directory.appendingPathComponent(name)
            do {
                let reserved = try reserve(url)
                return reserved
            } catch {
                if errorIsFileExists(error) { continue }
                throw CmuxConfigurationError.backupFailed(errorMessage(error))
            }
        }
        throw CmuxConfigurationError.backupFailed(
            "no available backup name for timestamp \(timestamp)"
        )
    }

    static func defaultConfigURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("cmux", isDirectory: true)
            .appendingPathComponent("cmux.json")
    }

    /// `replaceItemAt` on a live symlink fails with `NSCocoaErrorDomain Code=4` (`The file
    /// "cmux.json" doesn't exist.`) while leaving both the link and target unchanged (driver
    /// measurement). Follow the configuration link itself, not arbitrary parent components, so
    /// reads, backups, and the atomic replacement all address the target directory while the link
    /// remains the user's live path. A bounded walk turns a symlink cycle into an explicit error.
    private static func resolvedConfigURL(
        _ url: URL, fileManager: FileManager
    ) throws -> URL {
        var current = url
        var visited = Set<String>()
        for _ in 0..<symlinkResolutionLimit {
            var info = stat()
            guard current.path.withCString({ lstat($0, &info) == 0 }) else {
                return current
            }
            guard (info.st_mode & S_IFMT) == S_IFLNK else { return current }

            let key = current.standardizedFileURL.path
            guard visited.insert(key).inserted else {
                throw CmuxConfigurationError.writeFailed(
                    "cmux.json symlink cycle at \(current.path)"
                )
            }
            do {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: current.path)
                current = URL(
                    fileURLWithPath: destination,
                    relativeTo: current.deletingLastPathComponent()
                ).standardizedFileURL
            } catch {
                throw CmuxConfigurationError.writeFailed(
                    "could not resolve cmux.json symlink \(current.path): \(errorMessage(error))"
                )
            }
        }
        throw CmuxConfigurationError.writeFailed(
            "cmux.json symlink chain exceeded \(symlinkResolutionLimit) links"
        )
    }

    /// A placeholder may be removed only while it is still the inode we reserved and still empty.
    /// If replacement moved the original into that path before throwing, the inode or size differs
    /// and the path is a real recovery copy; deleting by path would lose both the original and its
    /// backup (the J1 reproduction).
    private static func ownsEmptyBackupPlaceholder(_ reservation: ReservedBackup) -> Bool {
        var info = stat()
        guard reservation.url.path.withCString({ lstat($0, &info) == 0 }) else { return false }
        return UInt64(info.st_ino) == reservation.inode
            && Int32(info.st_dev) == reservation.device
            && info.st_size == 0
    }

    /// Every placeholder deletion goes through the reservation identity check. A real backup
    /// left by a replacement is non-empty or has a different inode/device, so it is never removed.
    private static func removeReservedPlaceholder(_ reservation: ReservedBackup) {
        guard ownsEmptyBackupPlaceholder(reservation) else { return }
        try? FileManager.default.removeItem(at: reservation.url)
    }

    /// Test-only access to verify identity-safe placeholder cleanup.
    static func testOnlyRemoveReservedPlaceholder(_ reservation: ReservedBackup) {
        removeReservedPlaceholder(reservation)
    }

    /// Narrow a real backup through an O_NOFOLLOW descriptor. A symlink is rejected by open and a
    /// non-regular file is rejected after fstat, so this operation cannot chmod a target selected
    /// by a path swap.
    private static func narrowBackupPermissions(at url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        defer { _ = Darwin.close(descriptor) }

        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(EINVAL),
                userInfo: [NSLocalizedDescriptionKey: "cmux backup is not a regular file"]
            )
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    /// Test-only access to the descriptor-based chmod seam.
    static func testOnlyNarrowBackupPermissions(at url: URL) throws {
        try narrowBackupPermissions(at: url)
    }

    /// The synchronous file operation is injectable for tests; the button calls the asynchronous
    /// wrapper below so backup, disk I/O, and the bounded live probe never block AppKit.
    static func writeAutomation(
        configURL suppliedURL: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default,
        status: @escaping () -> CmuxSocketStatus = { PermissionChecker.cmuxSocketStatus() },
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        replaceItem: ((_ original: URL, _ replacement: URL, _ backupItemName: String?) throws -> Void)? = nil,
        reserveBackup: ((_ url: URL) throws -> ReservedBackup)? = nil,
        narrowBackup: ((_ url: URL) throws -> Void)? = nil
    ) throws -> CmuxAutomationWriteResult {
        let requestedConfigURL = suppliedURL ?? defaultConfigURL()
        let configURL = try resolvedConfigURL(requestedConfigURL, fileManager: fileManager)
        let exists = fileManager.fileExists(atPath: configURL.path)
        let existing: String?
        let existingData: Data?
        if exists {
            do {
                let data = try Data(contentsOf: configURL)
                guard let string = String(data: data, encoding: .utf8) else {
                    throw CmuxConfigurationError.invalidUTF8
                }
                existing = string
                existingData = data
            } catch let error as CmuxConfigurationError {
                throw error
            } catch {
                throw CmuxConfigurationError.readFailed(errorMessage(error))
            }
        } else {
            existing = nil
            existingData = nil
        }

        let edit: CmuxConfigEditResult
        do {
            edit = try cmuxConfigEnablingAutomation(existing: existing)
        } catch {
            throw CmuxConfigurationError.editFailed(errorMessage(error))
        }
        guard case .edited(let contents) = edit else {
            return status() == .reachable ? .alreadyEnabled : .notApplied(
                backupSecured: true, backupPath: nil
            )
        }

        // The replacement operation is the one backup operation for an existing config. If it
        // fails, FileManager leaves the original untouched; the temporary file is removed by the
        // defer below. Keeping the OS backup here also preserves bytes from a race that happens
        // after the comparison and before replacement.
        let directory = configURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".cmux.json.\(UUID().uuidString).tmp"
        )
        let backupURL: ReservedBackup?
        if exists {
            let reserve: (URL) throws -> ReservedBackup = reserveBackup ?? { url in
                try reserveBackupPlaceholder(at: url)
            }
            backupURL = try reserveBackupURL(
                timestamp: backupTimestamp(now), directory: directory, reserve: reserve
            )
        } else {
            backupURL = nil
        }

        var backupReservationActive = backupURL != nil
        // Install this immediately after reservation: even directory creation or temp-file setup
        // failing must release a placeholder, but only if its inode/device and zero size still
        // prove that it is ours.
        defer {
            try? fileManager.removeItem(at: temporaryURL)
            if backupReservationActive, let backupURL {
                removeReservedPlaceholder(backupURL)
            }
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CmuxConfigurationError.directoryFailed(errorMessage(error))
        }

        let replaceItemOperation = replaceItem ?? { original, replacement, backupItemName in
            _ = try fileManager.replaceItemAt(
                original, withItemAt: replacement, backupItemName: backupItemName,
                options: [.withoutDeletingBackupItem]
            )
        }
        let narrowBackupOperation: (URL) throws -> Void = narrowBackup ?? { url in
            try narrowBackupPermissions(at: url)
        }
        do {
            try Data(contents.utf8).write(to: temporaryURL, options: [])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path
            )
            if exists {
                let currentData = try Data(contentsOf: configURL)
                guard currentData == existingData else {
                    throw CmuxConfigurationError.writeFailed(
                        "configuration changed before replacement; refusing to overwrite (backup target: \(backupURL?.url.path ?? configURL.path))"
                    )
                }
                try replaceItemOperation(configURL, temporaryURL, backupURL?.url.lastPathComponent)
                backupReservationActive = false
            } else {
                try fileManager.moveItem(at: temporaryURL, to: configURL)
            }
        } catch let error as CmuxConfigurationError {
            throw error
        } catch {
            let replacementError = errorMessage(error)
            if let backupURL, !ownsEmptyBackupPlaceholder(backupURL) {
                do {
                    try narrowBackupOperation(backupURL.url)
                } catch {
                    throw CmuxConfigurationError.writeFailedWithUnsecuredBackup(
                        "\(replacementError); backup chmod failed: \(errorMessage(error))",
                        path: backupURL.url.path
                    )
                }
                // The replacement moved a real backup before failing. It is now protected, so
                // report the original write error without retaining an unsecured-backup warning.
                throw CmuxConfigurationError.writeFailed(
                    "\(replacementError) (backup path: \(backupURL.url.path))"
                )
            }
            throw CmuxConfigurationError.writeFailed(replacementError)
        }

        // Narrowing loses nothing, and cmux.json may contain socketPassword. This is deliberately
        // post-replacement: if chmod fails, the new configuration is already live and the result
        // must report that state rather than falsely calling the write a failure.
        var backupSecured = true
        if let backupURL {
            do {
                try narrowBackupOperation(backupURL.url)
            } catch {
                backupSecured = false
                // Replacement already applied the new config; reporting this as a write
                // failure would lie about the live state. Keep the diagnosis and probe it.
                checkoutLog(
                    "could not narrow cmux backup permissions to 0600 after replacement"
                        + " — configuration is already applied (\(errorMessage(error)))"
                )
            }
        }

        for attempt in 0...10 {
            if status() == .reachable {
                return .applied(
                    backupSecured: backupSecured, backupPath: backupURL?.url.path
                )
            }
            if attempt < 10 { sleep(0.3) }
        }
        return .notApplied(backupSecured: backupSecured, backupPath: backupURL?.url.path)
    }

    static func enableAutomation(
        completion: @escaping (Result<CmuxAutomationWriteResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let result = try writeAutomation()
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func backupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
