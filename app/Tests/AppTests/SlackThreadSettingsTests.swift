import AppKit
import Core
import Foundation
import XCTest
@testable import App

final class SlackThreadSettingsTests: XCTestCase {
    private var savedResources: String?

    private static var sourceResources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = Self.sourceResources
    }

    override func tearDown() {
        AppLocalization.tagOverrideForTesting = nil
        AppLocalization.resourcesPath = savedResources
        super.tearDown()
    }

    func testSlackSettingsAreStoredAsRawAppLocalStrings() {
        let defaults = UserDefaults.standard
        let workKey = "slackThreadWorkDirectory"
        let instructionKey = "slackThreadInstruction"
        let oldWork = defaults.object(forKey: workKey)
        let oldInstruction = defaults.object(forKey: instructionKey)
        defer {
            if let oldWork { defaults.set(oldWork, forKey: workKey) } else { defaults.removeObject(forKey: workKey) }
            if let oldInstruction { defaults.set(oldInstruction, forKey: instructionKey) } else { defaults.removeObject(forKey: instructionKey) }
        }

        defaults.removeObject(forKey: workKey)
        defaults.removeObject(forKey: instructionKey)
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "")
        XCTAssertEqual(Settings.slackThreadInstruction, "")

        Settings.slackThreadWorkDirectory = "~/work folder"
        Settings.slackThreadInstruction = "  keep the user's wording  "
        XCTAssertEqual(defaults.object(forKey: workKey) as? String, "~/work folder")
        XCTAssertEqual(defaults.object(forKey: instructionKey) as? String, "  keep the user's wording  ")
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "~/work folder")
        XCTAssertEqual(Settings.slackThreadInstruction, "  keep the user's wording  ")
    }

    func testSettingsAndURLRequestUseTheSameCoreValidator() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let coreSource = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/Core/SlackThreadRequest.swift"),
            encoding: .utf8
        )
        let windowSource = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/App/SetupWindowController.swift"),
            encoding: .utf8
        )
        let requestBody = try XCTUnwrap(segment(
            in: coreSource,
            from: "public func resolveSlackThreadRequest(",
            to: "\n/// Uses the existing request planner"
        ))
        let settingsBody = try XCTUnwrap(segment(
            in: windowSource,
            from: "private func updateSlackThreadSettingsCard() {",
            to: "\n    private func updateSlackShortcutPresentation()"
        ))

        XCTAssertTrue(requestBody.contains("validateSlackThreadSettings("))
        XCTAssertTrue(settingsBody.contains("validateSlackThreadSettings("))
        XCTAssertFalse(settingsBody.contains("normalizedBaseDirectory("))
    }

    func testEverySlackThreadFailureHasLocalizedMessagesInEveryLocale() {
        let underlying = CommandError.invalidBaseDirectory(.notAbsolute, "synthetic")
        let requestErrors: [SlackThreadRequestError] = [
            .invalidOuterURL,
            .invalidSlackLink,
            .slackLinkTooLong,
            .workDirectoryNotConfigured,
            .invalidWorkDirectory(underlying: underlying),
            .invalidWorkDirectory(underlying: CommandError.invalidBaseDirectory(.invalidCharacters, "synthetic")),
            .invalidWorkDirectory(underlying: CommandError.badRequest("synthetic")),
            .workDirectoryUnavailable,
            .invalidInstruction,
            .appendedPromptUnavailable,
        ]
        let otherUnderlying = NSError(domain: "synthetic", code: 1)
        let installerErrors: [Error] = [
            SlackThreadShortcutInstallerError.createDirectory(otherUnderlying),
            SlackThreadShortcutInstallerError.writeWorkflow(otherUnderlying),
            SlackThreadShortcutInstallerError.signProcess(otherUnderlying),
            SlackThreadShortcutInstallerError.signRejected(status: 1, stderr: "synthetic"),
            SlackThreadShortcutInstallerError.removePreviousSignedShortcut(otherUnderlying),
            SlackThreadShortcutInstallerError.signedShortcutMissing,
            SlackThreadShortcutInstallerError.signedShortcutReadFailed(otherUnderlying),
            SlackThreadShortcutInstallerError.invalidSignatureMagic,
            SlackThreadShortcutInstallerError.shortcutsLaunchFailed(otherUnderlying),
            SlackThreadShortcutInstallerError.shortcutsLaunchTimedOut,
            SlackThreadShortcutInstallerError.shortcutOpenFailed(otherUnderlying),
        ]

        for tag in supportedLocales {
            AppLocalization.tagOverrideForTesting = tag
            for error in requestErrors {
                let message = slackThreadRequestErrorMessage(error)
                XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tag): \(error)")
                XCTAssertFalse(message.hasPrefix("app."), "\(tag): unresolved request key")
            }
            for error in installerErrors {
                let message = slackThreadShortcutInstallerErrorMessage(error)
                XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tag): \(error)")
                XCTAssertFalse(message.hasPrefix("app."), "\(tag): unresolved installer key")
            }
            let unavailableMessage = slackThreadRequestErrorMessage(SlackThreadURLHandlerError.serverUnavailable)
            XCTAssertFalse(unavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tag): server unavailable")
            XCTAssertFalse(unavailableMessage.hasPrefix("app."), "\(tag): unresolved server unavailable key")
        }
    }

    func testShortcutButtonReflectsQueriedStatusNotInstallSuccess() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let installedManager = StubSlackThreadShortcutManager(status: .installed)
        let installedController = SetupWindowController(shortcutInstaller: installedManager)
        let installedButton = installedController.slackShortcutInstallButtonForTesting
        pump(until: { installedButton.title == localized("app.slack.button.reinstall") })
        XCTAssertTrue(installedManager.allCallsWereOffMainThread)

        let notInstalledManager = StubSlackThreadShortcutManager(status: .notInstalled)
        let controller = SetupWindowController(shortcutInstaller: notInstalledManager)
        let button = controller.slackShortcutInstallButtonForTesting
        pump(until: { button.title == localized("app.slack.button.install") && button.isEnabled })
        button.performClick(nil)
        pump(until: { notInstalledManager.installCount == 1 && button.isEnabled })

        XCTAssertEqual(notInstalledManager.installCount, 1)
        XCTAssertEqual(button.title, localized("app.slack.button.install"))
        XCTAssertTrue(
            controller.slackShortcutStatusLabelForTesting.stringValue.contains(
                localized("app.slack.status.notInstalled")
            )
        )
        XCTAssertTrue(notInstalledManager.allCallsWereOffMainThread)
    }

    func testSuccessfulInstallShowsAddShortcutGuidanceUntilStatusIsInstalled() {
        AppLocalization.tagOverrideForTesting = "en"
        let manager = StubSlackThreadShortcutManager(status: .notInstalled)
        let controller = SetupWindowController(shortcutInstaller: manager)
        let button = controller.slackShortcutInstallButtonForTesting
        let feedback = controller.slackShortcutFeedbackLabelForTesting
        pump(until: { button.title == localized("app.slack.button.install") && button.isEnabled })

        button.performClick(nil)
        pump(until: {
            manager.installCount == 1
                && button.isEnabled
                && feedback.stringValue.contains(localized("app.slack.status.addShortcut"))
        })
        XCTAssertTrue(
            controller.slackShortcutStatusLabelForTesting.stringValue.contains(
                localized("app.slack.status.notInstalled")
            )
        )

        manager.setStatus(.installed)
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        pump(until: {
            controller.slackShortcutStatusLabelForTesting.stringValue.contains(
                localized("app.slack.status.installed")
            ) && feedback.isHidden
        })
        XCTAssertEqual(feedback.stringValue, "")
    }

    func testSlackFieldsSaveRawTextAndShowValidationWhileEditing() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let defaults = UserDefaults.standard
        let workKey = "slackThreadWorkDirectory"
        let instructionKey = "slackThreadInstruction"
        let oldWork = defaults.object(forKey: workKey)
        let oldInstruction = defaults.object(forKey: instructionKey)
        defer {
            if let oldWork { defaults.set(oldWork, forKey: workKey) } else { defaults.removeObject(forKey: workKey) }
            if let oldInstruction { defaults.set(oldInstruction, forKey: instructionKey) } else { defaults.removeObject(forKey: instructionKey) }
        }
        Settings.slackThreadWorkDirectory = ""
        Settings.slackThreadInstruction = ""

        let controller = SetupWindowController(
            shortcutInstaller: StubSlackThreadShortcutManager(status: .unknown)
        )
        let workField = controller.slackWorkDirectoryFieldForTesting
        workField.stringValue = "/tmp/has space"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: workField))
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "/tmp/has space")
        XCTAssertTrue(
            controller.slackThreadValidationLabelForTesting.stringValue
                .contains(localized("app.slack.error.workDirectoryInvalidCharacters"))
        )

        workField.stringValue = NSTemporaryDirectory()
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: workField))
        let instructionField = controller.slackInstructionFieldForTesting
        instructionField.stringValue = "line\nbreak"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: instructionField))
        XCTAssertEqual(Settings.slackThreadInstruction, "line\nbreak")
        XCTAssertTrue(
            controller.slackThreadValidationLabelForTesting.stringValue
                .contains(localized("app.slack.error.invalidInstruction"))
        )
    }

    private func pump(until condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertTrue(condition(), "asynchronous shortcut status did not settle")
    }

    private func segment(in source: String, from start: String, to end: String) -> String? {
        guard let startRange = source.range(of: start),
              let endRange = source[startRange.upperBound...].range(of: end) else { return nil }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}

final class StubSlackThreadShortcutManager: SlackThreadShortcutManaging {
    private let lock = NSLock()
    private var storedStatus: SlackThreadShortcutInstallationStatus
    private var storedInstallCount = 0
    private var storedCallsWereOffMainThread = true

    init(status: SlackThreadShortcutInstallationStatus) {
        storedStatus = status
    }

    var installCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInstallCount
    }

    var allCallsWereOffMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedCallsWereOffMainThread
    }

    func setStatus(_ status: SlackThreadShortcutInstallationStatus) {
        lock.lock()
        storedStatus = status
        lock.unlock()
    }

    func install() throws {
        lock.lock()
        storedInstallCount += 1
        storedCallsWereOffMainThread = storedCallsWereOffMainThread && !Thread.isMainThread
        lock.unlock()
    }

    func installationStatus() -> SlackThreadShortcutInstallationStatus {
        lock.lock()
        storedCallsWereOffMainThread = storedCallsWereOffMainThread && !Thread.isMainThread
        let status = storedStatus
        lock.unlock()
        return status
    }
}
