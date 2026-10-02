import Core
import Foundation

enum SetupWindowManifestStatus {
    case registered
    case notRegistered
    case wrongRelayPath
    case wrongExtensionID
}

enum SetupWindowExtensionFolderStatus {
    case present
    case missing
}

enum SetupWindowAppSocketStatus {
    case listening
    case unavailable
}

/// The normalized value is produced at the Settings boundary by Core. The presentation model
/// never normalizes, expands, validates, or reads the path itself.
enum SetupWindowBaseDirectoryStatus {
    case unconfigured
    case invalidStoredValue
    case normalized(String, directoryExists: Bool)

    var isConfigured: Bool {
        if case .normalized = self { return true }
        return false
    }
}

struct SetupWindowTerminalInstallation {
    let terminal: Terminal
    let isInstalled: Bool
}

struct SetupWindowToolResults {
    let available: [String: Bool]
    let executable: [String: Bool]

    init(available: [String: Bool], executable: [String: Bool]) {
        self.available = available
        self.executable = executable
    }

    init(_ result: ToolCheckResult) {
        available = result.available
        executable = result.executable
    }
}

enum SetupWindowOpeningReason {
    case claudeInputRejected(blocker: ClaudeInputBlocker, arrivalOrder: Int)
    case slackThreadRequestFailed(arrivalOrder: Int)

    var arrivalOrder: Int {
        switch self {
        case .claudeInputRejected(_, let arrivalOrder), .slackThreadRequestFailed(let arrivalOrder):
            return arrivalOrder
        }
    }
}

/// One immutable collection of observations for one presentation pass. Callers supply facts;
/// construction and presentation do not query AppKit, the filesystem, TCC, defaults, or sockets.
struct SetupWindowSnapshot {
    let manifest: SetupWindowManifestStatus
    let extensionFolder: SetupWindowExtensionFolderStatus
    let lastRequestAt: Date?
    let appSocket: SetupWindowAppSocketStatus
    let selectedTerminal: Terminal
    let terminalInstallations: [SetupWindowTerminalInstallation]
    let iTermAutomation: AutomationStatus?
    let cmuxStableSocket: CmuxSocketStatus?
    let cmuxNightlySocket: CmuxSocketStatus?
    let warpAccessibilityGranted: Bool
    let wezTermSessionAvailable: Bool
    let tools: SetupWindowToolResults?
    let baseDirectory: SetupWindowBaseDirectoryStatus
    let openingReasons: [SetupWindowOpeningReason]
    let slackRequestFailureIsActive: Bool
    let tabActivation: TabActivation
    let cmuxIdentityMode: String?
    let cmuxFixedName: String?
    let cmuxArrangement: String?
    let guideWasReopened: Bool

    init(
        manifest: SetupWindowManifestStatus = .registered,
        extensionFolder: SetupWindowExtensionFolderStatus = .present,
        lastRequestAt: Date? = nil,
        appSocket: SetupWindowAppSocketStatus = .listening,
        selectedTerminal: Terminal = .iterm,
        terminalInstallations: [SetupWindowTerminalInstallation] = [],
        iTermAutomation: AutomationStatus? = .granted,
        cmuxStableSocket: CmuxSocketStatus? = .reachable,
        cmuxNightlySocket: CmuxSocketStatus? = .reachable,
        warpAccessibilityGranted: Bool = true,
        wezTermSessionAvailable: Bool = true,
        tools: SetupWindowToolResults? = nil,
        baseDirectory: SetupWindowBaseDirectoryStatus = .unconfigured,
        openingReasons: [SetupWindowOpeningReason] = [],
        slackRequestFailureIsActive: Bool = false,
        tabActivation: TabActivation = .foreground,
        cmuxIdentityMode: String? = nil,
        cmuxFixedName: String? = nil,
        cmuxArrangement: String? = nil,
        guideWasReopened: Bool = false
    ) {
        self.manifest = manifest
        self.extensionFolder = extensionFolder
        self.lastRequestAt = lastRequestAt
        self.appSocket = appSocket
        self.selectedTerminal = selectedTerminal
        self.terminalInstallations = terminalInstallations
        self.iTermAutomation = iTermAutomation
        self.cmuxStableSocket = cmuxStableSocket
        self.cmuxNightlySocket = cmuxNightlySocket
        self.warpAccessibilityGranted = warpAccessibilityGranted
        self.wezTermSessionAvailable = wezTermSessionAvailable
        self.tools = tools
        self.baseDirectory = baseDirectory
        self.openingReasons = openingReasons
        self.slackRequestFailureIsActive = slackRequestFailureIsActive
        self.tabActivation = tabActivation
        self.cmuxIdentityMode = cmuxIdentityMode
        self.cmuxFixedName = cmuxFixedName
        self.cmuxArrangement = cmuxArrangement
        self.guideWasReopened = guideWasReopened
    }

