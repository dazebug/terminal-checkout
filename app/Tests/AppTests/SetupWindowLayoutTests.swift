import AppKit
import Core
import TestSupport
import XCTest
@testable import App

final class SetupWindowLayoutTests: XCTestCase {
    static let populatedLocales = supportedLocales
    private let roomyScreen = NSRect(x: 0, y: 0, width: 1600, height: 2000)
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
        slackFailure: Error? = nil,
        manifest: SetupWindowManifestStatus = .registered,
        extensionFolder: SetupWindowExtensionFolderStatus = .present
    ) -> SetupWindowController {
        Settings.terminal = terminal
        return SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem(),
            openingBlocker: blocker, slackRequestFailure: slackFailure,
            manifestStatusProvider: { manifest },
            extensionFolderStatusProvider: { extensionFolder }
        )
    }

    private func contentHeight(_ window: NSWindow) -> CGFloat {
        window.contentRect(forFrameRect: window.frame).height
    }

    private func select(_ pane: String, in window: NSWindow) throws {
        let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "setup.pane.\(pane)" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    private func visibleWrappingLabels(in view: NSView) -> [NSTextField] {
        guard !view.isHidden else { return [] }
        var labels: [NSTextField] = []
        if let field = view as? NSTextField, field.cell?.wraps == true, !field.usesSingleLineMode {
            labels.append(field)
        }
        for child in view.subviews {
            labels.append(contentsOf: visibleWrappingLabels(in: child))
        }
        return labels
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
            slackRequestFailure: SlackThreadRequestError.invalidSlackLink,
            manifestStatusProvider: { .registered },
            extensionFolderStatusProvider: { .present }
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

        let previousAccessibilityProvider = PermissionChecker.accessibilityStatusProvider
        PermissionChecker.accessibilityStatusProvider = { false }
        defer { PermissionChecker.accessibilityStatusProvider = previousAccessibilityProvider }
        let claude = makeController(.warp, blocker: .warpAccessibility)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(try XCTUnwrap(claude.window)))
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

    func testTheWindowFitsEveryPaneInEveryPopulatedLocale() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for tag in Self.populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            if tag != "en" {
                controller.rebuildForLanguageChange()
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            }
            for pane in ["general", "github", "slack"] {
                try select(pane, in: window)
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                let needed = controller.rootStack.fittingSize.height
                XCTAssertGreaterThan(needed, 0, "\(tag)/\(pane) measured no pane content")
                XCTAssertEqual(contentHeight(window), needed, accuracy: 0.5, "\(tag)/\(pane) did not fit")
                XCTAssertEqual(controller.rootStack.frame.height, needed, accuracy: 0.5, "\(tag)/\(pane) was squeezed")
                let expectedTitle: String
                switch pane {
                case "general": expectedTitle = localized("app.setup.toolbar.general")
                case "github": expectedTitle = localized("app.setup.toolbar.github")
                default: expectedTitle = localized("app.setup.toolbar.slack")
                }
                XCTAssertEqual(window.title, expectedTitle)
            }
        }
    }

    func testEveryStatusLabelIsStyledToWrap() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let labels = controller.wrappingStatusLabelsForTesting
        XCTAssertGreaterThan(labels.count, 10, "the fixture found too few status and explanation labels")
        for label in labels {
            XCTAssertFalse(label.usesSingleLineMode, "single line: \(label)")
            XCTAssertEqual(label.cell?.wraps, true, "does not wrap: \(label)")
            XCTAssertTrue(
                label.maximumNumberOfLines == 0 || label.maximumNumberOfLines > 1,
                "cannot wrap to more than one line: \(label)"
            )
        }
    }

    func testEveryVisibleWrappedLabelFitsItsAssignedWidthInEveryLocaleAndPane() throws {
        Settings.lastRequestAt = nil
        let controller = makeController(
            .iterm,
            slackFailure: SlackThreadRequestError.invalidSlackLink,
            manifest: .wrongRelayPath
        )
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 720, accuracy: 0.5)

        for tag in Self.populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            controller.rebuildForLanguageChange()
            _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            let checklist = try XCTUnwrap(controller.sharedPanelForTesting.installChecklistView)
            XCTAssertFalse(checklist.isHidden)
            XCTAssertTrue(controller.sharedPanelForTesting.problemBlockViews.contains {
                $0.problem.copy == .slackThreadRequestFailed
            })
            if tag == "ko" {
                XCTAssertEqual(
                    checklist.steps[0].statusLabel.stringValue,
                    "Native Host가 다른 위치의 앱을 가리킵니다. 앱은 실행될 때마다 확인하고 고치지만, 이번에는 고치지 못했습니다."
                )
            }

            for pane in ["general", "github", "slack"] {
                try select(pane, in: window)
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                let labels = visibleWrappingLabels(in: controller.rootStack)
                XCTAssertGreaterThan(labels.count, 0, "\(tag)/\(pane) exposed no wrapping labels")
                for label in labels {
                    let width = label.bounds.width
                    XCTAssertGreaterThan(width, 0, "\(tag)/\(pane) has an unmeasured wrapping label: \(label.stringValue)")
                    let needed = try XCTUnwrap(label.cell).cellSize(forBounds: NSRect(
                        x: 0, y: 0, width: width, height: 10_000
                    )).height
                    XCTAssertGreaterThanOrEqual(
                        label.frame.height + 0.75,
                        needed,
                        "\(tag)/\(pane) clipped `\(label.stringValue)` at \(width)pt: frame \(label.frame.height), needed \(needed)"
                    )
                }
            }
        }
    }

    func testWindowMatchesContentAcrossEveryTerminalTransition() throws {
        let controller = makeController(.iterm)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen
        for terminal in [Terminal.warp, .wezterm, .cmux, .cmuxNightly, .iterm, .warp] {
            controller.selectTerminalForTesting(terminal)
            _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            let needed = controller.rootStack.fittingSize.height
            XCTAssertEqual(contentHeight(window), needed, accuracy: 0.5, "\(terminal) did not fit")
            XCTAssertEqual(controller.rootStack.frame.height, needed, accuracy: 0.5, "\(terminal) was squeezed")
            XCTAssertEqual(
                controller.githubPaneForTesting.cmuxSectionIsHiddenForTesting,
                terminal.cmuxChannel == nil,
                "GitHub placement visibility did not follow \(terminal)"
            )
        }
    }

    func testGrowingNearTheBottomEdgeKeepsTheWindowOnScreen() throws {
        let controller = makeController(.wezterm)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        window.setFrameOrigin(NSPoint(x: roomyScreen.minX + 20, y: roomyScreen.minY + 4))

        controller.selectTerminalForTesting(.warp)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertGreaterThanOrEqual(window.frame.minY, roomyScreen.minY - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxY, roomyScreen.maxY + 0.5)
        XCTAssertEqual(contentHeight(window), controller.rootStack.fittingSize.height, accuracy: 0.5)
    }

    func testCenteringAndClampingConsumeTheSameVisibleFrame() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        let visible = NSRect(x: 100, y: 200, width: 600, height: 600)
        FittedContentStackView.centerInside(visible, window)
        FittedContentStackView.moveInside(visible, window)
        XCTAssertEqual(window.frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, visible.midY, accuracy: 0.5)

        let otherVisible = NSRect(x: 1000, y: 1200, width: 600, height: 600)
        FittedContentStackView.moveInside(otherVisible, window)
        XCTAssertEqual(window.frame.minX, otherVisible.minX, accuracy: 0.5)
        XCTAssertEqual(window.frame.minY, otherVisible.minY, accuracy: 0.5)
    }

    func testAccessibilityGrantRefreshConvergesWithFittedPlacement() throws {
        let previousAccessibilityProvider = PermissionChecker.accessibilityStatusProvider
        var granted = false
        PermissionChecker.accessibilityStatusProvider = { granted }
        defer { PermissionChecker.accessibilityStatusProvider = previousAccessibilityProvider }

        let controller = makeController(.warp)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(controller.sharedPanelForTesting.problemBlockViews.contains {
            $0.problem.copy == .warpAccessibilityRequired
        })
        let deniedHeight = controller.rootStack.fittingSize.height

        granted = true
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertFalse(controller.sharedPanelForTesting.problemBlockViews.contains {
            $0.problem.copy == .warpAccessibilityRequired
        })
        XCTAssertLessThan(controller.rootStack.fittingSize.height, deniedHeight)
        XCTAssertEqual(contentHeight(window), controller.rootStack.fittingSize.height, accuracy: 0.5)

        let settled = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let repeated = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(settled.isStable(with: repeated))
    }

    func testCmuxLiveStatusComesFromRefreshAndStatusCheckClearsActionFeedback() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/App/SetupWindowController.swift").path
        let source = try auditSource(sourcePath, claim: .sourceStructure).text
        let refreshStart = try XCTUnwrap(source.range(of: "private func refresh() {")?.lowerBound)
        let refreshEnd = try XCTUnwrap(
            source.range(of: "\n    private func makeGeneralState", range: refreshStart..<source.endIndex)?.lowerBound
        )
        let refresh = String(source[refreshStart..<refreshEnd])
        XCTAssertTrue(refresh.contains("let generalState = makeGeneralState(environment)"))
        XCTAssertTrue(refresh.contains("generalPane.update(generalState)"))
        XCTAssertEqual(source.components(separatedBy: "makeGeneralState(environment)").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "generalPane.update(generalState)").count - 1, 1)
        let buildStart = try XCTUnwrap(source.range(of: "private func buildContent(using environment:")?.lowerBound)
        let buildEnd = try XCTUnwrap(
            source.range(of: "\n    private func", range: buildStart..<source.endIndex)?.lowerBound
        )
        XCTAssertTrue(String(source[buildStart..<buildEnd]).contains("state: makeGeneralState(environment)"))

        let statusActionStart = try XCTUnwrap(source.range(of: "@objc private func refreshCmuxStatus() {")?.lowerBound)
        let statusActionEnd = try XCTUnwrap(
            source.range(of: "\n    }", range: statusActionStart..<source.endIndex)?.lowerBound
        )
        let statusAction = String(source[statusActionStart..<statusActionEnd])
        XCTAssertTrue(statusAction.contains("cmuxFeedback = nil"))
        XCTAssertTrue(statusAction.contains("refresh()"))
    }

    func testPaneLeftColumnsFitTheirContentAndLeaveSurplusBelow() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        func assertVerticalStacksFit(_ view: NSView, file: StaticString = #filePath, line: UInt = #line) {
            guard !view.isHidden else { return }
            if let stack = view as? NSStackView, stack.orientation == .vertical {
                XCTAssertEqual(
                    stack.frame.height,
                    stack.fittingSize.height,
                    accuracy: 1,
                    "vertical stack should stay at its content height: \(stack.identifier?.rawValue ?? String(describing: type(of: stack)))",
                    file: file,
                    line: line
                )
            }
            for child in view.subviews {
                assertVerticalStacksFit(child, file: file, line: line)
            }
        }

        assertVerticalStacksFit(controller.generalPaneForTesting.leftColumnForTesting)
        try select("github", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        assertVerticalStacksFit(controller.githubPaneForTesting.leftColumnForTesting)
        try select("slack", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        assertVerticalStacksFit(controller.slackPaneForTesting.leftColumnForTesting)
    }

    func testPreviewWindowsUseEqualOuterMarginsAcrossAllThreePanes() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for pane in ["general", "github", "slack"] {
            try select(pane, in: window)
            _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            let preview = switch pane {
            case "general": controller.generalPaneForTesting.previewView
            case "github": controller.githubPaneForTesting.previewView
            default: controller.slackPaneForTesting.previewView
            }
            let frame = preview.previewWindowFrameForTesting
            XCTAssertEqual(frame.minX, 13, accuracy: 0.5, pane)
            XCTAssertEqual(frame.minY, 13, accuracy: 0.5, pane)
            XCTAssertEqual(preview.bounds.maxX - frame.maxX, 13, accuracy: 0.5, pane)
            XCTAssertEqual(preview.bounds.maxY - frame.maxY, 13, accuracy: 0.5, pane)
        }
    }

    func testSlackRequestFailureStaysVisibleAtTheTopOfAShortDocument() throws {
        let controller = makeController(.warp)
        let window = try XCTUnwrap(controller.window)
        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let needed = controller.rootStack.fittingSize.height
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: needed / 3)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        controller.presentSlackThreadRequestFailure(SlackThreadRequestError.invalidSlackLink)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let failure = try XCTUnwrap(controller.sharedPanelForTesting.problemBlockViews.first {
            if case .slackThreadRequestFailed = $0.problem.copy { return true }
            return false
        })
        let frame = failure.convert(failure.bounds, to: try XCTUnwrap(scroll.documentView))
        XCTAssertGreaterThan(NSIntersectionRect(frame, scroll.documentVisibleRect).height, 0)
        XCTAssertEqual(controller.selectedPaneForTesting, "slack")
    }

    func testLanguageRebuildChangesToolbarAndAllThreePaneSentences() throws {
        let controller = makeController(.iterm)
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let beforeToolbar = window.toolbar?.items.map(\.label)
        let beforeGeneral = controller.generalPaneForTesting.requestStatusTextForTesting
        let beforeGitHub = controller.githubPaneForTesting.previewCaptionForTesting
        let beforeSlack = controller.slackPaneForTesting.previewCaptionLabel.stringValue
        XCTAssertEqual(beforeGeneral, localized("app.setup.general.request.waiting"))
        XCTAssertEqual(beforeGitHub, localized("app.setup.github.effect.nonCmux"))
        XCTAssertEqual(beforeSlack, localized("app.setup.preview.slack.caption"))

        AppLocalization.tagOverrideForTesting = "ja"
        controller.rebuildForLanguageChange()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertNotEqual(window.toolbar?.items.map(\.label), beforeToolbar)
        XCTAssertNotEqual(controller.generalPaneForTesting.requestStatusTextForTesting, beforeGeneral)
        XCTAssertNotEqual(controller.githubPaneForTesting.previewCaptionForTesting, beforeGitHub)
        XCTAssertNotEqual(controller.slackPaneForTesting.previewCaptionLabel.stringValue, beforeSlack)
        XCTAssertEqual(
            controller.slackPaneForTesting.previewCaptionLabel.stringValue,
            localized("app.setup.preview.slack.caption")
        )
    }
}

