import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowGeneralPaneTests: XCTestCase {
    private var savedResources: String?
    private var savedTagOverride: String?

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        savedTagOverride = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"
    }

    override func tearDown() {
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTagOverride
        super.tearDown()
    }

    func testRequestRecordControlsStatusSentenceAndGitHubButtonVisibility() throws {
        let waiting = makePane(state: makeState())
        let waitingWindow = makeWindow(for: waiting.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(waitingWindow))
        XCTAssertEqual(waiting.pane.requestStatusTextForTesting, localized("app.setup.general.request.waiting"))
        XCTAssertTrue(waiting.pane.optionsButton.isHidden)

        let recorded = makePane(state: makeState(requestRecorded: true))
        let recordedWindow = makeWindow(for: recorded.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(recordedWindow))
        XCTAssertEqual(
            recorded.pane.requestStatusTextForTesting,
            localized("app.setup.general.request.recorded", "3 hours ago")
        )
        XCTAssertFalse(recorded.pane.optionsButton.isHidden)
    }

    func testRefreshUpdatesTheSameControlsAndPopover() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let identities = controlIdentities(fixture.pane)
        let popoverIdentity = ObjectIdentifier(fixture.pane.connectionDetailsPopover)
        let menuItemIdentities = fixture.pane.terminalPopup.itemArray.map(ObjectIdentifier.init)

        fixture.pane.update(makeState(terminal: .warp, tabActivation: .background))

        XCTAssertEqual(controlIdentities(fixture.pane), identities)
        XCTAssertEqual(ObjectIdentifier(fixture.pane.connectionDetailsPopover), popoverIdentity)
        XCTAssertEqual(fixture.pane.terminalPopup.itemArray.map(ObjectIdentifier.init), menuItemIdentities)
    }

    func testWarpDisablesActivationSegmentAndShowsForegroundWithoutChangingSavedValue() throws {
        let fixture = makePane(state: makeState(terminal: .warp, tabActivation: .background))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertFalse(fixture.pane.activationSegment.isEnabled)
        XCTAssertEqual(fixture.pane.activationSegment.selectedSegment, 0)
        XCTAssertEqual(fixture.pane.activationSegment.label(forSegment: 0), localized("app.setup.general.afterAction.terminal"))
        XCTAssertEqual(fixture.pane.savedTabActivationForTesting, .background)
    }

    func testLeavingWarpRestoresTheSelectedTerminalSavedActivation() throws {
        let fixture = makePane(state: makeState(terminal: .warp, tabActivation: .background))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        fixture.pane.update(makeState(terminal: .iterm, tabActivation: .background))

        XCTAssertTrue(fixture.pane.activationSegment.isEnabled)
        XCTAssertEqual(fixture.pane.activationSegment.selectedSegment, 1)
    }

    func testMissingTerminalIsDisabledAndMarkedInThePopup() throws {
        let fixture = makePane(state: makeState(terminal: .warp, installed: [.warp: false]))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let item = try XCTUnwrap(fixture.pane.terminalPopup.itemArray.first {
            ($0.representedObject as? String) == Terminal.warp.rawValue
        })

        XCTAssertFalse(item.isEnabled)
        XCTAssertEqual(item.title, localized("app.terminal.notInstalled", "Warp"))
    }

    func testLanguageRestartNoteAppearsOnlyAfterAChoiceAndRetainsBlockedOrFailedState() throws {
        let fixture = makePane(state: makeState(languageChange: .unchanged))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertTrue(fixture.pane.languageNoteLabel.isHidden)
        XCTAssertTrue(fixture.pane.languageRestartButton.isHidden)

        fixture.pane.update(makeState(languageChange: .changed))
        XCTAssertFalse(fixture.pane.languageNoteLabel.isHidden)
        XCTAssertFalse(fixture.pane.languageRestartButton.isHidden)
        XCTAssertEqual(fixture.pane.languageNoteLabel.stringValue, localized("app.language.note"))

        fixture.pane.update(makeState(languageChange: .restartBlocked))
        XCTAssertEqual(fixture.pane.languageNoteLabel.stringValue, localized("app.language.restartDeferred"))
        fixture.pane.update(makeState(languageChange: .restartFailed))
        XCTAssertEqual(fixture.pane.languageNoteLabel.stringValue, localized("app.language.restartFailed"))
    }

    func testControllerActionControlsUseRolesDerivedFromTheirSelectors() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let expected: [(NSControl, SetupWindowGeneralAction)] = [
            (fixture.pane.terminalPopup, .terminalChanged),
            (fixture.pane.activationSegment, .tabActivationChanged),
            (fixture.pane.terminalTestButton, .testTerminal),
            (fixture.pane.languagePopup, .languageChanged),
            (fixture.pane.languageRestartButton, .restartForLanguage),
            (fixture.pane.optionsButton, .openOptionsPage),
            (fixture.pane.guideButton, .reshowInstall),
        ]

        for (control, action) in expected {
            let selector = try XCTUnwrap(fixture.selectors[action])
            XCTAssertEqual(control.action, selector)
            XCTAssertEqual(control.identifier, setupWindowControlRole(selector))
        }
    }

    func testPreviewAccessibilityDescriptionFollowsDestinationAndFrontmostScreen() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let tabFront = fixture.pane.previewView.effectDescription

        fixture.pane.update(makeState(terminal: .cmux, tabActivation: .background))

        let workspaceBack = fixture.pane.previewView.effectDescription
        XCTAssertNotEqual(tabFront, workspaceBack)
        XCTAssertEqual(workspaceBack, fixture.pane.previewView.accessibilityLabel())
        XCTAssertEqual(
            workspaceBack,
            localized("app.setup.preview.general.workspace.currentFront")
        )
    }

    func testTerminalTestSuccessUsesACompleteLocalizedSentenceForItsDestination() throws {
        let fixture = makePane(state: makeState(terminalTestResult: .succeeded))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(
            fixture.pane.terminalTestResultTextForTesting,
            localized("app.setup.general.terminalTest.success.tab")
        )

        fixture.pane.update(makeState(terminal: .cmux, terminalTestResult: .succeeded))
        XCTAssertEqual(
            fixture.pane.terminalTestResultTextForTesting,
            localized("app.setup.general.terminalTest.success.workspace")
        )
    }

    func testConnectionDetailsPopoverIsTransientAndCmuxActionsAreActionDerived() throws {
        let fixture = makePane(state: makeState(terminal: .cmux))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(fixture.pane.connectionDetailsPopover.behavior, .transient)
        XCTAssertEqual(fixture.pane.cmuxActionButtonRolesForTesting.count, 2)
        XCTAssertEqual(
            fixture.pane.cmuxActionButtonRolesForTesting,
            [
                setupWindowControlRole(
                    try XCTUnwrap(fixture.selectors[.openCmuxConfig]), "connection-details.cmux-config"
                ),
                setupWindowControlRole(
                    try XCTUnwrap(fixture.selectors[.refreshCmuxStatus]), "connection-details.cmux-refresh"
                ),
            ]
        )
    }

    func testConnectionDetailsUpdatesCmuxFeedbackWithoutReplacingThePane() throws {
        let fixture = makePane(state: makeState(terminal: .cmux))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let pane = fixture.pane
        let popover = pane.connectionDetailsPopover

        pane.update(makeState(
            terminal: .cmux,
            cmuxFeedback: .init(text: localized("app.status.cmux.configOpened"), tone: .success)
        ))

        XCTAssertTrue(popover === pane.connectionDetailsPopover)
        XCTAssertFalse(pane.cmuxFeedbackIsHiddenForTesting)
        XCTAssertEqual(pane.cmuxFeedbackTextForTesting, localized("app.status.cmux.configOpened"))

        pane.update(makeState(terminal: .cmux))
        XCTAssertTrue(pane.cmuxFeedbackIsHiddenForTesting)
    }

    func testTerminalDetailTitleUsesOneLocalizedSentenceWithTerminalName() throws {
        let fixture = makePane(state: makeState(terminal: .cmux))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(
            fixture.pane.terminalDetailTitleForTesting,
            localized("app.setup.general.connection.terminal", "cmux")
        )
    }

    func testCmuxConnectionDetailsReadsTheTypedSocketState() throws {
        let expected = localized("app.setup.general.status.cmux.accessDenied")
        let fixture = makePane(state: makeState(
            terminal: .cmux,
            terminalStatus: .init(text: expected, tone: .error)
        ))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(fixture.pane.terminalDetailTitleForTesting, localized("app.setup.general.connection.terminal", "cmux"))
        XCTAssertEqual(fixture.pane.terminalDetailValueForTesting, expected)
    }

    func testNightlyCmuxConnectionDetailsKeepsItsChannelNameAndStatus() throws {
        let expected = localized("app.setup.general.status.cmux.reachable")
        let fixture = makePane(state: makeState(
            terminal: .cmuxNightly,
            terminalStatus: .init(text: expected, tone: .success)
        ))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(
            fixture.pane.terminalDetailTitleForTesting,
            localized("app.setup.general.connection.terminal", "cmux NIGHTLY")
        )
        XCTAssertEqual(fixture.pane.terminalDetailValueForTesting, expected)
    }

    func testHintUsesACompleteSentenceForTabsOrCmuxWorkspace() throws {
        let fixture = makePane(state: makeState(terminal: .iterm))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let tabsHint = fixture.pane.hintTextForTesting

        fixture.pane.update(makeState(terminal: .cmux))

        XCTAssertEqual(tabsHint, localized("app.setup.general.hint.tabs"))
        XCTAssertEqual(fixture.pane.hintTextForTesting, localized("app.setup.general.hint.workspace"))
    }

    private func makePane(state: SetupWindowGeneralPaneState) -> (
        pane: SetupWindowGeneralPane,
        target: GeneralPaneActionTarget,
        selectors: [SetupWindowGeneralAction: Selector]
    ) {
        let target = GeneralPaneActionTarget()
        let selectors: [SetupWindowGeneralAction: Selector] = [
            .terminalChanged: #selector(GeneralPaneActionTarget.terminalChanged),
            .tabActivationChanged: #selector(GeneralPaneActionTarget.tabActivationChanged),
            .testTerminal: #selector(GeneralPaneActionTarget.testTerminal),
            .languageChanged: #selector(GeneralPaneActionTarget.languageChanged),
            .restartForLanguage: #selector(GeneralPaneActionTarget.restartForLanguage),
            .openOptionsPage: #selector(GeneralPaneActionTarget.openOptionsPage),
            .reshowInstall: #selector(GeneralPaneActionTarget.reshowInstall),
            .openCmuxConfig: #selector(GeneralPaneActionTarget.openCmuxConfig),
            .refreshCmuxStatus: #selector(GeneralPaneActionTarget.refreshCmuxStatus),
        ]
        let pane = SetupWindowGeneralPane(state: state, target: target, selectors: selectors)
        return (pane, target, selectors)
    }

    private func makeState(
        requestRecorded: Bool = false,
        terminal: Terminal = .iterm,
        tabActivation: TabActivation = .foreground,
        installed: [Terminal: Bool] = Dictionary(uniqueKeysWithValues: Terminal.allCases.map { ($0, true) }),
        languageChange: SetupWindowGeneralLanguageChange = .unchanged,
        cmuxFeedback: SetupWindowGeneralIndicator? = nil,
        terminalStatus: SetupWindowGeneralIndicator = .init(text: "Ready", tone: .success),
        terminalTestResult: SetupWindowGeneralTerminalTestResult = .notRun
    ) -> SetupWindowGeneralPaneState {
        let requestDate = requestRecorded ? Date(timeIntervalSince1970: 1_791_000_000) : nil
        let installations = Terminal.allCases.map {
            SetupWindowTerminalInstallation(terminal: $0, isInstalled: installed[$0] ?? true)
        }
        let snapshot = SetupWindowSnapshot(
            lastRequestAt: requestDate,
            selectedTerminal: terminal,
            terminalInstallations: installations,
            tabActivation: tabActivation
        )
        return SetupWindowGeneralPaneState(
            presentation: SetupWindowPresentationModel.make(from: snapshot),
            appVersion: "v1.2.3",
            requestRelativeTime: requestRecorded ? "3 hours ago" : nil,
            terminalInstallations: installations,
            nativeHostStatus: .init(text: localized("app.setup.install.nativeHost.complete"), tone: .success),
            appSocketStatus: .init(text: "Listening", tone: .success),
            terminalStatus: terminalStatus,
            tools: SetupWindowToolResults(
                available: ["zoxide": true, "gh": true, "claude": true],
                executable: ["claude": true]
            ),
            savedTabActivation: tabActivation,
            terminalTestResult: terminalTestResult,
            storedLanguage: automaticLocalePreference,
            resolvedLanguage: "en",
            languageChange: languageChange,
            cmuxFeedback: cmuxFeedback
        )
    }

    private func makeWindow(for pane: SetupWindowGeneralPane) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 430))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let stack = FittedContentStackView(frame: NSRect(x: 0, y: 0, width: 720, height: 0))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.addArrangedSubview(pane)
        scrollView.documentView = stack
        window.contentView = scrollView
        return window
    }

    private func controlIdentities(_ pane: SetupWindowGeneralPane) -> [ObjectIdentifier] {
        [
            ObjectIdentifier(pane.connectionDetailsButton),
            ObjectIdentifier(pane.terminalPopup),
            ObjectIdentifier(pane.activationSegment),
            ObjectIdentifier(pane.terminalTestButton),
            ObjectIdentifier(pane.languagePopup),
            ObjectIdentifier(pane.languageRestartButton),
            ObjectIdentifier(pane.optionsButton),
            ObjectIdentifier(pane.guideButton),
            ObjectIdentifier(pane.previewView),
        ]
    }
}

private final class GeneralPaneActionTarget: NSObject {
    @objc func terminalChanged() {}
    @objc func tabActivationChanged() {}
    @objc func testTerminal() {}
    @objc func languageChanged() {}
    @objc func restartForLanguage() {}
    @objc func openOptionsPage() {}
    @objc func reshowInstall() {}
    @objc func openCmuxConfig() {}
    @objc func refreshCmuxStatus() {}
}