    func isInstalled(_ terminal: Terminal) -> Bool? {
        terminalInstallations.first { $0.terminal == terminal }?.isInstalled
    }

    func cmuxSocketStatus(for channel: CmuxChannel) -> CmuxSocketStatus? {
        switch channel {
        case .stable: return cmuxStableSocket
        case .nightly: return cmuxNightlySocket
        }
    }

    func isClaudeBlockerActive(_ blocker: ClaudeInputBlocker) -> Bool {
        switch blocker {
        case .warpAccessibility:
            return !warpAccessibilityGranted
        case .warpHelperUnavailable:
            return true
        case .wezTermSessionUnavailable:
            return false
        }
    }
}

enum SetupWindowProblemSeverity: Equatable {
    case error
    case warning
}

enum SetupWindowAutomationProblem: Equatable {
    case denied
    case notDetermined
    case targetNotRunning
    case unknown(Int32)
}

/// A typed catalogue key with its interpolation arguments. These cases deliberately contain no
/// localized text so the same presentation can be rendered after a language rebuild.
enum SetupWindowProblemCopy: Equatable {
    case claudeInputRejected(ClaudeInputBlocker)
    case slackThreadRequestFailed
    case manifestNotRegistered
    case manifestWrongRelayPath
    case manifestWrongExtensionID
    case extensionFolderMissingAfterRequest
    case appSocketUnavailable
    case selectedTerminalNotInstalled(Terminal)
    case iTermAutomation(SetupWindowAutomationProblem)
    case cmuxNotInstalled(CmuxChannel)
    case cmuxNotRunning(CmuxChannel)
    case cmuxAccessDenied(CmuxChannel)
    case cmuxCheckFailed(CmuxChannel, detail: String)
    case warpAccessibilityRequired
    case toolUnavailable(name: String)
    case criticalToolUnavailable(name: String)
    case claudeUnavailable
    case claudeNotExecutable
}

struct SetupWindowProblem: Equatable {
    let severity: SetupWindowProblemSeverity
    let copy: SetupWindowProblemCopy
}

enum SetupWindowConnectionSentence: Equatable {
    case waitingForFirstRequest
    case requestRecorded(at: Date)
}

enum SetupWindowBaseDirectoryNotice: Equatable {
    case notConfigured
    case storedValueInvalid
    case directoryMissing

    var severity: SetupWindowProblemSeverity {
        switch self {
        case .directoryMissing: return .warning
        case .notConfigured, .storedValueInvalid: return .error
        }
    }
}

enum SetupWindowPreviewDestination: Equatable {
    case newTab
    case newWorkspace
}

enum SetupWindowFrontmostScreen: Equatable {
    case newTerminalSession
    case existingScreen
}

struct SetupWindowGeneralPreview: Equatable {
    let terminal: Terminal
    let destination: SetupWindowPreviewDestination
    let frontmostScreen: SetupWindowFrontmostScreen
    let effectSentence: SetupWindowEffectSentence
}

enum SetupWindowWorkspacePreviewIdentity: Equatable {
    case createNewWorkspace
    case findNamedWorkspace
}

enum SetupWindowGitHubPreviewDestination: Equatable {
    case newTabPerRow
    case cmux(
        arrangement: CmuxPlacementArrangement,
        identity: SetupWindowWorkspacePreviewIdentity,
        preservesExistingPaneAndTab: Bool
    )
}

struct SetupWindowGitHubPreview: Equatable {
    let rowNumbers: [Int]
    let destination: SetupWindowGitHubPreviewDestination
    let effectSentence: SetupWindowEffectSentence
}

enum SetupWindowSlackPreviewFirstMessage: Equatable {
    case slackLinkThenInstruction
}

struct SetupWindowSlackPreview: Equatable {
    let usesWorkingFolder: Bool
    let firstMessage: SetupWindowSlackPreviewFirstMessage
    let requiresSlackMCP: Bool
    let effectSentence: SetupWindowEffectSentence
}

enum SetupWindowEffectSentence: Equatable {
    case general(
        terminal: Terminal,
        destination: SetupWindowPreviewDestination,
        frontmostScreen: SetupWindowFrontmostScreen
    )
    case githubRowsOpenNewTabs(rowNumbers: [Int])
    case githubCmuxBatch(
        rowNumbers: [Int],
        arrangement: CmuxPlacementArrangement,
        identity: CmuxPlacementIdentityMode
    )
    case slackClaudeInWorkingFolder(
        firstMessage: SetupWindowSlackPreviewFirstMessage,
        requiresSlackMCP: Bool
    )
}