private func loadCatalogue(_ tag: String) throws -> [String: String] {
    let path = (SetupWindowLayoutTests.sourceResources as NSString)
        .appendingPathComponent("\(tag).lproj/Localizable.strings")
    let parsed = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil
    ) as? [String: String]
    return try XCTUnwrap(parsed, "\(tag) catalogue did not parse")
}

final class ClaudeWrapperAdviceTests: XCTestCase {
    func testAdviceAppearsOnlyForAReachableClaudeThatIsNotAnExecutable() {
        func showsWarning(available: Bool?, executable: Bool?) -> Bool {
            let tools: SetupWindowToolResults?
            if let available {
                tools = SetupWindowToolResults(
                    available: ["claude": available],
                    executable: ["claude": executable ?? false]
                )
            } else {
                tools = nil
            }
            return SetupWindowPresentationModel.make(from: SetupWindowSnapshot(tools: tools)).problems.contains {
                $0.copy == .claudeNotExecutable
            }
        }
        XCTAssertTrue(showsWarning(available: true, executable: false))
        XCTAssertFalse(showsWarning(available: true, executable: true))
        XCTAssertFalse(showsWarning(available: false, executable: false))
        XCTAssertFalse(showsWarning(available: nil, executable: nil))
    }
}

final class WarpAccessibilityHelpTextTests: XCTestCase {
    private var savedResources: String?
    private var savedTag: String?

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        savedTag = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
    }

    override func tearDown() {
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTag
        super.tearDown()
    }

    func testTheSharedProblemSaysTheAppRejectsTheRequestRatherThanPartlyRunningIt() throws {
        let refusal = [
            "en": "rejects", "ko": "거절", "ja": "拒否", "zh-Hans": "拒绝", "zh-Hant": "拒絕",
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let title = try XCTUnwrap(try loadCatalogue(tag)["app.setup.problem.warpAccessibilityRequired.title"], tag)
            XCTAssertTrue(title.contains(try XCTUnwrap(refusal[tag])), "\(tag): \(title)")
        }
    }

    func testNoWindowTextStillPromisesTheCommandRunsWithoutThePermission() throws {
        let promises = [
            "en": ["the command still runs", "command still runs", "only the claude input"],
            "ko": ["명령은 실행되지만", "명령은 실행되고", "그대로 실행되지만"],
            "ja": ["コマンドは実行され", "コマンドだけは実行", "コマンドは動きます"],
            "zh-Hans": ["命令仍会运行", "命令仍然运行", "命令还是会运行"],
            "zh-Hant": ["指令仍會執行", "指令仍然執行", "指令還是會執行"],
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let values = try loadCatalogue(tag)
            XCTAssertFalse(values.isEmpty, "\(tag) catalogue is empty")
            for promise in try XCTUnwrap(promises[tag]) {
                for (key, value) in values {
                    XCTAssertFalse(value.contains(promise), "\(tag) \(key): \(promise)")
                }
            }
        }
    }

    func testNoValueSpellsOutAButtonLabelInsteadOfReceivingIt() throws {
        let labelKeys = [
            "app.button.chooseFolder", "app.button.installInChrome", "app.button.requestAccessibility",
            "app.button.requestItermPermission", "app.button.restartNow", "app.button.showSetupGuide",
            "app.setup.action.chromeInstall", "app.setup.action.dismissSetupGuide",
            "app.setup.action.openAccessibilitySettings", "app.setup.action.openAutomationSettings",
            "app.setup.action.openBaseDirectorySettings", "app.setup.action.openCmuxConfig",
            "app.setup.action.openSlackSettings", "app.setup.action.openTerminalSettings",
            "app.setup.action.refreshCmuxStatus", "app.setup.action.registerManifest",
            "app.setup.action.showAppInstallHelp", "app.setup.action.showClaudeInstallHelp",
            "app.setup.action.showGhInstallHelp", "app.setup.action.showZoxideInstallHelp",
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let values = try loadCatalogue(tag)
            for labelKey in labelKeys {
                let label = try XCTUnwrap(values[labelKey], "\(tag) \(labelKey)")
                for (key, value) in values where key != labelKey {
                    XCTAssertFalse(
                        value.localizedCaseInsensitiveContains(label),
                        "\(tag) \(key) spells out \(labelKey) instead of taking it as %@"
                    )
                }
            }
        }
    }

    func testNoCatalogueValueCarriesMarkupThatDoesNotRender() throws {
        for tag in SetupWindowLayoutTests.populatedLocales {
            for (key, value) in try loadCatalogue(tag) {
                XCTAssertFalse(value.contains("**"), "\(tag) \(key) carries bold markup")
                XCTAssertFalse(value.contains("`"), "\(tag) \(key) carries code markup")
            }
        }
    }
}
