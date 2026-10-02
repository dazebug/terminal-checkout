import Core
import XCTest
@testable import App

final class SetupWindowPresentationTests: XCTestCase {
    private func snapshot(
        selectedTerminal: Terminal = .iterm,
        changes: (inout SetupWindowSnapshotValues) -> Void = { _ in }
    ) -> SetupWindowSnapshot {
        var values = SetupWindowSnapshotValues(selectedTerminal: selectedTerminal)
        changes(&values)
        return values.makeSnapshot()
    }

    func testOpeningReasonsComeFirstAndNewestReasonComesFirst() {
        let state = snapshot(selectedTerminal: .warp) {
            $0.slackRequestFailureIsActive = true
            $0.openingReasons = [
                .claudeInputRejected(blocker: .warpHelperUnavailable, arrivalOrder: 1),
                .slackThreadRequestFailed(arrivalOrder: 2),
            ]
            $0.manifest = .notRegistered
        }

        let problems = SetupWindowPresentationModel.make(from: state).problems

        XCTAssertEqual(problems[0].copy, .slackThreadRequestFailed)
        XCTAssertEqual(problems[1].copy, .claudeInputRejected(.warpHelperUnavailable))
        XCTAssertEqual(problems[2].copy, .manifestNotRegistered)
    }

    func testResolvedClaudeOpeningReasonIsRemoved() {
        let state = snapshot(selectedTerminal: .warp) {
            $0.warpAccessibilityGranted = true
            $0.openingReasons = [
                .claudeInputRejected(blocker: .warpAccessibility, arrivalOrder: 1),
            ]
        }

        let problems = SetupWindowPresentationModel.make(from: state).problems

        XCTAssertFalse(problems.contains { $0.copy == .claudeInputRejected(.warpAccessibility) })
    }

    func testWarpHelperOpeningReasonRemainsVisibleUntilReasonIsCleared() {
        let open = snapshot(selectedTerminal: .iterm) {
            $0.openingReasons = [
                .claudeInputRejected(blocker: .warpHelperUnavailable, arrivalOrder: 1),
            ]
        }
        let closed = snapshot(selectedTerminal: .iterm)

        XCTAssertTrue(SetupWindowPresentationModel.make(from: open).problems.contains {
            $0.copy == .claudeInputRejected(.warpHelperUnavailable)
        })
        XCTAssertFalse(SetupWindowPresentationModel.make(from: closed).problems.contains {
            $0.copy == .claudeInputRejected(.warpHelperUnavailable)
        })
    }

    func testWezTermSessionBlockerDoesNotCreateSetupWindowProblem() {
        let state = snapshot(selectedTerminal: .wezterm) {
            $0.openingReasons = [
                .claudeInputRejected(blocker: .wezTermSessionUnavailable, arrivalOrder: 1),
            ]
        }

        XCTAssertFalse(SetupWindowPresentationModel.make(from: state).problems.contains {
            $0.copy == .claudeInputRejected(.wezTermSessionUnavailable)
        })
    }

    func testErrorsPrecedeWarningsAfterOpeningReasons() {
        let state = snapshot(selectedTerminal: .warp) {
            $0.manifest = .notRegistered
            $0.warpAccessibilityGranted = false
        }

        let problems = SetupWindowPresentationModel.make(from: state).problems

        XCTAssertEqual(problems.map(\.severity), [.error, .warning])
        XCTAssertEqual(problems.first?.copy, .manifestNotRegistered)
        XCTAssertEqual(problems.last?.copy, .warpAccessibilityRequired)
    }

