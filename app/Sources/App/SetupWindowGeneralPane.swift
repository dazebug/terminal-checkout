import AppKit
import Core
import Foundation

enum SetupWindowGeneralStatusTone {
    case success
    case warning
    case error
    case neutral

    var color: NSColor {
        switch self {
        case .success: return Theme.ok
        case .warning: return Theme.warn
        case .error: return Theme.err
        case .neutral: return Theme.textFaint
        }
    }
}

struct SetupWindowGeneralIndicator {
    let text: String
    let tone: SetupWindowGeneralStatusTone
}

enum SetupWindowGeneralTerminalTestResult {
    case notRun
    case running
    case succeeded
    case failed(String)
}

enum SetupWindowGeneralLanguageChange: Equatable {
    case unchanged
    case changed
    case restartBlocked
    case restartFailed

    var message: String? {
        switch self {
        case .unchanged: return nil
        case .changed: return localized("app.language.note")
        case .restartBlocked: return localized("app.language.restartDeferred")
        case .restartFailed: return localized("app.language.restartFailed")
        }
    }
}

/// A complete value passed into one retained pane. Text that depends on a live system check is
/// prepared by the controller; this view only turns the snapshot and presentation model into UI.
struct SetupWindowGeneralPaneState {
    let presentation: SetupWindowPresentation
    let appVersion: String
    let requestRelativeTime: String?
    let terminalInstallations: [SetupWindowTerminalInstallation]
    let nativeHostStatus: SetupWindowGeneralIndicator
    let appSocketStatus: SetupWindowGeneralIndicator
    let terminalStatus: SetupWindowGeneralIndicator
    let tools: SetupWindowToolResults?
    let savedTabActivation: TabActivation
    let terminalTestResult: SetupWindowGeneralTerminalTestResult
    let storedLanguage: String
    let resolvedLanguage: String
    let languageChange: SetupWindowGeneralLanguageChange

    var terminal: Terminal { presentation.previews.general.terminal }

    func isInstalled(_ terminal: Terminal) -> Bool {
        terminalInstallations.first { $0.terminal == terminal }?.isInstalled ?? false
    }
}

enum SetupWindowGeneralAction: CaseIterable, Hashable {
    case terminalChanged
    case tabActivationChanged
    case testTerminal
    case languageChanged
    case restartForLanguage
    case openOptionsPage
    case reshowInstall
    case openCmuxConfig
    case refreshCmuxStatus
}

func setupWindowGeneralPaneRole(_ action: Selector) -> NSUserInterfaceItemIdentifier {
    NSUserInterfaceItemIdentifier("control.\(action)")
}

