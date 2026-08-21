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

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        super.tearDown()
    }

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
    func testWindowMatchesContentAcrossEveryTerminalTransition() throws {
        let controller = makeController(.iterm)
        let window = try XCTUnwrap(controller.window)
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
        settle(window)
        let visible = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
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
        controller.rootStack.needsLayout = true
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
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        settle(window)
        XCTAssertGreaterThanOrEqual(
            contentHeight(window), controller.rootStack.fittingSize.height - 0.5
        )
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
        // claude 자체가 없으면 그건 "없음" 줄이 말한다 — 두 번 말하지 않는다
        XCTAssertNil(claudeWrapperAdvice(available: ["claude": false], executable: ["claude": false]))
        // 확인 전에는 아무 말도 하지 않는다
        XCTAssertNil(claudeWrapperAdvice(available: nil, executable: nil))
    }
}