    func testCmuxAccessDeniedAndNotRunningRemainDifferentProblems() {
        let denied = snapshot(selectedTerminal: .cmux) {
            $0.terminalInstallations = [.init(terminal: .cmux, isInstalled: true)]
            $0.cmuxStableSocket = .denied
        }
        let stopped = snapshot(selectedTerminal: .cmux) {
            $0.terminalInstallations = [.init(terminal: .cmux, isInstalled: true)]
            $0.cmuxStableSocket = .notRunning
        }

        XCTAssertEqual(
            SetupWindowPresentationModel.make(from: denied).problems.first?.copy,
            .cmuxAccessDenied(.stable)
        )
        XCTAssertEqual(SetupWindowPresentationModel.make(from: denied).problems.first?.severity, .error)
        XCTAssertEqual(
            SetupWindowPresentationModel.make(from: stopped).problems.first?.copy,
            .cmuxNotRunning(.stable)
        )
        XCTAssertEqual(SetupWindowPresentationModel.make(from: stopped).problems.first?.severity, .warning)
    }

    func testCmuxNotInstalledIsAnErrorAndCheckFailureIsAWarning() {
        let notInstalled = snapshot(selectedTerminal: .cmux) {
            $0.cmuxStableSocket = .notInstalled
        }
        let failed = snapshot(selectedTerminal: .cmux) {
            $0.cmuxStableSocket = .failed("unexpected response")
        }

        XCTAssertEqual(SetupWindowPresentationModel.make(from: notInstalled).problems.first, .init(
            severity: .error,
            copy: .cmuxNotInstalled(.stable)
        ))
        XCTAssertEqual(SetupWindowPresentationModel.make(from: failed).problems.first, .init(
            severity: .warning,
            copy: .cmuxCheckFailed(.stable, detail: "unexpected response")
        ))
    }

    func testSelectedTerminalNotInstalledIsAnError() {
        let state = snapshot {
            $0.terminalInstallations = [.init(terminal: .iterm, isInstalled: false)]
        }

        XCTAssertEqual(SetupWindowPresentationModel.make(from: state).problems.first, .init(
            severity: .error,
            copy: .selectedTerminalNotInstalled(.iterm)
        ))
    }

    func testDeniedITermAutomationIsAnError() {
        let state = snapshot {
            $0.iTermAutomation = .denied
        }

        XCTAssertEqual(SetupWindowPresentationModel.make(from: state).problems.first, .init(
            severity: .error,
            copy: .iTermAutomation(.denied)
        ))
    }

    func testUndeterminedOrStoppedITermAutomationRemainsAWarning() {
        let cases: [(AutomationStatus, SetupWindowAutomationProblem)] = [
            (.notDetermined, .notDetermined),
            (.targetNotRunning, .targetNotRunning),
            (.unknown(-1), .unknown(-1)),
        ]
        for (status, issue) in cases {
            let state = snapshot { $0.iTermAutomation = status }
            let problem = SetupWindowPresentationModel.make(from: state).problems.first

            XCTAssertEqual(problem?.severity, .warning)
            XCTAssertEqual(problem?.copy, .iTermAutomation(issue))
        }
    }

    func testUnexpectedManifestPathAndExtensionIDRemainWarnings() {
        for manifest in [SetupWindowManifestStatus.wrongRelayPath, .wrongExtensionID] {
            let state = snapshot { $0.manifest = manifest }
            let problem = SetupWindowPresentationModel.make(from: state).problems.first

            XCTAssertEqual(problem?.severity, .warning)
            XCTAssertTrue(
                problem?.copy == .manifestWrongRelayPath || problem?.copy == .manifestWrongExtensionID
            )
        }
    }

    func testMissingExtensionFolderIsAProblemOnlyAfterARequestWasRecorded() {
        let afterRequest = snapshot {
            $0.extensionFolder = .missing
            $0.lastRequestAt = Date(timeIntervalSince1970: 10)
        }
        let beforeRequest = snapshot {
            $0.extensionFolder = .missing
        }

        XCTAssertTrue(
            SetupWindowPresentationModel.make(from: afterRequest).problems
                .contains { $0.copy == .extensionFolderMissingAfterRequest }
        )
        XCTAssertFalse(
            SetupWindowPresentationModel.make(from: beforeRequest).problems
                .contains { $0.copy == .extensionFolderMissingAfterRequest }
        )
    }

