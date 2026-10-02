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
            $0.warpHelperAvailable = false
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
        XCTAssertEqual(
            SetupWindowPresentationModel.make(from: stopped).problems.first?.copy,
            .cmuxNotRunning(.stable)
        )
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
        let configuredBaseDirectory = snapshot {
            $0.tools = .init(available: ["zoxide": false], executable: ["zoxide": false])
            $0.baseDirectory = .normalized("/example")
        }

        let critical = SetupWindowPresentationModel.make(from: noBaseDirectory).problems
        let warning = SetupWindowPresentationModel.make(from: configuredBaseDirectory).problems

        XCTAssertTrue(critical.contains {
            $0.severity == .error && $0.copy == .criticalToolUnavailable(name: "zoxide")
        })
        XCTAssertTrue(warning.contains {
            $0.severity == .warning && $0.copy == .toolUnavailable(name: "zoxide")
        })
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

    func testClaudeExecutableWarningIdentifiesSlackImpact() {
        let state = snapshot {
            $0.tools = .init(
                available: ["claude": true],
                executable: ["claude": false]
            )
        }

        XCTAssertTrue(SetupWindowPresentationModel.make(from: state).problems.contains {
            $0.copy == .claudeNotExecutableForSlack
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
    var warpHelperAvailable = true
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
            warpHelperAvailable: warpHelperAvailable,
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
