import Core
import Foundation
import XCTest
@testable import App

final class ShortcutInstallerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory, FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testInstallationStatusMatchesOnlyAnExactOutputLine() {
        XCTAssertEqual(
            SlackThreadShortcutInstaller.parseListOutput("Other Shortcut\n\(SlackThreadShortcutWorkflow.name)\n"),
            .installed
        )
        XCTAssertEqual(
            SlackThreadShortcutInstaller.parseListOutput("prefix\(SlackThreadShortcutWorkflow.name)\n"),
            .notInstalled
        )
        XCTAssertEqual(SlackThreadShortcutInstaller.parseListOutput(""), .notInstalled)
        XCTAssertEqual(
            SlackThreadShortcutInstaller.parseListOutput(" \(SlackThreadShortcutWorkflow.name)\n"),
            .notInstalled
        )
        XCTAssertEqual(
            SlackThreadShortcutInstaller.parseListOutput("\(SlackThreadShortcutWorkflow.name) \n"),
            .notInstalled
        )
    }

    func testInstallationStatusIsUnknownWhenListCommandFailsOrThrows() {
        let nonzero = SlackThreadShortcutInstaller(
            directory: temporaryDirectory.path,
            processRunner: { _, _, _ in (status: 1, stdout: "\(SlackThreadShortcutWorkflow.name)\n", stderr: "failed") },
            application: FakeShortcutsApplication()
        )
        XCTAssertEqual(nonzero.installationStatus(), .unknown)

        let throwing = SlackThreadShortcutInstaller(
            directory: temporaryDirectory.path,
            processRunner: { _, _, _ in throw FakeProcessError.failed },
            application: FakeShortcutsApplication()
        )
        XCTAssertEqual(throwing.installationStatus(), .unknown)
    }

    func testInstallationStatusIsUnknownForMalformedListOutput() {
        XCTAssertEqual(
            SlackThreadShortcutInstaller.parseListOutput("\u{0000}\n\(SlackThreadShortcutWorkflow.name)\n"),
            .unknown
        )
    }

    func testInstallSignsFixedASCIIShortcutWithExpectedArguments() throws {
        let application = FakeShortcutsApplication(state: .finishedLaunching)
        var observed: (String, [String], TimeInterval)?
        let installer = makeInstaller(application: application) { path, arguments, timeout in
            observed = (path, arguments, timeout)
            try Self.writeSignedOutput(from: arguments)
            return (status: 0, stdout: "", stderr: "")
        }

        try installer.install()

        let call = try XCTUnwrap(observed)
        let sourcePath = temporaryDirectory.appendingPathComponent("\(SlackThreadShortcutWorkflow.name).plist").path
        let signedPath = temporaryDirectory.appendingPathComponent("\(SlackThreadShortcutWorkflow.name).shortcut").path
        XCTAssertEqual(call.0, "/usr/bin/shortcuts")
        XCTAssertEqual(
            call.1,
            ["sign", "--mode", "people-who-know-me", "--input", sourcePath, "--output", signedPath]
        )
        XCTAssertTrue(call.2 > 0)
        XCTAssertEqual(SlackThreadShortcutWorkflow.name, "Terminal Checkout Slack Thread")
        XCTAssertTrue(SlackThreadShortcutWorkflow.name.unicodeScalars.allSatisfy { $0.isASCII })
        XCTAssertEqual(application.events, ["state:finishedLaunching", "open"])
    }

    func testInstallRejectsMissingNewSignatureAfterRemovingPreviousFile() throws {
        let signedPath = temporaryDirectory
            .appendingPathComponent("\(SlackThreadShortcutWorkflow.name).shortcut")
        try Data([0x41, 0x45, 0x41, 0x31, 0x00]).write(to: signedPath)
        let installer = makeInstaller(
            application: FakeShortcutsApplication(state: .finishedLaunching)
        ) { _, _, _ in
            (status: 0, stdout: "", stderr: "")
        }

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? SlackThreadShortcutInstallerError,
                  case .signedShortcutMissing = installerError else {
                XCTFail("Expected signedShortcutMissing, got \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: signedPath.path))
    }

    func testInstallLaunchesShortcutsAndWaitsBeforeOpening() throws {
        let application = FakeShortcutsApplication(
            state: .notRunning,
            statesDuringWait: [.launching, .finishedLaunching]
        )
        let installer = makeInstaller(application: application) { _, arguments, _ in
            try Self.writeSignedOutput(from: arguments)
            return (status: 0, stdout: "", stderr: "")
        }

        try installer.install()

        XCTAssertEqual(
            application.events,
            ["state:notRunning", "launch", "wait", "poll:launching", "poll:finishedLaunching", "open"]
        )
    }

    func testInstallWaitsForAnExistingLaunchToFinishBeforeOpening() throws {
        let application = FakeShortcutsApplication(
            state: .launching,
            statesDuringWait: [.launching, .finishedLaunching]
        )
        let installer = makeInstaller(application: application) { _, arguments, _ in
            try Self.writeSignedOutput(from: arguments)
            return (status: 0, stdout: "", stderr: "")
        }

        try installer.install()

        XCTAssertEqual(
            application.events,
            ["state:launching", "wait", "poll:launching", "poll:finishedLaunching", "open"]
        )
    }

    func testInstallOpensDirectlyWhenShortcutsIsAlreadyRunning() throws {
        let application = FakeShortcutsApplication(state: .finishedLaunching)
        let installer = makeInstaller(application: application) { _, arguments, _ in
            try Self.writeSignedOutput(from: arguments)
            return (status: 0, stdout: "", stderr: "")
        }

        try installer.install()

        XCTAssertEqual(application.events, ["state:finishedLaunching", "open"])
    }

    func testInstallFailsWhenShortcutsDoesNotStartBeforeTimeout() throws {
        let application = FakeShortcutsApplication(
            state: .notRunning,
            statesDuringWait: [.launching]
        )
        let installer = makeInstaller(application: application) { _, arguments, _ in
            try Self.writeSignedOutput(from: arguments)
            return (status: 0, stdout: "", stderr: "")
        }

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? SlackThreadShortcutInstallerError,
                  case .shortcutsLaunchTimedOut = installerError else {
                XCTFail("Expected shortcutsLaunchTimedOut, got \(error)")
                return
            }
        }
        XCTAssertEqual(application.events, ["state:notRunning", "launch", "wait", "poll:launching"])
    }

    private func makeInstaller(
        application: FakeShortcutsApplication,
        processRunner: @escaping ShortcutProcessRunner
    ) -> SlackThreadShortcutInstaller {
        SlackThreadShortcutInstaller(
            directory: temporaryDirectory.path,
            processRunner: processRunner,
            application: application
        )
    }

    private static func writeSignedOutput(from arguments: [String]) throws {
        guard let outputFlag = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputFlag + 1) else {
            throw FakeProcessError.invalidArguments
        }
        try Data([0x41, 0x45, 0x41, 0x31]).write(
            to: URL(fileURLWithPath: arguments[outputFlag + 1])
        )
    }
}

private enum FakeProcessError: Error {
    case failed
    case invalidArguments
}

private final class FakeShortcutsApplication: ShortcutsApplication {
    private var currentState: ShortcutsApplicationState
    private let statesDuringWait: [ShortcutsApplicationState]
    private(set) var events: [String] = []

    init(
        state: ShortcutsApplicationState = .notRunning,
        statesDuringWait: [ShortcutsApplicationState] = []
    ) {
        currentState = state
        self.statesDuringWait = statesDuringWait
    }

    func state() -> ShortcutsApplicationState {
        events.append("state:\(currentState.eventName)")
        return currentState
    }

    func launch() throws {
        events.append("launch")
    }

    func waitUntilFinishedLaunching(timeout: TimeInterval) -> Bool {
        events.append("wait")
        for state in statesDuringWait {
            currentState = state
            events.append("poll:\(state.eventName)")
            if state == .finishedLaunching { return true }
        }
        return false
    }

    func openShortcut(at path: String) throws {
        events.append("open")
    }
}

private extension ShortcutsApplicationState {
    var eventName: String {
        switch self {
        case .notRunning: return "notRunning"
        case .launching: return "launching"
        case .finishedLaunching: return "finishedLaunching"
        }
    }
}
