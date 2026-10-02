import AppKit
import XCTest
@testable import App

final class SetupWindowSharedPanelTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []
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

    private func makePanel(
        presentation: SetupWindowPresentation,
        manifest: SetupWindowManifestStatus = .registered,
        extensionFolder: SetupWindowExtensionFolderStatus = .present,
        installStepsExpanded: Bool = false,
        installFeedback: String? = nil,
        slackFailureDetail: String? = nil
    ) throws -> SetupWindowSharedPanel {
        let target = NSObject()
        let selectors = Dictionary(uniqueKeysWithValues: SetupWindowSharedPanelAction.allCases.map {
            ($0, NSSelectorFromString($0.rawValue))
        })
        let panel = SetupWindowSharedPanel(
            presentation: presentation,
            manifest: manifest,
            extensionFolder: extensionFolder,
            installStepsExpanded: installStepsExpanded,
            installFeedback: installFeedback,
            slackFailureDetail: slackFailureDetail,
            target: target,
            selectors: selectors
        )
        let document = FittedContentStackView(views: [panel])
        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 0
        document.widthAnchor.constraint(equalToConstant: 720).isActive = true
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        Self.retainedWindows.append(window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        return panel
    }

    private func presentation(
        problems: [SetupWindowProblem] = [],
        showsFirstInstallChecklist: Bool = false,
        connectionSentence: SetupWindowConnectionSentence = .waitingForFirstRequest
    ) -> SetupWindowPresentation {
        SetupWindowPresentation(
            problems: problems,
            showsFirstInstallChecklist: showsFirstInstallChecklist,
            connectionSentence: connectionSentence,
            baseDirectoryNotice: nil,
            slackToolbarHasFailureDot: false,
            previews: .init(
                general: .init(
                    terminal: .iterm,
                    destination: .newTab,
                    frontmostScreen: .newTerminalSession,
                    effectSentence: .general(
                        terminal: .iterm,
                        destination: .newTab,
                        frontmostScreen: .newTerminalSession
                    )
                ),
                github: .init(
                    rowNumbers: [1, 2, 3],
                    destination: .newTabPerRow,
                    effectSentence: .githubRowsOpenNewTabs(rowNumbers: [1, 2, 3])
                ),
                slack: .init(
                    usesWorkingFolder: true,
                    firstMessage: .slackLinkThenInstruction,
                    requiresSlackMCP: true,
                    effectSentence: .slackClaudeInWorkingFolder(
                        firstMessage: .slackLinkThenInstruction,
                        requiresSlackMCP: true
                    )
                )
            )
        )
    }

    func testProblemBlocksFollowThePresentationModelOrder() throws {
        let problems = [
            SetupWindowProblem(
                severity: .warning,
                copy: .claudeInputRejected(.warpHelperUnavailable)
            ),
            SetupWindowProblem(severity: .error, copy: .slackThreadRequestFailed),
            SetupWindowProblem(severity: .error, copy: .manifestNotRegistered),
            SetupWindowProblem(severity: .warning, copy: .warpAccessibilityRequired),
        ]
        let panel = try makePanel(presentation: presentation(problems: problems))

        XCTAssertEqual(panel.problemBlockViews.map(\.problem), problems)
        let arrangedBlocks = panel.subviews
            .compactMap { $0 as? NSStackView }
            .flatMap(\.arrangedSubviews)
            .compactMap { $0 as? SetupWindowProblemBlockView }
        XCTAssertEqual(arrangedBlocks.map(\.problem), problems)
    }

    func testProblemBlockHasTitleCauseActionAndActionDerivedRole() throws {
        let problem = SetupWindowProblem(severity: .error, copy: .manifestNotRegistered)
        let panel = try makePanel(presentation: presentation(problems: [problem]), manifest: .notRegistered)
        let block = try XCTUnwrap(panel.problemBlockViews.first)
        let button = try XCTUnwrap(block.actionButtons.first)

        XCTAssertEqual(block.titleLabel.stringValue, localized("app.setup.problem.manifest.title"))
        XCTAssertFalse(block.paragraphLabels.isEmpty)
        XCTAssertEqual(button.title, localized("app.setup.action.registerManifest"))
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(button.action)), "registerManifest")
        XCTAssertEqual(
            button.identifier?.rawValue,
            setupWindowSharedPanelRole(try XCTUnwrap(button.action), "problem.manifest").rawValue
        )
        XCTAssertTrue(block.voiceOverLabel.contains(localized("app.setup.severity.error")))
    }

    func testFirstInstallChecklistShowsMissingFolderAndUnregisteredHost() throws {
        let issue = SetupWindowProblem(severity: .error, copy: .manifestNotRegistered)
        let panel = try makePanel(
            presentation: presentation(problems: [issue], showsFirstInstallChecklist: true),
            manifest: .notRegistered,
            extensionFolder: .missing
        )
        let checklist = try XCTUnwrap(panel.installChecklistView)

        XCTAssertTrue(panel.problemBlockViews.isEmpty, "the checklist already presents this Native Host problem")
        XCTAssertEqual(checklist.steps.count, 3)
        XCTAssertEqual(checklist.steps[0].titleLabel.stringValue, localized("app.setup.install.nativeHost.title"))
        XCTAssertEqual(checklist.steps[0].actionButton?.title, localized("app.setup.action.registerManifest"))
        XCTAssertEqual(checklist.steps[1].titleLabel.stringValue, localized("app.button.installInChrome"))
        XCTAssertEqual(checklist.steps[1].statusLabel.stringValue, localized("app.setup.install.chrome.folderMissing"))
        XCTAssertEqual(checklist.steps[1].actionButton?.title, localized("app.setup.action.chromeInstall"))
        XCTAssertEqual(checklist.steps[1].actionButton?.keyEquivalent, "\r")
        XCTAssertEqual(checklist.steps[2].titleLabel.stringValue, localized("app.setup.install.github.pendingTitle"))
        XCTAssertFalse(checklist.steps[2].isComplete)
        XCTAssertNil(checklist.closeGuideButton)
    }

    func testFirstInstallChecklistMarksRegisteredNativeHostComplete() throws {
        let panel = try makePanel(
            presentation: presentation(showsFirstInstallChecklist: true),
            manifest: .registered
        )
        let checklist = try XCTUnwrap(panel.installChecklistView)

        XCTAssertTrue(checklist.steps[0].isComplete)
        XCTAssertEqual(
            checklist.steps[0].statusLabel.stringValue,
            localized("app.setup.install.nativeHost.complete")
        )
        XCTAssertNil(checklist.steps[0].actionButton)
    }

    func testChromeInstallActionCanRevealFourStepsAndFeedback() throws {
        let panel = try makePanel(
            presentation: presentation(showsFirstInstallChecklist: true),
            extensionFolder: .present
        )
        let checklist = try XCTUnwrap(panel.installChecklistView)

        XCTAssertTrue(checklist.guideStepsContainer.isHidden)
        XCTAssertTrue(checklist.feedbackLabel.isHidden)

        panel.showChromeInstallationSteps()

        XCTAssertFalse(checklist.guideStepsContainer.isHidden)
        XCTAssertEqual(checklist.guideStepLabels.count, 4)
        XCTAssertEqual(checklist.guideStepLabels.map(\.stringValue), [
            localized("app.setup.install.chrome.step.developerMode"),
            localized("app.setup.install.chrome.step.loadUnpacked"),
            localized("app.setup.install.chrome.step.filePicker"),
            localized("app.setup.install.chrome.step.keepMode"),
        ])
        XCTAssertFalse(checklist.feedbackLabel.isHidden)
        XCTAssertEqual(checklist.feedbackLabel.stringValue, localized("app.setup.install.chrome.feedback"))
    }

    func testReopenedGuideCanBeClosedWithoutChangingRequestEvidence() throws {
        let requestedAt = Date(timeIntervalSince1970: 100)
        let panel = try makePanel(
            presentation: presentation(
                showsFirstInstallChecklist: true,
                connectionSentence: .requestRecorded(at: requestedAt)
            )
        )
        let checklist = try XCTUnwrap(panel.installChecklistView)
        let closeButton = try XCTUnwrap(checklist.closeGuideButton)

        XCTAssertTrue(checklist.steps[2].isComplete)
        XCTAssertEqual(checklist.steps[2].titleLabel.stringValue, localized("app.setup.install.github.completeTitle"))
        XCTAssertEqual(checklist.steps[2].statusLabel.stringValue, localized("app.setup.install.github.complete"))
        XCTAssertEqual(closeButton.title, localized("app.setup.action.dismissSetupGuide"))
        XCTAssertEqual(panel.presentation.connectionSentence, .requestRecorded(at: requestedAt))
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(closeButton.action)), "dismissSetupGuide")
    }
}
