import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowGeneralCompressionTests: XCTestCase {
    private struct TerminalStateCase {
        let terminal: Terminal
        let automation: AutomationStatus
        let cmux: CmuxSocketStatus
        let accessibilityGranted: Bool
        let expectedKey: StaticString
        let isInstalled: Bool

        init(
            terminal: Terminal,
            automation: AutomationStatus,
            cmux: CmuxSocketStatus,
            accessibilityGranted: Bool,
            expectedKey: StaticString,
            isInstalled: Bool = true
        ) {
            self.terminal = terminal
            self.automation = automation
            self.cmux = cmux
            self.accessibilityGranted = accessibilityGranted
            self.expectedKey = expectedKey
            self.isInstalled = isInstalled
        }

        var name: String { "\(terminal)-\(expectedKey)" }
    }

    private let locales = ["en", "ko", "ja", "zh-Hans", "zh-Hant"]
    private var savedResources: String?
    private var savedTagOverride: String?
    private var savedTerminal: Terminal!
    private var savedLastRequestAt: Date?
    private var savedTools: [String: Bool]?
    private var savedExecutables: [String: Bool]?
    private var savedInstallProvider: (Terminal) -> Bool = { _ in true }
    private var savedAutomationProvider: () -> AutomationStatus = { .granted }
    private var savedCmuxProvider: (CmuxChannel) -> CmuxSocketStatus = { _ in .reachable }
    private var savedAccessibilityProvider: () -> Bool = { true }
    private var accessedCmuxChannels: [CmuxChannel] = []

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        savedTagOverride = AppLocalization.tagOverrideForTesting
        savedTerminal = Settings.terminal
        savedLastRequestAt = Settings.lastRequestAt
        savedTools = Settings.toolAvailability
        savedExecutables = Settings.toolExecutables
        savedInstallProvider = PermissionChecker.terminalInstallationStatusProvider
        savedAutomationProvider = PermissionChecker.iTermAutomationStatusProvider
        savedCmuxProvider = PermissionChecker.cmuxSocketStatusProvider
        savedAccessibilityProvider = PermissionChecker.accessibilityStatusProvider
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        Settings.lastRequestAt = Date(timeIntervalSince1970: 1_791_000_000)
        Settings.toolAvailability = ["zoxide": true, "gh": true, "claude": true]
        Settings.toolExecutables = ["zoxide": true, "gh": true, "claude": true]
        PermissionChecker.terminalInstallationStatusProvider = { _ in true }
    }

    override func tearDown() {
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTagOverride
        Settings.terminal = savedTerminal
        Settings.lastRequestAt = savedLastRequestAt
        Settings.toolAvailability = savedTools
        Settings.toolExecutables = savedExecutables
        PermissionChecker.terminalInstallationStatusProvider = savedInstallProvider
        PermissionChecker.iTermAutomationStatusProvider = savedAutomationProvider
        PermissionChecker.cmuxSocketStatusProvider = savedCmuxProvider
        PermissionChecker.accessibilityStatusProvider = savedAccessibilityProvider
        super.tearDown()
    }

    func testNoVisibleControlIsCompressedAcrossLocalesPanesAndTerminalStates() throws {
        for tag in locales {
            AppLocalization.tagOverrideForTesting = tag
            apply(terminalStates[0])
            let controller = makeController(terminalStates[0].terminal)
            let window = try XCTUnwrap(controller.window)
            window.makeKeyAndOrderFront(nil)
            _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            for terminalState in terminalStates {
                apply(terminalState)
                controller.selectTerminalForTesting(terminalState.terminal)
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                if let selectedChannel = terminalState.terminal.cmuxChannel {
                    XCTAssertFalse(accessedCmuxChannels.isEmpty, "\(tag)/\(terminalState.name) skipped its selected channel")
                    XCTAssertTrue(
                        accessedCmuxChannels.allSatisfy { $0 == selectedChannel },
                        "\(tag)/\(terminalState.name) queried an unselected cmux channel"
                    )
                } else {
                    XCTAssertTrue(accessedCmuxChannels.isEmpty, "\(tag)/\(terminalState.name) queried cmux while another terminal was selected")
                }
                XCTAssertEqual(
                    controller.generalPaneForTesting.terminalStatusTextForTesting,
                    localized(terminalState.expectedKey),
                    "\(tag)/\(terminalState.name)"
                )

                for pane in ["general", "github", "slack"] {
                    try select(pane, in: window)
                    _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                    let contentView = try XCTUnwrap(window.contentView)
                    let issues = compressedControls(in: contentView)
                    XCTAssertTrue(
                        issues.isEmpty,
                        "\(tag)/\(terminalState.name)/\(pane): \(issues)"
                    )
                }
            }
        }
    }

    func testConnectionPopoverKeepsItsWidthAndFitsEveryLocaleAndTerminalState() throws {
        for tag in locales {
            AppLocalization.tagOverrideForTesting = tag
            apply(terminalStates[0])
            let controller = makeController(terminalStates[0].terminal)
            let window = try XCTUnwrap(controller.window)
            window.makeKeyAndOrderFront(nil)
            _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
            for terminalState in terminalStates {
                apply(terminalState)
                controller.selectTerminalForTesting(terminalState.terminal)
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                try select("general", in: window)
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
                let pane = controller.generalPaneForTesting
                let button = pane.connectionDetailsButton
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(button.action), to: button.target, from: button))
                _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

                let popover = pane.connectionDetailsPopover
                let root = try XCTUnwrap(popover.contentViewController?.view)
                XCTAssertTrue(popover.isShown, "\(tag)/\(terminalState.name) did not show the popover")
                XCTAssertEqual(popover.contentSize.width, 356, accuracy: 0.5)
                XCTAssertEqual(root.bounds.width, 356, accuracy: 0.5)
                XCTAssertTrue(
                    overflowingSubviews(in: root).isEmpty,
                    "\(tag)/\(terminalState.name): \(overflowingSubviews(in: root))"
                )
                XCTAssertTrue(
                    compressedControls(in: root).isEmpty,
                    "\(tag)/\(terminalState.name): \(compressedControls(in: root))"
                )
                for label in wrappedLabels(in: root) {
                    guard let requiredHeight = SetupWindowTestSupport.wrappedTextHeight(label) else {
                        XCTFail("missing wrapped label cell: \(label.stringValue)")
                        continue
                    }
                    XCTAssertGreaterThanOrEqual(
                        label.frame.height + 0.75,
                        requiredHeight,
                        "\(tag)/\(terminalState.name) clipped `\(label.stringValue)`"
                    )
                }
                for frame in pane.statusDotFramesForTesting {
                    XCTAssertEqual(frame.width, 8, accuracy: 0.5)
                    XCTAssertEqual(frame.height, 8, accuracy: 0.5)
                }
                XCTAssertTrue(pane.statusDotsAreAccessibilityElementsForTesting.allSatisfy { !$0 })
                popover.performClose(nil)
            }
        }
    }

    private var terminalStates: [TerminalStateCase] {
        [
            .init(terminal: .iterm, automation: .granted, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.iterm.automationAllowed"),
            .init(terminal: .iterm, automation: .denied, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.iterm.permissionDenied"),
            .init(terminal: .iterm, automation: .notDetermined, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.iterm.permissionNeeded"),
            .init(terminal: .iterm, automation: .targetNotRunning, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.iterm.cannotCheck"),
            .init(terminal: .iterm, automation: .unknown(-1), cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.iterm.checkFailed"),
            .init(terminal: .iterm, automation: .granted, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.terminalNotInstalled", isInstalled: false),
            .init(terminal: .cmux, automation: .granted, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.reachable"),
            .init(terminal: .cmuxNightly, automation: .granted, cmux: .denied, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.accessDenied"),
            .init(terminal: .cmux, automation: .granted, cmux: .denied, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.accessDenied"),
            .init(terminal: .cmux, automation: .granted, cmux: .notRunning, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.notRunning"),
            .init(terminal: .cmux, automation: .granted, cmux: .notInstalled, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.notInstalled", isInstalled: false),
            .init(terminal: .cmux, automation: .granted, cmux: .failed("test"), accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.cmux.checkFailed"),
            .init(terminal: .warp, automation: .granted, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.warp.accessibilityAllowed"),
            .init(terminal: .warp, automation: .granted, cmux: .reachable, accessibilityGranted: false,
                  expectedKey: "app.setup.general.status.warp.accessibilityMissing"),
            .init(terminal: .wezterm, automation: .granted, cmux: .reachable, accessibilityGranted: true,
                  expectedKey: "app.setup.general.status.wezterm.noPermissionNeeded"),
        ]
    }

    private func apply(_ state: TerminalStateCase) {
        Settings.terminal = state.terminal
        accessedCmuxChannels = []
        PermissionChecker.terminalInstallationStatusProvider = { terminal in
            terminal != state.terminal || state.isInstalled
        }
        PermissionChecker.iTermAutomationStatusProvider = { state.automation }
        PermissionChecker.cmuxSocketStatusProvider = { channel in
            self.accessedCmuxChannels.append(channel)
            guard state.terminal.cmuxChannel == channel else { return .failed("unexpected channel") }
            return state.cmux
        }
        PermissionChecker.accessibilityStatusProvider = { state.accessibilityGranted }
    }

    private func makeController(_ terminal: Terminal) -> SetupWindowController {
        Settings.terminal = terminal
        return SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(),
            loginItem: StubLoginItem(),
            manifestStatusProvider: { .registered },
            extensionFolderStatusProvider: { .present }
        )
    }

    private func select(_ pane: String, in window: NSWindow) throws {
        let item = try XCTUnwrap(window.toolbar?.items.first {
            $0.itemIdentifier.rawValue == "setup.pane.\(pane)"
        })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    private func compressedControls(in view: NSView) -> [String] {
        guard !view.isHiddenOrHasHiddenAncestor else { return [] }
        var issues: [String] = []
        for child in view.subviews where !child.isHiddenOrHasHiddenAncestor {
            if let popup = child as? NSPopUpButton,
               popup.intrinsicContentSize.width > 0,
               popup.frame.width + 0.5 < popup.intrinsicContentSize.width {
                issues.append("popup \(popup.titleOfSelectedItem ?? "") \(popup.frame.width) < \(popup.intrinsicContentSize.width)")
            } else if let segment = child as? NSSegmentedControl,
                      segment.intrinsicContentSize.width > 0,
                      segment.frame.width + 0.5 < segment.intrinsicContentSize.width {
                issues.append("segment \(segment.frame.width) < \(segment.intrinsicContentSize.width)")
            } else if let button = child as? NSButton,
                      !button.title.isEmpty,
                      button.intrinsicContentSize.width > 0,
                      button.frame.width + 0.5 < button.intrinsicContentSize.width {
                issues.append("button \(button.title) \(button.frame.width) < \(button.intrinsicContentSize.width)")
            } else if let label = child as? NSTextField,
                      !label.isEditable,
                      label.cell?.wraps != true,
                      !label.stringValue.isEmpty,
                      label.intrinsicContentSize.width > 0,
                      label.frame.width + 0.5 < label.intrinsicContentSize.width {
                issues.append("label \(label.stringValue) \(label.frame.width) < \(label.intrinsicContentSize.width)")
            }
            issues += compressedControls(in: child)
        }
        return issues
    }

    private func overflowingSubviews(in root: NSView) -> [String] {
        func visit(_ view: NSView) -> [String] {
            guard !view.isHiddenOrHasHiddenAncestor else { return [] }
            var issues: [String] = []
            for child in view.subviews where !child.isHiddenOrHasHiddenAncestor {
                let frame = child.convert(child.bounds, to: root)
                if frame.minX < -0.5 || frame.minY < -0.5
                    || frame.maxX > root.bounds.maxX + 0.5 || frame.maxY > root.bounds.maxY + 0.5 {
                    let text = (child as? NSTextField)?.stringValue ?? (child as? NSButton)?.title
                        ?? String(describing: type(of: child))
                    issues.append("\(text.prefix(40)) \(frame)")
                }
                issues += visit(child)
            }
            return issues
        }
        return visit(root)
    }

    private func wrappedLabels(in view: NSView) -> [NSTextField] {
        guard !view.isHiddenOrHasHiddenAncestor else { return [] }
        var labels: [NSTextField] = []
        if let label = view as? NSTextField, label.cell?.wraps == true, !label.usesSingleLineMode {
            labels.append(label)
        }
        for child in view.subviews {
            labels += wrappedLabels(in: child)
        }
        return labels
    }
}
