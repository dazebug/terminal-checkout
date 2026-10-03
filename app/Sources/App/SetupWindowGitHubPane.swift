import AppKit
import Core

struct SetupWindowGitHubPaneState {
    let presentation: SetupWindowPresentation
    let baseDirectory: String
    let baseDirectoryDraftProblem: BaseDirectoryProblem?
    let storedBaseDirectoryProblem: BaseDirectoryProblem?
    let cmuxIdentityMode: String?
    let cmuxFixedName: String?
}

enum SetupWindowGitHubAction: CaseIterable, Hashable {
    case chooseBaseDirectory
    case baseDirectoryEdited
    case cmuxPlacementArrangementChanged
    case cmuxPlacementIdentityChanged
    case cmuxPlacementNameEdited
}

func setupWindowGitHubEffectSentence(_ sentence: SetupWindowEffectSentence) -> String {
    switch sentence {
    case .githubRowsOpenNewTabs:
        return localized("app.setup.github.effect.nonCmux")
    case .githubCmuxBatch(_, let arrangement, let identity):
        switch (arrangement, identity) {
        case (.panePerItem, .alwaysNew):
            return localized("app.setup.github.effect.pane.new")
        case (.tabPerItem, .alwaysNew):
            return localized("app.setup.github.effect.tab.new")
        case (.workspacePerItem, .alwaysNew):
            return localized("app.setup.github.effect.workspace")
        case (.panePerItem, .fixedName(let name)):
            return localized("app.setup.github.effect.pane.named", name)
        case (.tabPerItem, .fixedName(let name)):
            return localized("app.setup.github.effect.tab.named", name)
        case (.workspacePerItem, .fixedName):
            // Core's effectiveIdentityMode makes this branch unreachable for workspace-per-item.
            preconditionFailure("workspace-per-item must use a new identity")
        }
    case .general, .slackClaudeInWorkingFolder:
        preconditionFailure("the GitHub pane received a non-GitHub effect sentence")
    }
}

private func setupWindowBaseDirectoryReason(_ problem: BaseDirectoryProblem) -> String {
    switch problem {
    case .notAbsolute:
        return localized("app.baseDir.reason.notAbsolute")
    case .invalidCharacters:
        return localized("app.baseDir.reason.invalidCharacters")
    }
}

final class SetupWindowGitHubPane: NSView {
    let baseDirectoryField: NSTextField
    let chooseBaseDirectoryButton: NSButton
    let baseDirectoryNoticeLabel = makeSetupWindowWrappingLabel()
    let arrangementSegment: NSSegmentedControl
    let identitySegment: NSSegmentedControl
    let workspaceNameField: NSTextField
    let emptyWorkspaceNameHint = NSTextField(labelWithString: "")
    let previewTitleLabel = NSTextField(labelWithString: "")
    let previewView: SetupWindowPreviewView

    private weak var actionTarget: AnyObject?
    private let selectors: [SetupWindowGitHubAction: Selector]
    private let baseDirectoryNoticeDot = SetupWindowGitHubStatusDot()
    private let baseDirectoryNoticeRow = NSStackView()
    private let cmuxSection = NSStackView()
    private let contentStack = NSStackView()
    private let leftColumn = NSStackView()
    private var drawnBaseDirectory: String?
    private var drawnCmuxPlacementName: String?

    var selectedArrangementForTesting: CmuxPlacementArrangement {
        guard case .cmux(let arrangement, _, _) = currentGitHubPreview.destination else {
            return .panePerItem
        }
        return arrangement
    }

    private var currentGitHubPreview: SetupWindowGitHubPreview

    init(
        state: SetupWindowGitHubPaneState,
        target: AnyObject,
        selectors: [SetupWindowGitHubAction: Selector]
    ) {
        precondition(
            SetupWindowGitHubAction.allCases.allSatisfy { selectors[$0] != nil },
            "the GitHub pane needs a selector for every controller action it presents"
        )
        self.actionTarget = target
        self.selectors = selectors
        currentGitHubPreview = state.presentation.previews.github
        baseDirectoryField = NSTextField(string: "")
        chooseBaseDirectoryButton = NSButton(title: "", target: nil, action: nil)
        arrangementSegment = NSSegmentedControl(
            labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil
        )
        identitySegment = NSSegmentedControl(
            labels: ["", ""], trackingMode: .selectOne, target: nil, action: nil
        )
        workspaceNameField = NSTextField(string: "")
        previewView = SetupWindowPreviewView(githubModel: state.presentation.previews.github)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 720).isActive = true

