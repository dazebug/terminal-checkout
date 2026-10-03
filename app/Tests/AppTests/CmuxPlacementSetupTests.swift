import AppKit
import Core
import XCTest
@testable import App

final class CmuxPlacementSettingsTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var savedTerminal: Terminal!
    private var savedValues: [(key: String, value: Any?, wasPresent: Bool)] = []
    private var savedResources: String?
    private var savedTag: String?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedResources = AppLocalization.resourcesPath
        savedTag = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"

        for key in placementKeys {
            let value = defaults.object(forKey: key)
            savedValues.append((key: key, value: value, wasPresent: value != nil))
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        for saved in savedValues {
            if saved.wasPresent {
                defaults.set(saved.value, forKey: saved.key)
            } else {
                defaults.removeObject(forKey: saved.key)
            }
        }
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTag
        super.tearDown()
    }

    func testPlacementSettingsRoundTripRawStrings() {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "group"
        Settings.cmuxPlacementArrangement = "tab"

        XCTAssertEqual(
            defaults.object(forKey: CmuxPlacementStorageKey.identityMode) as? String,
            "fixed-name"
        )
        XCTAssertEqual(
            defaults.object(forKey: CmuxPlacementStorageKey.fixedName) as? String,
            "group"
        )
        XCTAssertEqual(
            defaults.object(forKey: CmuxPlacementStorageKey.arrangement) as? String,
            "tab"
        )
        XCTAssertEqual(Settings.cmuxPlacementIdentityMode, "fixed-name")
        XCTAssertEqual(Settings.cmuxPlacementFixedName, "group")
        XCTAssertEqual(Settings.cmuxPlacementArrangement, "tab")
    }

    func testPlacementSettingsPassNonStringValuesAsText() {
        defaults.set(42, forKey: CmuxPlacementStorageKey.identityMode)
        defaults.set(false, forKey: CmuxPlacementStorageKey.fixedName)
        defaults.set(3.5, forKey: CmuxPlacementStorageKey.arrangement)

        XCTAssertEqual(Settings.cmuxPlacementIdentityMode, "42")
        XCTAssertEqual(Settings.cmuxPlacementFixedName, "0")
        XCTAssertEqual(Settings.cmuxPlacementArrangement, "3.5")
    }

    private var placementKeys: [String] {
        [
            CmuxPlacementStorageKey.identityMode,
            CmuxPlacementStorageKey.fixedName,
            CmuxPlacementStorageKey.arrangement,
        ]
    }
}

final class CmuxPlacementSetupWindowTests: XCTestCase {
    private var savedTerminal: Terminal!
    private var savedValues: [(key: String, value: Any?, wasPresent: Bool)] = []
    private var savedResources: String?
    private var savedTag: String?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedResources = AppLocalization.resourcesPath
        savedTag = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"

        let defaults = UserDefaults.standard
        for key in placementKeys {
            let value = defaults.object(forKey: key)
            savedValues.append((key: key, value: value, wasPresent: value != nil))
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        let defaults = UserDefaults.standard
        for saved in savedValues {
            if saved.wasPresent {
                defaults.set(saved.value, forKey: saved.key)
            } else {
                defaults.removeObject(forKey: saved.key)
            }
        }
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTag
        super.tearDown()
    }

    func testPlacementControlsAppearOnlyForCmuxChannels() throws {
        let controller = try makeController(terminal: .iterm)
        let window = try XCTUnwrap(controller.window)

        for terminal in [Terminal.iterm, .wezterm, .warp] {
            controller.selectTerminalForTesting(terminal)
            SetupWindowTestSupport.settle(window)
            XCTAssertTrue(
                controller.githubPaneForTesting.cmuxSectionIsHiddenForTesting,
                "placement controls were visible for \(terminal)"
            )
        }
        for terminal in [Terminal.cmux, .cmuxNightly] {
            controller.selectTerminalForTesting(terminal)
            SetupWindowTestSupport.settle(window)
            XCTAssertFalse(
                controller.githubPaneForTesting.cmuxSectionIsHiddenForTesting,
                "placement controls were hidden for \(terminal)"
            )
            XCTAssertEqual(controller.githubPaneForTesting.identitySegment.segmentCount, 2)
            XCTAssertEqual(controller.githubPaneForTesting.arrangementSegment.segmentCount, 3)
        }
    }