    func testFirstInstallChecklistDependsOnRequestEvidenceOrReopenAction() {
        let firstInstall = snapshot()
        let requestRecorded = snapshot {
            $0.lastRequestAt = Date(timeIntervalSince1970: 20)
        }
        let reopened = snapshot {
            $0.lastRequestAt = Date(timeIntervalSince1970: 20)
            $0.guideWasReopened = true
        }

        XCTAssertTrue(SetupWindowPresentationModel.make(from: firstInstall).showsFirstInstallChecklist)
        XCTAssertFalse(SetupWindowPresentationModel.make(from: requestRecorded).showsFirstInstallChecklist)
        XCTAssertTrue(SetupWindowPresentationModel.make(from: reopened).showsFirstInstallChecklist)
    }

    func testZoxideIsCriticalOnlyWithoutConfiguredBaseDirectory() {
        let noBaseDirectory = snapshot {
            $0.tools = .init(available: ["zoxide": false], executable: ["zoxide": false])
            $0.baseDirectory = .unconfigured
        }
        let usableBaseDirectory = snapshot {
            $0.tools = .init(available: ["zoxide": false], executable: ["zoxide": false])
            $0.baseDirectory = .normalized("/example", directoryExists: true)
        }
        let critical = SetupWindowPresentationModel.make(from: noBaseDirectory).problems
        let warning = SetupWindowPresentationModel.make(from: usableBaseDirectory).problems

        XCTAssertTrue(critical.contains {
            $0.severity == .error && $0.copy == .criticalToolUnavailable(name: "zoxide")
        })
        XCTAssertTrue(warning.contains {
            $0.severity == .warning && $0.copy == .toolUnavailable(name: "zoxide")
        })
    }

    func testMissingConfiguredBaseDirectoryKeepsZoxideWarningAndDirectoryNotice() {
        let state = snapshot {
            $0.tools = .init(available: ["zoxide": false], executable: ["zoxide": false])
            $0.baseDirectory = .normalized("/example", directoryExists: false)
        }
        let presentation = SetupWindowPresentationModel.make(from: state)

        XCTAssertTrue(presentation.problems.contains {
            $0.severity == .warning && $0.copy == .toolUnavailable(name: "zoxide")
        })
        XCTAssertFalse(presentation.problems.contains {
            $0.severity == .error && $0.copy == .criticalToolUnavailable(name: "zoxide")
        })
        XCTAssertEqual(presentation.baseDirectoryNotice, .directoryMissing)
        XCTAssertEqual(presentation.baseDirectoryNotice?.severity, .warning)
    }

    func testEmptyBaseDirectoryNeedsNoNoticeWhenZoxideIsAvailable() {
        let state = snapshot {
            $0.tools = .init(available: ["zoxide": true], executable: ["zoxide": true])
            $0.baseDirectory = .unconfigured
        }

        XCTAssertNil(SetupWindowPresentationModel.make(from: state).baseDirectoryNotice)
    }

    func testEmptyBaseDirectoryShowsErrorNoticeWhenZoxideIsUnavailable() {
        let state = snapshot {
            $0.tools = .init(available: ["zoxide": false], executable: ["zoxide": false])
            $0.baseDirectory = .unconfigured
        }
        let notice = SetupWindowPresentationModel.make(from: state).baseDirectoryNotice

        XCTAssertEqual(notice, .notConfigured)
        XCTAssertEqual(notice?.severity, .error)
    }

    func testEmptyBaseDirectoryDoesNotAssumeZoxideIsMissingBeforeToolCheck() {
        let state = snapshot { $0.baseDirectory = .unconfigured }

        XCTAssertNil(SetupWindowPresentationModel.make(from: state).baseDirectoryNotice)
    }

    func testExistingNormalizedBaseDirectoryNeedsNoNotice() {
        let state = snapshot { $0.baseDirectory = .normalized("/example", directoryExists: true) }

        XCTAssertNil(SetupWindowPresentationModel.make(from: state).baseDirectoryNotice)
    }

