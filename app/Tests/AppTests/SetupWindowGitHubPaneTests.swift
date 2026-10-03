import AppKit
import Core
import XCTest
@testable import App

final class SetupWindowGitHubPaneTests: XCTestCase {
    private var savedResources: String?
    private var savedTagOverride: String?

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        savedTagOverride = AppLocalization.tagOverrideForTesting
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
        AppLocalization.tagOverrideForTesting = "en"
    }

    override func tearDown() {
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = savedTagOverride
        super.tearDown()
    }

    func testBaseDirectoryDraftAndWorkspaceNameSurviveRefreshOnTheSameControls() throws {
        let fixture = makePane(state: makeState(
            baseDirectory: "/saved/base",
            identityMode: "fixed-name",
            fixedName: "saved-workspace"
        ))
        XCTAssertEqual(fixture.pane.baseDirectoryField.stringValue, "/saved/base")
        XCTAssertEqual(fixture.pane.workspaceNameField.stringValue, "saved-workspace")
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let baseField = fixture.pane.baseDirectoryField
        let nameField = fixture.pane.workspaceNameField
        let controlIdentities = fixture.pane.actionControlsForTesting.map { ObjectIdentifier($0.0) }
        let previewIdentity = ObjectIdentifier(fixture.pane.previewView)

        baseField.stringValue = "~/draft path"
        nameField.stringValue = "draft-workspace"
        fixture.pane.update(makeState(
            baseDirectory: "/refreshed/base",
            identityMode: "fixed-name",
            fixedName: "refreshed-workspace"
        ))

        XCTAssertEqual(fixture.pane.baseDirectoryField.stringValue, "~/draft path")
        XCTAssertEqual(fixture.pane.workspaceNameField.stringValue, "draft-workspace")
        XCTAssertEqual(fixture.pane.actionControlsForTesting.map { ObjectIdentifier($0.0) }, controlIdentities)
        XCTAssertEqual(ObjectIdentifier(fixture.pane.previewView), previewIdentity)
    }

    func testBaseDirectoryNoticeAppearsOnlyForUnusableCases() throws {
        let fixture = makePane(state: makeState(
            baseStatus: .normalized("/saved/base", directoryExists: true),
            baseDirectory: "/saved/base",
            tools: SetupWindowToolResults(available: ["zoxide": true], executable: [:])
        ))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(fixture.pane.baseDirectoryNoticeRowIsHiddenForTesting)

        fixture.pane.update(makeState(
            baseStatus: .unconfigured,
            baseDirectory: "",
            tools: SetupWindowToolResults(available: ["zoxide": false], executable: [:])
        ))
        XCTAssertEqual(
            fixture.pane.baseDirectoryNoticeText,
            localized("app.setup.github.baseDirectory.noZoxide")
        )

        fixture.pane.update(makeState(
            baseStatus: .invalidStoredValue,
            baseDirectory: "relative/path",
            storedProblem: .notAbsolute
        ))
        XCTAssertEqual(
            fixture.pane.baseDirectoryNoticeText,
            localized("app.baseDir.storedInvalid", localized("app.baseDir.reason.notAbsolute"))
        )

        fixture.pane.update(makeState(
            baseStatus: .normalized("/not-created/yet", directoryExists: false),
            baseDirectory: "/not-created/yet"
        ))
        XCTAssertEqual(
            fixture.pane.baseDirectoryNoticeText,
            localized("app.setup.github.baseDirectory.missing")
        )

        fixture.pane.update(makeState(
            baseDirectory: "/saved/base",
            draftProblem: .invalidCharacters
        ))
        XCTAssertEqual(
            fixture.pane.baseDirectoryNoticeText,
            localized("app.baseDir.notSaved", localized("app.baseDir.reason.invalidCharacters"))
        )
    }

    func testWorkspaceArrangementDisablesIdentityAndRestoresTheSavedChoice() throws {
        let fixture = makePane(state: makeState(
            identityMode: "fixed-name",
            fixedName: "named-workspace",
            arrangement: CmuxPlacementArrangement.panePerItem.rawValue
        ))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        XCTAssertTrue(fixture.pane.identitySegment.isEnabled)
        XCTAssertEqual(fixture.pane.identitySegment.selectedSegment, 1)
        XCTAssertTrue(fixture.pane.workspaceNameField.isEnabled)
        XCTAssertFalse(fixture.pane.workspaceNameField.isHidden)

        fixture.pane.update(makeState(
            identityMode: "fixed-name",
            fixedName: "named-workspace",
            arrangement: CmuxPlacementArrangement.workspacePerItem.rawValue
        ))

        XCTAssertFalse(fixture.pane.identitySegment.isEnabled)
        XCTAssertEqual(fixture.pane.identitySegment.selectedSegment, 0)
        XCTAssertFalse(fixture.pane.workspaceNameField.isEnabled)
        XCTAssertTrue(fixture.pane.workspaceNameField.isHidden)
        XCTAssertEqual(fixture.pane.workspaceNameField.stringValue, "named-workspace")
        XCTAssertEqual(fixture.pane.effectSentenceForTesting, localized("app.setup.github.effect.workspace"))

        fixture.pane.update(makeState(
            identityMode: "fixed-name",
            fixedName: "named-workspace",
            arrangement: CmuxPlacementArrangement.tabPerItem.rawValue
        ))

        XCTAssertTrue(fixture.pane.identitySegment.isEnabled)
        XCTAssertEqual(fixture.pane.identitySegment.selectedSegment, 1)
        XCTAssertTrue(fixture.pane.workspaceNameField.isEnabled)
        XCTAssertFalse(fixture.pane.workspaceNameField.isHidden)
        XCTAssertEqual(fixture.pane.workspaceNameField.stringValue, "named-workspace")
    }

    func testEffectSentenceUsesEachCorePlacementCombinationFromTheCatalogue() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let cases: [(String?, String?, String, () -> String)] = [
            (nil, nil, CmuxPlacementArrangement.panePerItem.rawValue, {
                localized("app.setup.github.effect.pane.new")
            }),
            (nil, nil, CmuxPlacementArrangement.tabPerItem.rawValue, {
                localized("app.setup.github.effect.tab.new")
            }),
            (nil, nil, CmuxPlacementArrangement.workspacePerItem.rawValue, {
                localized("app.setup.github.effect.workspace")
            }),
            ("fixed-name", "named-workspace", CmuxPlacementArrangement.panePerItem.rawValue, {
                localized("app.setup.github.effect.pane.named", "named-workspace")
            }),
            ("fixed-name", "named-workspace", CmuxPlacementArrangement.tabPerItem.rawValue, {
                localized("app.setup.github.effect.tab.named", "named-workspace")
            }),
        ]
        for (identity, name, arrangement, expectedSentence) in cases {
            fixture.pane.update(makeState(
                identityMode: identity,
                fixedName: name,
                arrangement: arrangement
            ))
            XCTAssertEqual(fixture.pane.effectSentenceForTesting, expectedSentence())
        }

        fixture.pane.update(makeState(
            identityMode: "fixed-name",
            fixedName: "",
            arrangement: CmuxPlacementArrangement.panePerItem.rawValue
        ))
        XCTAssertEqual(
            fixture.pane.effectSentenceForTesting,
            localized("app.setup.github.effect.pane.new")
        )
        XCTAssertFalse(fixture.pane.workspaceNameHintIsHidden)

        fixture.pane.update(makeState(terminal: .warp))
        XCTAssertEqual(
            fixture.pane.effectSentenceForTesting,
            localized("app.setup.github.effect.nonCmux")
        )
    }

    func testNonCmuxShowsThePerRowTabSentenceWithoutCmuxControls() throws {
        let fixture = makePane(state: makeState(terminal: .iterm))
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        XCTAssertTrue(fixture.pane.cmuxSectionIsHiddenForTesting)
        XCTAssertEqual(fixture.pane.previewView.githubTerminalForTesting, .iterm)
        XCTAssertEqual(
            fixture.pane.effectSentenceForTesting,
            localized("app.setup.github.effect.nonCmux")
        )
        XCTAssertEqual(fixture.pane.previewTitleLabel.stringValue, localized("app.setup.preview.github.title.rows"))
    }

    func testPreviewAccessibilityDescriptionChangesWithArrangementAndIdentity() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let newPaneDescription = fixture.pane.previewView.effectDescription

        fixture.pane.update(makeState(
            identityMode: "fixed-name",
            fixedName: "named-workspace",
            arrangement: CmuxPlacementArrangement.tabPerItem.rawValue
        ))
        let namedTabDescription = fixture.pane.previewView.effectDescription
        XCTAssertNotEqual(newPaneDescription, namedTabDescription)
        XCTAssertEqual(namedTabDescription, fixture.pane.previewView.accessibilityLabel())
        XCTAssertEqual(
            fixture.pane.previewTitleLabel.stringValue,
            localized("app.setup.preview.github.title.named", "named-workspace")
        )
        XCTAssertEqual(
            namedTabDescription,
            localized("app.setup.github.effect.tab.named", "named-workspace")
        )

        fixture.pane.update(makeState(
            identityMode: "fixed-name",
            fixedName: "named-workspace",
            arrangement: CmuxPlacementArrangement.workspacePerItem.rawValue
        ))
        XCTAssertNotEqual(namedTabDescription, fixture.pane.previewView.effectDescription)
        XCTAssertEqual(
            fixture.pane.previewTitleLabel.stringValue,
            localized("app.setup.preview.github.title.rows")
        )
    }

    func testActionControlRolesAreDerivedFromTheirSelectors() throws {
        let fixture = makePane(state: makeState())
        let window = makeWindow(for: fixture.pane)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        for (control, action) in fixture.pane.actionControlsForTesting {
            let selector = try XCTUnwrap(fixture.selectors[action])
            XCTAssertEqual(control.action, selector)
            XCTAssertEqual(control.identifier, setupWindowControlRole(selector))
        }
    }

    private func makePane(state: SetupWindowGitHubPaneState) -> (
        pane: SetupWindowGitHubPane,
        target: GitHubPaneActionTarget,
        selectors: [SetupWindowGitHubAction: Selector]
    ) {
        let target = GitHubPaneActionTarget()
        let selectors: [SetupWindowGitHubAction: Selector] = [
            .chooseBaseDirectory: #selector(GitHubPaneActionTarget.chooseBaseDirectory(_:)),
            .baseDirectoryEdited: #selector(GitHubPaneActionTarget.baseDirectoryEdited(_:)),
            .cmuxPlacementArrangementChanged: #selector(GitHubPaneActionTarget.cmuxPlacementArrangementChanged(_:)),
            .cmuxPlacementIdentityChanged: #selector(GitHubPaneActionTarget.cmuxPlacementIdentityChanged(_:)),
            .cmuxPlacementNameEdited: #selector(GitHubPaneActionTarget.cmuxPlacementNameEdited),
        ]
        let pane = SetupWindowGitHubPane(state: state, target: target, selectors: selectors)
        return (pane, target, selectors)
    }

    private func makeState(
        terminal: Terminal = .cmux,
        baseStatus: SetupWindowBaseDirectoryStatus = .unconfigured,
        baseDirectory: String = "",
        draftProblem: BaseDirectoryProblem? = nil,
        storedProblem: BaseDirectoryProblem? = nil,
        tools: SetupWindowToolResults? = nil,
        identityMode: String? = nil,
        fixedName: String? = nil,
        arrangement: String? = nil
    ) -> SetupWindowGitHubPaneState {
        let snapshot = SetupWindowSnapshot(
            selectedTerminal: terminal,
            tools: tools,
            baseDirectory: baseStatus,
            cmuxIdentityMode: identityMode,
            cmuxFixedName: fixedName,
            cmuxArrangement: arrangement
        )
        return SetupWindowGitHubPaneState(
            presentation: SetupWindowPresentationModel.make(from: snapshot),
            baseDirectory: baseDirectory,
            baseDirectoryDraftProblem: draftProblem,
            storedBaseDirectoryProblem: storedProblem,
            cmuxIdentityMode: identityMode,
            cmuxFixedName: fixedName
        )
    }

    private func makeWindow(for pane: SetupWindowGitHubPane) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 430))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let stack = FittedContentStackView(frame: NSRect(x: 0, y: 0, width: 720, height: 0))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.addArrangedSubview(pane)
        scrollView.documentView = stack
        window.contentView = scrollView
        return window
    }
}

private final class GitHubPaneActionTarget: NSObject {
    @objc func chooseBaseDirectory(_ sender: NSButton) {}
    @objc func baseDirectoryEdited(_ sender: NSTextField) {}
    @objc func cmuxPlacementArrangementChanged(_ sender: NSSegmentedControl) {}
    @objc func cmuxPlacementIdentityChanged(_ sender: NSSegmentedControl) {}
    @objc func cmuxPlacementNameEdited() {}
}
