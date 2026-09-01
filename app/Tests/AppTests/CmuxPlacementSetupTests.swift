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
            controller.select(terminal: terminal)
            SetupWindowTestSupport.settle(window)
            XCTAssertTrue(
                controller.refillableSectionsForTesting[1].isHidden,
                "placement controls were visible for \(terminal)"
            )
        }
        for terminal in [Terminal.cmux, .cmuxNightly] {
            controller.select(terminal: terminal)
            SetupWindowTestSupport.settle(window)
            XCTAssertFalse(
                controller.refillableSectionsForTesting[1].isHidden,
                "placement controls were hidden for \(terminal)"
            )
            XCTAssertEqual(controller.cmuxPlacementIdentityRadiosForTesting.count, 2)
            XCTAssertEqual(controller.cmuxPlacementArrangementRadiosForTesting.count, 3)
        }
    }

    func testPlacementControlsUseFreshDefaults() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(controller.cmuxPlacementIdentityRadiosForTesting.map(\.state), [.on, .off])
        XCTAssertEqual(
            controller.cmuxPlacementArrangementRadiosForTesting.map(\.state),
            [.on, .off, .off]
        )
        XCTAssertFalse(controller.cmuxPlacementNameFieldForTesting.isEnabled)
        XCTAssertTrue(controller.cmuxPlacementInterpretationLabelForTesting.stringValue.contains("New workspace"))
        XCTAssertTrue(controller.cmuxPlacementInterpretationLabelForTesting.stringValue.contains("Pane per item"))
    }

    func testPlacementRadioChangesSaveImmediately() throws {
        let controller = try makeController(terminal: .cmux)
        let fixedName = controller.cmuxPlacementIdentityRadiosForTesting[1]
        fixedName.performClick(nil)

        XCTAssertEqual(Settings.cmuxPlacementIdentityMode, "fixed-name")
        XCTAssertTrue(controller.cmuxPlacementNameFieldForTesting.isEnabled)

        let tab = controller.cmuxPlacementArrangementRadiosForTesting[1]
        tab.performClick(nil)
        XCTAssertEqual(
            Settings.cmuxPlacementArrangement,
            CmuxPlacementArrangement.tabPerItem.rawValue
        )
    }

    func testPlacementNameUsesBaseDirectoryEditingSaveTiming() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        let fixedName = controller.cmuxPlacementIdentityRadiosForTesting[1]
        fixedName.performClick(nil)

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
            controller.cmuxPlacementInterpretationLabelForTesting.stringValue,
            localized(
                "app.cmux.placement.interpretation",
                localized("app.cmux.placement.identity.alwaysNew"),
                localized("app.cmux.placement.arrangement.tab")
            )
        )
    }

    func testPlacementControlsReachASettledLayout() throws {
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for control in controller.cmuxPlacementIdentityRadiosForTesting
            + controller.cmuxPlacementArrangementRadiosForTesting {
            XCTAssertGreaterThan(control.frame.width, 0)
            XCTAssertGreaterThan(control.frame.height, 0)
        }
        XCTAssertGreaterThan(controller.cmuxPlacementNameFieldForTesting.frame.width, 0)
        XCTAssertGreaterThan(controller.cmuxPlacementInterpretationLabelForTesting.frame.width, 0)
    }

    func testPlacementNameFieldReparentsAndKeepsAnUnstoredDraftAcrossRedraw() throws {
        Settings.cmuxPlacementIdentityMode = "fixed-name"
        Settings.cmuxPlacementFixedName = "stored-group"
        let controller = try makeController(terminal: .cmux)
        let window = try XCTUnwrap(controller.window)
        let field = controller.cmuxPlacementNameFieldForTesting

        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        try XCTUnwrap(field.currentEditor()).string = "draft-group"
        XCTAssertNotEqual(Settings.cmuxPlacementFixedName, "draft-group")

        NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)

        XCTAssertTrue(
            field === controller.cmuxPlacementNameFieldForTesting,
            "the placement field was recreated instead of reparented"
        )
        XCTAssertNotNil(field.window, "the placement field was dropped instead of reparented")
        XCTAssertEqual(field.stringValue, "draft-group")
        XCTAssertNotEqual(Settings.cmuxPlacementFixedName, "draft-group")
    }

    private func makeController(terminal: Terminal) throws -> SetupWindowController {
        Settings.terminal = terminal
        let controller = SetupWindowController()
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