    func testMissingNormalizedBaseDirectoryShowsWarningNotice() {
        let state = snapshot { $0.baseDirectory = .normalized("/example", directoryExists: false) }
        let notice = SetupWindowPresentationModel.make(from: state).baseDirectoryNotice

        XCTAssertEqual(notice, .directoryMissing)
        XCTAssertEqual(notice?.severity, .warning)
    }

    func testInvalidStoredBaseDirectoryShowsErrorNotice() {
        let state = snapshot { $0.baseDirectory = .invalidStoredValue }
        let notice = SetupWindowPresentationModel.make(from: state).baseDirectoryNotice

        XCTAssertEqual(notice, .storedValueInvalid)
        XCTAssertEqual(notice?.severity, .error)
    }

    func testWorkspacePerItemIgnoresStoredNamedWorkspaceIdentity() {
        let state = snapshot(selectedTerminal: .cmux) {
            $0.cmuxIdentityMode = "fixed-name"
            $0.cmuxFixedName = "Design"
            $0.cmuxArrangement = CmuxPlacementArrangement.workspacePerItem.rawValue
        }

        let preview = SetupWindowPresentationModel.make(from: state).previews.github

        XCTAssertEqual(preview.destination, .cmux(
            arrangement: .workspacePerItem,
            identity: .createNewWorkspace,
            preservesExistingPaneAndTab: false
        ))
        XCTAssertEqual(preview.effectSentence, .githubCmuxBatch(
            rowNumbers: [1, 2, 3],
            arrangement: .workspacePerItem,
            identity: .alwaysNew
        ))
    }

    func testNamedWorkspaceWithEmptyNameUsesNewWorkspace() {
        let state = snapshot(selectedTerminal: .cmux) {
            $0.cmuxIdentityMode = "fixed-name"
            $0.cmuxFixedName = ""
            $0.cmuxArrangement = CmuxPlacementArrangement.panePerItem.rawValue
        }

        let preview = SetupWindowPresentationModel.make(from: state).previews.github

        XCTAssertEqual(preview.destination, .cmux(
            arrangement: .panePerItem,
            identity: .createNewWorkspace,
            preservesExistingPaneAndTab: false
        ))
    }

    func testNamedWorkspacePreviewPreservesTheExistingPaneAndTab() {
        let state = snapshot(selectedTerminal: .cmux) {
            $0.cmuxIdentityMode = "fixed-name"
            $0.cmuxFixedName = "Design"
            $0.cmuxArrangement = CmuxPlacementArrangement.panePerItem.rawValue
        }

        let preview = SetupWindowPresentationModel.make(from: state).previews.github

        XCTAssertEqual(preview.destination, .cmux(
            arrangement: .panePerItem,
            identity: .findNamedWorkspace,
            preservesExistingPaneAndTab: true
        ))
        XCTAssertEqual(preview.rowNumbers, [1, 2, 3])
    }

    func testWarpKeepsTheTerminalInFrontEvenWhenStoredChoiceIsBackground() {
        let state = snapshot(selectedTerminal: .warp) {
            $0.tabActivation = .background
        }

        let preview = SetupWindowPresentationModel.make(from: state).previews.general

        XCTAssertEqual(preview.destination, .newTab)
        XCTAssertEqual(preview.frontmostScreen, .newTerminalSession)
        XCTAssertEqual(preview.effectSentence, .general(
            terminal: .warp,
            destination: .newTab,
            frontmostScreen: .newTerminalSession
        ))
    }

    func testNonCmuxGitHubPreviewUsesOneNewTabPerExampleRow() {
        let preview = SetupWindowPresentationModel.make(from: snapshot(selectedTerminal: .iterm))
            .previews.github

        XCTAssertEqual(preview.destination, .newTabPerRow)
        XCTAssertEqual(preview.rowNumbers, [1, 2, 3])
        XCTAssertEqual(preview.effectSentence, .githubRowsOpenNewTabs(rowNumbers: [1, 2, 3]))
    }