struct SetupWindowPreviewModels: Equatable {
    let general: SetupWindowGeneralPreview
    let github: SetupWindowGitHubPreview
    let slack: SetupWindowSlackPreview
}

struct SetupWindowPresentation {
    let problems: [SetupWindowProblem]
    let showsFirstInstallChecklist: Bool
    let connectionSentence: SetupWindowConnectionSentence
    let baseDirectoryNotice: SetupWindowBaseDirectoryNotice?
    let slackToolbarHasFailureDot: Bool
    let previews: SetupWindowPreviewModels
}

enum SetupWindowPresentationModel {
    static func make(from snapshot: SetupWindowSnapshot) -> SetupWindowPresentation {
        let previews = previewModels(from: snapshot)
        let baseDirectoryNotice: SetupWindowBaseDirectoryNotice?
        switch snapshot.baseDirectory {
        case .unconfigured:
            baseDirectoryNotice = snapshot.tools?.available["zoxide"] == false ? .notConfigured : nil
        case .invalidStoredValue:
            baseDirectoryNotice = .storedValueInvalid
        case .normalized(_, let directoryExists):
            baseDirectoryNotice = directoryExists ? nil : .directoryMissing
        }

        return SetupWindowPresentation(
            problems: problems(from: snapshot),
            showsFirstInstallChecklist: snapshot.lastRequestAt == nil || snapshot.guideWasReopened,
            connectionSentence: snapshot.lastRequestAt.map {
                .requestRecorded(at: $0)
            } ?? .waitingForFirstRequest,
            baseDirectoryNotice: baseDirectoryNotice,
            slackToolbarHasFailureDot: snapshot.slackRequestFailureIsActive,
            previews: previews
        )
    }

    private static func problems(from snapshot: SetupWindowSnapshot) -> [SetupWindowProblem] {
        let opening = snapshot.openingReasons.enumerated()
            .sorted { left, right in
                if left.element.arrivalOrder == right.element.arrivalOrder {
                    return left.offset > right.offset
                }
                return left.element.arrivalOrder > right.element.arrivalOrder
            }
            .compactMap { _, reason -> SetupWindowProblem? in
                switch reason {
                case .claudeInputRejected(let blocker, _):
                    guard blocker.setupWindowCanHelp, snapshot.isClaudeBlockerActive(blocker) else {
                        return nil
                    }
                    return SetupWindowProblem(
                        severity: .warning,
                        copy: .claudeInputRejected(blocker)
                    )
                case .slackThreadRequestFailed:
                    guard snapshot.slackRequestFailureIsActive else { return nil }
                    return SetupWindowProblem(severity: .error, copy: .slackThreadRequestFailed)
                }
            }

        var current: [SetupWindowProblem] = []
        switch snapshot.manifest {
        case .registered:
            break
        case .notRegistered:
            current.append(.init(severity: .error, copy: .manifestNotRegistered))
        case .wrongRelayPath:
            current.append(.init(severity: .warning, copy: .manifestWrongRelayPath))
        case .wrongExtensionID:
            current.append(.init(severity: .warning, copy: .manifestWrongExtensionID))
        }

        if snapshot.lastRequestAt != nil, snapshot.extensionFolder == .missing {
            current.append(.init(severity: .error, copy: .extensionFolderMissingAfterRequest))
        }
        if snapshot.appSocket == .unavailable {
            current.append(.init(severity: .error, copy: .appSocketUnavailable))
        }

        if snapshot.isInstalled(snapshot.selectedTerminal) == false {
            current.append(.init(
                severity: .error,
                copy: .selectedTerminalNotInstalled(snapshot.selectedTerminal)
            ))
        }

        appendTerminalProblem(from: snapshot, to: &current)
        appendToolProblems(from: snapshot, to: &current)

        return opening + current.filter { $0.severity == .error }
            + current.filter { $0.severity == .warning }
    }