    func testPlacementControlsUseFreshDefaults() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(controller.githubPaneForTesting.identitySegment.selectedSegment, 0)
        XCTAssertEqual(
            controller.githubPaneForTesting.arrangementSegment.selectedSegment,
            0
        )
        XCTAssertFalse(controller.cmuxPlacementNameFieldForTesting.isEnabled)
        XCTAssertEqual(
            controller.githubPaneForTesting.effectSentenceForTesting,
            localized("app.setup.github.effect.pane.new")
        )
    }

    func testPlacementSegmentsSaveImmediately() throws {
        let controller = try makeController(terminal: .cmux)
        let identity = controller.githubPaneForTesting.identitySegment
        identity.selectedSegment = 1
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(identity.action), to: identity.target, from: identity))

        XCTAssertEqual(Settings.cmuxPlacementIdentityMode, "fixed-name")
        XCTAssertTrue(controller.cmuxPlacementNameFieldForTesting.isEnabled)

        let arrangement = controller.githubPaneForTesting.arrangementSegment
        arrangement.selectedSegment = 1
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrangement.action), to: arrangement.target, from: arrangement))
        XCTAssertEqual(
            Settings.cmuxPlacementArrangement,
            CmuxPlacementArrangement.tabPerItem.rawValue
        )
    }

    func testPlacementNameUsesBaseDirectoryEditingSaveTiming() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        let identity = controller.githubPaneForTesting.identitySegment
        identity.selectedSegment = 1
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(identity.action), to: identity.target, from: identity))

        let field = controller.cmuxPlacementNameFieldForTesting
        XCTAssertTrue(field.cell?.sendsActionOnEndEditing == true)
        field.stringValue = "group"
        let action = try XCTUnwrap(field.action)
        XCTAssertTrue(NSApp.sendAction(action, to: field.target, from: field))
        SetupWindowTestSupport.settle(window)

        XCTAssertEqual(Settings.cmuxPlacementFixedName, "group")
    }

    func testPlacementInterpretationLabelUsesCoreParseResult() throws {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = ""
        Settings.cmuxPlacementArrangement = CmuxPlacementArrangement.tabPerItem.rawValue
        let controller = try makeController(terminal: .cmux)

        let parsed = CmuxPlacementPreset.parse(
            rawIdentityMode: Settings.cmuxPlacementIdentityMode,
            rawFixedName: Settings.cmuxPlacementFixedName,
            rawArrangement: Settings.cmuxPlacementArrangement
        )
        guard case .alwaysNew = parsed.identityMode else {
            return XCTFail("empty fixed name was not parsed as always-new")
        }
        XCTAssertEqual(
            controller.githubPaneForTesting.effectSentenceForTesting,
            localized("app.setup.github.effect.tab.new")
        )
    }

    func testPlacementInterpretationLabelReportsWorkspacePerItemAsAlwaysNew() throws {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "work"
        Settings.cmuxPlacementArrangement = CmuxPlacementArrangement.workspacePerItem.rawValue
        let controller = try makeController(terminal: .cmux)

        // The planner cannot give N workspaces one identity, so it creates them untitled.
        // The label has to say that, or a stored name reads as an address that is never used.
        XCTAssertEqual(
            controller.githubPaneForTesting.effectSentenceForTesting,
            localized("app.setup.github.effect.workspace")
        )
    }

    func testPlacementControlsReachASettledLayout() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for control in [controller.githubPaneForTesting.identitySegment,
                        controller.githubPaneForTesting.arrangementSegment] {
            XCTAssertGreaterThan(control.frame.width, 0)
            XCTAssertGreaterThan(control.frame.height, 0)
        }
        XCTAssertGreaterThan(controller.cmuxPlacementNameFieldForTesting.frame.width, 0)
        XCTAssertGreaterThan(controller.githubPaneForTesting.previewCaptionWidthForTesting, 0)
    }

    func testPlacementNameFieldRebuildKeepsAnUnstoredDraft() throws {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "stored-group"
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        let field = controller.cmuxPlacementNameFieldForTesting

        XCTAssertTrue(window.makeFirstResponder(field))
        try XCTUnwrap(field.currentEditor()).string = "draft-group"
        XCTAssertNotEqual(Settings.cmuxPlacementFixedName, "draft-group")

        NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let rebuiltField = controller.cmuxPlacementNameFieldForTesting

        XCTAssertFalse(field === rebuiltField, "language change did not rebuild the pane")
        XCTAssertNotNil(rebuiltField.window, "the rebuilt placement field is not in the window")
        XCTAssertEqual(rebuiltField.stringValue, "draft-group")
        XCTAssertNotEqual(Settings.cmuxPlacementFixedName, "draft-group")
    }

    /// macOS 15 ended the replaced field's editing after the rebuild had returned and sent its
    /// action then, which stored the draft the rebuild only carried over. Sending the old field's
    /// action after the rebuild stands in for that late end of editing on any macOS version.
    func testAReplacedFieldCannotStoreTheDraftAfterTheRebuild() throws {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "stored-group"
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        let field = controller.cmuxPlacementNameFieldForTesting
        XCTAssertTrue(window.makeFirstResponder(field))
        try XCTUnwrap(field.currentEditor()).string = "draft-group"

        NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertFalse(field === controller.cmuxPlacementNameFieldForTesting, "language change did not rebuild the pane")

        field.sendAction(field.action, to: field.target)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertEqual(Settings.cmuxPlacementFixedName, "stored-group")
        XCTAssertEqual(controller.cmuxPlacementNameFieldForTesting.stringValue, "draft-group")
    }

    private func makeController(terminal: Terminal) throws -> SetupWindowController {
        Settings.terminal = terminal
        let controller = SetupWindowTestSupport.onRoomyScreen(SetupWindowController(
            slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem()
        ))
        _ = try XCTUnwrap(controller.window)
        return controller
    }

    private var placementKeys: [String] {
        [
            CmuxPlacementStorageKey.identityMode,
            CmuxPlacementStorageKey.fixedName,
            CmuxPlacementStorageKey.arrangement,
        ]
    }
}
