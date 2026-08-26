import Core
import Darwin
import Foundation

enum CmuxAutomationWriteResult: Equatable {
    case alreadyEnabled
    case applied(backupSecured: Bool)
    case notApplied(backupSecured: Bool)
}

enum CmuxConfigurationError: Error, CustomStringConvertible {
    case readFailed(String)
    case invalidUTF8
    case editFailed(String)
    case backupFailed(String)
    case directoryFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .readFailed(let detail): return "read failed: \(detail)"
        case .invalidUTF8: return "the configuration is not UTF-8"
        case .editFailed(let detail): return "configuration edit failed: \(detail)"
        case .backupFailed(let detail): return "backup failed: \(detail)"
        case .directoryFailed(let detail): return "directory creation failed: \(detail)"
        case .writeFailed(let detail): return "atomic write failed: \(detail)"
        }
    }
}

enum CmuxAutomation {
    private static let backupNameAttemptLimit = 1000

    private static func backupCandidateName(timestamp: String, suffix: Int) -> String {
        if suffix == 1 { return "cmux.json.\(timestamp).bak" }
        return "cmux.json.\(timestamp)-\(suffix).bak"
    }

    private static func errorIsFileExists(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EEXIST)
    }

    private static func reserveBackupPlaceholder(at url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard Darwin.close(descriptor) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    /// `backupItemName` removes an existing item with that name during replacement, so checking
    /// then using a path leaves a TOCTOU window. O_EXCL reservation makes the placeholder ours;
    /// Foundation replaces that placeholder with the bytes it evicts, and failures remove it.
    private static func reserveBackupURL(
        timestamp: String, directory: URL, reserve: (URL) throws -> Void
    ) throws -> URL {
        for suffix in 1...backupNameAttemptLimit {
            let name = backupCandidateName(timestamp: timestamp, suffix: suffix)
            let url = directory.appendingPathComponent(name)
            do {
                try reserve(url)
                return url
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

    /// The synchronous file operation is injectable for tests; the button calls the asynchronous
    /// wrapper below so backup, disk I/O, and the bounded live probe never block AppKit.
    static func writeAutomation(
        configURL suppliedURL: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default,
        status: @escaping () -> CmuxSocketStatus = { PermissionChecker.cmuxSocketStatus() },
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        replaceItem: ((_ original: URL, _ replacement: URL, _ backupItemName: String?) throws -> Void)? = nil,
        reserveBackup: ((_ url: URL) throws -> Void)? = nil
    ) throws -> CmuxAutomationWriteResult {
        let configURL = suppliedURL ?? defaultConfigURL()
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
            return status() == .reachable ? .alreadyEnabled : .notApplied(backupSecured: true)
        }

        // The replacement operation is the one backup operation for an existing config. If it
        // fails, FileManager leaves the original untouched; the temporary file is removed by the
        // defer below. Keeping the OS backup here also preserves bytes from a race that happens
        // after the comparison and before replacement.
        let directory = configURL.deletingLastPathComponent()
        let backupURL: URL?
        if exists {
            let reserve = reserveBackup ?? { url in
                try reserveBackupPlaceholder(at: url)
            }
            backupURL = try reserveBackupURL(
                timestamp: backupTimestamp(now), directory: directory, reserve: reserve
            )
        } else {
            backupURL = nil
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CmuxConfigurationError.directoryFailed(errorMessage(error))
        }

        let temporaryURL = directory.appendingPathComponent(
            ".cmux.json.\(UUID().uuidString).tmp"
        )
        var backupReservationActive = backupURL != nil
        defer {
            try? fileManager.removeItem(at: temporaryURL)
            if backupReservationActive, let backupURL {
                try? fileManager.removeItem(at: backupURL)
            }
        }
        let replaceItemOperation = replaceItem ?? { original, replacement, backupItemName in
            _ = try fileManager.replaceItemAt(
                original, withItemAt: replacement, backupItemName: backupItemName,
                options: [.withoutDeletingBackupItem]
            )
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
                        "configuration changed before replacement; refusing to overwrite (backup target: \(backupURL?.path ?? configURL.path))"
                    )
                }
                try replaceItemOperation(configURL, temporaryURL, backupURL?.lastPathComponent)
                backupReservationActive = false
            } else {
                try fileManager.moveItem(at: temporaryURL, to: configURL)
            }
        } catch let error as CmuxConfigurationError {
            throw error
        } catch {
            throw CmuxConfigurationError.writeFailed(errorMessage(error))
        }

        // Narrowing loses nothing, and cmux.json may contain socketPassword. This is deliberately
        // post-replacement: if chmod fails, the new configuration is already live and the result
        // must report that state rather than falsely calling the write a failure.
        var backupSecured = true
        if let backupURL {
            do {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: backupURL.path
                )
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
            if status() == .reachable { return .applied(backupSecured: backupSecured) }
            if attempt < 10 { sleep(0.3) }
        }
        return .notApplied(backupSecured: backupSecured)
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
