import AppKit
import Core
import XCTest
@testable import App

/// The setup window sizes itself to its content, and the content changes as the user picks a
/// terminal or grants a permission. When the window ends up shorter than the stack needs, the
/// cards do not merely clip — the layout engine breaks a constraint and they land on top of each
/// other, which is what the reported screenshot shows. These tests pin the invariants that make
/// that impossible rather than the one call site that happened to get it wrong.
final class SetupWindowLayoutTests: XCTestCase {
    private var savedTerminal: Terminal!

    private var savedResources: String?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        // Without this the window draws **raw keys**, and a key is shorter than every sentence it
        // stands for — a layout test that passed on keys would be silent about the case it exists
        // for. `swift test` has no app bundle, so the source tree is where the catalogues are
        savedResources = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        AppLocalization.resourcesPath = savedResources
        super.tearDown()
    }

    static var sourceResources: String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/SetupWindowLayoutTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    /// The catalogues that have bodies. **All five, now that item 24 filled the last three** — the
    /// list existed because a window drawn from an empty catalogue is a window of raw keys, and a
    /// key is shorter than every sentence it stands for, so measuring one would have been a pass
    /// that meant nothing. A layout that fits English and Korean is likewise not evidence about
    /// Japanese or either Chinese, whose glyphs and line lengths differ.
    ///
    /// **It reads `supportedLocales` rather than repeating it.** As a spelled-out list it was a
    /// second source of truth: measured, a sixth tag added to the constant left every case in this
    /// file green without the window ever being drawn in it — the silent failure this comment
    /// already warned about, one level up from where it was looking.
    static var populatedLocales: [String] { supportedLocales }

    private func makeController(_ terminal: Terminal) -> SetupWindowController {
        Settings.terminal = terminal
        return SetupWindowController()
    }

    private func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func contentHeight(_ window: NSWindow) -> CGFloat {
        window.contentRect(forFrameRect: window.frame).height
    }

    /// A screen with room to spare, for the tests whose subject is "the window tracks its
    /// content". Tall enough that no layout in this window reaches the clamp — the clamp has its
    /// own test, and mixing the two makes a pass depend on the display the suite runs on.
    private let roomyScreen = NSRect(x: 0, y: 0, width: 1600, height: 2000)

    /// **The window has to fit its content in every language it can be drawn in.** This is the only
    /// automatic check of that: a translated sentence is longer or shorter than the Korean it
    /// replaced, and a card that fits one can clip in another.
    ///
    /// It walks `populatedLocales`, which **is** `supportedLocales` and is declared four lines
    /// above with the measurement that made it one. This paragraph used to say the opposite — that
    /// it was a hardcoded list, kept next to the fix that had stopped it being one — and a sentence
    /// wrong in that direction is the worse kind: it invites someone to re-fix what is fixed, or to
    /// distrust a gate that works.
    func testTheWindowFitsItsContentInEveryPopulatedLocale() throws {
        for tag in Self.populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            defer { AppLocalization.tagOverrideForTesting = nil }

            let controller = makeController(.warp)
            let window = try XCTUnwrap(controller.window)
            // The same measurement the transition test uses: the stack asks, the window answers.
            // A roomy screen because the property only holds while the content fits — past that
            // the clamp is deliberate and has its own test
            controller.rootStack.visibleFrameOverride = roomyScreen
            settle(window)

            let needed = controller.rootStack.fittingSize.height
            XCTAssertGreaterThan(needed, 0, "\(tag) measured nothing")
            XCTAssertGreaterThanOrEqual(
                contentHeight(window), needed - 0.5,
                "the window is shorter than its content in \(tag) — cards will overlap"
            )
            XCTAssertEqual(
                controller.rootStack.frame.height, needed, accuracy: 0.5, "\(tag) squeezed the stack"
            )
            // And the sentences really are that locale's, not keys or another locale's.
            //
            // Compared against **that locale's own catalogue** rather than a literal. The literal
            // form was `tag == "en" ? … : "저장소 기본 폴더"`, which is a two-locale shape: it says
            // "English or Korean" in its structure, and adding a third language made it assert that
            // Japanese equals Korean. Reading the catalogue asks the question that was meant — did
            // the window draw this locale's sentence — in a way that does not need editing again.
            let title = localized("app.card.baseDir.title")
            XCTAssertFalse(title.hasPrefix("app."), "\(tag) drew a raw key")
            XCTAssertEqual(title, try loadCatalogue(tag)["app.card.baseDir.title"], "\(tag) drew another locale")
        }
    }

    /// Every status line must wrap. One of them (`accessibilityStatusLabel`) was declared beside
    /// its siblings but missed the styling loop, so it kept the default font and a single line —
    /// a long status clipped at the card edge instead of flowing. Asserting the whole family is
    /// the point: the defect was one member being forgotten, not the value being wrong.
    func testEveryStatusLabelIsStyledToWrap() throws {
        let controller = makeController(.warp)
        for label in controller.statusLabelsForTesting {
            XCTAssertFalse(label.usesSingleLineMode, "single line: \(label)")
            XCTAssertEqual(label.cell?.wraps, true)
            XCTAssertEqual(label.maximumNumberOfLines, 0)
            XCTAssertEqual(label.preferredMaxLayoutWidth, setupTextWidth)
            XCTAssertEqual(label.font?.pointSize, 11.5, "\(String(describing: label.font))")
        }
    }

    /// The window is never shorter than its content, in either direction of every transition —
    /// growing (a section appears) and shrinking (it goes away).
    ///
    /// The screen is pinned because the property only holds while the content *fits* it: past
    /// that the window is clamped on purpose and the stack scrolls (the test below). Left to the
    /// real display this passes on a roomy desktop and fails wherever the runner's screen is
    /// shorter than the content — measured on CI at 681pt against 721.5pt of content, which is
    /// the designed clamp, not a defect.
    func testWindowMatchesContentAcrossEveryTerminalTransition() throws {
        let controller = makeController(.iterm)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen
        for terminal in [Terminal.warp, .wezterm, .warp, .iterm, .warp] {
            controller.select(terminal: terminal)
            settle(window)
            XCTAssertGreaterThanOrEqual(
                contentHeight(window), controller.rootStack.fittingSize.height - 0.5,
                "\(terminal) left the window shorter than its content"
            )
            XCTAssertEqual(
                controller.rootStack.frame.height, controller.rootStack.fittingSize.height,
                accuracy: 0.5, "\(terminal) squeezed the stack"
            )
        }
    }

    /// The window is movable by its background, so it is easy to leave near the bottom edge.
    /// Growing there pushes the bottom off screen and AppKit clamps the frame — which hands the
    /// stack less height than it asked for. Growth has to move the window instead.
    func testGrowingNearTheBottomEdgeKeepsTheWindowOnScreen() throws {
        let controller = makeController(.wezterm) // shortest layout, so switching grows it
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen // see the transition test
        settle(window)
        let visible = roomyScreen
        window.setFrameOrigin(NSPoint(x: visible.minX + 20, y: visible.minY + 4))

        controller.select(terminal: .warp)
        settle(window)

        XCTAssertGreaterThanOrEqual(window.frame.minY, visible.minY - 0.5, "bottom went off screen")
        XCTAssertLessThanOrEqual(window.frame.maxY, visible.maxY + 0.5, "top went off screen")
        XCTAssertGreaterThanOrEqual(
            contentHeight(window), controller.rootStack.fittingSize.height - 0.5
        )
    }

    /// When the content genuinely cannot fit the screen the window is clamped — but the stack
    /// keeps its full height and scrolls, rather than being squeezed into an overlapping mess.
    func testContentTallerThanTheScreenScrollsInsteadOfBeingSqueezed() throws {
        let controller = makeController(.warp)
        let window = try XCTUnwrap(controller.window)
        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        settle(window)
        let needed = controller.rootStack.fittingSize.height

        controller.rootStack.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: needed / 2)
        settle(window)

        XCTAssertEqual(contentHeight(window), needed / 2, accuracy: 1, "clamp did not apply")
        XCTAssertEqual(
            controller.rootStack.frame.height, needed, accuracy: 0.5,
            "the stack was squeezed instead of scrolled"
        )
        XCTAssertGreaterThan(
            controller.rootStack.frame.height, scroll.contentView.bounds.height,
            "nothing to scroll — the document should exceed the clip"
        )
    }

    /// A permission flipping while the window is open is the other trigger for the same resize,
    /// and it does not go through `select(terminal:)`.
    func testPermissionRefreshKeepsTheWindowFitted() throws {
        let controller = makeController(.warp)
        let window = try XCTUnwrap(controller.window)
        controller.rootStack.visibleFrameOverride = roomyScreen // see the transition test
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        settle(window)
        XCTAssertGreaterThanOrEqual(
            contentHeight(window), controller.rootStack.fittingSize.height - 0.5
        )
    }

    /// **Every sentence in the pipeline strip comes from the catalogue** (round 10 review).
    ///
    /// The strip was assembling one of its own: `"Native Host: \(manifest.message)"` put an English
    /// word in front of a translated status, and `"relay"` was a bare literal. Item 12's gate could
    /// not see either of them — it counts `localized(…)` calls and catalogue keys, so a string
    /// nobody localised is invisible to it. That is the limit of a scan-shaped gate, and this case
    /// is what covers the shape it cannot.
    ///
    /// What is checked is the **frame**, not the wording (D59): a node's text has to be a catalogue
    /// value, or a catalogue value's frame with its `%@` filled in — the payload is allowed to be
    /// anything, including a product name. `iTerm2`, `WezTerm` and `Warp` are the declared
    /// exceptions, because a product name is the same word in every language.
    ///
    /// The states handed in are synthetic and built from that locale's own catalogue, so the case
    /// enumerates the rows it means instead of whatever this machine's manifest happens to say.
    func testPipelineNodesAreLocalized() throws {
        let productNames: Set<String> = ["iTerm2", "WezTerm", "Warp"]
        var renderings: [String: [String]] = [:]

        for tag in SetupWindowLayoutTests.populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            defer { AppLocalization.tagOverrideForTesting = nil }
            let values = Array(try loadCatalogue(tag).values)
            let controller = makeController(.warp)

            let nodes = controller.pipelineNodes(
                manifest: .ok(try XCTUnwrap(try loadCatalogue(tag)["app.status.manifest.registered"])),
                extensionState: .ok(try XCTUnwrap(try loadCatalogue(tag)["app.status.extensionFolder.ready"])),
                socketAlive: true, permission: nil, accessibilityGranted: true
            )
            XCTAssertEqual(nodes.count, 4, "\(tag): the strip lost a node")

            for node in nodes {
                XCTAssertTrue(
                    productNames.contains(node.label) || framed(node.label, by: values),
                    "\(tag): the label \"\(node.label)\" is not from the catalogue"
                )
                XCTAssertTrue(
                    framed(node.detail, by: values),
                    "\(tag): the sentence \"\(node.detail)\" is not from the catalogue"
                )
            }
            renderings[tag] = nodes.map { "\($0.label)|\($0.detail)" }
        }

        // Every sentence has to move with the language. A frame that came from the catalogue but
        // answered the same in both would mean the lookup never reached a second file.
        let english = try XCTUnwrap(renderings["en"])
        let korean = try XCTUnwrap(renderings["ko"])
        for (index, pair) in zip(english, korean).enumerated() {
            XCTAssertNotEqual(pair.0, pair.1, "pipeline node \(index) reads the same in both languages")
        }
    }

    /// Whether `text` is a catalogue value, or one with its single `%@` filled in. A frame with
    /// almost nothing around the placeholder would match anything, so those are not counted.
    private func framed(_ text: String, by values: [String]) -> Bool {
        for value in values {
            if value == text { return true }
            let parts = value.components(separatedBy: "%@")
            guard parts.count == 2, parts[0].count + parts[1].count >= 3 else { continue }
            if text.hasPrefix(parts[0]), text.hasSuffix(parts[1]), text.count > parts[0].count + parts[1].count {
                return true
            }
        }
        return false
    }
}


