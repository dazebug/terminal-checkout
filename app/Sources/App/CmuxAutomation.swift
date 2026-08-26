import Core
import Foundation

enum CmuxAutomationWriteResult: Equatable {
    case alreadyEnabled
    case applied
    case notApplied
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
        replaceItem: ((_ original: URL, _ replacement: URL, _ backupItemName: String?) throws -> Void)? = nil
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
            return status() == .reachable ? .alreadyEnabled : .notApplied
        }

        // The replacement operation is the one backup operation for an existing config. If it
        // fails, FileManager leaves the original untouched; the temporary file is removed by the
        // defer below. Keeping the OS backup here also preserves bytes from a race that happens
        // after the comparison and before replacement.
        let directory = configURL.deletingLastPathComponent()
        let backupURL: URL?
        if exists {
            let path = configURL.deletingLastPathComponent().appendingPathComponent(
                "cmux.json.\(backupTimestamp(now)).bak"
            )
            backupURL = path
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
        defer { try? fileManager.removeItem(at: temporaryURL) }
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
                // Narrowing a backup loses nothing, and cmux.json may contain socketPassword.
                if let backupURL {
                    try fileManager.setAttributes(
                        [.posixPermissions: 0o600], ofItemAtPath: backupURL.path
                    )
                }
            } else {
                try fileManager.moveItem(at: temporaryURL, to: configURL)
            }
        } catch let error as CmuxConfigurationError {
            throw error
        } catch {
            throw CmuxConfigurationError.writeFailed(errorMessage(error))
        }

        for attempt in 0...10 {
            if status() == .reachable { return .applied }
            if attempt < 10 { sleep(0.3) }
        }
        return .notApplied
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