        buildBaseDirectoryControls()
        buildCmuxControls()
        buildPreviewColumn()
        buildLayout()
        update(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var baseDirectoryNoticeText: String { baseDirectoryNoticeLabel.stringValue }
    var baseDirectoryNoticeRowIsHiddenForTesting: Bool { baseDirectoryNoticeRow.isHidden }
    var cmuxSectionIsHiddenForTesting: Bool { cmuxSection.isHidden }
    var isCmuxPlacementVisible: Bool { !cmuxSection.isHidden }
    var workspaceNameHintIsHidden: Bool { emptyWorkspaceNameHint.isHidden }
    var effectSentenceForTesting: String {
        setupWindowGitHubEffectSentence(currentGitHubPreview.effectSentence)
    }
    var previewCaptionForTesting: String { previewCaption.stringValue }
    var previewCaptionWidthForTesting: CGFloat { previewCaption.frame.width }
    var leftColumnForTesting: NSStackView { leftColumn }
    var wrappingStatusLabelsForTesting: [NSTextField] {
        [baseDirectoryNoticeLabel, previewCaption]
    }

    var actionControlsForTesting: [(NSControl, SetupWindowGitHubAction)] {
        [
            (chooseBaseDirectoryButton, .chooseBaseDirectory),
            (baseDirectoryField, .baseDirectoryEdited),
            (arrangementSegment, .cmuxPlacementArrangementChanged),
            (identitySegment, .cmuxPlacementIdentityChanged),
            (workspaceNameField, .cmuxPlacementNameEdited),
        ]
    }

    func update(_ state: SetupWindowGitHubPaneState) {
        let storedBaseDirectory = state.baseDirectory
        if baseDirectoryField.stringValue == storedBaseDirectory {
            // A successful edit may have normalized and saved a new value since the previous draw.
            drawnBaseDirectory = storedBaseDirectory
        } else if !isEditing(baseDirectoryField),
                  drawnBaseDirectory == nil || baseDirectoryField.stringValue == drawnBaseDirectory {
            baseDirectoryField.stringValue = storedBaseDirectory
            drawnBaseDirectory = storedBaseDirectory
        }

        let storedName = state.cmuxFixedName ?? ""
        if workspaceNameField.stringValue == storedName {
            drawnCmuxPlacementName = storedName
        } else if !isEditing(workspaceNameField),
                  drawnCmuxPlacementName == nil || workspaceNameField.stringValue == drawnCmuxPlacementName {
            workspaceNameField.stringValue = storedName
            drawnCmuxPlacementName = storedName
        }

        currentGitHubPreview = state.presentation.previews.github
        previewView.update(githubModel: currentGitHubPreview)
        updateBaseDirectoryNotice(state)
        updateCmuxControls(state)
        updatePreviewTitle(currentGitHubPreview)
    }

    private func buildBaseDirectoryControls() {
        let title = NSTextField(labelWithString: localized("app.setup.github.baseDirectory.title"))
        title.font = Theme.ui(12, .medium)
        title.textColor = Theme.text

        baseDirectoryField.font = Theme.mono(11.5)
        baseDirectoryField.placeholderString = localized("app.baseDir.placeholder")
        baseDirectoryField.target = actionTarget
        baseDirectoryField.action = selectors[.baseDirectoryEdited]
        baseDirectoryField.identifier = setupWindowControlRole(selectors[.baseDirectoryEdited]!)
        baseDirectoryField.cell?.sendsActionOnEndEditing = true
        baseDirectoryField.widthAnchor.constraint(equalToConstant: 225).isActive = true

        chooseBaseDirectoryButton.title = localized("app.button.chooseFolder")
        chooseBaseDirectoryButton.bezelStyle = .rounded
        chooseBaseDirectoryButton.target = actionTarget
        chooseBaseDirectoryButton.action = selectors[.chooseBaseDirectory]
        chooseBaseDirectoryButton.identifier = setupWindowControlRole(selectors[.chooseBaseDirectory]!)

        let row = NSStackView(views: [baseDirectoryField, chooseBaseDirectoryButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        baseDirectoryNoticeDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            baseDirectoryNoticeDot.widthAnchor.constraint(equalToConstant: 8),
            baseDirectoryNoticeDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        baseDirectoryNoticeLabel.font = Theme.ui(11)
        baseDirectoryNoticeLabel.textColor = Theme.textDim
        baseDirectoryNoticeLabel.maximumNumberOfLines = 2
        baseDirectoryNoticeRow.orientation = .horizontal
        baseDirectoryNoticeRow.alignment = .firstBaseline
        baseDirectoryNoticeRow.spacing = 6
        baseDirectoryNoticeRow.addArrangedSubview(baseDirectoryNoticeDot)
        baseDirectoryNoticeRow.addArrangedSubview(baseDirectoryNoticeLabel)
        baseDirectoryNoticeRow.isHidden = true

        folderSection.orientation = .vertical
        folderSection.alignment = .leading
        folderSection.spacing = 7
        folderSection.addArrangedSubview(title)
        folderSection.addArrangedSubview(row)
        folderSection.addArrangedSubview(baseDirectoryNoticeRow)
    }

    private func isEditing(_ field: NSTextField) -> Bool {
        guard let window, let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private let folderSection = NSStackView()
    private let arrangementRow = NSStackView()
    private let identityRow = NSStackView()
    private let previewColumn = NSStackView()
    private let previewCaption = makeSetupWindowWrappingLabel()

    private func buildCmuxControls() {
        let sectionTitle = NSTextField(labelWithString: localized("app.setup.github.batch.title"))
        sectionTitle.font = Theme.ui(12, .semibold)
        sectionTitle.textColor = Theme.text

        let arrangementTitle = NSTextField(labelWithString: localized("app.setup.github.batch.arrangement"))
        arrangementTitle.font = Theme.ui(11, .medium)
        arrangementTitle.textColor = Theme.textDim
        arrangementSegment.setLabel(localized("app.setup.github.arrangement.pane"), forSegment: 0)
        arrangementSegment.setLabel(localized("app.setup.github.arrangement.tab"), forSegment: 1)
        arrangementSegment.setLabel(localized("app.setup.github.batch.workspace"), forSegment: 2)
        arrangementSegment.segmentStyle = .rounded
        arrangementSegment.setWidth(64, forSegment: 0)
        arrangementSegment.setWidth(64, forSegment: 1)
        arrangementSegment.setWidth(96, forSegment: 2)
        arrangementSegment.target = actionTarget
        arrangementSegment.action = selectors[.cmuxPlacementArrangementChanged]
        arrangementSegment.identifier = setupWindowControlRole(
            selectors[.cmuxPlacementArrangementChanged]!
        )
        arrangementSegment.setAccessibilityLabel(localized("app.setup.github.batch.arrangement"))
        arrangementRow.orientation = .horizontal
        arrangementRow.alignment = .centerY
        arrangementRow.spacing = 10
        arrangementRow.addArrangedSubview(arrangementTitle)
        arrangementRow.addArrangedSubview(arrangementSegment)

        let identityTitle = NSTextField(labelWithString: localized("app.setup.github.batch.workspace"))
        identityTitle.font = Theme.ui(11, .medium)
        identityTitle.textColor = Theme.textDim
        identitySegment.setLabel(localized("app.cmux.placement.identity.alwaysNew"), forSegment: 0)
        identitySegment.setLabel(localized("app.cmux.placement.identity.fixedName"), forSegment: 1)
        identitySegment.segmentStyle = .rounded
        identitySegment.setWidth(114, forSegment: 0)
        identitySegment.setWidth(124, forSegment: 1)
        identitySegment.target = actionTarget
        identitySegment.action = selectors[.cmuxPlacementIdentityChanged]
        identitySegment.identifier = setupWindowControlRole(
            selectors[.cmuxPlacementIdentityChanged]!
        )
        identitySegment.setAccessibilityLabel(localized("app.setup.github.batch.workspace"))

        workspaceNameField.font = Theme.mono(11.5)
        workspaceNameField.placeholderString = localized("app.cmux.placement.name.placeholder")
        workspaceNameField.target = actionTarget
        workspaceNameField.action = selectors[.cmuxPlacementNameEdited]
        workspaceNameField.identifier = setupWindowControlRole(
            selectors[.cmuxPlacementNameEdited]!
        )
        workspaceNameField.cell?.sendsActionOnEndEditing = true
        workspaceNameField.widthAnchor.constraint(equalToConstant: 156).isActive = true

        emptyWorkspaceNameHint.font = Theme.ui(10)
        emptyWorkspaceNameHint.textColor = Theme.textDim
        let identityChoiceRow = NSStackView(views: [identityTitle, identitySegment])
        identityChoiceRow.orientation = .horizontal
        identityChoiceRow.alignment = .centerY
        identityChoiceRow.spacing = 10
        identityRow.orientation = .vertical
        identityRow.alignment = .leading
        identityRow.spacing = 6
        identityRow.addArrangedSubview(identityChoiceRow)
        identityRow.addArrangedSubview(workspaceNameField)

        cmuxSection.orientation = .vertical
        cmuxSection.alignment = .leading
        cmuxSection.spacing = 8
        cmuxSection.addArrangedSubview(sectionTitle)
        cmuxSection.addArrangedSubview(arrangementRow)
        cmuxSection.addArrangedSubview(identityRow)
        cmuxSection.addArrangedSubview(emptyWorkspaceNameHint)
    }

    private func buildPreviewColumn() {
        previewTitleLabel.font = Theme.ui(11, .semibold)
        previewTitleLabel.textColor = Theme.textDim
        previewTitleLabel.maximumNumberOfLines = 2
        previewView.heightAnchor.constraint(equalToConstant: 236).isActive = true
        previewCaption.font = Theme.ui(10)
        previewCaption.textColor = Theme.textDim
        previewCaption.maximumNumberOfLines = 4
        previewColumn.orientation = .vertical
        previewColumn.alignment = .leading
        previewColumn.spacing = 8
        previewColumn.addArrangedSubview(previewTitleLabel)
        previewColumn.addArrangedSubview(previewView)
        previewColumn.addArrangedSubview(previewCaption)
    }

    private func buildLayout() {
        leftColumn.addArrangedSubview(folderSection)
        leftColumn.addArrangedSubview(cmuxSection)
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.distribution = .fill
        leftColumn.spacing = 17
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.setHuggingPriority(.required, for: .vertical)
        leftColumn.widthAnchor.constraint(equalToConstant: 390).isActive = true

        contentStack.orientation = .horizontal
        contentStack.alignment = .top
        contentStack.distribution = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        // This value breaks the tie with the left column's section stacks.
        contentStack.setHuggingPriority(NSLayoutConstraint.Priority(240), for: .vertical)
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

    private func updateBaseDirectoryNotice(_ state: SetupWindowGitHubPaneState) {
        let notice: (String, SetupWindowProblemSeverity)?
        if let draftProblem = state.baseDirectoryDraftProblem {
            notice = (
                localized("app.baseDir.notSaved", setupWindowBaseDirectoryReason(draftProblem)),
                .error
            )
        } else {
            switch state.presentation.baseDirectoryNotice {
            case .notConfigured:
                notice = (localized("app.setup.github.baseDirectory.noZoxide"), .error)
            case .storedValueInvalid:
                if let problem = state.storedBaseDirectoryProblem {
                    notice = (
                        localized("app.baseDir.storedInvalid", setupWindowBaseDirectoryReason(problem)),
                        .error
                    )
                } else {
                    notice = (localized("app.setup.github.baseDirectory.storedInvalid"), .error)
                }
            case .directoryMissing:
                notice = (localized("app.setup.github.baseDirectory.missing"), .warning)
            case nil:
                notice = nil
            }
        }

        guard let notice else {
            baseDirectoryNoticeRow.isHidden = true
            baseDirectoryNoticeLabel.stringValue = ""
            return
        }
        baseDirectoryNoticeLabel.stringValue = notice.0
        baseDirectoryNoticeLabel.textColor = notice.1 == .error ? Theme.err : Theme.warn
        baseDirectoryNoticeDot.update(severity: notice.1)
        baseDirectoryNoticeRow.isHidden = false
    }

    private func updateCmuxControls(_ state: SetupWindowGitHubPaneState) {
        let preview = state.presentation.previews.github
        guard case .cmux(let arrangement, _, _) = preview.destination else {
            cmuxSection.isHidden = true
            return
        }
        cmuxSection.isHidden = false
        arrangementSegment.selectedSegment = Self.segmentIndex(for: arrangement)

        let identityDisabled = arrangement == .workspacePerItem
        identitySegment.isEnabled = !identityDisabled
        identitySegment.selectedSegment = identityDisabled
            ? 0
            : (state.cmuxIdentityMode == "fixed-name" ? 1 : 0)
        let showsName = !identityDisabled && state.cmuxIdentityMode == "fixed-name"
        workspaceNameField.isEnabled = showsName
        workspaceNameField.isHidden = !showsName
        emptyWorkspaceNameHint.stringValue = localized("app.setup.github.identity.emptyName")
        emptyWorkspaceNameHint.isHidden = !showsName || !workspaceNameField.stringValue.isEmpty
        identitySegment.setAccessibilityValue(
            identitySegment.label(forSegment: identitySegment.selectedSegment)
        )
    }

    private func updatePreviewTitle(_ preview: SetupWindowGitHubPreview) {
        if case .cmux(_, .findNamedWorkspace, _) = preview.destination,
           case .githubCmuxBatch(_, _, .fixedName(let name)) = preview.effectSentence {
            previewTitleLabel.stringValue = localized("app.setup.preview.github.title.named", name)
        } else {
            previewTitleLabel.stringValue = localized("app.setup.preview.github.title.rows")
        }
        previewCaption.stringValue = previewView.effectDescription
    }

    private static func segmentIndex(for arrangement: CmuxPlacementArrangement) -> Int {
        switch arrangement {
        case .panePerItem: return 0
        case .tabPerItem: return 1
        case .workspacePerItem: return 2
        }
    }
}

private final class SetupWindowGitHubStatusDot: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(severity: SetupWindowProblemSeverity) {
        layer?.backgroundColor = (severity == .error ? Theme.err : Theme.warn).cgColor
        setAccessibilityLabel(severity == .error ? localized("app.setup.severity.error") : localized("app.setup.severity.warning"))
    }
}
