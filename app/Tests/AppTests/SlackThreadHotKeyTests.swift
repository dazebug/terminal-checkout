import AppKit
import Carbon.HIToolbox
import Core
import Foundation
import XCTest
@testable import App

final class SlackThreadHotKeyTests: XCTestCase {
    private var previousTerminal: Any?
    private var previousActivation: Any?
    private var previousResourcesPath: String?

    private static var sourceResources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    private let link = "https://example.slack.com/archives/C0123ABCD/p1700000000123456"
    private let combination = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .shift, .command]
    )!

    override func setUp() {
        super.setUp()
        previousTerminal = UserDefaults.standard.object(forKey: "terminal")
        previousActivation = UserDefaults.standard.object(forKey: "tabActivation")
        previousResourcesPath = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = Self.sourceResources
        UserDefaults.standard.set(Terminal.iterm.rawValue, forKey: "terminal")
        UserDefaults.standard.set(TabActivation.foreground.rawValue, forKey: "tabActivation")
    }

    override func tearDown() {
        restore(previousTerminal, forKey: "terminal")
        restore(previousActivation, forKey: "tabActivation")
        AppLocalization.tagOverrideForTesting = nil
        AppLocalization.resourcesPath = previousResourcesPath
        super.tearDown()
    }

    func testModifierMasksAreCarbonsOwnSoRegistrationNeedsNoMapping() {
        XCTAssertEqual(HotKeyModifiers.command.rawValue, UInt32(cmdKey))
        XCTAssertEqual(HotKeyModifiers.shift.rawValue, UInt32(shiftKey))
        XCTAssertEqual(HotKeyModifiers.option.rawValue, UInt32(optionKey))
        XCTAssertEqual(HotKeyModifiers.control.rawValue, UInt32(controlKey))
    }

    func testEventFlagsKeepOnlyTheFourShortcutModifiers() {
        XCTAssertEqual(
            hotKeyModifiers(from: [.command, .shift, .control, .capsLock, .function, .numericPad]),
            [.command, .shift, .control]
        )
        XCTAssertEqual(hotKeyModifiers(from: [.option]), [.option])
        XCTAssertEqual(hotKeyModifiers(from: []), [])
    }

    func testSpecialKeysHaveFixedLabelsAndCharacterKeysAreUppercase() {
        XCTAssertEqual(hotKeyKeyLabel(UInt32(kVK_F1)), "F1")
        XCTAssertEqual(hotKeyKeyLabel(UInt32(kVK_F12)), "F12")
        XCTAssertEqual(hotKeyKeyLabel(UInt32(kVK_Space)), "Space")
        XCTAssertEqual(hotKeyKeyLabel(UInt32(kVK_Return)), "↩")
        XCTAssertEqual(hotKeyKeyLabel(UInt32(kVK_LeftArrow)), "←")
        let letter = hotKeyKeyLabel(UInt32(kVK_ANSI_C))
        XCTAssertEqual(letter.count, 1)
        XCTAssertEqual(letter, letter.uppercased())
    }

    func testApplyRegistersReplacesAndTurnsOff() {
        let registrar = FakeHotKeyRegistrar()
        let controller = makeController(registrar: registrar)
        var states: [SlackThreadHotKeyState] = []
        controller.onStateChange = { states.append($0) }

        controller.apply(combination)
        let other = HotKeyCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: [.option, .command])!
        controller.apply(other)
        controller.apply(nil)

        XCTAssertEqual(registrar.registered, [combination, other])
        XCTAssertEqual(controller.state, .off)
        XCTAssertNil(controller.combination)
        XCTAssertEqual(states, [.active(combination), .active(other), .off])
        XCTAssertNil(registrar.onPress, "turning the shortcut off must leave nothing that can fire")
    }

    func testRegistrationRefusalIsAStateTheWindowCanShow() {
        let registrar = FakeHotKeyRegistrar()
        registrar.refusal = -9878
        let controller = makeController(registrar: registrar)

        controller.apply(combination)

        XCTAssertEqual(controller.state, .failed(combination, status: -9878))
        XCTAssertEqual(controller.combination, combination, "a refused shortcut is still the stored choice")
        AppLocalization.tagOverrideForTesting = "en"
        let message = slackThreadHotKeyStateMessage(controller.state)
        XCTAssertTrue(message.contains("-9878"))
        XCTAssertFalse(message.hasPrefix("app."))
    }

    func testPressReadsTheClipboardAtPressTimeAndReportsTheOutcome() {
        let registrar = FakeHotKeyRegistrar()
        var clipboard: String? = "first"
        var executed: [String?] = []
        var outcomes: [Result<Void, Error>] = [
            .failure(SlackThreadRequestError.invalidSlackLink),
            .success(()),
        ]
        var presented: [Error] = []
        var clears = 0
        let controller = SlackThreadHotKeyController(
            registrar: registrar,
            readClipboard: { clipboard },
            execute: { text, completion in
                executed.append(text)
                completion(outcomes.removeFirst())
            },
            presentFailure: { presented.append($0) },
            clearFailure: { clears += 1 },
            log: { _ in }
        )
        controller.apply(combination)

        clipboard = link
        registrar.onPress?()
        clipboard = nil
        registrar.onPress?()

        XCTAssertEqual(executed, [link, nil])
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(presented.first is SlackThreadRequestError)
        XCTAssertEqual(clears, 1)
    }

    func testSuspendedControllerKeepsTheChoiceButCannotFireUntilResumed() {
        let registrar = FakeHotKeyRegistrar()
        let controller = makeController(registrar: registrar)
        controller.apply(combination)

        controller.suspend()
        XCTAssertNil(registrar.onPress)
        let other = HotKeyCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: [.option, .command])!
        controller.apply(other)
        XCTAssertEqual(registrar.registered, [combination], "nothing registers while recording")
        XCTAssertEqual(controller.combination, other)

        controller.resume()
        XCTAssertEqual(registrar.registered, [combination, other])
        XCTAssertNotNil(registrar.onPress)
        XCTAssertEqual(controller.state, .active(other))
    }

    func testAutomaticLaunchWindowSkipsLoginAndBackgroundLaunches() {
        XCTAssertTrue(shouldShowSetupWindowAtLaunch(launchedAsLoginItem: false, hasBackgroundArgument: false))
        XCTAssertFalse(shouldShowSetupWindowAtLaunch(launchedAsLoginItem: true, hasBackgroundArgument: false))
        XCTAssertFalse(shouldShowSetupWindowAtLaunch(launchedAsLoginItem: false, hasBackgroundArgument: true))
    }

    func testHostServerResolvesSettingsAndUsesItsInjectedTerminalExecutor() throws {
        let workDirectory = NSTemporaryDirectory()
        var settingsReadCount = 0
        var commands: [String] = []
        let completion = expectation(description: "Slack thread request completed")
        let server = makeServer(
            workDirectory: workDirectory,
            instruction: "review this synthetic thread",
            settingsRead: { settingsReadCount += 1 },
            runner: { command, terminal, admission, activation in
                commands.append(command)
                XCTAssertEqual(terminal, .iterm)
                XCTAssertNil(admission)
                XCTAssertEqual(activation, .foreground)
                return .none
            }
        )

        server.enqueueSlackThread(clipboardText: "\(link)\n") { result in
            if case .failure(let error) = result {
                XCTFail("unexpected Slack thread failure: \(errorMessage(error))")
            }
            completion.fulfill()
        }
        wait(for: [completion], timeout: 3)

        XCTAssertEqual(settingsReadCount, 1)
        XCTAssertEqual(commands.count, 1)
        let normalizedWorkDirectory = try XCTUnwrap(try normalizedBaseDirectory(workDirectory))
        XCTAssertTrue(commands[0].hasPrefix("cd \(normalizedWorkDirectory) && command claude -- '\(link) "))
        XCTAssertTrue(commands[0].contains("review this synthetic thread"))
    }

    func testHostServerValidationFailureSkipsTheTerminalExecutor() {
        var runnerCount = 0
        let completion = expectation(description: "invalid clipboard rejected")
        let server = makeServer(
            workDirectory: NSTemporaryDirectory(),
            instruction: "",
            runner: { _, _, _, _ in
                runnerCount += 1
                return .none
            }
        )

        server.enqueueSlackThread(clipboardText: "https://evil.example/archives/C0123ABCD/p1700000000123456") { result in
            guard case .failure(let error) = result else {
                XCTFail("expected invalid permalink failure")
                completion.fulfill()
                return
            }
            XCTAssertTrue(error is SlackThreadRequestError)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 3)
        XCTAssertEqual(runnerCount, 0)
    }

    func testHostServerExecutionFailureIsReturnedForVisiblePresentation() {
        var runnerCount = 0
        let completion = expectation(description: "terminal failure returned")
        let server = makeServer(
            workDirectory: NSTemporaryDirectory(),
            instruction: "",
            runner: { _, _, _, _ in
                runnerCount += 1
                throw TerminalError.cmuxNotFound
            }
        )

        server.enqueueSlackThread(clipboardText: link) { result in
            guard case .failure(let error) = result else {
                XCTFail("expected terminal launch failure")
                completion.fulfill()
                return
            }
            XCTAssertEqual(errorMessage(error), "cmux not found. Install cmux or check your PATH.")
            completion.fulfill()
        }
        wait(for: [completion], timeout: 3)
        XCTAssertEqual(runnerCount, 1)
        XCTAssertEqual(
            slackThreadRequestErrorMessage(TerminalError.cmuxSocketDenied),
            localizedErrorMessage(TerminalError.cmuxSocketDenied)
        )
    }

    func testSocketAndSlackHotKeyLaunchesShareOneSerialQueueAndInjectedExecutor() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tcsh-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let socketPath = directory.appendingPathComponent("s").path
        XCTAssertLessThanOrEqual(socketPath.utf8.count, 104)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let socketRunnerEntered = DispatchSemaphore(value: 0)
        let slackRunnerEntered = DispatchSemaphore(value: 0)
        let releaseSocketRunner = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var runnerKinds: [String] = []
        let server = HostServer(
            socketPath: socketPath,
            runInTerminal: { command, _, _, _ in
                let kind = command.contains("socket-path") ? "socket" : "slack"
                lock.lock()
                runnerKinds.append(kind)
                lock.unlock()
                if kind == "socket" {
                    socketRunnerEntered.signal()
                    releaseSocketRunner.wait()
                } else {
                    slackRunnerEntered.signal()
                }
                return .none
            },
            slackThreadSettings: { (workDirectory: NSTemporaryDirectory(), instruction: "") },
            loginShellPathProvider: { "/bin/zsh" },
            claudeExecutableProvider: { true }
        )
        defer {
            releaseSocketRunner.signal()
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try server.start()

        RelayAtTheDoor().connectAndAsk(["command_template": "echo socket-path"], at: socketPath, givingUp: 5)
        XCTAssertEqual(socketRunnerEntered.wait(timeout: .now() + 2), .success)
        let completion = expectation(description: "queued Slack launch completed")
        server.enqueueSlackThread(clipboardText: link) { result in
            if case .failure(let error) = result {
                XCTFail("unexpected Slack thread failure: \(errorMessage(error))")
            }
            completion.fulfill()
        }

        XCTAssertEqual(slackRunnerEntered.wait(timeout: .now() + 0.1), .timedOut)
        releaseSocketRunner.signal()
        XCTAssertEqual(slackRunnerEntered.wait(timeout: .now() + 2), .success)
        wait(for: [completion], timeout: 2)
        lock.lock()
        let observedKinds = runnerKinds
        lock.unlock()
        XCTAssertEqual(observedKinds, ["socket", "slack"])
    }

    private func makeController(registrar: FakeHotKeyRegistrar) -> SlackThreadHotKeyController {
        SlackThreadHotKeyController(
            registrar: registrar,
            readClipboard: { nil },
            execute: { _, completion in completion(.success(())) },
            presentFailure: { _ in },
            clearFailure: {},
            log: { _ in }
        )
    }

    private func makeServer(
        workDirectory: String,
        instruction: String,
        settingsRead: @escaping () -> Void = {},
        runner: @escaping (String, Terminal, ClaudeDelivery.Admission?, TabActivation) throws -> TerminalSessionHandle
    ) -> HostServer {
        HostServer(
            socketPath: "/tmp/tc-slack-hotkey-test-\(UUID().uuidString.prefix(8))/server.sock",
            runInTerminal: runner,
            slackThreadSettings: {
                settingsRead()
                return (workDirectory: workDirectory, instruction: instruction)
            },
            loginShellPathProvider: { "/bin/zsh" },
            claudeExecutableProvider: { true }
        )
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Stands in for Carbon, which the suite cannot press keys against.
final class FakeHotKeyRegistrar: HotKeyRegistering {
    private(set) var registered: [HotKeyCombination] = []
    var refusal: Int32?
    private(set) var onPress: (() -> Void)?

    func register(_ combination: HotKeyCombination, onPress: @escaping () -> Void) throws {
        if let refusal { throw HotKeyRegistrationError(status: refusal) }
        registered.append(combination)
        self.onPress = onPress
    }

    func unregister() {
        onPress = nil
    }
}
