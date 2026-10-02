import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowSlackPaneTests: XCTestCase {
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

    func testRefreshKeepsBothFieldDraftsAndTheSameControls() throws {
        let fixture = makePane(state: makeState(workDirectory: "/saved/work", instruction: "saved instruction"))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let identities = fixture.pane.actionControlsForTesting.map { ObjectIdentifier($0.0) }
        let previewIdentity = ObjectIdentifier(fixture.pane.previewView)

        fixture.pane.workDirectoryField.stringValue = "~/draft work folder"
        fixture.pane.instructionField.stringValue = "draft instruction"
        fixture.pane.update(makeState(workDirectory: "/saved/work", instruction: "saved instruction"))

        XCTAssertEqual(fixture.pane.workDirectoryField.stringValue, "~/draft work folder")
        XCTAssertEqual(fixture.pane.instructionField.stringValue, "draft instruction")
        XCTAssertEqual(fixture.pane.actionControlsForTesting.map { ObjectIdentifier($0.0) }, identities)
        XCTAssertEqual(ObjectIdentifier(fixture.pane.previewView), previewIdentity)
    }

    func testValidationMessageAppearsOnlyForUnusableSettings() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertTrue(fixture.pane.workDirectoryValidationIsHiddenForTesting)
        XCTAssertTrue(fixture.pane.instructionValidationIsHiddenForTesting)

        fixture.pane.update(makeState(validationNotice: .workDirectory(
            localized("app.slack.error.workDirectoryUnavailable")
        )))
        XCTAssertFalse(fixture.pane.workDirectoryValidationIsHiddenForTesting)
        XCTAssertTrue(fixture.pane.instructionValidationIsHiddenForTesting)

        fixture.pane.update(makeState(validationNotice: .instruction(
            localized("app.slack.error.invalidInstruction")
        )))
        XCTAssertTrue(fixture.pane.workDirectoryValidationIsHiddenForTesting)
        XCTAssertFalse(fixture.pane.instructionValidationIsHiddenForTesting)
        XCTAssertEqual(
            fixture.pane.instructionValidationLabel.stringValue,
            localized("app.slack.error.invalidInstruction")
        )

        fixture.pane.update(makeState())
        XCTAssertTrue(fixture.pane.workDirectoryValidationIsHiddenForTesting)
        XCTAssertTrue(fixture.pane.instructionValidationIsHiddenForTesting)
    }

    func testHotKeyTitleAndClearButtonFollowTheRecordingAndSavedChoice() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(fixture.pane.hotKeyButton.title, localized("app.slack.hotKey.set"))
        XCTAssertTrue(fixture.pane.clearHotKeyButton.isHidden)

        fixture.pane.update(makeState(isRecording: true))
        XCTAssertEqual(fixture.pane.hotKeyButton.title, localized("app.slack.hotKey.recording"))
        XCTAssertTrue(fixture.pane.clearHotKeyButton.isHidden)

        fixture.pane.update(makeState(hotKeyDisplayString: "⌃⌘C"))
        XCTAssertEqual(fixture.pane.hotKeyButton.title, "⌃⌘C")
        XCTAssertFalse(fixture.pane.clearHotKeyButton.isHidden)
    }

    func testModifierWarningAndRegistrationFailureUseTheExistingSlackMessages() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        fixture.pane.update(makeState(isRecording: true, needsModifierWarning: true))
        XCTAssertFalse(fixture.pane.hotKeyStatusIsHiddenForTesting)
        XCTAssertEqual(
            fixture.pane.hotKeyStatusTextForTesting,
            localized("app.slack.hotKey.needsModifier")
        )

        fixture.pane.update(makeState(registrationFailureStatus: -9878))
        XCTAssertFalse(fixture.pane.hotKeyStatusIsHiddenForTesting)
        XCTAssertEqual(
            fixture.pane.hotKeyStatusTextForTesting,
            localized("app.slack.hotKey.registerFailed", -9878)
        )
    }

    func testLoginItemCheckboxAndStatusReflectTheServiceState() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertEqual(fixture.pane.loginItemCheckbox.state, .off)
        XCTAssertTrue(fixture.pane.loginItemStatusIsHiddenForTesting)

        fixture.pane.update(makeState(loginItemStatus: .requiresApproval))
        XCTAssertEqual(fixture.pane.loginItemCheckbox.state, .on)
        XCTAssertFalse(fixture.pane.loginItemStatusIsHiddenForTesting)
        XCTAssertEqual(
            fixture.pane.loginItemStatusTextForTesting,
            localized("app.slack.loginItem.requiresApproval")
        )

        fixture.pane.update(makeState(loginItemStatus: .enabled, loginItemFailureMessage: "system refusal"))
        XCTAssertEqual(fixture.pane.loginItemCheckbox.state, .on)
        XCTAssertEqual(fixture.pane.loginItemStatusTextForTesting, "system refusal")
    }

    func testPreviewTitleUsesTheCombinationAndAccessibilityTracksItsDestination() throws {
        let fixture = makePane(state: makeState(terminal: .iterm))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let display = "⌃⌘C"
        fixture.pane.update(makeState(terminal: .iterm, hotKeyDisplayString: display))
        XCTAssertEqual(
            fixture.pane.previewTitleForTesting,
            localized("app.setup.preview.slack.title.withHotKey", display)
        )
        XCTAssertEqual(
            fixture.pane.previewView.effectDescription,
            localized(
                "app.setup.preview.slack.accessibility",
                localized("app.setup.preview.general.destination.tab")
            )
        )

        fixture.pane.update(makeState(terminal: .cmux))
        XCTAssertEqual(
            fixture.pane.previewView.effectDescription,
            localized(
                "app.setup.preview.slack.accessibility",
                localized("app.setup.preview.general.destination.workspace")
            )
        )
        fixture.pane.update(makeState(terminal: .iterm))
        XCTAssertEqual(
            fixture.pane.previewTitleForTesting,
            localized("app.setup.preview.slack.title.withoutHotKey")
        )
    }

    func testActionControlsUseTheirExistingSelectorsAndActionDerivedRoles() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for (control, action, qualifier) in fixture.pane.actionControlsForTesting {
            let selector = try XCTUnwrap(fixture.selectors[action])
            XCTAssertEqual(control.action, selector)
            XCTAssertEqual(control.identifier, setupWindowSlackPaneRole(selector, qualifier))
        }
        XCTAssertEqual(
            fixture.pane.workDirectoryField.identifier,
            setupWindowSlackPaneRole(try XCTUnwrap(fixture.selectors[.slackThreadSettingsEdited]), "workDirectory")
        )
        XCTAssertEqual(
            fixture.pane.instructionField.identifier,
            setupWindowSlackPaneRole(try XCTUnwrap(fixture.selectors[.slackThreadSettingsEdited]), "instruction")
        )
    }

    private func makePane(state: SetupWindowSlackPaneState) -> (
        pane: SetupWindowSlackPane,
        target: SlackPaneActionTarget,
        selectors: [SetupWindowSlackAction: Selector]
    ) {
        let target = SlackPaneActionTarget()
        let selectors: [SetupWindowSlackAction: Selector] = [
            .slackThreadSettingsEdited: #selector(SlackPaneActionTarget.slackThreadSettingsEdited),
            .chooseSlackWorkDirectory: #selector(SlackPaneActionTarget.chooseSlackWorkDirectory),
            .recordSlackHotKey: #selector(SlackPaneActionTarget.recordSlackHotKey),
            .clearSlackHotKey: #selector(SlackPaneActionTarget.clearSlackHotKey),
            .slackLoginItemToggled: #selector(SlackPaneActionTarget.slackLoginItemToggled),
        ]
        return (SetupWindowSlackPane(state: state, target: target, selectors: selectors), target, selectors)
    }

    private func makeState(
        terminal: Terminal = .iterm,
        workDirectory: String = "",
        instruction: String = "",
        validationNotice: SetupWindowSlackValidationNotice? = nil,
        hotKeyDisplayString: String? = nil,
        isRecording: Bool = false,
        needsModifierWarning: Bool = false,
        registrationFailureStatus: Int32? = nil,
        loginItemStatus: LoginItemStatus = .disabled,
        loginItemFailureMessage: String? = nil
    ) -> SetupWindowSlackPaneState {
        let presentation = SetupWindowPresentationModel.make(
            from: SetupWindowSnapshot(selectedTerminal: terminal)
        )
        return SetupWindowSlackPaneState(
            presentation: presentation,
            storedWorkDirectory: workDirectory,
            storedInstruction: instruction,
            validationNotice: validationNotice,
            hotKeyDisplayString: hotKeyDisplayString,
            isRecordingHotKey: isRecording,
            needsModifierWarning: needsModifierWarning,
            registrationFailureStatus: registrationFailureStatus,
            loginItemStatus: loginItemStatus,
            loginItemFailureMessage: loginItemFailureMessage
        )
    }

    private func makeWindow(for pane: SetupWindowSlackPane) -> NSWindow {
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
        Self.retainedWindows.append(window)
        return window
    }
}

private final class SlackPaneActionTarget: NSObject {
    @objc func slackThreadSettingsEdited() {}
    @objc func chooseSlackWorkDirectory() {}
    @objc func recordSlackHotKey() {}
    @objc func clearSlackHotKey() {}
    @objc func slackLoginItemToggled() {}
}
