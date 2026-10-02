import Core
import Foundation
import XCTest
@testable import App

final class SlackThreadURLHandlingTests: XCTestCase {
    private var previousTerminal: Any?
    private var previousActivation: Any?
    private var previousResourcesPath: String?

    private static var sourceResources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    private var validURL: URL {
        URL(string: "terminal-checkout://slack-thread?url=https://example.slack.com/archives/C0123ABCD/p1700000000123456")!
    }

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

    func testURLCoordinatorBuffersAcceptedEventsUntilInitializationInOrder() {
        let first = URL(string: "terminal-checkout://slack-thread?url=first")!
        let second = URL(string: "terminal-checkout://slack-thread?url=second")!
        let wrongScheme = URL(string: "https://example.slack.com/archives/C0123ABCD/p1700000000123456")!
        var processed: [URL] = []
        var ignored: [String] = []
        var displayedFailures = 0
        let coordinator = SlackThreadURLCoordinator(
            execute: { url, completion in
                processed.append(url)
                completion(.success(()))
            },
            presentFailure: { _ in displayedFailures += 1 },
            clearFailure: {},
            log: { ignored.append($0) }
        )

        coordinator.receive([first, wrongScheme, second, first])
        XCTAssertEqual(processed, [])
        XCTAssertEqual(ignored.count, 1)
        coordinator.finishInitialization()
        coordinator.finishInitialization()
        XCTAssertEqual(processed, [first, second, first])
        coordinator.receive([second])
        XCTAssertEqual(processed, [first, second, first, second])
        XCTAssertEqual(displayedFailures, 0)
    }

    func testURLCoordinatorRunsSuccessOncePresentsFailuresAndClearsAfterSuccess() {
        let successBeforeFailureURL = URL(string: "terminal-checkout://slack-thread/success-before-failure")!
        let validationFailureURL = URL(string: "terminal-checkout://slack-thread/validation")!
        let executionFailureURL = URL(string: "terminal-checkout://slack-thread/execution")!
        let successAfterFailureURL = URL(string: "terminal-checkout://slack-thread/success-after-failure")!
        var executed: [URL] = []
        var presented: [Error] = []
        var setupWindowExists = false
        var failureLineVisible = false
        var clearCount = 0
        let coordinator = SlackThreadURLCoordinator(
            execute: { url, completion in
                executed.append(url)
                switch url.path {
                case "/success-before-failure", "/success-after-failure": completion(.success(()))
                case "/validation": completion(.failure(SlackThreadRequestError.invalidSlackLink))
                default: completion(.failure(TerminalError.cmuxNotFound))
                }
            },
            presentFailure: {
                presented.append($0)
                setupWindowExists = true
                failureLineVisible = true
            },
            clearFailure: {
                guard setupWindowExists else { return }
                clearCount += 1
                failureLineVisible = false
            },
            log: { _ in }
        )
        coordinator.finishInitialization()

        coordinator.receive([
            successBeforeFailureURL,
            validationFailureURL,
            executionFailureURL,
            successAfterFailureURL,
        ])

        XCTAssertEqual(executed, [
            successBeforeFailureURL,
            validationFailureURL,
            executionFailureURL,
            successAfterFailureURL,
        ])
        XCTAssertEqual(presented.count, 2)
        XCTAssertEqual(clearCount, 1)
        XCTAssertFalse(failureLineVisible)
        guard presented.count == 2 else { return }
        XCTAssertTrue(presented[0] is SlackThreadRequestError)
        XCTAssertEqual(
            slackThreadRequestErrorMessage(presented[1]),
            localizedErrorMessage(TerminalError.cmuxNotFound)
        )
        XCTAssertEqual(
            slackThreadRequestErrorMessage(TerminalError.cmuxSocketDenied),
            localizedErrorMessage(TerminalError.cmuxSocketDenied)
        )
    }

    func testAutomaticLaunchWindowRequiresDefaultLaunchWithoutBackgroundArgument() {
        XCTAssertTrue(shouldShowSetupWindowAtLaunch(launchIsDefault: true, hasBackgroundArgument: false))
        XCTAssertFalse(shouldShowSetupWindowAtLaunch(launchIsDefault: true, hasBackgroundArgument: true))
        XCTAssertFalse(shouldShowSetupWindowAtLaunch(launchIsDefault: false, hasBackgroundArgument: false))
        XCTAssertTrue(shouldShowSetupWindowAtLaunch(launchIsDefault: nil, hasBackgroundArgument: false))
        XCTAssertFalse(shouldShowSetupWindowAtLaunch(launchIsDefault: nil, hasBackgroundArgument: true))
    }

    func testServerUnavailableFailureHasLocalizedMessagesInEveryLocale() {
        for tag in supportedLocales {
            AppLocalization.tagOverrideForTesting = tag
            let message = slackThreadRequestErrorMessage(SlackThreadURLHandlerError.serverUnavailable)
            XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tag): empty message")
            XCTAssertFalse(message.hasPrefix("app."), "\(tag): unresolved key")
        }
    }

    func testHostServerResolvesSettingsAndUsesItsInjectedTerminalExecutor() throws {
        let workDirectory = NSTemporaryDirectory()
        var settingsReadCount = 0
        var commands: [String] = []
        let completion = expectation(description: "Slack thread URL completed")
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

        server.enqueueSlackThreadURL(validURL) { result in
            if case .failure(let error) = result {
                XCTFail("unexpected Slack URL failure: \(errorMessage(error))")
            }
            completion.fulfill()
        }
        wait(for: [completion], timeout: 3)

        XCTAssertEqual(settingsReadCount, 1)
        XCTAssertEqual(commands.count, 1)
        let normalizedWorkDirectory = try XCTUnwrap(try normalizedBaseDirectory(workDirectory))
        XCTAssertTrue(commands[0].hasPrefix("cd \(normalizedWorkDirectory) && command claude -- '"))
        XCTAssertTrue(commands[0].contains("review this synthetic thread"))
    }

    func testHostServerValidationFailureSkipsTheTerminalExecutor() {
        var runnerCount = 0
        let completion = expectation(description: "invalid Slack permalink rejected")
        let invalidURL = URL(string: "terminal-checkout://slack-thread?url=https://evil.example/archives/C0123ABCD/p1700000000123456")!
        let server = makeServer(
            workDirectory: NSTemporaryDirectory(),
            instruction: "",
            runner: { _, _, _, _ in
                runnerCount += 1
                return .none
            }
        )

        server.enqueueSlackThreadURL(invalidURL) { result in
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

        server.enqueueSlackThreadURL(validURL) { result in
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
    }

    func testSocketAndSlackURLLaunchesShareOneSerialQueueAndInjectedExecutor() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tcsu-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let socketPath = directory.appendingPathComponent("s").path
        XCTAssertLessThanOrEqual(socketPath.utf8.count, 104)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
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
        server.enqueueSlackThreadURL(validURL) { result in
            if case .failure(let error) = result {
                XCTFail("unexpected Slack URL failure: \(errorMessage(error))")
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

    private func makeServer(
        workDirectory: String,
        instruction: String,
        settingsRead: @escaping () -> Void = {},
        runner: @escaping (String, Terminal, ClaudeDelivery.Admission?, TabActivation) throws -> TerminalSessionHandle
    ) -> HostServer {
        HostServer(
            socketPath: "/tmp/tc-slack-url-test-\(UUID().uuidString.prefix(8))/server.sock",
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
