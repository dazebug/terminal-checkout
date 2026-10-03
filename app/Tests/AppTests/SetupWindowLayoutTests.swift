import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowLayoutTests: XCTestCase {
    private var savedTerminal: Terminal!
    private var savedResources: String?
    private var savedTag: String?
    private var savedBaseDirectory: String!
    private var savedLastRequestAt: Date?
    private var savedTools: [String: Bool]?
    private var savedExecutables: [String: Bool]?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedBaseDirectory = Settings.baseDirectory
        savedLastRequestAt = Settings.lastRequestAt
        savedTools = Settings.toolAvailability
        savedExecutables = Settings.toolExecutables
        savedResources = AppLocalization.resourcesPath
        savedTag = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = Self.sourceResources
        AppLocalization.tagOverrideForTesting = "en"
        Settings.lastRequestAt = nil
        Settings.toolAvailability = nil
        Settings.toolExecutables = nil
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        Settings.baseDirectory = savedBaseDirectory
        Settings.lastRequestAt = savedLastRequestAt
        Settings.toolAvailability = savedTools
        Settings.toolExecutables = savedExecutables
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTag
        super.tearDown()
    }

    static var sourceResources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    private func makeController(
        _ terminal: Terminal = .iterm,
        blocker: ClaudeInputBlocker? = nil,
        slackFailure: Error? = nil
    ) -> SetupWindowController {
        Settings.terminal = terminal
        return SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem(),
            openingBlocker: blocker, slackRequestFailure: slackFailure
        )
    }

    private func contentHeight(_ window: NSWindow) -> CGFloat {
        window.contentRect(forFrameRect: window.frame).height
    }

    private func select(_ pane: String, in window: NSWindow) throws {
        let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "setup.pane.\(pane)" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    func testPreferenceToolbarHasThreePanesAndUsesAStandardTitlebar() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(window.toolbarStyle, .preference)
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.title, localized("app.setup.toolbar.general"))
        XCTAssertEqual(contentHeight(window), controller.rootStack.fittingSize.height, accuracy: 0.5)
        XCTAssertEqual(controller.rootStack.arrangedSubviews.map { $0.identifier?.rawValue }, [
            "panel.shared", "pane.general", "pane.github", "pane.slack",
        ])
        XCTAssertEqual(window.toolbar?.items.map(\.label), [
            localized("app.setup.toolbar.general"), localized("app.setup.toolbar.github"),
            localized("app.setup.toolbar.slack"),
        ])
        let toolbarItems = try XCTUnwrap(window.toolbar?.items)
        XCTAssertTrue(toolbarItems[0].image === NSApp.applicationIconImage)
        XCTAssertNotNil(toolbarItems[1].image)
        XCTAssertEqual(toolbarItems[2].image?.accessibilityDescription, localized("app.setup.toolbar.slack"))
        XCTAssertTrue(controller.sharedPanelForTesting.isHidden == false)
        XCTAssertFalse(controller.generalPaneForTesting.isHidden)
        XCTAssertTrue(controller.githubPaneForTesting.isHidden)
        XCTAssertTrue(controller.slackPaneForTesting.isHidden)
    }

    func testSelectingAToolbarPaneFitsOnlyThatPaneBelowTheSharedPanel() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        try select("github", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(controller.selectedPaneForTesting, "github")
        XCTAssertEqual(window.title, localized("app.setup.toolbar.github"))
        XCTAssertEqual(window.toolbar?.selectedItemIdentifier?.rawValue, "setup.pane.github")
        XCTAssertFalse(controller.sharedPanelForTesting.isHidden)
        XCTAssertTrue(controller.generalPaneForTesting.isHidden)
        XCTAssertFalse(controller.githubPaneForTesting.isHidden)
        XCTAssertTrue(controller.slackPaneForTesting.isHidden)
        XCTAssertEqual(contentHeight(window), controller.rootStack.fittingSize.height, accuracy: 0.5)

        try select("slack", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(controller.selectedPaneForTesting, "slack")
        XCTAssertFalse(controller.sharedPanelForTesting.isHidden)
        XCTAssertFalse(controller.slackPaneForTesting.isHidden)
        XCTAssertEqual(contentHeight(window), controller.rootStack.fittingSize.height, accuracy: 0.5)
    }

    func testOpeningReasonsChooseTheirPaneAndSlackFailureMarksItsToolbarItem() throws {
        let slack = SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem(),
            slackRequestFailure: SlackThreadRequestError.invalidSlackLink
        )
        let slackWindow = try XCTUnwrap(slack.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(slackWindow))
        XCTAssertEqual(slack.selectedPaneForTesting, "slack")
        XCTAssertTrue(slack.sharedPanelForTesting.problemBlockViews.contains {
            if case .slackThreadRequestFailed = $0.problem.copy { return true }
            return false
        })
        let slackItem = try XCTUnwrap(slackWindow.toolbar?.items.first {
            $0.itemIdentifier.rawValue == "setup.pane.slack"
        })
        XCTAssertEqual(slackItem.toolTip, localized("app.setup.toolbar.slack.failure"))
        XCTAssertEqual(
            slackItem.image?.accessibilityDescription,
            localized("app.setup.toolbar.slack.failure")
        )

        let claude = makeController(.warp, blocker: .warpAccessibility)
        XCTAssertEqual(claude.selectedPaneForTesting, "general")
        XCTAssertTrue(claude.sharedPanelForTesting.problemBlockViews.contains {
            if case .claudeInputRejected(.warpAccessibility) = $0.problem.copy { return true }
            return false
        })
    }

    func testFittedStackClampsToItsVisibleFrameWithoutSqueezingTheDocument() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let needed = controller.rootStack.fittingSize.height
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: needed / 2)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        XCTAssertEqual(contentHeight(window), needed / 2, accuracy: 0.5)
        XCTAssertGreaterThan(controller.rootStack.frame.height, scroll.contentView.bounds.height)
        XCTAssertEqual(controller.rootStack.frame.height, controller.rootStack.fittingSize.height, accuracy: 0.5)
    }

    func testARefreshKeepsEveryPaneAndSharedPanelInstance() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let shared = controller.sharedPanelForTesting
        let general = controller.generalPaneForTesting
        let github = controller.githubPaneForTesting
        let slack = controller.slackPaneForTesting
        let generalPopup = general.terminalPopup
        let githubField = github.baseDirectoryField
        let slackField = slack.workDirectoryField

        controller.refreshForTesting()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertTrue(shared === controller.sharedPanelForTesting)
        XCTAssertTrue(general === controller.generalPaneForTesting)
        XCTAssertTrue(github === controller.githubPaneForTesting)
        XCTAssertTrue(slack === controller.slackPaneForTesting)
        XCTAssertTrue(generalPopup === controller.generalPaneForTesting.terminalPopup)
        XCTAssertTrue(githubField === controller.githubPaneForTesting.baseDirectoryField)
        XCTAssertTrue(slackField === controller.slackPaneForTesting.workDirectoryField)
    }
}