/// The merge path needs `claude` to resolve to an executable, and when it does not the only thing
/// the user notices is that delivery got slower — or, on Warp without the Accessibility
/// permission, that the button now refuses outright. That reason has to be visible somewhere
/// (independent reviewer, round 7).
final class ClaudeWrapperAdviceTests: XCTestCase {
    func testAdviceAppearsOnlyForAReachableClaudeThatIsNotAnExecutable() {
        XCTAssertNotNil(claudeWrapperAdvice(available: ["claude": true], executable: ["claude": false]))
        XCTAssertNil(claudeWrapperAdvice(available: ["claude": true], executable: ["claude": true]))
        // When claude itself is absent, the "missing" row says so — do not repeat it.
        XCTAssertNil(claudeWrapperAdvice(available: ["claude": false], executable: ["claude": false]))
        // Before the check answers, say nothing.
        XCTAssertNil(claudeWrapperAdvice(available: nil, executable: nil))
    }
}


/// The Accessibility card told users the command would still run without the permission — the
/// opposite of what the app does since the precondition gate landed: the request is refused and no
/// tab opens (round 8, Codex P2). A card that contradicts the behaviour is worse than no card.
final class WarpAccessibilityHelpTextTests: XCTestCase {
    /// **The subject moved, so the test moved with it.** These sentences used to be literals in
    /// `SetupWindowController.swift`, and this class read that file. After item 10 they live in the
    /// catalogues, and a check that still scanned the source would pass by finding nothing —
    /// vacuously green, which is worse than deleted.
    private func catalogue(_ tag: String) throws -> [String: String] {
        try loadCatalogue(tag)
    }

