import AppKit
import Core

enum SetupWindowSlackValidationNotice {
    case workDirectory(String)
    case instruction(String)
}

struct SetupWindowSlackPaneState {
    let presentation: SetupWindowPresentation
    let storedWorkDirectory: String
    let storedInstruction: String
    let validationNotice: SetupWindowSlackValidationNotice?
    let hotKeyDisplayString: String?
    let isRecordingHotKey: Bool
    let needsModifierWarning: Bool
    let registrationFailureStatus: Int32?
    let loginItemStatus: LoginItemStatus
    let loginItemFailureMessage: String?
}

enum SetupWindowSlackAction: CaseIterable, Hashable {
    case slackThreadSettingsEdited
    case chooseSlackWorkDirectory
    case recordSlackHotKey
    case clearSlackHotKey
    case slackLoginItemToggled
}

func setupWindowSlackPreviewCaption(_ sentence: SetupWindowEffectSentence) -> String {
    switch sentence {
    case .slackClaudeInWorkingFolder:
        return localized("app.setup.preview.slack.caption")
    case .general, .githubRowsOpenNewTabs, .githubCmuxBatch:
        preconditionFailure("the Slack pane received a non-Slack effect sentence")
    }
}

final class SetupWindowSlackPane: NSView {
    let workDirectoryField = NSTextField(string: "")
    let chooseWorkDirectoryButton = NSButton(title: "", target: nil, action: nil)
    let workDirectoryValidationLabel = makeSetupWindowWrappingLabel()
    let instructionField = NSTextField(string: "")
    let instructionValidationLabel = makeSetupWindowWrappingLabel()
    let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    let clearHotKeyButton = NSButton(title: "", target: nil, action: nil)
    let hotKeyStatusLabel = makeSetupWindowWrappingLabel()
    let loginItemCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let loginItemStatusLabel = makeSetupWindowWrappingLabel()
    let previewTitleLabel = makeSetupWindowWrappingLabel()
    let previewView: SetupWindowPreviewView
    let previewCaptionLabel = makeSetupWindowWrappingLabel()

    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowSlackAction: Selector]
    private let contentStack = NSStackView()
    private let leftColumn = NSStackView()
    private let workDirectorySection = NSStackView()
    private let instructionSection = NSStackView()
    private let hotKeySection = NSStackView()
    private let loginItemSection = NSStackView()
    private let previewColumn = NSStackView()
    private var drawnWorkDirectory: String?
    private var drawnInstruction: String?

    var workDirectoryValidationIsHiddenForTesting: Bool { workDirectoryValidationLabel.isHidden }
    var instructionValidationIsHiddenForTesting: Bool { instructionValidationLabel.isHidden }
    var hotKeyStatusIsHiddenForTesting: Bool { hotKeyStatusLabel.isHidden }
    var loginItemStatusIsHiddenForTesting: Bool { loginItemStatusLabel.isHidden }
    var hotKeyStatusTextForTesting: String { hotKeyStatusLabel.stringValue }
    var loginItemStatusTextForTesting: String { loginItemStatusLabel.stringValue }
    var previewTitleForTesting: String { previewTitleLabel.stringValue }
    var leftColumnForTesting: NSStackView { leftColumn }
    var wrappingStatusLabelsForTesting: [NSTextField] {
        [workDirectoryValidationLabel, instructionValidationLabel, hotKeyStatusLabel,
         loginItemStatusLabel, previewTitleLabel, previewCaptionLabel]
    }

    var actionControlsForTesting: [(NSControl, SetupWindowSlackAction, String?)] {
        [
            (workDirectoryField, .slackThreadSettingsEdited, "workDirectory"),
            (instructionField, .slackThreadSettingsEdited, "instruction"),
            (chooseWorkDirectoryButton, .chooseSlackWorkDirectory, nil),
            (hotKeyButton, .recordSlackHotKey, nil),
            (clearHotKeyButton, .clearSlackHotKey, nil),
            (loginItemCheckbox, .slackLoginItemToggled, nil),
        ]
    }

    init(
        state: SetupWindowSlackPaneState,
        target: AnyObject,
        selectors: [SetupWindowSlackAction: Selector]
    ) {
        precondition(
            SetupWindowSlackAction.allCases.allSatisfy { selectors[$0] != nil },
            "the Slack pane needs a selector for every controller action it presents"
        )
        actionTarget = target
        self.selectors = selectors
        previewView = SetupWindowPreviewView(slackModel: state.presentation.previews.slack)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 720).isActive = true

        buildWorkDirectorySection()
        buildInstructionSection()
        buildHotKeySection()
        buildLoginItemSection()
        buildPreviewColumn()
        buildLayout()
        update(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ state: SetupWindowSlackPaneState) {
        updateDraft(
            workDirectoryField,
            storedValue: state.storedWorkDirectory,
            drawnValue: &drawnWorkDirectory
        )
        updateDraft(
            instructionField,
            storedValue: state.storedInstruction,
            drawnValue: &drawnInstruction
        )

        workDirectoryValidationLabel.stringValue = ""
        instructionValidationLabel.stringValue = ""
        workDirectoryValidationLabel.isHidden = true
        instructionValidationLabel.isHidden = true
        switch state.validationNotice {
        case .workDirectory(let message):
            workDirectoryValidationLabel.stringValue = message
            workDirectoryValidationLabel.isHidden = message.isEmpty
        case .instruction(let message):
            instructionValidationLabel.stringValue = message
            instructionValidationLabel.isHidden = message.isEmpty
        case nil:
            break
        }

        updateHotKey(state)
        updateLoginItem(state)

        let preview = state.presentation.previews.slack
        previewView.update(slackModel: preview)
        if let hotKeyDisplayString = state.hotKeyDisplayString {
            previewTitleLabel.stringValue = localized(
                "app.setup.preview.slack.title.withHotKey",
                hotKeyDisplayString
            )
        } else {
            previewTitleLabel.stringValue = localized("app.setup.preview.slack.title.withoutHotKey")
        }
        previewCaptionLabel.stringValue = setupWindowSlackPreviewCaption(preview.effectSentence)
    }

    private func updateDraft(_ field: NSTextField, storedValue: String, drawnValue: inout String?) {
        if field.stringValue == storedValue {
            drawnValue = storedValue
        } else if !isEditing(field),
                  drawnValue == nil || field.stringValue == drawnValue {
            field.stringValue = storedValue
            drawnValue = storedValue
        }
    }

    private func isEditing(_ field: NSTextField) -> Bool {
        guard let window, let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private func updateHotKey(_ state: SetupWindowSlackPaneState) {
        if state.isRecordingHotKey {
            hotKeyButton.title = localized("app.slack.hotKey.recording")
        } else if let hotKeyDisplayString = state.hotKeyDisplayString {
            hotKeyButton.title = hotKeyDisplayString
        } else {
            hotKeyButton.title = localized("app.slack.hotKey.set")
        }
        clearHotKeyButton.isHidden = state.isRecordingHotKey || state.hotKeyDisplayString == nil

        if state.isRecordingHotKey, state.needsModifierWarning {
            hotKeyStatusLabel.stringValue = localized("app.slack.hotKey.needsModifier")
            hotKeyStatusLabel.textColor = Theme.warn
            hotKeyStatusLabel.isHidden = false
        } else if !state.isRecordingHotKey, let status = state.registrationFailureStatus {
            hotKeyStatusLabel.stringValue = localized("app.slack.hotKey.registerFailed", status)
            hotKeyStatusLabel.textColor = Theme.err
            hotKeyStatusLabel.isHidden = false
        } else {
            hotKeyStatusLabel.stringValue = ""
            hotKeyStatusLabel.isHidden = true
        }
    }

    private func updateLoginItem(_ state: SetupWindowSlackPaneState) {
        loginItemCheckbox.state = state.loginItemStatus == .disabled ? .off : .on
        if let failure = state.loginItemFailureMessage, !failure.isEmpty {
            loginItemStatusLabel.stringValue = failure
            loginItemStatusLabel.textColor = Theme.err
            loginItemStatusLabel.isHidden = false
        } else if state.loginItemStatus == .requiresApproval {
            loginItemStatusLabel.stringValue = slackLoginItemStatusMessage(state.loginItemStatus)
            loginItemStatusLabel.textColor = Theme.warn
            loginItemStatusLabel.isHidden = false
        } else {
            loginItemStatusLabel.stringValue = ""
            loginItemStatusLabel.isHidden = true
        }
    }

    private func buildWorkDirectorySection() {
        let title = NSTextField(labelWithString: localized("app.setup.slack.workDirectory.label"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text
        workDirectoryField.font = Theme.mono(11.5)
        workDirectoryField.placeholderString = localized("app.slack.workDirectory.placeholder")
        workDirectoryField.target = actionTarget
        workDirectoryField.action = selectors[.slackThreadSettingsEdited]
        workDirectoryField.identifier = setupWindowControlRole(
            selectors[.slackThreadSettingsEdited]!, "workDirectory"
        )
        workDirectoryField.cell?.sendsActionOnEndEditing = true
        workDirectoryField.widthAnchor.constraint(equalToConstant: 250).isActive = true

        chooseWorkDirectoryButton.title = localized("app.button.chooseFolder")
        chooseWorkDirectoryButton.bezelStyle = .rounded
        chooseWorkDirectoryButton.target = actionTarget
        chooseWorkDirectoryButton.action = selectors[.chooseSlackWorkDirectory]
        chooseWorkDirectoryButton.identifier = setupWindowControlRole(
            selectors[.chooseSlackWorkDirectory]!
        )

        let row = NSStackView(views: [workDirectoryField, chooseWorkDirectoryButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7

        workDirectoryValidationLabel.font = Theme.ui(11)
        workDirectoryValidationLabel.textColor = Theme.err
        workDirectoryValidationLabel.maximumNumberOfLines = 2
        workDirectoryValidationLabel.isHidden = true
        workDirectorySection.orientation = .vertical
        workDirectorySection.alignment = .leading
        workDirectorySection.spacing = 6
        workDirectorySection.addArrangedSubview(title)
        workDirectorySection.addArrangedSubview(row)
        workDirectorySection.addArrangedSubview(workDirectoryValidationLabel)
    }

    private func buildInstructionSection() {
        let title = NSTextField(labelWithString: localized("app.setup.slack.instruction.label"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text
        instructionField.font = Theme.mono(11.5)
        instructionField.placeholderString = localized("app.slack.instruction.help")
        instructionField.target = actionTarget
        instructionField.action = selectors[.slackThreadSettingsEdited]
        instructionField.identifier = setupWindowControlRole(
            selectors[.slackThreadSettingsEdited]!, "instruction"
        )
        instructionField.cell?.sendsActionOnEndEditing = true
        instructionField.widthAnchor.constraint(equalToConstant: 374).isActive = true
        instructionValidationLabel.font = Theme.ui(11)
        instructionValidationLabel.textColor = Theme.err
        instructionValidationLabel.maximumNumberOfLines = 2
        instructionValidationLabel.isHidden = true
        instructionSection.orientation = .vertical
        instructionSection.alignment = .leading
        instructionSection.spacing = 6
        instructionSection.addArrangedSubview(title)
        instructionSection.addArrangedSubview(instructionField)
        instructionSection.addArrangedSubview(instructionValidationLabel)
    }

    private func buildHotKeySection() {
        let title = NSTextField(labelWithString: localized("app.slack.hotKey.label"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text

        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.target = actionTarget
        hotKeyButton.action = selectors[.recordSlackHotKey]
        hotKeyButton.identifier = setupWindowControlRole(selectors[.recordSlackHotKey]!)

        clearHotKeyButton.title = localized("app.slack.hotKey.clear")
        clearHotKeyButton.bezelStyle = .rounded
        clearHotKeyButton.target = actionTarget
        clearHotKeyButton.action = selectors[.clearSlackHotKey]
        clearHotKeyButton.identifier = setupWindowControlRole(selectors[.clearSlackHotKey]!)

        let row = NSStackView(views: [title, hotKeyButton, clearHotKeyButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        hotKeyStatusLabel.font = Theme.ui(11)
        hotKeyStatusLabel.maximumNumberOfLines = 2
        hotKeyStatusLabel.isHidden = true
        hotKeySection.orientation = .vertical
        hotKeySection.alignment = .leading
        hotKeySection.spacing = 6
        hotKeySection.addArrangedSubview(row)
        hotKeySection.addArrangedSubview(hotKeyStatusLabel)
    }

    private func buildLoginItemSection() {
        loginItemCheckbox.title = localized("app.slack.loginItem.title")
        loginItemCheckbox.target = actionTarget
        loginItemCheckbox.action = selectors[.slackLoginItemToggled]
        loginItemCheckbox.identifier = setupWindowControlRole(selectors[.slackLoginItemToggled]!)

        let hint = makeSetupWindowWrappingLabel(localized("app.slack.loginItem.help"))
        hint.font = Theme.ui(10.5)
        hint.textColor = Theme.textDim
        loginItemStatusLabel.font = Theme.ui(11)
        loginItemStatusLabel.maximumNumberOfLines = 2
        loginItemStatusLabel.isHidden = true
        loginItemSection.orientation = .vertical
        loginItemSection.alignment = .leading
        loginItemSection.spacing = 6
        loginItemSection.addArrangedSubview(loginItemCheckbox)
        loginItemSection.addArrangedSubview(loginItemStatusLabel)
        loginItemSection.addArrangedSubview(hint)
    }

    private func buildPreviewColumn() {
        previewTitleLabel.font = Theme.ui(11, .semibold)
        previewTitleLabel.textColor = Theme.textDim
        previewTitleLabel.maximumNumberOfLines = 2
        previewView.heightAnchor.constraint(equalToConstant: 236).isActive = true
        previewCaptionLabel.font = Theme.ui(10)
        previewCaptionLabel.textColor = Theme.textDim
        previewCaptionLabel.maximumNumberOfLines = 4
        previewColumn.orientation = .vertical
        previewColumn.alignment = .leading
        previewColumn.spacing = 8
        previewColumn.addArrangedSubview(previewTitleLabel)
        previewColumn.addArrangedSubview(previewView)
        previewColumn.addArrangedSubview(previewCaptionLabel)
    }

    private func buildLayout() {
        for view in [
            workDirectorySection,
            instructionSection,
            hotKeySection,
            loginItemSection,
        ] {
            leftColumn.addArrangedSubview(view)
        }
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.distribution = .fill
        leftColumn.spacing = 15
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.setHuggingPriority(.required, for: .vertical)
        leftColumn.setContentCompressionResistancePriority(.required, for: .vertical)
        leftColumn.widthAnchor.constraint(equalToConstant: 390).isActive = true

        contentStack.orientation = .horizontal
        contentStack.alignment = .top
        contentStack.distribution = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(leftColumn)
        contentStack.addArrangedSubview(previewColumn)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            previewColumn.widthAnchor.constraint(equalToConstant: 280),
            previewView.widthAnchor.constraint(equalTo: previewColumn.widthAnchor),
        ])
    }

}