    func testSlackPreviewUsesSymbolicFolderAndSlackLinkThenInstruction() {
        let preview = SetupWindowPresentationModel.make(from: snapshot()).previews.slack

        XCTAssertTrue(preview.usesWorkingFolder)
        XCTAssertEqual(preview.firstMessage, .slackLinkThenInstruction)
        XCTAssertTrue(preview.requiresSlackMCP)
        XCTAssertEqual(preview.effectSentence, .slackClaudeInWorkingFolder(
            firstMessage: .slackLinkThenInstruction,
            requiresSlackMCP: true
        ))
    }

    func testSuccessfulSlackRequestClearsOpeningFailureAndToolbarDot() {
        let state = snapshot {
            $0.slackRequestFailureIsActive = false
            $0.openingReasons = [.slackThreadRequestFailed(arrivalOrder: 1)]
        }

        let presentation = SetupWindowPresentationModel.make(from: state)

        XCTAssertFalse(presentation.slackToolbarHasFailureDot)
        XCTAssertFalse(presentation.problems.contains { $0.copy == .slackThreadRequestFailed })
    }

    func testClaudeUnavailableWarningUsesSharedImpactIdentifier() {
        let state = snapshot {
            $0.tools = .init(available: ["claude": false], executable: ["claude": false])
        }

        XCTAssertTrue(SetupWindowPresentationModel.make(from: state).problems.contains {
            $0.copy == .claudeUnavailable
        })
    }

    func testClaudeExecutableWarningUsesSharedImpactIdentifier() {
        let state = snapshot {
            $0.tools = .init(
                available: ["claude": true],
                executable: ["claude": false]
            )
        }

        XCTAssertTrue(SetupWindowPresentationModel.make(from: state).problems.contains {
            $0.copy == .claudeNotExecutable
        })
    }
}

private struct SetupWindowSnapshotValues {
    var manifest: SetupWindowManifestStatus = .registered
    var extensionFolder: SetupWindowExtensionFolderStatus = .present
    var lastRequestAt: Date?
    var appSocket: SetupWindowAppSocketStatus = .listening
    let selectedTerminal: Terminal
    var terminalInstallations: [SetupWindowTerminalInstallation] = []
    var iTermAutomation: AutomationStatus? = .granted
    var cmuxStableSocket: CmuxSocketStatus? = .reachable
    var cmuxNightlySocket: CmuxSocketStatus? = .reachable
    var warpAccessibilityGranted = true
    var wezTermSessionAvailable = true
    var tools: SetupWindowToolResults?
    var baseDirectory: SetupWindowBaseDirectoryStatus = .unconfigured
    var openingReasons: [SetupWindowOpeningReason] = []
    var slackRequestFailureIsActive = false
    var tabActivation: TabActivation = .foreground
    var cmuxIdentityMode: String?
    var cmuxFixedName: String?
    var cmuxArrangement: String?
    var guideWasReopened = false

    init(selectedTerminal: Terminal) {
        self.selectedTerminal = selectedTerminal
    }

    func makeSnapshot() -> SetupWindowSnapshot {
        SetupWindowSnapshot(
            manifest: manifest,
            extensionFolder: extensionFolder,
            lastRequestAt: lastRequestAt,
            appSocket: appSocket,
            selectedTerminal: selectedTerminal,
            terminalInstallations: terminalInstallations,
            iTermAutomation: iTermAutomation,
            cmuxStableSocket: cmuxStableSocket,
            cmuxNightlySocket: cmuxNightlySocket,
            warpAccessibilityGranted: warpAccessibilityGranted,
            wezTermSessionAvailable: wezTermSessionAvailable,
            tools: tools,
            baseDirectory: baseDirectory,
            openingReasons: openingReasons,
            slackRequestFailureIsActive: slackRequestFailureIsActive,
            tabActivation: tabActivation,
            cmuxIdentityMode: cmuxIdentityMode,
            cmuxFixedName: cmuxFixedName,
            cmuxArrangement: cmuxArrangement,
            guideWasReopened: guideWasReopened
        )
    }
}