    func testTheCardSaysTheRequestIsRefusedRatherThanPartlyRun() throws {
        // One word per language, and it has to be the word that locale actually uses — the point of
        // the check is that the card says the request is *refused*, not that it is partly carried
        // out, and only the sentence in front of the user can answer that.
        let refusal = [
            "en": "refused", "ko": "거절", "ja": "拒否", "zh-Hans": "拒绝", "zh-Hant": "拒絕",
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let help = try XCTUnwrap(catalogue(tag)["app.section.accessibility.help"], tag)
            XCTAssertTrue(help.contains(try XCTUnwrap(refusal[tag])), "\(tag): \(help)")
        }
    }

    /// The same promise was made in two more places — the permission status line and the pipeline
    /// row — and round 8 fixed only the card. **No value in any catalogue** may say the command
    /// still runs without the permission; scanning every value is what keeps the next translation
    /// from reintroducing it in one locale only.
    func testNoWindowTextStillPromisesTheCommandRunsWithoutThePermission() throws {
        // The sentence that must appear in **no** catalogue, in each language's natural forms. A
        // negative check is only as wide as the phrasings it knows, which is why each locale lists
        // several rather than one — and why this list grows with the catalogues rather than being
        // written once for English.
        let promises = [
            "en": ["the command still runs", "command still runs", "only the claude input"],
            "ko": ["명령은 실행되지만", "명령은 실행되고", "그대로 실행되지만"],
            "ja": ["コマンドは実行され", "コマンドだけは実行", "コマンドは動きます"],
            "zh-Hans": ["命令仍会运行", "命令仍然运行", "命令还是会运行"],
            "zh-Hant": ["指令仍會執行", "指令仍然執行", "指令還是會執行"],
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let values = try catalogue(tag)
            XCTAssertFalse(values.isEmpty, "\(tag) catalogue is empty — this would pass on nothing")
            for promise in try XCTUnwrap(promises[tag]) {
                for (key, value) in values {
                    XCTAssertFalse(value.contains(promise), "\(tag) \(key): \(promise)")
                }
            }
        }
    }

