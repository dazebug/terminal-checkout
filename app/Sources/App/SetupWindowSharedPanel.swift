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

func setupWindowControlRole(
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
    private(set) var presentation: SetupWindowPresentation
    private var manifest: SetupWindowManifestStatus
    private var extensionFolder: SetupWindowExtensionFolderStatus
    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowSharedPanelAction: Selector]
    private let contentStack = NSStackView()
    private var blocksByRole: [String: SetupWindowProblemBlockView] = [:]

    private(set) var problemBlockViews: [SetupWindowProblemBlockView] = []
    private(set) var installChecklistView: SetupWindowInstallChecklistView?
    var wrappingStatusLabelsForTesting: [NSTextField] {
        let problemLabels = blocksByRole.values.flatMap { $0.paragraphLabels + $0.effectLabels }
        let checklistLabels = installChecklistView.map { checklist in
            checklist.steps.map(\.statusLabel) + checklist.guideStepLabels + [checklist.feedbackLabel]
        } ?? []
        return problemLabels + checklistLabels
    }

    init(
        presentation: SetupWindowPresentation,
        manifest: SetupWindowManifestStatus,
        extensionFolder: SetupWindowExtensionFolderStatus,
        installStepsExpanded: Bool = false,
        installFeedback: String? = nil,
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

        var createdRoles: Set<String> = []
        for template in Self.problemTemplates {
            let role = Self.blockRoleQualifier(for: template)
            guard createdRoles.insert(role).inserted else { continue }
            let block = SetupWindowProblemBlockView(
                problem: template,
                roleQualifier: role,
                copy: Self.copy(for: template, manifest: manifest),
                target: target,
                selectors: selectors
            )
            block.isHidden = true
            blocksByRole[role] = block
            contentStack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
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
        update(presentation, manifest: manifest, extensionFolder: extensionFolder,
               installStepsExpanded: installStepsExpanded,
               installFeedback: installFeedback)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Called by the existing Chrome-install action after it prepares the extension copy and opens
    /// chrome://extensions. The controller remains the action target; this only reveals the
    /// instructions and feedback in the retained panel.
    func showChromeInstallationSteps() {
        installChecklistView?.showChromeInstallationSteps()
    }

    func update(
        _ presentation: SetupWindowPresentation,
        manifest: SetupWindowManifestStatus,
        extensionFolder: SetupWindowExtensionFolderStatus,
        installStepsExpanded: Bool,
        installFeedback: String?
    ) {
        self.presentation = presentation
        self.manifest = manifest
        self.extensionFolder = extensionFolder
        installChecklistView?.update(
            manifest: manifest,
            extensionFolder: extensionFolder,
            requestRecorded: Self.hasRequestRecord(presentation),
            visible: presentation.showsFirstInstallChecklist,
            guideStepsExpanded: installStepsExpanded,
            installFeedback: installFeedback
        )

        let visibleProblems = presentation.problems.filter { problem in
            guard presentation.showsFirstInstallChecklist else { return true }
            switch problem.copy {
            case .manifestNotRegistered, .manifestWrongRelayPath, .manifestWrongExtensionID:
                return false
            default:
                return true
            }
        }
        var ordered: [SetupWindowProblemBlockView] = []
        for problem in visibleProblems {
            let role = Self.blockRoleQualifier(for: problem)
            let block: SetupWindowProblemBlockView
            if let retained = blocksByRole[role] {
                block = retained
            } else {
                let created = SetupWindowProblemBlockView(
                    problem: problem,
                    roleQualifier: role,
                    copy: Self.copy(for: problem, manifest: manifest),
                    target: actionTarget,
                    selectors: selectors
                )
                created.isHidden = true
                blocksByRole[role] = created
                contentStack.addArrangedSubview(created)
                created.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                block = created
            }
            block.update(
                problem: problem,
                copy: Self.copy(for: problem, manifest: manifest)
            )
            block.isHidden = false
            ordered.append(block)
        }
        for block in blocksByRole.values where !ordered.contains(where: { $0 === block }) {
            block.isHidden = true
        }
        problemBlockViews = ordered
        let opening = ordered.filter { $0.problem.isOpeningReason }
        let remaining = ordered.filter { !$0.problem.isOpeningReason }
        var arranged: [NSView] = opening
        if presentation.showsFirstInstallChecklist, let installChecklistView { arranged.append(installChecklistView) }
        arranged += remaining
        let current = contentStack.arrangedSubviews
        if current.count != arranged.count || zip(current, arranged).contains(where: { $0 !== $1 }) {
            for view in current { contentStack.removeArrangedSubview(view) }
            for view in arranged { contentStack.addArrangedSubview(view) }
        }
        isHidden = arranged.isEmpty
        contentStack.isHidden = isHidden
    }

    private static let problemTemplates: [SetupWindowProblem] = [
        .init(severity: .error, copy: .manifestNotRegistered),
        .init(severity: .error, copy: .extensionFolderMissingAfterRequest),
        .init(severity: .error, copy: .appSocketUnavailable),
        .init(severity: .error, copy: .selectedTerminalNotInstalled(.iterm)),
        .init(severity: .error, copy: .iTermAutomation(.denied)),
        .init(severity: .warning, copy: .cmuxNotRunning(.stable)),
        .init(severity: .warning, copy: .warpAccessibilityRequired),
        .init(severity: .warning, copy: .toolUnavailable(name: "zoxide")),
        .init(severity: .warning, copy: .toolUnavailable(name: "gh")),
        .init(severity: .error, copy: .criticalToolUnavailable(name: "zoxide")),
        .init(severity: .error, copy: .claudeUnavailable),
        .init(severity: .warning, copy: .claudeNotExecutable),
    ]

    private static func roleQualifier(for copy: SetupWindowProblemCopy) -> String {
        switch copy {
        case .claudeInputRejected: return "problem.opened-claude"
        case .slackThreadRequestFailed: return "problem.slack-request"
        case .manifestNotRegistered, .manifestWrongRelayPath, .manifestWrongExtensionID:
            return "problem.manifest"
        case .extensionFolderMissingAfterRequest: return "problem.extension-folder"
        case .appSocketUnavailable: return "problem.app-socket"
        case .selectedTerminalNotInstalled: return "problem.selected-terminal"
        case .iTermAutomation: return "problem.iterm-automation"
        case .cmuxNotInstalled, .cmuxNotRunning, .cmuxAccessDenied, .cmuxCheckFailed:
            return "problem.cmux"
        case .warpAccessibilityRequired: return "problem.warp-accessibility"
        case .toolUnavailable(let name), .criticalToolUnavailable(let name): return "problem.tool-\(name)"
        case .claudeUnavailable, .claudeNotExecutable: return "problem.tool-claude"
        }
    }

    private static func blockRoleQualifier(for problem: SetupWindowProblem) -> String {
        guard let order = problem.openingReasonOrder else {
            return roleQualifier(for: problem.copy)
        }
        switch problem.copy {
        case .claudeInputRejected:
            return "problem.opened-claude.\(order)"
        case .slackThreadRequestFailed:
            return "problem.slack-request.\(order)"
        default:
            return roleQualifier(for: problem.copy)
        }
    }

    private static func hasRequestRecord(_ presentation: SetupWindowPresentation) -> Bool {
        if case .requestRecorded = presentation.connectionSentence { return true }
        return false
    }

    private static func copy(
        for problem: SetupWindowProblem,
        manifest: SetupWindowManifestStatus
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
                paragraphs: [problem.detail ?? localized("app.setup.problem.slack.detailUnavailable")],
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
                paragraphs: [localized(
                    "app.setup.problem.cmux.notInstalled.cause",
                    localized("app.setup.action.openTerminalSettings")
                )],
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
    private(set) var problem: SetupWindowProblem
    let titleLabel: NSTextField
    let paragraphLabels: [NSTextField]
    let effectLabels: [NSTextField]
    let actionButtons: [NSButton]
    var voiceOverLabelForTesting: String { accessibilityLabelText }

    private let contentStack = NSStackView()
    private let severityDot = makeStatusDot(for: .warning)
    private let actionsStack = NSStackView()
    private let roleQualifier: String
    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowSharedPanelAction: Selector]
    private var accessibilityLabelText = ""

    init(
        problem: SetupWindowProblem,
        roleQualifier: String,
        copy: SetupWindowSharedPanelBlockCopy,
        target: AnyObject?,
        selectors: [SetupWindowSharedPanelAction: Selector]
    ) {
        self.problem = problem
        self.roleQualifier = roleQualifier
        self.actionTarget = target
        self.selectors = selectors
        titleLabel = makeSetupPanelLabel(copy.title, font: Theme.ui(13, .semibold), color: Theme.text)
        paragraphLabels = (0..<2).map { _ in makeSetupPanelLabel("", font: Theme.ui(12), color: Theme.text) }
        effectLabels = (0..<1).map { _ in makeSetupPanelLabel("", font: Theme.ui(11), color: Theme.textDim) }
        actionButtons = (0..<2).map { _ in
            let button = NSButton(title: "", target: nil, action: nil)
            button.bezelStyle = .rounded
            return button
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
        setAccessibilityLabel("")

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

        let heading = NSStackView(views: [severityDot, titleLabel])
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
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = 8
        for button in actionButtons { actionsStack.addArrangedSubview(button) }
        contentStack.addArrangedSubview(actionsStack)
        update(problem: problem, copy: copy)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(problem: SetupWindowProblem, copy: SetupWindowSharedPanelBlockCopy) {
        self.problem = problem
        titleLabel.stringValue = copy.title
        severityDot.layer?.backgroundColor = (problem.severity == .error ? Theme.err : Theme.warn).cgColor
        for (index, label) in paragraphLabels.enumerated() {
            label.stringValue = index < copy.paragraphs.count ? copy.paragraphs[index] : ""
            label.isHidden = index >= copy.paragraphs.count
        }
        for (index, label) in effectLabels.enumerated() {
            label.stringValue = index < copy.effects.count ? copy.effects[index] : ""
            label.isHidden = index >= copy.effects.count
        }
        for (index, button) in actionButtons.enumerated() {
            guard index < copy.buttons.count else {
                button.isHidden = true
                continue
            }
            let model = copy.buttons[index]
            button.title = model.title
            if let selector = selectors[model.action] {
                button.target = actionTarget
                button.action = selector
                button.identifier = setupWindowControlRole(selector, roleQualifier)
            }
            button.isHidden = false
        }
        actionsStack.isHidden = copy.buttons.isEmpty
        accessibilityLabelText = localized(
            "app.setup.problem.accessibilityLabel",
            localized(problem.severity == .error ? "app.setup.severity.error" : "app.setup.severity.warning"),
            copy.title
        )
        setAccessibilityLabel(accessibilityLabelText)
    }
}

final class SetupWindowInstallStepView: NSView {
    let titleLabel: NSTextField
    let statusLabel: NSTextField
    let actionButton: NSButton?
    private(set) var isComplete: Bool

    private let marker: NSTextField
    private let number: Int
    private let textStack = NSStackView()

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
        self.number = number
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

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(statusLabel)
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
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let reservedWidth: CGFloat = 22
            + CGFloat(rowViews.count - 1) * row.spacing
            + (actionButton?.fittingSize.width ?? 0)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            textStack.widthAnchor.constraint(equalTo: widthAnchor, constant: -reservedWidth),
            titleLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func appendDetailViews(_ views: [NSView]) {
        for view in views {
            textStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }
    }

    func update(
        title: String, status: String, isComplete: Bool, isProblem: Bool,
        buttonTitle: String? = nil, buttonVisible: Bool = false, isPrimary: Bool = false
    ) {
        self.isComplete = isComplete
        titleLabel.stringValue = title
        statusLabel.stringValue = status
        marker.stringValue = isComplete ? "✓" : (isProblem ? "!" : String(number))
        let color = isComplete ? Theme.ok : (isProblem ? Theme.err : Theme.textDim)
        marker.textColor = color
        marker.layer?.backgroundColor = (isComplete ? Theme.ok : (isProblem ? Theme.err : Theme.border))
            .withAlphaComponent(0.17).cgColor
        actionButton?.title = buttonTitle ?? ""
        actionButton?.isHidden = !buttonVisible
        actionButton?.bezelColor = isPrimary ? Theme.actionGreen : nil
        actionButton?.contentTintColor = isPrimary ? .white : nil
        actionButton?.keyEquivalent = isPrimary ? "\r" : ""
    }
}

final class SetupWindowInstallChecklistView: NSView {
    let steps: [SetupWindowInstallStepView]
    let guideStepsContainer: NSStackView
    let guideStepLabels: [NSTextField]
    let feedbackLabel: NSTextField
    let closeGuideButton: NSButton

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
            button: (localized("app.setup.action.registerManifest"), .registerManifest, "guide.native-host"),
            target: target,
            selectors: selectors
        )
        let step1 = SetupWindowInstallStepView(
            number: 2,
            title: localized("app.setup.install.chrome.title"),
            status: chromeStatus,
            isComplete: requestRecorded && !folderIsMissing,
            button: (
                localized("app.button.installInChrome"), .installInChrome, "guide.chrome-install"
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
        let guideStepNumberLabels = (1...4).map {
            let label = makeSetupPanelLabel("\($0).", font: Theme.ui(11, .medium), color: Theme.textDim)
            label.alignment = .right
            return label
        }
        guideStepLabels = [
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.developerMode"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.loadUnpacked"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.filePicker"), font: Theme.ui(11), color: Theme.textDim),
            makeSetupPanelLabel(localized("app.setup.install.chrome.step.keepMode"), font: Theme.ui(11), color: Theme.textDim),
        ]
        guideStepsContainer = NSStackView()
        feedbackLabel = makeSetupPanelLabel(
            installFeedback ?? (guideStepsExpanded ? localized("app.setup.install.chrome.feedback") : ""),
            font: Theme.ui(11),
            color: Theme.accent
        )
        closeGuideButton = makeSetupPanelButton(
            title: localized("app.setup.action.dismissSetupGuide"),
            action: .dismissSetupGuide,
            qualifier: "guide.close",
            target: target,
            selectors: selectors
        )
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

        step1.appendDetailViews([feedbackLabel, guideStepsContainer])

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
        for (index, label) in guideStepLabels.enumerated() {
            let numberLabel = guideStepNumberLabels[index]
            let row = NSStackView(views: [numberLabel, label])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false
            guideStepsContainer.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: guideStepsContainer.widthAnchor),
                numberLabel.widthAnchor.constraint(equalToConstant: 18),
                label.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -24),
            ])
        }
        guideStepsContainer.isHidden = !guideStepsExpanded

        feedbackLabel.isHidden = !guideStepsExpanded

        let closeRow = NSStackView(views: [closeGuideButton])
        closeRow.orientation = .horizontal
        closeRow.alignment = .centerY
        closeRow.translatesAutoresizingMaskIntoConstraints = false
        closeRow.setAccessibilityElement(true)
        closeRow.setAccessibilityRole(.group)
        closeRow.setAccessibilityLabel(localized(
            "app.setup.install.closeGuide.accessibilityLabel", closeGuideButton.title
        ))
        contentStack.addArrangedSubview(closeRow)
        closeRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        update(manifest: manifest, extensionFolder: extensionFolder,
               requestRecorded: requestRecorded, visible: true,
               guideStepsExpanded: guideStepsExpanded, installFeedback: installFeedback)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showChromeInstallationSteps() {
        guideStepsContainer.isHidden = false
        feedbackLabel.stringValue = localized("app.setup.install.chrome.feedback")
        feedbackLabel.isHidden = false
    }

    func update(
        manifest: SetupWindowManifestStatus,
        extensionFolder: SetupWindowExtensionFolderStatus,
        requestRecorded: Bool,
        visible: Bool,
        guideStepsExpanded: Bool,
        installFeedback: String?
    ) {
        isHidden = !visible
        let registered = manifest == .registered
        let manifestStatus: String
        switch manifest {
        case .registered: manifestStatus = localized("app.setup.install.nativeHost.complete")
        case .notRegistered: manifestStatus = localized("app.setup.install.nativeHost.problem.notRegistered")
        case .wrongRelayPath: manifestStatus = localized("app.setup.install.nativeHost.problem.wrongPath")
        case .wrongExtensionID: manifestStatus = localized("app.setup.install.nativeHost.problem.wrongExtensionID")
        }
        steps[0].update(
            title: localized("app.setup.install.nativeHost.title"), status: manifestStatus,
            isComplete: registered, isProblem: !registered,
            buttonTitle: localized("app.setup.action.registerManifest"), buttonVisible: !registered
        )
        let folderMissing = extensionFolder == .missing
        let chromeStatus = folderMissing
            ? localized("app.setup.install.chrome.folderMissing")
            : (requestRecorded ? localized("app.setup.install.chrome.complete") : localized("app.setup.install.chrome.folderReady"))
        steps[1].update(
            title: localized("app.setup.install.chrome.title"), status: chromeStatus,
            isComplete: requestRecorded && !folderMissing, isProblem: folderMissing,
            buttonTitle: localized("app.button.installInChrome"),
            buttonVisible: !requestRecorded || folderMissing,
            isPrimary: !requestRecorded || folderMissing
        )
        steps[2].update(
            title: localized(requestRecorded ? "app.setup.install.github.completeTitle" : "app.setup.install.github.pendingTitle"),
            status: localized(requestRecorded ? "app.setup.install.github.complete" : "app.setup.install.github.pending"),
            isComplete: requestRecorded, isProblem: false
        )
        guideStepsContainer.isHidden = !guideStepsExpanded
        feedbackLabel.stringValue = installFeedback ?? (guideStepsExpanded ? localized("app.setup.install.chrome.feedback") : "")
        feedbackLabel.isHidden = !guideStepsExpanded
        closeGuideButton.isHidden = !requestRecorded
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
    button.identifier = setupWindowControlRole(selector, qualifier)
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
    let label = makeSetupWindowWrappingLabel(text)
    label.font = font
    label.textColor = color
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}
