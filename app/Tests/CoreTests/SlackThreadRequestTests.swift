import Foundation
import XCTest
@testable import Core

final class SlackThreadRequestTests: XCTestCase {
    private let validLink = "https://example.slack.com/archives/C0123ABCD/p1700000000123456"
    private let validWorkDirectory = "/tmp/terminal-checkout-tests"

    private func outerURL(for link: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/"
        )
        let encoded = link.addingPercentEncoding(withAllowedCharacters: allowed)!
        return "\(SlackThreadURLContract.shortcutURLPrefix)\(encoded)"
    }

    private func resolve(
        _ link: String = "https://example.slack.com/archives/C0123ABCD/p1700000000123456",
        instruction: String = "",
        workDirectory: String? = "/tmp/terminal-checkout-tests",
        directoryIsValid: (String) -> Bool = { _ in true }
    ) throws -> ResolvedRequest {
        try resolveSlackThreadRequest(
            outerURL: outerURL(for: link),
            workDirectory: workDirectory,
            instruction: instruction,
            directoryIsValid: directoryIsValid
        )
    }

    private func assertOuterURLRejected(
        _ outerURL: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try parseSlackThreadLink(from: outerURL), file: file, line: line) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .invalidOuterURL = requestError else {
                XCTFail("Expected invalidOuterURL, got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func assertSlackLinkRejected(
        _ link: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try parseSlackThreadLink(from: outerURL(for: link)), file: file, line: line) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .invalidSlackLink = requestError else {
                XCTFail("Expected invalidSlackLink, got \(error)", file: file, line: line)
                return
            }
        }
    }

    func testAcceptsDriverShortcutURLAndQuerylessPermalinkPreservingOriginalLink() throws {
        let driverLink = "https://example.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=1700000000.000100&cid=C0123ABCD"
        let driverURL = "terminal-checkout://slack-thread?url=https://example.slack.com/archives/C0123ABCD/p1700000000123456%3Fthread_ts%3D1700000000.000100%26cid%3DC0123ABCD"

        XCTAssertEqual(try parseSlackThreadLink(from: driverURL), driverLink)
        XCTAssertEqual(
            try parseSlackThreadLink(from: outerURL(for: validLink)),
            validLink
        )
        XCTAssertEqual(
            try parseSlackThreadLink(
                from: outerURL(for: validLink).replacingOccurrences(
                    of: SlackThreadURLContract.scheme,
                    with: SlackThreadURLContract.scheme.uppercased()
                )
            ),
            validLink
        )
    }

    func testAcceptsEnterpriseHostIDsAndTrimmedOriginalLink() throws {
        let enterprise = "https://example.enterprise.slack.com/archives/C0123ABCDEF/p1700000000123456?thread_ts=1700000000.000100&cid=G0123ABCD"
        let group = "https://example.slack.com/archives/G0123ABCD/p1700000000123456"
        let direct = "https://example.slack.com/archives/D0123ABCD/p1700000000123456"
        let replyWithoutChannelID = "https://example.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=1700000000.000100"
        let uppercaseHost = "https://EXAMPLE.slack.com/archives/C0123ABCD/p1700000000123456"
        let padded = " \t\r\n\(validLink)\n\r\t "

        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: enterprise)), enterprise)
        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: group)), group)
        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: direct)), direct)
        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: replyWithoutChannelID)), replyWithoutChannelID)
        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: uppercaseHost)), uppercaseHost)
        XCTAssertEqual(try parseSlackThreadLink(from: outerURL(for: padded)), validLink)
    }

    func testRejectsMalformedOuterURLs() {
        let validOuter = outerURL(for: validLink)
        let encodedLink = validOuter.dropFirst(SlackThreadURLContract.shortcutURLPrefix.count)

        assertOuterURLRejected("https://slack-thread?url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://other-host?url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://SLACK-THREAD?url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://slack-thread/path?url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://slack-thread?url=\(encodedLink)#fragment")
        assertOuterURLRejected("terminal-checkout://slack-thread")
        assertOuterURLRejected("terminal-checkout://slack-thread?url")
        assertOuterURLRejected("terminal-checkout://slack-thread?url=")
        assertOuterURLRejected("terminal-checkout://slack-thread?url=\(encodedLink)&url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://user:password@slack-thread?url=\(encodedLink)")
        assertOuterURLRejected("terminal-checkout://slack-thread:443?url=\(encodedLink)")
    }

    func testRejectsInvalidSlackLinks() {
        let path = "/archives/C0123ABCD/p1700000000123456"
        let invalidLinks = [
            "http://example.slack.com\(path)",
            "https://slack.com\(path)",
            "https://evil.com\(path)",
            "https://example.slack.com.evil.com\(path)",
            "https://evilslack.com\(path)",
            "https://ex_ample.slack.com\(path)",
            "https://example.slack.com@evil.com\(path)",
            "https://evil.com@example.slack.com\(path)",
            "https://example.slack.com:443\(path)",
            "https://example.slack.com\(path)#fragment",
            "https://example.slack.com/archives/C0123ABCD/p123",
            "https://example.slack.com/messages/C0123ABCD/p1700000000123456",
            "https://example.slack.com\(path)/",
            "https://example.slack.com/archives%2FC0123ABCD/p1700000000123456",
            "https://example.slack.com\(path)?other=value",
            "https://example.slack.com\(path)?thread_ts=1700000000.000100&thread_ts=1700000000.000100",
            "https://example.slack.com\(path)?cid=C0123ABCD&cid=C0123ABCD",
            "https://example.slack.com\(path)?thread_ts=bad",
            "https://example.slack.com\(path)?cid=bad",
            "https://example.slack.com/archives/X0123ABCD/p1700000000123456",
            "https://example.slack.com/archives/C0123ABCD/p123456789012345",
            "https://example.slack.com\(path)%25",
        ]

        for link in invalidLinks {
            assertSlackLinkRejected(link)
        }
    }

    func testRejectsSlackLinkOver512UTF8BytesBeforeValidation() {
        // Valid Slack links cannot approach this size under the allowlist grammar.
        let overLimit = validLink + String(repeating: "é", count: 300)
        XCTAssertGreaterThan(overLimit.utf8.count, 512)
        XCTAssertThrowsError(try parseSlackThreadLink(from: outerURL(for: overLimit))) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .slackLinkTooLong = requestError else {
                XCTFail("Expected slackLinkTooLong, got \(error)")
                return
            }
        }
    }

    func testHostLabelBoundaryAllows63AndRejects64Characters() throws {
        let label63 = String(repeating: "a", count: 63)
        let label64 = String(repeating: "a", count: 64)
        let path = "/archives/C0123ABCD/p1700000000123456"

        XCTAssertEqual(
            try parseSlackThreadLink(from: outerURL(for: "https://\(label63).slack.com\(path)")),
            "https://\(label63).slack.com\(path)"
        )
        assertSlackLinkRejected("https://\(label64).slack.com\(path)")
    }

    func testRejectsUnknownOuterQueryKeys() {
        let encodedLink = outerURL(for: validLink).dropFirst(SlackThreadURLContract.shortcutURLPrefix.count)
        assertOuterURLRejected("terminal-checkout://slack-thread?url=\(encodedLink)&command=claude")
        assertOuterURLRejected("terminal-checkout://slack-thread?url=\(encodedLink)&folder=%2Ftmp")
    }

    func testBuildsLinkFirstCommandFromSettingsAndAllowsEmptyInstruction() throws {
        let instruction = "  review this thread {base}  "
        let request = try resolve(instruction: instruction)
        let emptyInstruction = try resolve()
        let whitespaceOnlyInstruction = try resolve(instruction: "   ")

        XCTAssertEqual(request.command, "cd \(validWorkDirectory) && claude")
        XCTAssertEqual(request.claudeInputs, ["\(validLink) review this thread {base}"])
        XCTAssertEqual(emptyInstruction.claudeInputs, [validLink])
        XCTAssertEqual(whitespaceOnlyInstruction.claudeInputs, [validLink])
    }

    func testLiveSettingsValidatorMatchesRequestResolution() throws {
        func verdict<T>(_ operation: () throws -> T) -> String {
            do {
                _ = try operation()
                return "valid"
            } catch let error as SlackThreadRequestError {
                switch error {
                case .workDirectoryNotConfigured:
                    return "workDirectoryNotConfigured"
                case .invalidWorkDirectory(let underlying):
                    guard let commandError = underlying as? CommandError,
                          case .invalidBaseDirectory(let problem, _) = commandError else {
                        return "invalidWorkDirectory"
                    }
                    switch problem {
                    case .notAbsolute: return "workDirectoryNotAbsolute"
                    case .invalidCharacters: return "workDirectoryInvalidCharacters"
                    }
                case .workDirectoryUnavailable:
                    return "workDirectoryUnavailable"
                case .invalidInstruction:
                    return "invalidInstruction"
                case .invalidOuterURL, .invalidSlackLink, .slackLinkTooLong,
                     .appendedPromptUnavailable:
                    return "unrelatedRequestError"
                }
            } catch {
                return "unexpectedError"
            }
        }

        let cases: [(String?, String, Bool)] = [
            (nil, "review", true),
            ("", "review", true),
            ("relative/path", "review", true),
            ("/tmp/has space", "review", true),
            (validWorkDirectory, "review", false),
            (validWorkDirectory, "line\nbreak", true),
            (validWorkDirectory, "review", true),
        ]

        for (workDirectory, instruction, directoryExists) in cases {
            let isValid: (String) -> Bool = { _ in directoryExists }
            let liveVerdict = verdict {
                try validateSlackThreadSettings(
                    workDirectory: workDirectory,
                    instruction: instruction,
                    directoryIsValid: isValid
                )
            }
            let requestVerdict = verdict {
                try resolveSlackThreadRequest(
                    outerURL: outerURL(for: validLink),
                    workDirectory: workDirectory,
                    instruction: instruction,
                    directoryIsValid: isValid
                )
            }
            XCTAssertEqual(liveVerdict, requestVerdict, "settings: \(workDirectory ?? "nil") / \(instruction)")
        }

        let settings = try validateSlackThreadSettings(
            workDirectory: " /tmp/terminal-checkout-tests/ ",
            instruction: "  review this thread  ",
            directoryIsValid: { _ in true }
        )
        let request = try resolve(instruction: "  review this thread  ")
        XCTAssertEqual(settings.workDirectory, "/tmp/terminal-checkout-tests")
        XCTAssertEqual(settings.instruction, "review this thread")
        XCTAssertEqual(request.command, "cd \(settings.workDirectory) && claude")
        XCTAssertEqual(request.claudeInputs, ["\(validLink) \(settings.instruction)"])
    }

    func testRejectsInvalidInstructionsAndInvalidDirectories() throws {
        let c0Instructions = (0...0x1F).compactMap { value in
            UnicodeScalar(UInt32(value)).map { "control\($0)byte" }
        }
        let invalidInstructions = ["line\nbreak", "line\rbreak", "delete\u{7f}"] + c0Instructions
        for instruction in invalidInstructions {
            XCTAssertThrowsError(try resolve(instruction: instruction)) { error in
                guard let requestError = error as? SlackThreadRequestError,
                      case .invalidInstruction = requestError else {
                    XCTFail("Expected invalidInstruction, got \(error)")
                    return
                }
            }
        }

        XCTAssertThrowsError(try resolve(workDirectory: nil)) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .workDirectoryNotConfigured = requestError else {
                XCTFail("Expected workDirectoryNotConfigured, got \(error)")
                return
            }
        }
        XCTAssertThrowsError(try resolve(workDirectory: "")) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .workDirectoryNotConfigured = requestError else {
                XCTFail("Expected workDirectoryNotConfigured, got \(error)")
                return
            }
        }
        for path in ["relative/path", "/tmp/has space"] {
            XCTAssertThrowsError(try resolve(workDirectory: path)) { error in
                guard let requestError = error as? SlackThreadRequestError,
                      case .invalidWorkDirectory = requestError else {
                    XCTFail("Expected invalidWorkDirectory for \(path), got \(error)")
                    return
                }
            }
        }
        XCTAssertThrowsError(try resolve(directoryIsValid: { _ in false })) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .workDirectoryUnavailable = requestError else {
                XCTFail("Expected workDirectoryUnavailable, got \(error)")
                return
            }
        }
    }

    func testFileManagerDefaultAcceptsAnExistingTemporaryDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.path
        XCTAssertNoThrow(try resolve(workDirectory: directory))
    }

    func testPreparedSlackRequestUsesArgvOnlyAndFailsClosed() throws {
        let request = try resolve(instruction: "review this thread")
        let input = "\(validLink) review this thread"

        XCTAssertTrue(commandAcceptsAppendedClaudePrompt(request.commandJudgedForAppendedPrompt))
        let prepared = try prepareSlackThreadRequest(request, loginShell: "/bin/zsh")
        XCTAssertTrue(prepared.claudeInputs.isEmpty)
        XCTAssertTrue(prepared.command.hasSuffix("-- '\(input)'"))

        for (loginShell, claudeIsExecutable) in [("/bin/tcsh", true), ("/bin/zsh", false)] {
            XCTAssertThrowsError(
                try prepareSlackThreadRequest(
                    request,
                    loginShell: loginShell,
                    claudeIsExecutable: claudeIsExecutable
                )
            ) { error in
                guard let requestError = error as? SlackThreadRequestError,
                      case .appendedPromptUnavailable = requestError else {
                    XCTFail("Expected appendedPromptUnavailable, got \(error)")
                    return
                }
            }
        }
    }
}
