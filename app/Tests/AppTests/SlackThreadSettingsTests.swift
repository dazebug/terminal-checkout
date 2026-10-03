import AppKit
import Carbon.HIToolbox
import Core
import Foundation
import TestSupport
import XCTest
@testable import App

final class SlackThreadSettingsTests: XCTestCase {
    private var savedResources: String?

    private static var sourceResources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = Self.sourceResources
    }

    override func tearDown() {
        AppLocalization.tagOverrideForTesting = nil
        AppLocalization.resourcesPath = savedResources
        super.tearDown()
    }

    func testSlackSettingsAreStoredAsRawAppLocalStrings() {
        let defaults = UserDefaults.standard
        let workKey = "slackThreadWorkDirectory"
        let instructionKey = "slackThreadInstruction"
        let oldWork = defaults.object(forKey: workKey)
        let oldInstruction = defaults.object(forKey: instructionKey)
        defer {
            if let oldWork { defaults.set(oldWork, forKey: workKey) } else { defaults.removeObject(forKey: workKey) }
            if let oldInstruction { defaults.set(oldInstruction, forKey: instructionKey) } else { defaults.removeObject(forKey: instructionKey) }
        }

        defaults.removeObject(forKey: workKey)
        defaults.removeObject(forKey: instructionKey)
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "")
        XCTAssertEqual(Settings.slackThreadInstruction, "")

        Settings.slackThreadWorkDirectory = "~/work folder"
        Settings.slackThreadInstruction = "  keep the user's wording  "
        XCTAssertEqual(defaults.object(forKey: workKey) as? String, "~/work folder")
        XCTAssertEqual(defaults.object(forKey: instructionKey) as? String, "  keep the user's wording  ")
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "~/work folder")
        XCTAssertEqual(Settings.slackThreadInstruction, "  keep the user's wording  ")
    }

    func testControllerAndHotKeyRequestUseTheSameCoreValidator() throws {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let coreSource = try auditSource(
            appRoot.appendingPathComponent("Sources/Core/SlackThreadRequest.swift").path,
            claim: .sourceStructure
        ).text
        let windowSource = try auditSource(
            appRoot.appendingPathComponent("Sources/App/SetupWindowController.swift").path,
            claim: .sourceStructure
        ).text
        let requestBody = try XCTUnwrap(segment(
            in: coreSource,
            from: "public func resolveSlackThreadRequest(",
            to: "\n/// Uses the existing request planner"
        ))
        let validationBody = try XCTUnwrap(segment(
            in: windowSource,
            from: "private func slackValidationNotice(",
            to: "\n    private func baseDirectoryProblem("
        ))

        XCTAssertTrue(requestBody.contains("validateSlackThreadSettings("))
        XCTAssertEqual(validationBody.components(separatedBy: "validateSlackThreadSettings(").count - 1, 1)
        XCTAssertFalse(validationBody.contains("normalizedBaseDirectory("))
    }

    func testEverySlackThreadFailureHasLocalizedMessagesInEveryLocale() {
        let underlying = CommandError.invalidBaseDirectory(.notAbsolute, "synthetic")
        let requestErrors: [SlackThreadRequestError] = [
            .clipboardEmpty,
            .invalidSlackLink,
            .slackLinkTooLong,
            .workDirectoryNotConfigured,
            .invalidWorkDirectory(underlying: underlying),
            .invalidWorkDirectory(underlying: CommandError.invalidBaseDirectory(.invalidCharacters, "synthetic")),
            .invalidWorkDirectory(underlying: CommandError.badRequest("synthetic")),
            .workDirectoryUnavailable,
            .invalidInstruction,
            .appendedPromptUnavailable,
        ]
        let refusal = NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "synthetic refusal"])

        for tag in supportedLocales {
            AppLocalization.tagOverrideForTesting = tag
            var messages = requestErrors.map { ("\($0)", slackThreadRequestErrorMessage($0)) }
            messages.append(("server unavailable", slackThreadRequestErrorMessage(SlackThreadHotKeyError.serverUnavailable)))
            messages.append(("login item approval", slackLoginItemStatusMessage(.requiresApproval)))
            messages.append(("login item refused", slackLoginItemFailureMessage(refusal)))
            for key in [
                "app.slack.hotKey.label", "app.slack.hotKey.set", "app.slack.hotKey.recording", "app.slack.hotKey.clear",
                "app.slack.hotKey.needsModifier",
                "app.slack.loginItem.title", "app.slack.loginItem.help",
            ] {
                messages.append((key, AppLocalization.string(key)))
            }
            for (name, message) in messages {
                XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tag): \(name)")
                XCTAssertFalse(message.hasPrefix("app."), "\(tag): unresolved key for \(name)")
            }
            XCTAssertTrue(slackLoginItemFailureMessage(refusal).contains("synthetic refusal"), tag)
            if tag == "en" {
                let message = slackThreadRequestErrorMessage(SlackThreadRequestError.appendedPromptUnavailable)
                XCTAssertTrue(message.contains("login shell"))
                XCTAssertTrue(message.contains("executable"))
                XCTAssertTrue(message.contains("PATH"))
            }
        }
    }

    func testHotKeyIsStoredAsItsDictionaryAndAnythingElseReadsAsNone() throws {
        let defaults = UserDefaults.standard
        let key = "slackThreadHotKey"
        let old = defaults.object(forKey: key)
        defer { if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let combination = try XCTUnwrap(
            HotKeyCombination(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .shift, .command])
        )

        Settings.slackThreadHotKey = combination
        XCTAssertEqual(defaults.dictionary(forKey: key) as? [String: Int], ["keyCode": 8, "modifiers": 0x1300])
        XCTAssertEqual(Settings.slackThreadHotKey, combination)

        defaults.set("⌃⇧⌘C", forKey: key)
        XCTAssertNil(Settings.slackThreadHotKey)
        Settings.slackThreadHotKey = nil
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testRecordingStoresOnlyACombinationWithCommandControlOrOption() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let restore = preserveHotKeySetting()
        defer { restore() }
        Settings.slackThreadHotKey = nil
        let hotKey = StubSlackThreadHotKey()
        let controller = SetupWindowController(slackHotKey: hotKey, loginItem: StubLoginItem())
        let button = controller.slackPaneForTesting.hotKeyButton
        let clear = controller.slackPaneForTesting.clearHotKeyButton
        let status = controller.slackPaneForTesting.hotKeyStatusLabel
        XCTAssertEqual(button.title, localized("app.slack.hotKey.set"))
        XCTAssertTrue(clear.isHidden)

        button.performClick(nil)
        XCTAssertEqual(hotKey.calls, ["suspend"])
        XCTAssertEqual(button.title, localized("app.slack.hotKey.recording"))

        XCTAssertNil(controller.handleHotKeyRecordingEvent(keyDown(kVK_ANSI_C, [.shift])))
        XCTAssertTrue(status.stringValue.contains(localized("app.slack.hotKey.needsModifier")))
        XCTAssertEqual(hotKey.applied.count, 0)

        XCTAssertNil(controller.handleHotKeyRecordingEvent(keyDown(kVK_ANSI_C, [.control, .shift, .command])))
        let combination = try XCTUnwrap(
            HotKeyCombination(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .shift, .command])
        )
        XCTAssertEqual(hotKey.applied, [combination])
        XCTAssertEqual(Settings.slackThreadHotKey, combination)
        XCTAssertEqual(hotKey.calls, ["suspend", "apply", "resume"])
        XCTAssertEqual(button.title, combination.displayString(keyLabel: hotKeyKeyLabel(combination.keyCode)))
        XCTAssertFalse(clear.isHidden)
        XCTAssertTrue(status.isHidden)

        let unrelated = keyDown(kVK_ANSI_K, [.command])
        XCTAssertTrue(controller.handleHotKeyRecordingEvent(unrelated) === unrelated, "outside recording the window leaves keys alone")

        clear.performClick(nil)
        XCTAssertNil(Settings.slackThreadHotKey)
        XCTAssertEqual(hotKey.applied, [combination, nil])
        XCTAssertEqual(button.title, localized("app.slack.hotKey.set"))
        XCTAssertTrue(clear.isHidden)
    }

    func testEscapeCancelsRecordingAndKeepsThePreviousChoice() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let restore = preserveHotKeySetting()
        defer { restore() }
        let combination = try XCTUnwrap(
            HotKeyCombination(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .shift, .command])
        )
        Settings.slackThreadHotKey = combination
        let hotKey = StubSlackThreadHotKey()
        hotKey.combination = combination
        hotKey.state = .active(combination)
        let controller = SetupWindowController(slackHotKey: hotKey, loginItem: StubLoginItem())
        let button = controller.slackPaneForTesting.hotKeyButton

        button.performClick(nil)
        XCTAssertNil(controller.handleHotKeyRecordingEvent(keyDown(kVK_Escape, [])))

        XCTAssertEqual(hotKey.calls, ["suspend", "resume"])
        XCTAssertEqual(hotKey.applied.count, 0)
        XCTAssertEqual(Settings.slackThreadHotKey, combination)
        XCTAssertEqual(button.title, combination.displayString(keyLabel: hotKeyKeyLabel(combination.keyCode)))
    }

    func testRefusedRegistrationIsShownAndClearsWhenTheStateRecovers() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let combination = try XCTUnwrap(
            HotKeyCombination(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .shift, .command])
        )
        let hotKey = StubSlackThreadHotKey()
        hotKey.combination = combination
        hotKey.state = .failed(combination, status: -9878)
        let controller = SetupWindowController(slackHotKey: hotKey, loginItem: StubLoginItem())
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let status = controller.slackPaneForTesting.hotKeyStatusLabel
        XCTAssertFalse(status.isHidden)
        XCTAssertTrue(status.stringValue.contains("-9878"))

        hotKey.state = .active(combination)
        hotKey.onStateChange?(hotKey.state)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(status.isHidden)
    }

    func testLoginItemCheckboxShowsTheServiceStateNotTheClick() {
        AppLocalization.tagOverrideForTesting = "en"
        let loginItem = StubLoginItem(status: .disabled)
        let controller = SetupWindowController(slackHotKey: StubSlackThreadHotKey(), loginItem: loginItem)
        let checkbox = controller.slackPaneForTesting.loginItemCheckbox
        let status = controller.slackPaneForTesting.loginItemStatusLabel
        XCTAssertEqual(checkbox.state, .off)
        XCTAssertTrue(status.isHidden)

        checkbox.performClick(nil)
        XCTAssertEqual(loginItem.requests, [true])
        XCTAssertEqual(checkbox.state, .on)

        loginItem.status = .requiresApproval
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        XCTAssertEqual(checkbox.state, .on)
        XCTAssertTrue(status.stringValue.contains(slackLoginItemStatusMessage(.requiresApproval)))

        loginItem.failure = NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "synthetic refusal"])
        checkbox.performClick(nil)
        XCTAssertEqual(loginItem.requests, [true, false])
        XCTAssertEqual(checkbox.state, .on, "a refused change leaves the box showing what the service reports")
        XCTAssertTrue(status.stringValue.contains("synthetic refusal"))
    }

    func testSlackFieldsSaveRawTextAndShowValidationWhileEditing() throws {
        AppLocalization.tagOverrideForTesting = "en"
        let defaults = UserDefaults.standard
        let workKey = "slackThreadWorkDirectory"
        let instructionKey = "slackThreadInstruction"
        let oldWork = defaults.object(forKey: workKey)
        let oldInstruction = defaults.object(forKey: instructionKey)
        defer {
            if let oldWork { defaults.set(oldWork, forKey: workKey) } else { defaults.removeObject(forKey: workKey) }
            if let oldInstruction { defaults.set(oldInstruction, forKey: instructionKey) } else { defaults.removeObject(forKey: instructionKey) }
        }
        Settings.slackThreadWorkDirectory = ""
        Settings.slackThreadInstruction = ""

        let controller = SetupWindowController(slackHotKey: StubSlackThreadHotKey(), loginItem: StubLoginItem())
        let window = try XCTUnwrap(controller.window)
        select("slack", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let workField = controller.slackPaneForTesting.workDirectoryField
        try enterText("/tmp/has space", in: workField, window: window)
        XCTAssertEqual(Settings.slackThreadWorkDirectory, "/tmp/has space")
        XCTAssertTrue(
            controller.slackPaneForTesting.workDirectoryValidationLabel.stringValue
                .contains(localized("app.slack.error.workDirectoryInvalidCharacters"))
        )

        try enterText(NSTemporaryDirectory(), in: workField, window: window)
        XCTAssertEqual(Settings.slackThreadWorkDirectory, NSTemporaryDirectory())
        let instructionField = controller.slackPaneForTesting.instructionField
        try enterText("line\nbreak", in: instructionField, window: window)
        XCTAssertEqual(Settings.slackThreadInstruction, "line\nbreak")
        XCTAssertTrue(
            controller.slackPaneForTesting.instructionValidationLabel.stringValue
                .contains(localized("app.slack.error.invalidInstruction"))
        )
    }

    func testLeavingSlackPaneEndsHotKeyRecordingBeforePasteCanChangeTheChoice() throws {
        let restore = preserveHotKeySetting()
        defer { restore() }
        let original = try XCTUnwrap(
            HotKeyCombination(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .option])
        )
        Settings.slackThreadHotKey = original
        let hotKey = StubSlackThreadHotKey()
        hotKey.combination = original
        hotKey.state = .active(original)
        let controller = SetupWindowController(slackHotKey: hotKey, loginItem: StubLoginItem())
        let window = try XCTUnwrap(controller.window)
        select("slack", in: window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        controller.slackPaneForTesting.hotKeyButton.performClick(nil)
        XCTAssertTrue(controller.isRecordingHotKeyForTesting)
        select("github", in: window)

        XCTAssertFalse(controller.isRecordingHotKeyForTesting)
        let paste = keyDown(kVK_ANSI_V, [.command])
        XCTAssertTrue(controller.handleHotKeyRecordingEvent(paste) === paste)
        XCTAssertEqual(Settings.slackThreadHotKey, original)
    }

    private func select(_ pane: String, in window: NSWindow) {
        guard let item = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "setup.pane.\(pane)" }),
              let action = item.action else {
            XCTFail("missing toolbar item for \(pane)")
            return
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func enterText(_ text: String, in field: NSTextField, window: NSWindow) throws {
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let replacedRange = NSRange(location: 0, length: editor.string.utf16.count)
        editor.insertText(text, replacementRange: replacedRange)
    }

    private func keyDown(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    private func preserveHotKeySetting() -> () -> Void {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "slackThreadHotKey")
        return {
            if let old { defaults.set(old, forKey: "slackThreadHotKey") } else { defaults.removeObject(forKey: "slackThreadHotKey") }
        }
    }

    private func segment(in source: String, from start: String, to end: String) -> String? {
        guard let startRange = source.range(of: start),
              let endRange = source[startRange.upperBound...].range(of: end) else { return nil }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}

/// Records what the window asks of the app's shortcut, which the window does not own.
final class StubSlackThreadHotKey: SlackThreadHotKeyManaging {
    var combination: HotKeyCombination?
    var state: SlackThreadHotKeyState = .off
    var onStateChange: ((SlackThreadHotKeyState) -> Void)?
    private(set) var applied: [HotKeyCombination?] = []
    private(set) var calls: [String] = []

    func apply(_ combination: HotKeyCombination?) {
        calls.append("apply")
        applied.append(combination)
        self.combination = combination
        state = combination.map { .active($0) } ?? .off
        onStateChange?(state)
    }

    func suspend() { calls.append("suspend") }
    func resume() { calls.append("resume") }
}

final class StubLoginItem: LoginItemManaging {
    var status: LoginItemStatus
    var failure: Error?
    private(set) var requests: [Bool] = []

    init(status: LoginItemStatus = .disabled) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let failure { throw failure }
        status = enabled ? .enabled : .disabled
    }
}
