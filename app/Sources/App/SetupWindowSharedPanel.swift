import AppKit
import Core
import Foundation

enum SetupWindowSharedPanelAction: String, CaseIterable, Hashable {
    case registerManifest
    case installInChrome
    case requestPermission
    case openAutomationSettings
    case requestAccessibility
    case openAccessibilitySettings
    case openCmuxConfig
    case refreshCmuxStatus
    case restartApp
    case openTerminalSettings
    case openSlackSettings
    case openBaseDirectorySettings
    case showZoxideInstallHelp
    case showGhInstallHelp
    case showClaudeInstallHelp
    case showAppInstallHelp
    case dismissSetupGuide
}

func setupWindowSharedPanelRole(
    _ action: Selector, _ qualifier: String? = nil
) -> NSUserInterfaceItemIdentifier {
    NSUserInterfaceItemIdentifier(
        ( ["control", "\(action)"] + [qualifier].compactMap { $0 } ).joined(separator: ".")
    )
}

struct SetupWindowSharedPanelButtonModel {
    let title: String
    let action: SetupWindowSharedPanelAction
}

struct SetupWindowSharedPanelBlockCopy {
    let title: String
    let paragraphs: [String]
    let effects: [String]
    let buttons: [SetupWindowSharedPanelButtonModel]
}

