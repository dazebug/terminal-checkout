import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowControllerActionTests: XCTestCase {
    private var savedTerminal: Terminal!
    private var savedLanguage: String!
    private var savedBaseDirectory: String!
    private var savedLastRequestAt: Date?
    private var savedTools: [String: Bool]?
    private var savedExecutables: [String: Bool]?
    private var savedResources: String?
    private var savedTagOverride: String?
    private var savedInstallationProvider: (Terminal) -> Bool = { _ in false }
    private var savedCmuxStatusProvider: (CmuxChannel) -> CmuxSocketStatus = { _ in .notRunning }

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedLanguage = Settings.language
        savedBaseDirectory = Settings.baseDirectory
        savedLastRequestAt = Settings.lastRequestAt
        savedTools = Settings.toolAvailability
        savedExecutables = Settings.toolExecutables
        savedResources = AppLocalization.resourcesPath
        savedTagOverride = AppLocalization.tagOverrideForTesting
        savedInstallationProvider = PermissionChecker.terminalInstallationStatusProvider
        savedCmuxStatusProvider = PermissionChecker.cmuxSocketStatusProvider
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"
        PermissionChecker.terminalInstallationStatusProvider = { _ in true }
        PermissionChecker.cmuxSocketStatusProvider = { _ in .denied }
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        Settings.language = savedLanguage
        Settings.baseDirectory = savedBaseDirectory
        Settings.lastRequestAt = savedLastRequestAt
        Settings.toolAvailability = savedTools
        Settings.toolExecutables = savedExecutables
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTagOverride
        PermissionChecker.terminalInstallationStatusProvider = savedInstallationProvider
        PermissionChecker.cmuxSocketStatusProvider = savedCmuxStatusProvider
        super.tearDown()
    }

    func testCmuxProblemButtonShowsEachOutcomeInItsBlock() throws {
        let effects = SetupWindowControllerEffectsStub()
        let controller = makeController(.cmux, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let block = try cmuxAccessDeniedBlock(in: controller)
        let button = try cmuxConfigButton(in: block)

        sendAction(button)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertFalse(block.actionFeedbackIsHiddenForTesting)
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.status.cmux.configUnavailable"))
        XCTAssertTrue(effects.openedURLs.isEmpty)
        XCTAssertEqual(effects.checkedPaths.count, 2)

        effects.clipboardWriteSucceeds = false
        sendAction(button)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.status.cmux.configClipboardFailed"))
        XCTAssertEqual(effects.checkedPaths.count, 2)
        XCTAssertTrue(effects.openedURLs.isEmpty)

        effects.clipboardWriteSucceeds = true
        effects.configFileExists = true
        effects.workspaceOpenSucceeds = false
        sendAction(button)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.status.cmux.configOpenFailed"))
        XCTAssertEqual(effects.openedURLs.count, 1)

        effects.configFileExists = false
        effects.configDirectoryExists = true
        effects.workspaceOpenSucceeds = true
        sendAction(button)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.status.cmux.configDirectoryOpened"))
        XCTAssertEqual(effects.openedURLs.count, 2)
    }

    func testTerminalTestResultStaysWithTestedTerminalWhenSelectionChangesAndOldRunFinishesLate() throws {
        let effects = SetupWindowControllerEffectsStub()
        let wezTermStarted = DispatchSemaphore(value: 0)
        let finishWezTerm = DispatchSemaphore(value: 0)
        let wezTermReturned = DispatchSemaphore(value: 0)
        let cmuxReturned = DispatchSemaphore(value: 0)
        effects.terminalRunner = { _, terminal in
            if terminal == .wezterm {
                wezTermStarted.signal()
                _ = finishWezTerm.wait(timeout: .now() + 5)
                wezTermReturned.signal()
            } else if terminal == .cmux {
                cmuxReturned.signal()
            }
        }
        let controller = makeController(.wezterm, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let pane = controller.generalPaneForTesting

        sendAction(pane.terminalTestButton)
        XCTAssertEqual(wezTermStarted.wait(timeout: .now() + 2), .success)
        try selectTerminal(.cmux, in: pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(pane.terminalTestResultIsHiddenForTesting)

        sendAction(pane.terminalTestButton)
        XCTAssertEqual(cmuxReturned.wait(timeout: .now() + 2), .success)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertFalse(pane.terminalTestResultIsHiddenForTesting)
        XCTAssertEqual(
            pane.terminalTestResultTextForTesting,
            localized("app.setup.general.terminalTest.success.workspace")
        )

        finishWezTerm.signal()
        XCTAssertEqual(wezTermReturned.wait(timeout: .now() + 2), .success)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(
            pane.terminalTestResultTextForTesting,
            localized("app.setup.general.terminalTest.success.workspace")
        )
    }

    func testCmuxActionFeedbackUsesTheSelectedLanguageAfterRebuilding() throws {
        let effects = SetupWindowControllerEffectsStub()
        effects.configFileExists = true
        effects.workspaceOpenSucceeds = true
        let controller = makeController(.cmux, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let block = try cmuxAccessDeniedBlock(in: controller)

        sendAction(try cmuxConfigButton(in: block))
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.status.cmux.configOpened"))
        XCTAssertEqual(effects.openedURLs.count, 1)

        AppLocalization.tagOverrideForTesting = "ko"
        controller.rebuildForLanguageChange()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let rebuiltBlock = try cmuxAccessDeniedBlock(in: controller)
        XCTAssertEqual(rebuiltBlock.actionFeedbackTextForTesting, localized("app.status.cmux.configOpened"))
        XCTAssertEqual(
            controller.generalPaneForTesting.cmuxFeedbackTextForTesting,
            localized("app.status.cmux.configOpened")
        )
    }

    private func makeController(
        _ terminal: Terminal,
        effects: SetupWindowControllerEffects
    ) -> SetupWindowController {
        Settings.terminal = terminal
        Settings.lastRequestAt = nil
        Settings.baseDirectory = ""
        Settings.toolAvailability = nil
        Settings.toolExecutables = nil
        return SetupWindowTestSupport.onRoomyScreen(SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(),
            loginItem: StubLoginItem(),
            manifestStatusProvider: { .registered },
            extensionFolderStatusProvider: { .present },
            effects: effects
        ))
    }

    func testSocketRecoveryRestartIsRefusedDuringDeliveryAndSaysSoInItsBlock() throws {
        let previousGate = LocaleRestartGate.admitRestart
        let previousSocket = PermissionChecker.appSocketStatusProvider
        var asked = 0
        LocaleRestartGate.admitRestart = { asked += 1; return false }
        PermissionChecker.appSocketStatusProvider = { .unavailable }
        defer {
            LocaleRestartGate.admitRestart = previousGate
            PermissionChecker.appSocketStatusProvider = previousSocket
        }
        let effects = SetupWindowControllerEffectsStub()
        let controller = makeController(.wezterm, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        sendAction(try firstVisibleButton(in: appSocketBlock(in: controller)))
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(effects.relaunchCount, 0)
        XCTAssertEqual(effects.terminateCount, 0)
        let block = try appSocketBlock(in: controller)
        XCTAssertFalse(block.actionFeedbackIsHiddenForTesting)
        XCTAssertEqual(block.actionFeedbackTextForTesting, localized("app.language.restartDeferred"))
    }

    func testBothRestartsRelaunchOnlyThroughTheGateAndAFailedRelaunchGivesTheAdmissionBack() throws {
        let previousGate = LocaleRestartGate.admitRestart
        let previousWithdraw = LocaleRestartGate.withdrawAdmission
        let previousSocket = PermissionChecker.appSocketStatusProvider
        var withdrawn = 0
        LocaleRestartGate.admitRestart = { true }
        LocaleRestartGate.withdrawAdmission = { withdrawn += 1 }
        PermissionChecker.appSocketStatusProvider = { .unavailable }
        defer {
            LocaleRestartGate.admitRestart = previousGate
            LocaleRestartGate.withdrawAdmission = previousWithdraw
            PermissionChecker.appSocketStatusProvider = previousSocket
        }
        let effects = SetupWindowControllerEffectsStub()
        let controller = makeController(.wezterm, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        sendAction(try firstVisibleButton(in: appSocketBlock(in: controller)))
        controller.perform(NSSelectorFromString("restartForLanguage"))
        XCTAssertEqual(effects.relaunchCount, 2)
        XCTAssertEqual(effects.terminateCount, 2)

        effects.relaunchError = CocoaError(.fileNoSuchFile)
        sendAction(try firstVisibleButton(in: appSocketBlock(in: controller)))
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(effects.terminateCount, 2)
        XCTAssertEqual(withdrawn, 1)
        XCTAssertEqual(try appSocketBlock(in: controller).actionFeedbackTextForTesting, localized("app.language.restartFailed"))
    }

    func testInstallRecoveryReopensTheGuideWithItsChromeStepsExpanded() throws {
        Settings.terminal = .wezterm
        Settings.lastRequestAt = Date()
        var folder = SetupWindowExtensionFolderStatus.missing
        let effects = SetupWindowControllerEffectsStub()
        effects.onInstall = { folder = .present }
        let controller = SetupWindowTestSupport.onRoomyScreen(SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(),
            loginItem: StubLoginItem(),
            manifestStatusProvider: { .registered },
            extensionFolderStatusProvider: { folder },
            effects: effects.dependencies
        ))
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let block = try XCTUnwrap(controller.sharedPanelForTesting.problemBlockViews.first {
            $0.problem.copy == .extensionFolderMissingAfterRequest
        })

        sendAction(try firstVisibleButton(in: block))
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(effects.installCount, 1)
        XCTAssertEqual(effects.openedInChrome, ["chrome://extensions"])
        let checklist = try XCTUnwrap(controller.sharedPanelForTesting.installChecklistView)
        XCTAssertFalse(checklist.isHiddenOrHasHiddenAncestor, "the guide stayed closed for a user with a recorded request")
        XCTAssertFalse(checklist.guideStepsContainer.isHiddenOrHasHiddenAncestor)
    }

    func testATerminalTestFailureIsTranslatedWhenItIsDrawn() throws {
        let effects = SetupWindowControllerEffectsStub()
        effects.terminalRunner = { _, _ in throw TerminalError.cmuxSocketDenied }
        let controller = makeController(.cmux, effects: effects.dependencies)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        sendAction(controller.generalPaneForTesting.terminalTestButton)
        let english = localized("app.test.failed", localized("app.error.cmux.socketDenied"))
        try pump(until: { controller.generalPaneForTesting.terminalTestResultTextForTesting == english }, in: window)

        AppLocalization.tagOverrideForTesting = "ko"
        NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let korean = localized("app.test.failed", localized("app.error.cmux.socketDenied"))
        XCTAssertNotEqual(korean, english)
        XCTAssertEqual(controller.generalPaneForTesting.terminalTestResultTextForTesting, korean)
    }

    private func appSocketBlock(in controller: SetupWindowController) throws -> SetupWindowProblemBlockView {
        try XCTUnwrap(controller.sharedPanelForTesting.problemBlockViews.first {
            $0.problem.copy == .appSocketUnavailable
        })
    }

    private func firstVisibleButton(in block: SetupWindowProblemBlockView) throws -> NSButton {
        try XCTUnwrap(block.actionButtons.first { !$0.isHidden })
    }

    /// The terminal test finishes on a background queue; wait for its main-queue completion with a
    /// named bound, then let layout settle.
    private func pump(
        until condition: () -> Bool, in window: NSWindow, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "the terminal test result never arrived", file: file, line: line)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
    }

    private func cmuxAccessDeniedBlock(in controller: SetupWindowController) throws -> SetupWindowProblemBlockView {
        try XCTUnwrap(controller.sharedPanelForTesting.problemBlockViews.first {
            if case .cmuxAccessDenied = $0.problem.copy { return true }
            return false
        })
    }

    private func cmuxConfigButton(in block: SetupWindowProblemBlockView) throws -> NSButton {
        try XCTUnwrap(block.actionButtons.first {
            $0.title == localized("app.setup.action.openCmuxConfig") && !$0.isHidden
        })
    }

    private func sendAction(_ control: NSControl, file: StaticString = #filePath, line: UInt = #line) {
        guard let action = control.action else {
            XCTFail("control has no action", file: file, line: line)
            return
        }
        XCTAssertTrue(NSApp.sendAction(action, to: control.target, from: control), file: file, line: line)
    }

    private func selectTerminal(_ terminal: Terminal, in pane: SetupWindowGeneralPane) throws {
        let index = try XCTUnwrap(pane.terminalPopup.itemArray.firstIndex {
            ($0.representedObject as? String) == terminal.rawValue
        })
        pane.terminalPopup.selectItem(at: index)
        sendAction(pane.terminalPopup)
    }
}

private final class SetupWindowControllerEffectsStub {
    var clipboardWriteSucceeds = true
    var configFileExists = false
    var configDirectoryExists = false
    var workspaceOpenSucceeds = false
    var checkedPaths: [String] = []
    var openedURLs: [URL] = []
    var terminalRunner: (String, Terminal) throws -> Void = { _, _ in }
    var relaunchCount = 0
    var relaunchError: Error?
    var terminateCount = 0
    var installCount = 0
    var onInstall: () -> Void = {}
    var openedInChrome: [String] = []

    var dependencies: SetupWindowControllerEffects {
        SetupWindowControllerEffects(
            writeClipboard: { [weak self] _ in self?.clipboardWriteSucceeds ?? false },
            fileExists: { [weak self] url in
                guard let self else { return false }
                self.checkedPaths.append(url.path)
                return url.lastPathComponent == "cmux.json" ? self.configFileExists : self.configDirectoryExists
            },
            openURL: { [weak self] url in
                guard let self else { return false }
                self.openedURLs.append(url)
                return self.workspaceOpenSucceeds
            },
            runTerminal: { [weak self] command, terminal in
                try self?.terminalRunner(command, terminal)
            },
            relaunch: { [weak self] in
                guard let self else { return }
                self.relaunchCount += 1
                if let error = self.relaunchError { throw error }
            },
            terminate: { [weak self] in self?.terminateCount += 1 },
            installExtensionCopyIfNeeded: { [weak self] in
                self?.installCount += 1
                self?.onInstall()
            },
            openInChrome: { [weak self] url in self?.openedInChrome.append(url) }
        )
    }
}