    /// **A body quotes a label by receiving it, never by repeating it** (D28). Eight places in this
    /// window and the extension name another control in their text; spelled out, each is a copy that
    /// goes stale the moment the label is reworded — in five locales independently, so four of them
    /// can be wrong while the one you read is right.
    ///
    /// The relationship's real gate is item 12, which will check the placeholder against the key it
    /// receives. This is the half that can be checked from here: no value may contain another key's
    /// label as literal text.
    func testNoValueSpellsOutALabelInsteadOfReceivingIt() throws {
        let labelKeys = [
            "app.button.registerUpdate", "app.button.installInChrome", "app.button.chooseFolder",
            "app.button.requestItermPermission", "app.button.openSystemSettings",
            "app.button.requestAccessibility", "app.button.runInTerminal",
            "app.button.openOptionsPage", "app.button.showSetupGuide", "app.button.restartNow",
        ]
        for tag in SetupWindowLayoutTests.populatedLocales {
            let values = try catalogue(tag)
            for labelKey in labelKeys {
                let label = try XCTUnwrap(values[labelKey], "\(tag) \(labelKey)")
                for (key, value) in values where key != labelKey {
                    XCTAssertFalse(
                        value.localizedCaseInsensitiveContains(label),
                        "\(tag) \(key) spells out \(labelKey) (\"\(label)\") instead of taking it as %@"
                    )
                }
            }
        }
    }

    /// The markup that never rendered. `NSTextField` draws `**bold**` and `` `code` `` literally,
    /// so those characters were on screen as themselves — and translating them would have copied
    /// the defect into five catalogues at once.
    func testNoCatalogueValueCarriesMarkupThatDoesNotRender() throws {
        for tag in SetupWindowLayoutTests.populatedLocales {
            for (key, value) in try catalogue(tag) {
                XCTAssertFalse(value.contains("**"), "\(tag) \(key) carries ** **")
                XCTAssertFalse(value.contains("`"), "\(tag) \(key) carries a backtick")
            }
        }
    }
}


/// One catalogue, read from the source tree. File scope because two of the classes here need it:
/// `swift test` has no app bundle, and a `Bundle` lookup would resolve through the host's language
/// (D7) rather than through the tag being asked about.
private func loadCatalogue(_ tag: String) throws -> [String: String] {
    let path = (SetupWindowLayoutTests.sourceResources as NSString)
        .appendingPathComponent("\(tag).lproj/Localizable.strings")
    let parsed = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil
    ) as? [String: String]
    return try XCTUnwrap(parsed, "\(tag) catalogue did not parse")
}