final class SetupWindowSharedPanel: NSView {
    let presentation: SetupWindowPresentation
    private let manifest: SetupWindowManifestStatus
    private let extensionFolder: SetupWindowExtensionFolderStatus
    private let slackFailureDetail: String?
    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowSharedPanelAction: Selector]
    private let contentStack = NSStackView()

    private(set) var problemBlockViews: [SetupWindowProblemBlockView] = []
    private(set) var installChecklistView: SetupWindowInstallChecklistView?

    init(
        presentation: SetupWindowPresentation,
        manifest: SetupWindowManifestStatus,
        extensionFolder: SetupWindowExtensionFolderStatus,
        installStepsExpanded: Bool = false,
        installFeedback: String? = nil,
        slackFailureDetail: String? = nil,
        target: AnyObject?,
        selectors: [SetupWindowSharedPanelAction: Selector]
    ) {
        precondition(
            SetupWindowSharedPanelAction.allCases.allSatisfy { selectors[$0] != nil },
            "the shared panel needs a selector for every action it can present"
        )
        self.presentation = presentation
        self.manifest = manifest
        self.extensionFolder = extensionFolder
        self.slackFailureDetail = slackFailureDetail
        self.actionTarget = target
        self.selectors = selectors
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 720),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let visibleProblems = presentation.problems.filter { problem in
            guard presentation.showsFirstInstallChecklist else { return true }
            switch problem.copy {
            case .manifestNotRegistered, .manifestWrongRelayPath, .manifestWrongExtensionID:
                return false // The checklist's Native Host step already shows this state and action.
            default:
                return true
            }
        }
        problemBlockViews = visibleProblems.map { problem in
            let copy = Self.copy(
                for: problem,
                manifest: manifest,
                slackFailureDetail: slackFailureDetail
            )
            return SetupWindowProblemBlockView(
                problem: problem,
                roleQualifier: Self.roleQualifier(for: problem.copy),
                copy: copy,
                target: target,
                selectors: selectors
            )
        }

        let openingReasonBlocks = zip(visibleProblems, problemBlockViews)
            .filter { $0.0.isOpeningReason }
            .map(\.1)
        let remainingProblemBlocks = zip(visibleProblems, problemBlockViews)
            .filter { !$0.0.isOpeningReason }
            .map(\.1)
        for block in openingReasonBlocks {
            addProblemBlock(block)
        }

        if presentation.showsFirstInstallChecklist {
            let checklist = SetupWindowInstallChecklistView(
                manifest: manifest,
                extensionFolder: extensionFolder,
                requestRecorded: Self.hasRequestRecord(presentation),
                guideStepsExpanded: installStepsExpanded,
                installFeedback: installFeedback,
                target: target,
                selectors: selectors
            )
            installChecklistView = checklist
            contentStack.addArrangedSubview(checklist)
            checklist.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        for block in remainingProblemBlocks {
            addProblemBlock(block)
        }

        isHidden = contentStack.arrangedSubviews.isEmpty
        contentStack.isHidden = isHidden
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Called by the existing Chrome-install action after it prepares the extension copy and opens
    /// chrome://extensions. The controller remains the action target; this only reveals the
    /// instructions and feedback in the retained panel.
    func showChromeInstallationSteps() {
        installChecklistView?.showChromeInstallationSteps()
    }

    private func addProblemBlock(_ block: SetupWindowProblemBlockView) {
        contentStack.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private static func roleQualifier(for copy: SetupWindowProblemCopy) -> String {
        switch copy {
        case .claudeInputRejected(let blocker): return "problem.claude-input-\(blocker)"
        case .slackThreadRequestFailed: return "problem.slack-request"
        case .manifestNotRegistered: return "problem.manifest-not-registered"
        case .manifestWrongRelayPath: return "problem.manifest-wrong-path"
        case .manifestWrongExtensionID: return "problem.manifest-wrong-id"
        case .extensionFolderMissingAfterRequest: return "problem.extension-folder"
        case .appSocketUnavailable: return "problem.app-socket"
        case .selectedTerminalNotInstalled: return "problem.terminal-not-installed"
        case .iTermAutomation(let issue): return "problem.iterm-\(issue)"
        case .cmuxNotInstalled: return "problem.cmux-not-installed"
        case .cmuxNotRunning: return "problem.cmux-not-running"
        case .cmuxAccessDenied: return "problem.cmux-access-denied"
        case .cmuxCheckFailed: return "problem.cmux-check-failed"
        case .warpAccessibilityRequired: return "problem.warp-accessibility"
        case .toolUnavailable(let name): return "problem.tool-\(name)"
        case .criticalToolUnavailable(let name): return "problem.critical-tool-\(name)"
        case .claudeUnavailable: return "problem.claude-unavailable"
        case .claudeNotExecutable: return "problem.claude-not-executable"
        }
    }

    private static func hasRequestRecord(_ presentation: SetupWindowPresentation) -> Bool {
        if case .requestRecorded = presentation.connectionSentence { return true }
        return false
    }

    private static func copy(
        for problem: SetupWindowProblem,
        manifest: SetupWindowManifestStatus,
        slackFailureDetail: String?
    ) -> SetupWindowSharedPanelBlockCopy {
        func button(
            _ title: String,
            _ action: SetupWindowSharedPanelAction
        ) -> SetupWindowSharedPanelButtonModel {
            SetupWindowSharedPanelButtonModel(title: title, action: action)
        }

        switch problem.copy {
        case .claudeInputRejected(.warpAccessibility):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.openedClaude.title"),
                paragraphs: [localized("app.setup.problem.warpAccessibility.cause")],
                effects: [localized("app.setup.problem.warpAccessibility.effect")],
                buttons: [
                    button(localized("app.button.requestAccessibility"), .requestAccessibility),
                    button(localized("app.setup.action.openAccessibilitySettings"), .openAccessibilitySettings),
                ]
            )
        case .claudeInputRejected(.warpHelperUnavailable):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.openedClaude.title"),
                paragraphs: [localized("app.setup.problem.warpHelperUnavailable.cause")],
                effects: [localized("app.setup.problem.warpHelperUnavailable.effect")],
                buttons: [button(localized("app.setup.action.showAppInstallHelp"), .showAppInstallHelp)]
            )
        case .claudeInputRejected(.wezTermSessionUnavailable):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.wezTermInput.title"),
                paragraphs: [localized("app.setup.problem.wezTermInput.cause")],
                effects: [],
                buttons: [button(localized("app.setup.action.openTerminalSettings"), .openTerminalSettings)]
            )
        case .slackThreadRequestFailed:
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.slack.title"),
                paragraphs: [slackFailureDetail ?? localized("app.setup.problem.slack.detailUnavailable")],
                effects: [],
                buttons: [button(localized("app.setup.action.openSlackSettings"), .openSlackSettings)]
            )
        case .manifestNotRegistered, .manifestWrongRelayPath, .manifestWrongExtensionID:
            let cause: String
            switch manifest {
            case .registered, .notRegistered:
                cause = localized("app.setup.install.nativeHost.problem.notRegistered")
            case .wrongRelayPath:
                cause = localized("app.setup.install.nativeHost.problem.wrongPath")
            case .wrongExtensionID:
                cause = localized("app.setup.install.nativeHost.problem.wrongExtensionID")
            }
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.manifest.title"),
                paragraphs: [cause],
                effects: [],
                buttons: [button(localized("app.setup.action.registerManifest"), .registerManifest)]
            )
        case .extensionFolderMissingAfterRequest:
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.extensionFolder.title"),
                paragraphs: [localized("app.setup.problem.extensionFolder.cause")],
                effects: [],
                buttons: [button(localized("app.setup.action.chromeInstall"), .installInChrome)]
            )
        case .appSocketUnavailable:
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.socket.title"),
                paragraphs: [localized("app.setup.problem.socket.cause")],
                effects: [],
                buttons: [button(localized("app.button.restartNow"), .restartApp)]
            )
        case .selectedTerminalNotInstalled(let terminal):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.terminalNotInstalled.title", terminalName(terminal)),
                paragraphs: [localized("app.setup.problem.terminalNotInstalled.cause")],
                effects: [],
                buttons: [button(localized("app.setup.action.openTerminalSettings"), .openTerminalSettings)]
            )
        case .iTermAutomation(.denied):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.iterm.denied.title"),
                paragraphs: [localized("app.setup.problem.iterm.denied.cause")],
                effects: [],
                buttons: [button(localized("app.setup.action.openAutomationSettings"), .openAutomationSettings)]
            )
        case .iTermAutomation(.notDetermined):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.iterm.notDetermined.title"),
                paragraphs: [localized("app.setup.problem.iterm.notDetermined.cause")],
                effects: [],
                buttons: [button(localized("app.button.requestItermPermission"), .requestPermission)]
            )
        case .iTermAutomation(.targetNotRunning):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.iterm.targetNotRunning.title"),
                paragraphs: [localized("app.setup.problem.iterm.targetNotRunning.cause")],
                effects: [],
                buttons: [button(localized("app.button.requestItermPermission"), .requestPermission)]
            )
        case .iTermAutomation(.unknown(let code)):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.iterm.unknown.title"),
                paragraphs: [localized("app.setup.problem.iterm.unknown.cause", String(code))],
                effects: [],
                buttons: [button(localized("app.setup.action.openAutomationSettings"), .openAutomationSettings)]
            )
        case .cmuxNotInstalled(let channel):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.cmux.notInstalled.title", terminalName(channel)),
                paragraphs: [localized("app.setup.problem.cmux.notInstalled.cause")],
                effects: [localized("app.setup.problem.cmux.notInstalled.effect")],
                buttons: [button(localized("app.setup.action.openTerminalSettings"), .openTerminalSettings)]
            )
        case .cmuxNotRunning(let channel):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.cmux.notRunning.title", terminalName(channel)),
                paragraphs: [localized("app.setup.problem.cmux.notRunning.cause")],
                effects: [],
                buttons: [button(localized("app.setup.action.refreshCmuxStatus"), .refreshCmuxStatus)]
            )
        case .cmuxAccessDenied(let channel):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.cmux.denied.title", terminalName(channel)),
                paragraphs: [localized("app.setup.problem.cmux.denied.cause")],
                effects: [localized("app.setup.problem.cmux.denied.effect")],
                buttons: [
                    button(localized("app.setup.action.openCmuxConfig"), .openCmuxConfig),
                    button(localized("app.setup.action.refreshCmuxStatus"), .refreshCmuxStatus),
                ]
            )
        case .cmuxCheckFailed(let channel, let detail):
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.cmux.failed.title", terminalName(channel)),
                paragraphs: [localized("app.setup.problem.cmux.failed.cause", detail)],
                effects: [],
                buttons: [button(localized("app.setup.action.refreshCmuxStatus"), .refreshCmuxStatus)]
            )
        case .warpAccessibilityRequired:
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.warpAccessibilityRequired.title"),
                paragraphs: [localized("app.setup.problem.warpAccessibilityRequired.cause")],
                effects: [localized("app.setup.problem.warpAccessibilityRequired.effect")],
                buttons: [
                    button(localized("app.button.requestAccessibility"), .requestAccessibility),
                    button(localized("app.setup.action.openAccessibilitySettings"), .openAccessibilitySettings),
                ]
            )
        case .toolUnavailable(let name):
            switch name {
            case "gh":
                return SetupWindowSharedPanelBlockCopy(
                    title: localized("app.setup.problem.gh.title"),
                    paragraphs: [localized("app.setup.problem.gh.cause")],
                    effects: [localized("app.setup.problem.gh.effect")],
                    buttons: [button(localized("app.setup.action.showGhInstallHelp"), .showGhInstallHelp)]
                )
            case "claude":
                return claudeUnavailable(button: button)
            case "zoxide":
                return SetupWindowSharedPanelBlockCopy(
                    title: localized("app.setup.problem.zoxide.title"),
                    paragraphs: [localized("app.setup.problem.zoxide.cause")],
                    effects: [localized("app.setup.problem.zoxide.effect")],
                    buttons: [button(localized("app.setup.action.showZoxideInstallHelp"), .showZoxideInstallHelp)]
                )
            default:
                return SetupWindowSharedPanelBlockCopy(
                    title: localized("app.setup.problem.toolUnavailable.title", name),
                    paragraphs: [localized("app.setup.problem.toolUnavailable.cause", name)],
                    effects: [],
                    buttons: [button(localized("app.setup.action.showAppInstallHelp"), .showAppInstallHelp)]
                )
            }
        case .criticalToolUnavailable(let name):
            if name == "zoxide" {
                return SetupWindowSharedPanelBlockCopy(
                    title: localized("app.setup.problem.noEntry.title"),
                    paragraphs: [localized("app.setup.problem.noEntry.cause")],
                    effects: [],
                    buttons: [
                        button(localized("app.setup.action.openBaseDirectorySettings"), .openBaseDirectorySettings),
                        button(localized("app.setup.action.showZoxideInstallHelp"), .showZoxideInstallHelp),
                    ]
                )
            }
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.toolUnavailable.title", name),
                paragraphs: [localized("app.setup.problem.toolUnavailable.cause", name)],
                effects: [],
                buttons: [button(localized("app.setup.action.showAppInstallHelp"), .showAppInstallHelp)]
            )
        case .claudeUnavailable:
            return claudeUnavailable(button: button)
        case .claudeNotExecutable:
            return SetupWindowSharedPanelBlockCopy(
                title: localized("app.setup.problem.claudeNotExecutable.title"),
                paragraphs: [
                    localized("app.setup.problem.claudeNotExecutable.cause"),
                    localized("app.setup.problem.claudeNotExecutable.slack"),
                ],
                effects: [],
                buttons: [button(localized("app.setup.action.showClaudeInstallHelp"), .showClaudeInstallHelp)]
            )
        }
    }

    private static func claudeUnavailable(
        button: (String, SetupWindowSharedPanelAction) -> SetupWindowSharedPanelButtonModel
    ) -> SetupWindowSharedPanelBlockCopy {
        SetupWindowSharedPanelBlockCopy(
            title: localized("app.setup.problem.claudeUnavailable.title"),
            paragraphs: [localized("app.setup.problem.claudeUnavailable.cause")],
            effects: [],
            buttons: [button(localized("app.setup.action.showClaudeInstallHelp"), .showClaudeInstallHelp)]
        )
    }

    private static func terminalName(_ terminal: Terminal) -> String {
        switch terminal {
        case .iterm: return "iTerm2"
        case .wezterm: return "WezTerm"
        case .warp: return "Warp"
        case .cmux: return "cmux"
        case .cmuxNightly: return "cmux NIGHTLY"
        }
    }

    private static func terminalName(_ channel: CmuxChannel) -> String {
        switch channel {
        case .stable: return "cmux"
        case .nightly: return "cmux NIGHTLY"
        }
    }
}

