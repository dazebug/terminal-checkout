import AppKit
import Core
import Foundation

typealias ShortcutProcessResult = (status: Int32, stdout: String, stderr: String)
typealias ShortcutProcessRunner = (
    _ path: String, _ arguments: [String], _ timeout: TimeInterval
) throws -> ShortcutProcessResult

enum SlackThreadShortcutInstallationStatus: Equatable {
    case installed
    case notInstalled
    case unknown
}

enum SlackThreadShortcutInstallerError: Error {
    case createDirectory(Error)
    case writeWorkflow(Error)
    case signProcess(Error)
    case signRejected(status: Int32, stderr: String)
    case removePreviousSignedShortcut(Error)
    case signedShortcutMissing
    case signedShortcutReadFailed(Error)
    case invalidSignatureMagic
    case shortcutsLaunchFailed(Error)
    case shortcutsLaunchTimedOut
    case shortcutOpenFailed(Error)
}

protocol SlackThreadShortcutManaging {
    func install() throws
    func installationStatus() -> SlackThreadShortcutInstallationStatus
}

enum ShortcutsApplicationState: Equatable {
    case notRunning
    case launching
    case finishedLaunching
}

protocol ShortcutsApplication {
    func state() -> ShortcutsApplicationState
    func launch() throws
    func waitUntilFinishedLaunching(timeout: TimeInterval) -> Bool
    func openShortcut(at path: String) throws
}

struct SlackThreadShortcutInstaller: SlackThreadShortcutManaging {
    private static let shortcutsExecutable = "/usr/bin/shortcuts"
    private static let operationTimeout: TimeInterval = 30
    private static let applicationLaunchTimeout: TimeInterval = 10

    private let directory: URL
    private let fileManager: FileManager
    private let processRunner: ShortcutProcessRunner
    private let application: ShortcutsApplication

    init(
        directory: String = appSupportDirectory(),
        fileManager: FileManager = .default,
        processRunner: ShortcutProcessRunner? = nil,
        application: ShortcutsApplication? = nil
    ) {
        let runner = processRunner ?? { path, arguments, timeout in
            try runProcess(path, arguments, timeout: timeout)
        }
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        self.fileManager = fileManager
        self.processRunner = runner
        self.application = application ?? SystemShortcutsApplication(processRunner: runner)
    }

    /// Call off the main thread; signing and launch readiness waits can block for up to 40 seconds.
    func install() throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw SlackThreadShortcutInstallerError.createDirectory(error)
        }

        // The unsigned source must also end in `.shortcut`: `shortcuts sign` rejects a `.plist` input
        // as "isn't in the correct format" (exit 1, measured). It lives in its own folder because
        // the signed output must be exactly `<name>.shortcut` — Shortcuts imports it under that name.
        let unsignedDirectory = directory.appendingPathComponent("unsigned", isDirectory: true)
        let source = unsignedDirectory.appendingPathComponent("\(SlackThreadShortcutWorkflow.name).shortcut")
        let signed = directory.appendingPathComponent("\(SlackThreadShortcutWorkflow.name).shortcut")
        do {
            try fileManager.createDirectory(
                at: unsignedDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try SlackThreadShortcutWorkflow.makePropertyListData().write(to: source, options: .atomic)
        } catch {
            throw SlackThreadShortcutInstallerError.writeWorkflow(error)
        }

        let signArguments = [
            "sign", "--mode", "people-who-know-me", "--input", source.path,
            "--output", signed.path,
        ]
        if fileManager.fileExists(atPath: signed.path) {
            do {
                try fileManager.removeItem(at: signed)
            } catch {
                throw SlackThreadShortcutInstallerError.removePreviousSignedShortcut(error)
            }
        }
        let signResult: ShortcutProcessResult
        do {
            signResult = try processRunner(Self.shortcutsExecutable, signArguments, Self.operationTimeout)
        } catch {
            throw SlackThreadShortcutInstallerError.signProcess(error)
        }
        guard signResult.status == 0 else {
            // The setup window shows only the exit status; the CLI's reason goes to the app log.
            checkoutLog("shortcuts sign failed (exit \(signResult.status)): \(signResult.stderr)")
            throw SlackThreadShortcutInstallerError.signRejected(
                status: signResult.status,
                stderr: signResult.stderr
            )
        }
        guard fileManager.fileExists(atPath: signed.path) else {
            throw SlackThreadShortcutInstallerError.signedShortcutMissing
        }

        let signedData: Data
        do {
            signedData = try Data(contentsOf: signed)
        } catch {
            throw SlackThreadShortcutInstallerError.signedShortcutReadFailed(error)
        }
        guard signedData.starts(with: Data([0x41, 0x45, 0x41, 0x31])) else {
            throw SlackThreadShortcutInstallerError.invalidSignatureMagic
        }

        // Do not hand the file to a Shortcuts that is still launching — opening it into a cold
        // Shortcuts left an extra empty shortcut in the library (measured); a plain launch did not.
        let applicationState = application.state()
        if applicationState == .notRunning {
            do {
                try application.launch()
            } catch {
                throw SlackThreadShortcutInstallerError.shortcutsLaunchFailed(error)
            }
        }
        if applicationState != .finishedLaunching,
           !application.waitUntilFinishedLaunching(timeout: Self.applicationLaunchTimeout) {
            throw SlackThreadShortcutInstallerError.shortcutsLaunchTimedOut
        }

        do {
            try application.openShortcut(at: signed.path)
        } catch {
            throw SlackThreadShortcutInstallerError.shortcutOpenFailed(error)
        }
    }

    func installationStatus() -> SlackThreadShortcutInstallationStatus {
        do {
            let result = try processRunner(Self.shortcutsExecutable, ["list"], Self.operationTimeout)
            guard result.status == 0 else { return .unknown }
            return Self.parseListOutput(result.stdout)
        } catch {
            return .unknown
        }
    }

    static func parseListOutput(_ output: String) -> SlackThreadShortcutInstallationStatus {
        guard !output.unicodeScalars.contains(where: { $0.value == 0 }) else { return .unknown }
        return output.components(separatedBy: .newlines).contains(SlackThreadShortcutWorkflow.name)
            ? .installed
            : .notInstalled
    }
}

private enum ShortcutsApplicationError: Error {
    case commandFailed(status: Int32, stderr: String)
}

private struct SystemShortcutsApplication: ShortcutsApplication {
    private static let bundleIdentifier = "com.apple.shortcuts"
    private let processRunner: ShortcutProcessRunner

    init(processRunner: @escaping ShortcutProcessRunner) {
        self.processRunner = processRunner
    }

    func state() -> ShortcutsApplicationState {
        let applications = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .filter { !$0.isTerminated }
        if applications.contains(where: \.isFinishedLaunching) {
            return .finishedLaunching
        }
        return applications.isEmpty ? .notRunning : .launching
    }

    func launch() throws {
        let result = try processRunner("/usr/bin/open", ["-b", Self.bundleIdentifier], 10)
        guard result.status == 0 else {
            throw ShortcutsApplicationError.commandFailed(status: result.status, stderr: result.stderr)
        }
    }

    func waitUntilFinishedLaunching(timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        repeat {
            if state() == .finishedLaunching { return true }
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
    }

    func openShortcut(at path: String) throws {
        let result = try processRunner("/usr/bin/open", [path], 10)
        guard result.status == 0 else {
            throw ShortcutsApplicationError.commandFailed(status: result.status, stderr: result.stderr)
        }
    }
}
