import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowRedrawTests: XCTestCase {
    private var savedTerminal: Terminal!
    private var savedBaseDirectory: String!
    private var savedPlacementIdentity: String!
    private var savedPlacementName: String!
    private var savedSlackWorkDirectory: String!
    private var savedSlackInstruction: String!
    private var savedResources: String?
    private var savedTag: String?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedBaseDirectory = Settings.baseDirectory
        savedPlacementIdentity = Settings.cmuxPlacementIdentityMode
        savedPlacementName = Settings.cmuxPlacementFixedName
        savedSlackWorkDirectory = Settings.slackThreadWorkDirectory
        savedSlackInstruction = Settings.slackThreadInstruction
        savedResources = AppLocalization.resourcesPath
        savedTag = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"
        Settings.baseDirectory = "/tmp"
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "stored-workspace"
        Settings.slackThreadWorkDirectory = NSTemporaryDirectory()
        Settings.slackThreadInstruction = "stored instruction"
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        Settings.baseDirectory = savedBaseDirectory
        Settings.cmuxPlacementIdentityMode = savedPlacementIdentity
        Settings.cmuxPlacementFixedName = savedPlacementName
        Settings.slackThreadWorkDirectory = savedSlackWorkDirectory
        Settings.slackThreadInstruction = savedSlackInstruction
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTag
        super.tearDown()
    }

    private func makeController() -> SetupWindowController {
        SetupWindowController(slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem())
    }

    private func select(_ pane: String, in window: NSWindow) throws {
        let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "setup.pane.\(pane)" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    func testOrdinaryRefreshUpdatesTheSamePaneControlsAndKeepsDrafts() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        try select("github", in: window)
        try select("slack", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        try select("github", in: window)

        let githubField = controller.githubPaneForTesting.baseDirectoryField
        let nameField = controller.githubPaneForTesting.workspaceNameField
        let slackWorkField = controller.slackPaneForTesting.workDirectoryField
        let slackInstruction = controller.slackPaneForTesting.instructionField
        githubField.stringValue = "~/draft path"
        nameField.stringValue = "draft-workspace"
        slackWorkField.stringValue = "/draft/work"
        slackInstruction.stringValue = "draft instruction"

        controller.refreshForTesting()

        XCTAssertTrue(githubField === controller.githubPaneForTesting.baseDirectoryField)
        XCTAssertTrue(nameField === controller.githubPaneForTesting.workspaceNameField)
        XCTAssertTrue(slackWorkField === controller.slackPaneForTesting.workDirectoryField)
        XCTAssertTrue(slackInstruction === controller.slackPaneForTesting.instructionField)
        XCTAssertEqual(githubField.stringValue, "~/draft path")
        XCTAssertEqual(nameField.stringValue, "draft-workspace")
        XCTAssertEqual(slackWorkField.stringValue, "/draft/work")
        XCTAssertEqual(slackInstruction.stringValue, "draft instruction")
    }

    func testLanguageRebuildKeepsTheSelectedPaneAndAllFourDrafts() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        try select("github", in: window)
        let oldGeneral = controller.generalPaneForTesting
        let oldGitHub = controller.githubPaneForTesting
        let oldSlack = controller.slackPaneForTesting
        controller.githubPaneForTesting.baseDirectoryField.stringValue = "~/draft path"
        controller.githubPaneForTesting.workspaceNameField.stringValue = "draft-workspace"
        controller.slackPaneForTesting.workDirectoryField.stringValue = "/draft/work"
        controller.slackPaneForTesting.instructionField.stringValue = "draft instruction"
        AppLocalization.tagOverrideForTesting = "ja"

        controller.rebuildForLanguageChange()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertFalse(oldGeneral === controller.generalPaneForTesting)
        XCTAssertFalse(oldGitHub === controller.githubPaneForTesting)
        XCTAssertFalse(oldSlack === controller.slackPaneForTesting)
        XCTAssertEqual(controller.selectedPaneForTesting, "github")
        XCTAssertEqual(window.toolbar?.selectedItemIdentifier?.rawValue, "setup.pane.github")
        XCTAssertEqual(controller.githubPaneForTesting.baseDirectoryField.stringValue, "~/draft path")
        XCTAssertEqual(controller.githubPaneForTesting.workspaceNameField.stringValue, "draft-workspace")
        XCTAssertEqual(controller.slackPaneForTesting.workDirectoryField.stringValue, "/draft/work")
        XCTAssertEqual(controller.slackPaneForTesting.instructionField.stringValue, "draft instruction")
    }

    func testLanguageRebuildRestoresFocusedRoleAndUTF16Selection() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        try select("github", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let field = controller.githubPaneForTesting.baseDirectoryField
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        editor.string = "folder/😀name"
        editor.selectedRange = NSRange(location: 10, length: 2)
        AppLocalization.tagOverrideForTesting = "ko"

        controller.rebuildForLanguageChange()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let restored = controller.githubPaneForTesting.baseDirectoryField
        XCTAssertFalse(field === restored)
        XCTAssertEqual(restored.identifier, setupWindowControlRole(try XCTUnwrap(restored.action)))
        XCTAssertEqual(window.toolbar?.items.map(\.label), [
            localized("app.setup.toolbar.general"), localized("app.setup.toolbar.github"),
            localized("app.setup.toolbar.slack"),
        ])
        XCTAssertEqual(window.toolbar?.selectedItemIdentifier?.rawValue, "setup.pane.github")
        XCTAssertTrue(window.firstResponder === restored.currentEditor())
        XCTAssertEqual(restored.currentEditor()?.selectedRange, NSRange(location: 10, length: 2))
    }

    func testLanguageRebuildDoesNotRecenterAWindowAfterItsFirstMeasuredPlacement() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        window.setFrameOrigin(NSPoint(x: 180, y: 190))
        let origin = window.frame.origin
        AppLocalization.tagOverrideForTesting = "zh-Hant"

        controller.rebuildForLanguageChange()
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(window.frame.origin, origin)
    }

    func testAllPaneControlsKeepRolesDerivedFromTheirActions() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let general = controller.generalPaneForTesting
        let generalControls: [NSControl] = [
            general.connectionDetailsButton,
            general.terminalPopup, general.activationSegment, general.terminalTestButton,
            general.languagePopup, general.languageRestartButton, general.optionsButton, general.guideButton,
        ]
        for control in generalControls {
            XCTAssertEqual(control.identifier, setupWindowControlRole(try XCTUnwrap(control.action)))
        }
        for (control, _) in controller.githubPaneForTesting.actionControlsForTesting {
            XCTAssertEqual(control.identifier, setupWindowControlRole(try XCTUnwrap(control.action)))
        }
        for (control, _, qualifier) in controller.slackPaneForTesting.actionControlsForTesting {
            XCTAssertEqual(
                control.identifier,
                setupWindowControlRole(try XCTUnwrap(control.action), qualifier)
            )
        }
        XCTAssertNotEqual(
            controller.slackPaneForTesting.workDirectoryField.identifier,
            controller.slackPaneForTesting.instructionField.identifier
        )
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
    }

    func testTheRelativeFormatterIsKeyedByLanguage() {
        let english = SetupWindowController.relativeFormatter(for: "en")
        let japanese = SetupWindowController.relativeFormatter(for: "ja")
        XCTAssertFalse(english === japanese)
        XCTAssertTrue(japanese === SetupWindowController.relativeFormatter(for: "ja"))
    }
}