private extension SetupWindowProblem {
    var isOpeningReason: Bool {
        switch copy {
        case .claudeInputRejected, .slackThreadRequestFailed: return true
        default: return false
        }
    }
}

final class SetupWindowProblemBlockView: NSView {
    let problem: SetupWindowProblem
    let titleLabel: NSTextField
    let paragraphLabels: [NSTextField]
    let effectLabels: [NSTextField]
    let actionButtons: [NSButton]
    let voiceOverLabel: String

    private let contentStack = NSStackView()

    init(
        problem: SetupWindowProblem,
        roleQualifier: String,
        copy: SetupWindowSharedPanelBlockCopy,
        target: AnyObject?,
        selectors: [SetupWindowSharedPanelAction: Selector]
    ) {
        self.problem = problem
        titleLabel = makeSetupPanelLabel(copy.title, font: Theme.ui(13, .semibold), color: Theme.text)
        paragraphLabels = copy.paragraphs.map {
            makeSetupPanelLabel($0, font: Theme.ui(12), color: Theme.text)
        }
        effectLabels = copy.effects.map {
            makeSetupPanelLabel($0, font: Theme.ui(11), color: Theme.textDim)
        }
        voiceOverLabel = localized(
            "app.setup.problem.accessibilityLabel",
            localized(problem.severity == .error ? "app.setup.severity.error" : "app.setup.severity.warning"),
            copy.title
        )
        actionButtons = copy.buttons.map { button in
            makeSetupPanelButton(
                title: button.title,
                action: button.action,
                qualifier: roleQualifier,
                target: target,
                selectors: selectors
            )
        }
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 9
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(voiceOverLabel)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 7
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        let heading = NSStackView(views: [makeStatusDot(for: problem.severity), titleLabel])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8
        contentStack.addArrangedSubview(heading)
        for label in paragraphLabels {
            contentStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        for label in effectLabels {
            contentStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        if !actionButtons.isEmpty {
            let actions = NSStackView(views: actionButtons)
            actions.orientation = .horizontal
            actions.alignment = .centerY
            actions.spacing = 8
            contentStack.addArrangedSubview(actions)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class SetupWindowInstallStepView: NSView {
    let titleLabel: NSTextField
    let statusLabel: NSTextField
    let actionButton: NSButton?
    let isComplete: Bool

    private let marker: NSTextField

    init(
        number: Int,
        title: String,
        status: String,
        isComplete: Bool,
        isProblem: Bool = false,
        button: (String, SetupWindowSharedPanelAction, String)? = nil,
        target: AnyObject?,
        selectors: [SetupWindowSharedPanelAction: Selector]
    ) {
        self.isComplete = isComplete
        marker = makeSetupPanelLabel(
            isComplete ? "✓" : (isProblem ? "!" : String(number)),
            font: Theme.ui(12, .semibold),
            color: isComplete ? Theme.ok : (isProblem ? Theme.err : Theme.textDim)
        )
        titleLabel = makeSetupPanelLabel(title, font: Theme.ui(12, .semibold), color: Theme.text)
        statusLabel = makeSetupPanelLabel(status, font: Theme.ui(11), color: Theme.textDim)
        if let button {
            actionButton = makeSetupPanelButton(
                title: button.0,
                action: button.1,
                qualifier: button.2,
                target: target,
                selectors: selectors
            )
        } else {
            actionButton = nil
        }
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        marker.alignment = .center
        marker.wantsLayer = true
        marker.layer?.cornerRadius = 10
        marker.layer?.backgroundColor = (isComplete ? Theme.ok : (isProblem ? Theme.err : Theme.border)).withAlphaComponent(0.17).cgColor
        marker.widthAnchor.constraint(equalToConstant: 22).isActive = true
        marker.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let textStack = NSStackView(views: [titleLabel, statusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        let rowViews: [NSView] = [marker, textStack] + [actionButton].compactMap { $0 }
        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class SetupWindowInstallChecklistView: NSView {
    let steps: [SetupWindowInstallStepView]
    let guideStepsContainer: NSStackView
    let guideStepLabels: [NSTextField]
    let feedbackLabel: NSTextField
    let closeGuideButton: NSButton?

    private let contentStack = NSStackView()
    private let chromeInstallButton: NSButton

    init(
        manifest: SetupWindowManifestStatus,
        extensionFolder: SetupWindowExtensionFolderStatus,
        requestRecorded: Bool,
        guideStepsExpanded: Bool,
        installFeedback: String?,
        target: AnyObject?,
        selectors: [SetupWindowSharedPanelAction: Selector]
    ) {
        let registered: Bool
        let nativeHostStatus: String
        let manifestProblem: Bool
        switch manifest {
        case .registered:
            registered = true
            manifestProblem = false
            nativeHostStatus = localized("app.setup.install.nativeHost.complete")
        case .notRegistered, .wrongRelayPath, .wrongExtensionID:
            registered = false
            manifestProblem = true
            let nativeHostProblem: String
            switch manifest {
            case .registered, .notRegistered:
                nativeHostProblem = localized("app.setup.install.nativeHost.problem.notRegistered")
            case .wrongRelayPath:
                nativeHostProblem = localized("app.setup.install.nativeHost.problem.wrongPath")
            case .wrongExtensionID:
                nativeHostProblem = localized("app.setup.install.nativeHost.problem.wrongExtensionID")
            }
            nativeHostStatus = nativeHostProblem
        }

        let folderIsMissing: Bool
        switch extensionFolder {
        case .present: folderIsMissing = false
        case .missing: folderIsMissing = true
        }
        let chromeStatus: String
        if folderIsMissing {
            chromeStatus = localized("app.setup.install.chrome.folderMissing")
        } else if requestRecorded {
            chromeStatus = localized("app.setup.install.chrome.complete")
        } else {
            chromeStatus = localized("app.setup.install.chrome.folderReady")
        }

        let step0 = SetupWindowInstallStepView(
            number: 1,
            title: localized("app.setup.install.nativeHost.title"),
            status: nativeHostStatus,
            isComplete: registered,
            isProblem: manifestProblem,
            button: registered ? nil : (
                localized("app.setup.action.registerManifest"), .registerManifest, "guide.native-host"
            ),
            target: target,
            selectors: selectors
        )
        let step1 = SetupWindowInstallStepView(
            number: 2,
            title: localized("app.button.installInChrome"),
            status: chromeStatus,
            isComplete: requestRecorded && !folderIsMissing,
            button: (
                localized("app.setup.action.chromeInstall"), .installInChrome, "guide.chrome-install"
            ),
            target: target,
            selectors: selectors
        )
        let step2 = SetupWindowInstallStepView(
            number: 3,
            title: localized(requestRecorded
                ? "app.setup.install.github.completeTitle"
                : "app.setup.install.github.pendingTitle"),
            status: localized(requestRecorded
                ? "app.setup.install.github.complete"
                : "app.setup.install.github.pending"),
            isComplete: requestRecorded,
            target: target,
            selectors: selectors
        )
        steps = [step0, step1, step2]
        chromeInstallButton = step1.actionButton!
        guideStepLabels = [
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.developerMode"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.loadUnpacked"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.filePicker"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.keepMode"), font: Theme.ui(11), color: Theme.textDim),
        ]
        guideStepsContainer = NSStackView(views: guideStepLabels)
        feedbackLabel = makeSetupPanelLabel(
            installFeedback ?? (guideStepsExpanded ? localized("app.setup.install.chrome.feedback") : ""),
            font: Theme.ui(11),
            color: Theme.accent
        )
        if requestRecorded {
            closeGuideButton = makeSetupPanelButton(
                title: localized("app.setup.action.dismissSetupGuide"),
                action: .dismissSetupGuide,
                qualifier: "guide.close",
                target: target,
                selectors: selectors
            )
        } else {
            closeGuideButton = nil
        }
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 9
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(localized("app.setup.install.accessibilityLabel"))

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 9
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        for step in steps {
            contentStack.addArrangedSubview(step)
            step.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        guideStepsContainer.orientation = .vertical
        guideStepsContainer.alignment = .leading
        guideStepsContainer.spacing = 5
        guideStepsContainer.translatesAutoresizingMaskIntoConstraints = false
        guideStepsContainer.setAccessibilityElement(true)
        guideStepsContainer.setAccessibilityRole(.list)
        guideStepsContainer.setAccessibilityLabel(localized("app.setup.install.chrome.steps.accessibilityLabel"))
        contentStack.addArrangedSubview(guideStepsContainer)
        for label in guideStepLabels {
            guideStepsContainer.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        guideStepsContainer.isHidden = !guideStepsExpanded

        feedbackLabel.isHidden = !guideStepsExpanded
        contentStack.addArrangedSubview(feedbackLabel)
        feedbackLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        if let closeGuideButton {
            let closeRow = NSStackView(views: [closeGuideButton])
            closeRow.orientation = .horizontal
            closeRow.alignment = .centerY
            closeRow.translatesAutoresizingMaskIntoConstraints = false
            closeRow.setAccessibilityElement(true)
            closeRow.setAccessibilityRole(.group)
            closeRow.setAccessibilityLabel(localized("app.setup.install.closeGuide.accessibilityLabel"))
            contentStack.addArrangedSubview(closeRow)
            closeRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        if !requestRecorded {
            chromeInstallButton.keyEquivalent = "\r"
            chromeInstallButton.contentTintColor = Theme.ok
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showChromeInstallationSteps() {
        guideStepsContainer.isHidden = false
        feedbackLabel.stringValue = localized("app.setup.install.chrome.feedback")
        feedbackLabel.isHidden = false
    }
}

private func makeSetupPanelButton(
    title: String,
    action: SetupWindowSharedPanelAction,
    qualifier: String,
    target: AnyObject?,
    selectors: [SetupWindowSharedPanelAction: Selector]
) -> NSButton {
    guard let selector = selectors[action] else {
        preconditionFailure("missing selector for shared panel action \(action.rawValue)")
    }
    let button = NSButton(title: title, target: target, action: selector)
    button.bezelStyle = .rounded
    button.identifier = setupWindowSharedPanelRole(selector, qualifier)
    return button
}

private func makeStatusDot(for severity: SetupWindowProblemSeverity) -> NSView {
    let dot = NSView(frame: .zero)
    dot.wantsLayer = true
    dot.layer?.backgroundColor = (severity == .error ? Theme.err : Theme.warn).cgColor
    dot.layer?.cornerRadius = 4
    dot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        dot.widthAnchor.constraint(equalToConstant: 8),
        dot.heightAnchor.constraint(equalToConstant: 8),
    ])
    return dot
}

private func makeSetupPanelLabel(
    _ text: String, font: NSFont, color: NSColor
) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = font
    label.textColor = color
    label.usesSingleLineMode = false
    label.cell?.wraps = true
    label.cell?.isScrollable = false
    label.maximumNumberOfLines = 0
    label.preferredMaxLayoutWidth = 660
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}