final class SetupWindowGeneralPane: NSView {
    let connectionDetailsButton: NSButton
    let terminalPopup: NSPopUpButton
    let activationSegment: NSSegmentedControl
    let terminalTestButton: NSButton
    let languagePopup: NSPopUpButton
    let languageRestartButton: NSButton
    let optionsButton: NSButton
    let guideButton: NSButton
    let previewView: SetupWindowPreviewView
    let connectionDetailsPopover: NSPopover
    let requestStatusLabel = NSTextField(labelWithString: "")
    let languageNoteLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var savedTabActivationForTesting: TabActivation = .foreground

    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowGeneralAction: Selector]
    private let requestDot = SetupWindowGeneralStatusDot()
    private let popoverRequestDot = SetupWindowGeneralStatusDot()
    private let terminalDot = SetupWindowGeneralStatusDot()
    private let terminalStatusLabel = NSTextField(labelWithString: "")
    private let terminalTestResultLabel = NSTextField(wrappingLabelWithString: "")
    private let extensionStatusExplanation = NSTextField(wrappingLabelWithString: "")
    private let nativeHostDetailRow: SetupWindowGeneralPopoverRow
    private let appSocketDetailRow: SetupWindowGeneralPopoverRow
    private let terminalDetailRow: SetupWindowGeneralPopoverRow
    private let toolDetailRows: [String: SetupWindowGeneralPopoverRow]
    private let cmuxActionsRow: NSStackView
    private let mainContentStack = NSStackView()
    private let languageSection = NSStackView()
    private let identityIcon = NSImageView()
    private let versionLabel = NSTextField(labelWithString: "")

    var requestStatusText: String { requestStatusLabel.stringValue }
    var cmuxActionButtonRoles: [NSUserInterfaceItemIdentifier] {
        cmuxActionsRow.arrangedSubviews.compactMap { ($0 as? NSButton)?.identifier }
    }

    init(
        state: SetupWindowGeneralPaneState,
        target: AnyObject,
        selectors: [SetupWindowGeneralAction: Selector]
    ) {
        precondition(
            SetupWindowGeneralAction.allCases.allSatisfy { selectors[$0] != nil },
            "the General pane needs a selector for every controller action it presents"
        )
        self.actionTarget = target
        self.selectors = selectors

        let detailsButton = NSButton(title: "", target: nil, action: nil)
        connectionDetailsButton = detailsButton
        let terminalControl = NSPopUpButton(frame: .zero, pullsDown: false)
        terminalPopup = terminalControl
        activationSegment = NSSegmentedControl(labels: ["", ""], trackingMode: .selectOne, target: target, action: selectors[.tabActivationChanged]!)
        terminalTestButton = NSButton(title: "", target: target, action: selectors[.testTerminal]!)
        languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languageRestartButton = NSButton(title: "", target: target, action: selectors[.restartForLanguage]!)
        optionsButton = NSButton(title: "", target: target, action: selectors[.openOptionsPage]!)
        guideButton = NSButton(title: "", target: target, action: selectors[.reshowInstall]!)
        previewView = SetupWindowPreviewView(model: state.presentation.previews.general)
        connectionDetailsPopover = NSPopover()
        nativeHostDetailRow = SetupWindowGeneralPopoverRow(title: localized("app.setup.general.connection.nativeHost"))
        appSocketDetailRow = SetupWindowGeneralPopoverRow(title: localized("app.setup.general.connection.appSocket"))
        terminalDetailRow = SetupWindowGeneralPopoverRow(title: localized("app.setup.general.connection.terminal"))
        toolDetailRows = Dictionary(uniqueKeysWithValues: ["zoxide", "gh", "claude"].map {
            ($0, SetupWindowGeneralPopoverRow(title: $0))
        })
        cmuxActionsRow = NSStackView()

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 720).isActive = true

        buildIdentityRow()
        buildRequestStatusRow()
        buildTerminalRow()
        buildActivationRow()
        buildLanguageAndActions()
        buildConnectionPopover()

        mainContentStack.orientation = .horizontal
        mainContentStack.alignment = .top
        mainContentStack.distribution = .fill
        mainContentStack.spacing = 14
        mainContentStack.translatesAutoresizingMaskIntoConstraints = false
        let leftColumn = NSStackView(views: [
            identityRow,
            requestStatusRow,
            terminalRow,
            terminalTestResultLabel,
            activationRow,
            hintLabel,
            languageSection,
        ])
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.distribution = .fill
        leftColumn.spacing = 13
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.widthAnchor.constraint(equalToConstant: 390).isActive = true
        previewColumn.orientation = .vertical
        previewColumn.alignment = .leading
        previewColumn.spacing = 9
        previewColumn.translatesAutoresizingMaskIntoConstraints = false
        previewColumn.addArrangedSubview(previewTitle)
        previewColumn.addArrangedSubview(previewView)
        previewColumn.addArrangedSubview(previewCaption)
        previewColumn.widthAnchor.constraint(equalToConstant: 280).isActive = true
        previewView.heightAnchor.constraint(equalToConstant: 236).isActive = true
        previewView.widthAnchor.constraint(equalTo: previewColumn.widthAnchor).isActive = true
        mainContentStack.addArrangedSubview(leftColumn)
        mainContentStack.addArrangedSubview(previewColumn)
        addSubview(mainContentStack)
        NSLayoutConstraint.activate([
            mainContentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            mainContentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            mainContentStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            mainContentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        update(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private let identityRow = NSStackView()
    private let requestStatusRow = NSStackView()
    private let terminalRow = NSStackView()
    private let activationRow = NSStackView()
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let previewColumn = NSStackView()
    private let previewTitle = NSTextField(labelWithString: localized("app.setup.preview.general.title"))
    private let previewCaption = NSTextField(wrappingLabelWithString: "")

    func update(_ state: SetupWindowGeneralPaneState) {
        updateRequestStatus(state)
        updateTerminalControls(state)
        updateActivation(state)
        updateLanguageControls(state)
        updateConnectionPopover(state)
        updateTestResult(state)
        previewView.update(state.presentation.previews.general)
        previewCaption.stringValue = previewView.effectDescription
        versionLabel.stringValue = state.appVersion
    }

    private func buildIdentityRow() {
        identityIcon.image = NSApp.applicationIconImage
        identityIcon.imageScaling = .scaleProportionallyUpOrDown
        identityIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            identityIcon.widthAnchor.constraint(equalToConstant: 34),
            identityIcon.heightAnchor.constraint(equalToConstant: 34),
        ])

        let name = NSTextField(labelWithString: "Terminal Checkout")
        name.font = Theme.ui(15, .semibold)
        name.textColor = Theme.text
        versionLabel.font = Theme.ui(11)
        versionLabel.textColor = Theme.textDim
        let titles = NSStackView(views: [name, versionLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        identityRow.orientation = .horizontal
        identityRow.alignment = .centerY
        identityRow.spacing = 10
        identityRow.addArrangedSubview(identityIcon)
        identityRow.addArrangedSubview(titles)
    }

    private func buildRequestStatusRow() {
        requestDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            requestDot.widthAnchor.constraint(equalToConstant: 8),
            requestDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        requestStatusLabel.font = Theme.ui(12, .medium)
        requestStatusLabel.textColor = Theme.text
        connectionDetailsButton.title = localized("app.setup.general.connectionDetails")
        connectionDetailsButton.bezelStyle = .rounded
        connectionDetailsButton.target = self
        connectionDetailsButton.action = #selector(presentConnectionDetails(_:))
        connectionDetailsButton.identifier = setupWindowGeneralPaneRole(#selector(presentConnectionDetails(_:)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        requestStatusRow.orientation = .horizontal
        requestStatusRow.alignment = .centerY
        requestStatusRow.spacing = 8
        requestStatusRow.addArrangedSubview(requestDot)
        requestStatusRow.addArrangedSubview(requestStatusLabel)
        requestStatusRow.addArrangedSubview(spacer)
        requestStatusRow.addArrangedSubview(connectionDetailsButton)
    }

    private func buildTerminalRow() {
        let title = NSTextField(labelWithString: localized("app.setup.general.terminal.title"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text
        terminalPopup.target = actionTarget
        terminalPopup.action = selectors[.terminalChanged]
        terminalPopup.identifier = setupWindowGeneralPaneRole(selectors[.terminalChanged]!)
        terminalPopup.widthAnchor.constraint(equalToConstant: 137).isActive = true
        for terminal in Terminal.allCases {
            terminalPopup.addItem(withTitle: terminalName(terminal))
            terminalPopup.lastItem?.representedObject = terminal.rawValue
        }
        terminalDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalDot.widthAnchor.constraint(equalToConstant: 8),
            terminalDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        terminalStatusLabel.font = Theme.ui(11)
        terminalStatusLabel.lineBreakMode = .byTruncatingTail
        terminalTestButton.title = localized("app.setup.general.terminalTest.title")
        terminalTestButton.bezelStyle = .rounded
        terminalTestButton.identifier = setupWindowGeneralPaneRole(selectors[.testTerminal]!)
        terminalTestResultLabel.font = Theme.ui(11)
        terminalTestResultLabel.textColor = Theme.textDim
        terminalTestResultLabel.isHidden = true

        let status = NSStackView(views: [terminalDot, terminalStatusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        terminalRow.orientation = .horizontal
        terminalRow.alignment = .centerY
        terminalRow.spacing = 7
        terminalRow.addArrangedSubview(title)
        terminalRow.addArrangedSubview(terminalPopup)
        terminalRow.addArrangedSubview(status)
        terminalRow.addArrangedSubview(terminalTestButton)
    }

    private func buildActivationRow() {
        let title = NSTextField(labelWithString: localized("app.setup.general.afterAction.title"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text
        activationSegment.setLabel(localized("app.setup.general.afterAction.terminal"), forSegment: 0)
        activationSegment.setLabel(localized("app.setup.general.afterAction.current"), forSegment: 1)
        activationSegment.segmentStyle = .rounded
        activationSegment.setWidth(118, forSegment: 0)
        activationSegment.setWidth(130, forSegment: 1)
        activationSegment.identifier = setupWindowGeneralPaneRole(selectors[.tabActivationChanged]!)
        activationSegment.setAccessibilityLabel(localized("app.setup.general.afterAction.title"))
        activationRow.orientation = .horizontal
        activationRow.alignment = .centerY
        activationRow.spacing = 10
        activationRow.addArrangedSubview(title)
        activationRow.addArrangedSubview(activationSegment)
        hintLabel.font = Theme.ui(11)
        hintLabel.textColor = Theme.textDim
        hintLabel.maximumNumberOfLines = 2
    }

    private func buildLanguageAndActions() {
        languagePopup.addItem(withTitle: localized("app.language.followSystem"))
        languagePopup.lastItem?.representedObject = automaticLocalePreference
        for tag in supportedLocales {
            languagePopup.addItem(withTitle: Self.languageMenuTitles[tag] ?? tag)
            languagePopup.lastItem?.representedObject = tag
        }
        languagePopup.target = actionTarget
        languagePopup.action = selectors[.languageChanged]
        languagePopup.identifier = setupWindowGeneralPaneRole(selectors[.languageChanged]!)
        languagePopup.widthAnchor.constraint(equalToConstant: 185).isActive = true
        languageRestartButton.title = localized("app.button.restartNow")
        languageRestartButton.bezelStyle = .rounded
        languageRestartButton.identifier = setupWindowGeneralPaneRole(selectors[.restartForLanguage]!)
        languageNoteLabel.font = Theme.ui(11)
        languageNoteLabel.textColor = Theme.textDim

        optionsButton.title = localized("app.setup.general.editGitHubButton")
        optionsButton.bezelStyle = .rounded
        optionsButton.identifier = setupWindowGeneralPaneRole(selectors[.openOptionsPage]!)
        guideButton.title = localized("app.setup.general.showGuideAgain")
        guideButton.bezelStyle = .rounded
        guideButton.identifier = setupWindowGeneralPaneRole(selectors[.reshowInstall]!)

        let languageTitle = NSTextField(labelWithString: localized("app.card.language.title"))
        languageTitle.font = Theme.ui(12, .medium)
        languageTitle.textColor = Theme.text
        let languageChoice = NSStackView(views: [languageTitle, languagePopup])
        languageChoice.orientation = .horizontal
        languageChoice.alignment = .centerY
        languageChoice.spacing = 8
        let restartRow = NSStackView(views: [languageNoteLabel, languageRestartButton])
        restartRow.orientation = .horizontal
        restartRow.alignment = .centerY
        restartRow.spacing = 8
        let utilityRow = NSStackView(views: [optionsButton, guideButton])
        utilityRow.orientation = .horizontal
        utilityRow.alignment = .centerY
        utilityRow.spacing = 7
        languageSection.orientation = .vertical
        languageSection.alignment = .leading
        languageSection.spacing = 7
        languageSection.addArrangedSubview(languageChoice)
        languageSection.addArrangedSubview(restartRow)
        languageSection.addArrangedSubview(utilityRow)
    }

    private func buildConnectionPopover() {
        connectionDetailsPopover.behavior = .transient
        let controller = NSViewController()
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: localized("app.setup.general.connectionDetails"))
        title.font = Theme.ui(14, .semibold)
        title.textColor = Theme.text
        let chromeHeader = NSStackView(views: [popoverRequestDot, NSTextField(labelWithString: localized("app.setup.general.connection.chrome"))])
        chromeHeader.orientation = .horizontal
        chromeHeader.alignment = .centerY
        chromeHeader.spacing = 7
        extensionStatusExplanation.font = Theme.ui(11)
        extensionStatusExplanation.textColor = Theme.textDim
        extensionStatusExplanation.maximumNumberOfLines = 0
        extensionStatusExplanation.preferredMaxLayoutWidth = 320

        let cmuxConfig = generalButton(
            localized("app.setup.action.openCmuxConfig"), action: .openCmuxConfig
        )
        let cmuxRefresh = generalButton(
            localized("app.setup.action.refreshCmuxStatus"), action: .refreshCmuxStatus
        )
        cmuxActionsRow.orientation = .horizontal
        cmuxActionsRow.alignment = .centerY
        cmuxActionsRow.spacing = 7
        cmuxActionsRow.addArrangedSubview(cmuxConfig)
        cmuxActionsRow.addArrangedSubview(cmuxRefresh)

        content.addArrangedSubview(title)
        content.addArrangedSubview(chromeHeader)
        content.addArrangedSubview(extensionStatusExplanation)
        content.addArrangedSubview(nativeHostDetailRow)
        content.addArrangedSubview(appSocketDetailRow)
        content.addArrangedSubview(terminalDetailRow)
        let toolsTitle = NSTextField(labelWithString: localized("app.setup.general.connection.tools"))
        toolsTitle.font = Theme.ui(12, .semibold)
        toolsTitle.textColor = Theme.text
        content.addArrangedSubview(toolsTitle)
        for tool in ["zoxide", "gh", "claude"] {
            content.addArrangedSubview(toolDetailRows[tool]!)
        }
        content.addArrangedSubview(cmuxActionsRow)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 356, height: 340))
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 15),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -15),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
        ])
        controller.view = root
        connectionDetailsPopover.contentViewController = controller
        connectionDetailsPopover.contentSize = NSSize(width: 356, height: 340)
    }

    private func generalButton(_ title: String, action: SetupWindowGeneralAction) -> NSButton {
        let button = NSButton(title: title, target: actionTarget, action: selectors[action]!)
        button.bezelStyle = .rounded
        button.identifier = setupWindowGeneralPaneRole(selectors[action]!)
        return button
    }

    private func updateRequestStatus(_ state: SetupWindowGeneralPaneState) {
        switch state.presentation.connectionSentence {
        case .waitingForFirstRequest:
            requestDot.update(tone: .warning)
            requestStatusLabel.stringValue = localized("app.setup.general.request.waiting")
            extensionStatusExplanation.stringValue = localized("app.setup.general.connection.chrome.waiting")
        case .requestRecorded:
            requestDot.update(tone: .success)
            requestStatusLabel.stringValue = localized("app.setup.general.request.recorded", state.requestRelativeTime ?? "")
            extensionStatusExplanation.stringValue = localized("app.setup.general.connection.chrome.recorded", state.requestRelativeTime ?? "")
        }
        optionsButton.isHidden = !Self.hasRequestRecord(state.presentation)
    }

    private func updateTerminalControls(_ state: SetupWindowGeneralPaneState) {
        for terminal in Terminal.allCases {
            guard let item = terminalPopup.itemArray.first(where: {
                ($0.representedObject as? String) == terminal.rawValue
            }) else { continue }
            if state.isInstalled(terminal) {
                item.title = terminalName(terminal)
                item.isEnabled = true
            } else {
                item.title = localized("app.terminal.notInstalled", terminalName(terminal))
                item.isEnabled = false
            }
        }
        if let index = Terminal.allCases.firstIndex(of: state.terminal) {
            terminalPopup.selectItem(at: index)
        }
        terminalStatusLabel.stringValue = state.terminalStatus.text
        terminalDot.update(tone: state.terminalStatus.tone)
        hintLabel.stringValue = state.terminal == .warp
            ? localized("app.setup.general.hint.warp")
            : localized(
                "app.setup.general.hint.other",
                state.terminal.cmuxChannel == nil
                    ? localized("app.setup.preview.general.destination.tab")
                    : localized("app.setup.preview.general.destination.workspace")
            )
    }

    private func updateActivation(_ state: SetupWindowGeneralPaneState) {
        savedTabActivationForTesting = state.savedTabActivation
        if state.terminal == .warp {
            activationSegment.selectedSegment = 0
            activationSegment.isEnabled = false
        } else {
            activationSegment.selectedSegment = state.savedTabActivation == .background ? 1 : 0
            activationSegment.isEnabled = true
        }
        activationSegment.setAccessibilityValue(
            activationSegment.label(forSegment: activationSegment.selectedSegment)
        )
    }

    private func updateLanguageControls(_ state: SetupWindowGeneralPaneState) {
        let entries = languagePopup.itemArray.map { $0.representedObject as? String }
        languagePopup.selectItem(at: languagePickerIndex(
            stored: state.storedLanguage,
            drawn: state.resolvedLanguage,
            entries: entries
        ))
        languageNoteLabel.stringValue = state.languageChange.message ?? ""
        let showRestart = state.languageChange != .unchanged
        languageNoteLabel.isHidden = !showRestart
        languageRestartButton.isHidden = !showRestart
    }

    private func updateConnectionPopover(_ state: SetupWindowGeneralPaneState) {
        nativeHostDetailRow.update(state.nativeHostStatus)
        appSocketDetailRow.update(state.appSocketStatus)
        terminalDetailRow.titleLabel.stringValue = localized("app.setup.general.connection.terminal")
            + " — " + terminalName(state.terminal)
        terminalDetailRow.update(state.terminalStatus)
        for name in ["zoxide", "gh", "claude"] {
            let status: SetupWindowGeneralIndicator
            guard let tools = state.tools, let available = tools.available[name] else {
                status = .init(text: localized("app.setup.general.tools.notChecked"), tone: .neutral)
                toolDetailRows[name]?.update(status)
                continue
            }
            if !available {
                status = .init(text: localized("app.setup.general.tools.notFound"), tone: .warning)
            } else if name == "claude", tools.executable[name] == false {
                status = .init(text: localized("app.setup.general.tools.notExecutable"), tone: .warning)
            } else {
                status = .init(text: localized("app.setup.general.tools.found"), tone: .success)
            }
            toolDetailRows[name]?.update(status)
        }
        let requestRecorded = Self.hasRequestRecord(state.presentation)
        popoverRequestDot.update(tone: requestRecorded ? .success : .warning)
        cmuxActionsRow.isHidden = state.terminal.cmuxChannel == nil
    }

    private func updateTestResult(_ state: SetupWindowGeneralPaneState) {
        switch state.terminalTestResult {
        case .notRun:
            terminalTestResultLabel.isHidden = true
            terminalTestResultLabel.stringValue = ""
        case .running:
            terminalTestResultLabel.stringValue = localized("app.test.running")
            terminalTestResultLabel.textColor = Theme.textDim
            terminalTestResultLabel.isHidden = false
        case .succeeded:
            let destination = state.terminal.cmuxChannel == nil
                ? localized("app.setup.preview.general.destination.tab")
                : localized("app.setup.preview.general.destination.workspace")
            terminalTestResultLabel.stringValue = localized("app.setup.general.terminalTest.success", destination)
            terminalTestResultLabel.textColor = Theme.ok
            terminalTestResultLabel.isHidden = false
        case .failed(let reason):
            terminalTestResultLabel.stringValue = localized("app.test.failed", reason)
            terminalTestResultLabel.textColor = Theme.err
            terminalTestResultLabel.isHidden = false
        }
    }

    @objc private func presentConnectionDetails(_ sender: NSButton) {
        connectionDetailsPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private static func hasRequestRecord(_ presentation: SetupWindowPresentation) -> Bool {
        if case .requestRecorded = presentation.connectionSentence { return true }
        return false
    }

    private static let languageMenuTitles = [
        "en": "English",
        "ko": "한국어",
        "ja": "日本語",
        "zh-Hans": "简体中文",
        "zh-Hant": "繁體中文",
    ]
}

private final class SetupWindowGeneralStatusDot: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(tone: SetupWindowGeneralStatusTone) {
        layer?.backgroundColor = tone.color.cgColor
        setAccessibilityLabel(localized(Self.accessibilityKey(for: tone)))
    }

    private static func accessibilityKey(for tone: SetupWindowGeneralStatusTone) -> StaticString {
        switch tone {
        case .success: return "app.setup.severity.success"
        case .warning: return "app.setup.severity.warning"
        case .error: return "app.setup.severity.error"
        case .neutral: return "app.setup.severity.unknown"
        }
    }
}

private final class SetupWindowGeneralPopoverRow: NSStackView {
    let titleLabel: NSTextField
    private let dot = SetupWindowGeneralStatusDot()
    private let valueLabel = NSTextField(labelWithString: "")

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 7
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        titleLabel.font = Theme.ui(11, .medium)
        titleLabel.textColor = Theme.text
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        valueLabel.font = Theme.ui(11)
        valueLabel.textColor = Theme.textDim
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addArrangedSubview(dot)
        addArrangedSubview(titleLabel)
        addArrangedSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ indicator: SetupWindowGeneralIndicator) {
        dot.update(tone: indicator.tone)
        valueLabel.stringValue = indicator.text
    }
}

private func terminalName(_ terminal: Terminal) -> String {
    switch terminal {
    case .iterm: return "iTerm2"
    case .wezterm: return "WezTerm"
    case .warp: return "Warp"
    case .cmux: return "cmux"
    case .cmuxNightly: return "cmux NIGHTLY"
    }
}
