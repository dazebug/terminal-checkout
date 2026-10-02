import Foundation
import XCTest
@testable import Core

final class SlackThreadRequestTests: XCTestCase {
    private let validLink = "https://example.slack.com/archives/C0123ABCD/p1700000000123456"
    private let validWorkDirectory = "/tmp/terminal-checkout-tests"

    private func resolve(
        _ link: String = "https://example.slack.com/archives/C0123ABCD/p1700000000123456",
        instruction: String = "",
        workDirectory: String? = "/tmp/terminal-checkout-tests",
        directoryIsValid: (String) -> Bool = { _ in true }
    ) throws -> ResolvedRequest {
        try resolveSlackThreadRequest(
            clipboardText: link,
            workDirectory: workDirectory,
            instruction: instruction,
            directoryIsValid: directoryIsValid
        )
    }

    private func assertClipboardEmpty(
        _ text: String?, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try slackThreadLink(fromClipboard: text), file: file, line: line) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .clipboardEmpty = requestError else {
                XCTFail("Expected clipboardEmpty, got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func assertSlackLinkRejected(
        _ link: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try slackThreadLink(fromClipboard: link), file: file, line: line) { error in
            guard let requestError = error as? SlackThreadRequestError,
                  case .invalidSlackLink = requestError else {
                XCTFail("Expected invalidSlackLink, got \(error)", file: file, line: line)
                return
            }
        }
    }

    func testAcceptsCopiedThreadLinkAndQuerylessPermalinkPreservingOriginalLink() throws {
        let copiedReply = "https://example.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=1700000000.000100&cid=C0123ABCD"

        XCTAssertEqual(try slackThreadLink(fromClipboard: copiedReply), copiedReply)
        XCTAssertEqual(try slackThreadLink(fromClipboard: validLink), validLink)
    }

    func testAcceptsEnterpriseHostIDsAndTrimmedOriginalLink() throws {
        let enterprise = "https://example.enterprise.slack.com/archives/C0123ABCDEF/p1700000000123456?thread_ts=1700000000.000100&cid=G0123ABCD"
        let group = "https://example.slack.com/archives/G0123ABCD/p1700000000123456"
        let direct = "https://example.slack.com/archives/D0123ABCD/p1700000000123456"
        let replyWithoutChannelID = "https://example.slack.com/archives/C0123ABCD/p1700000000123456?thread_ts=1700000000.000100"
        let uppercaseHost = "https://EXAMPLE.slack.com/archives/C0123ABCD/p1700000000123456"
        let padded = " \t\r\n\(validLink)\n\r\t "

        XCTAssertEqual(try slackThreadLink(fromClipboard: enterprise), enterprise)
        XCTAssertEqual(try slackThreadLink(fromClipboard: group), group)
        XCTAssertEqual(try slackThreadLink(fromClipboard: direct), direct)
        XCTAssertEqual(try slackThreadLink(fromClipboard: replyWithoutChannelID), replyWithoutChannelID)
        XCTAssertEqual(try slackThreadLink(fromClipboard: uppercaseHost), uppercaseHost)
        XCTAssertEqual(try slackThreadLink(fromClipboard: padded), validLink)
    }

    func testEmptyClipboardIsReportedApartFromAnInvalidLink() {
        assertClipboardEmpty(nil)
        assertClipboardEmpty("")
        assertClipboardEmpty(" \t\r\n ")
    }

    func testClipboardMustHoldOnlyTheLink() {
        assertSlackLinkRejected("see \(validLink)")
        assertSlackLinkRejected("\(validLink) please")
        assertSlackLinkRejected("\(validLink)\n\(validLink)")
        assertSlackLinkRejected("<\(validLink)>")
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

    func testRejectsNonASCIIAndNonPrintableSlackLinkScalarsBeforeURLParsing() {
        let path = "/archives/C0123ABCD/p1700000000123456"
        let invalidLinks = [
            "https://ac\u{00AD}me.slack.com\(path)",
            "https://ac\u{200B}me.slack.com\(path)",
            "https://ac\u{FEFF}me.slack.com\(path)",
            "https://ac\u{FE00}me.slack.com\(path)",
            "https://ac\u{E0100}me.slack.com\(path)",
            "https://ac\u{007F}me.slack.com\(path)",
            "https://ａｃｍｅ.slack.com\(path)",
            "https://acme。slack.com\(path)",
            "https://𝐚𝐜𝐦𝐞.slack.com\(path)",
            "HTTPS://example.slack.com\(path)",
            "https://example.slack.com/archives/C0123ABCD/p170000000012345é",
            "https://example.slack.com\(path)?thread_ts=1700000000.00010é",
        ]

        for link in invalidLinks {
            assertSlackLinkRejected(link)
        }

        let variationSelectors = String(repeating: "\u{FE00}", count: 100)
        let hiddenPayload = "https://ac\(variationSelectors)me.slack.com\(path)"
        XCTAssertLessThanOrEqual(hiddenPayload.utf8.count, 512)
        assertSlackLinkRejected(hiddenPayload)
    }

    func testRejectsSlackLinkOver512UTF8BytesBeforeValidation() {
        // Valid Slack links cannot approach this size under the allowlist grammar.
        let overLimit = validLink + String(repeating: "é", count: 300)
        XCTAssertGreaterThan(overLimit.utf8.count, 512)
        XCTAssertThrowsError(try slackThreadLink(fromClipboard: overLimit)) { error in
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
            try slackThreadLink(fromClipboard: "https://\(label63).slack.com\(path)"),
            "https://\(label63).slack.com\(path)"
        )
        assertSlackLinkRejected("https://\(label64).slack.com\(path)")
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
                case .clipboardEmpty, .invalidSlackLink, .slackLinkTooLong,
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
                    clipboardText: validLink,
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