    private static func appendTerminalProblem(
        from snapshot: SetupWindowSnapshot, to problems: inout [SetupWindowProblem]
    ) {
        switch snapshot.selectedTerminal {
        case .iterm:
            guard snapshot.isInstalled(.iterm) != false,
                  let status = snapshot.iTermAutomation else { return }
            let issue: SetupWindowAutomationProblem
            switch status {
            case .granted: return
            case .denied:
                issue = .denied
                problems.append(.init(severity: .error, copy: .iTermAutomation(issue)))
                return
            case .notDetermined: issue = .notDetermined
            case .targetNotRunning: issue = .targetNotRunning
            case .unknown(let code): issue = .unknown(code)
            }
            problems.append(.init(severity: .warning, copy: .iTermAutomation(issue)))
        case .wezterm:
            break
        case .warp:
            guard !snapshot.warpAccessibilityGranted,
                  !snapshot.openingReasons.contains(where: {
                      if case .claudeInputRejected(.warpAccessibility, _) = $0 { return true }
                      return false
                  }) else { return }
            problems.append(.init(severity: .warning, copy: .warpAccessibilityRequired))
        case .cmux, .cmuxNightly:
            guard let channel = snapshot.selectedTerminal.cmuxChannel,
                  let status = snapshot.cmuxSocketStatus(for: channel) else { return }
            switch status {
            case .reachable:
                break
            case .notInstalled:
                problems.append(.init(severity: .error, copy: .cmuxNotInstalled(channel)))
            case .notRunning:
                problems.append(.init(severity: .warning, copy: .cmuxNotRunning(channel)))
            case .denied:
                problems.append(.init(severity: .error, copy: .cmuxAccessDenied(channel)))
            case .failed(let detail):
                problems.append(.init(
                    severity: .warning,
                    copy: .cmuxCheckFailed(channel, detail: detail)
                ))
            }
        }
    }

    private static func appendToolProblems(
        from snapshot: SetupWindowSnapshot, to problems: inout [SetupWindowProblem]
    ) {
        guard let tools = snapshot.tools else { return }
        for name in checkedTools where tools.available[name] == false {
            if name == "claude" {
                problems.append(.init(severity: .warning, copy: .claudeUnavailable))
            } else {
                let critical = toolIsCritical(
                    name,
                    baseDirectoryConfigured: snapshot.baseDirectory.isConfigured
                )
                problems.append(.init(
                    severity: critical ? .error : .warning,
                    copy: critical
                        ? .criticalToolUnavailable(name: name)
                        : .toolUnavailable(name: name)
                ))
            }
        }
        if tools.available["claude"] == true, tools.executable["claude"] == false {
            problems.append(.init(severity: .warning, copy: .claudeNotExecutable))
        }
    }

    private static func previewModels(from snapshot: SetupWindowSnapshot) -> SetupWindowPreviewModels {
        let destination: SetupWindowPreviewDestination =
            snapshot.selectedTerminal.cmuxChannel == nil ? .newTab : .newWorkspace
        let frontmost: SetupWindowFrontmostScreen =
            snapshot.selectedTerminal == .warp || snapshot.tabActivation == .foreground
                ? .newTerminalSession
                : .existingScreen
        let general = SetupWindowGeneralPreview(
            terminal: snapshot.selectedTerminal,
            destination: destination,
            frontmostScreen: frontmost,
            effectSentence: .general(
                terminal: snapshot.selectedTerminal,
                destination: destination,
                frontmostScreen: frontmost
            )
        )

        let rowNumbers = [1, 2, 3]
        let github: SetupWindowGitHubPreview
        if snapshot.selectedTerminal.cmuxChannel == nil {
            github = SetupWindowGitHubPreview(
                rowNumbers: rowNumbers,
                destination: .newTabPerRow,
                effectSentence: .githubRowsOpenNewTabs(rowNumbers: rowNumbers)
            )
        } else {
            let preset = CmuxPlacementPreset.parse(
                rawIdentityMode: snapshot.cmuxIdentityMode,
                rawFixedName: snapshot.cmuxFixedName,
                rawArrangement: snapshot.cmuxArrangement
            )
            let identity: SetupWindowWorkspacePreviewIdentity
            switch preset.effectiveIdentityMode {
            case .alwaysNew:
                identity = .createNewWorkspace
            case .fixedName:
                identity = .findNamedWorkspace
            }
            let preservesExistingPaneAndTab = identity == .findNamedWorkspace
            github = SetupWindowGitHubPreview(
                rowNumbers: rowNumbers,
                destination: .cmux(
                    arrangement: preset.arrangement,
                    identity: identity,
                    preservesExistingPaneAndTab: preservesExistingPaneAndTab
                ),
                effectSentence: .githubCmuxBatch(
                    rowNumbers: rowNumbers,
                    arrangement: preset.arrangement,
                    identity: preset.effectiveIdentityMode
                )
            )
        }

        let firstMessage = SetupWindowSlackPreviewFirstMessage.slackLinkThenInstruction
        let slack = SetupWindowSlackPreview(
            usesWorkingFolder: true,
            firstMessage: firstMessage,
            requiresSlackMCP: true,
            effectSentence: .slackClaudeInWorkingFolder(
                firstMessage: firstMessage,
                requiresSlackMCP: true
            )
        )
        return SetupWindowPreviewModels(general: general, github: github, slack: slack)
    }
}
