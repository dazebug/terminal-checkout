import AppKit
import Core
import XCTest
@testable import App

/// **When the window redraws**, which is a different question from what it draws (item 10 owns
/// that). The premise round 1 set out is that a lookup function alone switches nothing: this window
/// is built once and `refresh()` rewrites only the status lines, so every title, heading, help
/// paragraph and button label keeps the language it was created in until something builds them
/// again.
///
/// These tests do not write settings. `Settings.language` publishes and posts, and running that
/// against `.standard` would rewrite the language of the app installed on this machine — so the
/// notification is posted directly, which is the same thing the setter does and nothing more.
final class SetupWindowRedrawTests: XCTestCase {
    private var savedTerminal: Terminal!

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        super.tearDown()
    }

    private func makeController() -> SetupWindowController {
        let controller = SetupWindowController()
        _ = controller.window
        return controller
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
        // The observers are registered on `.main`, so the block runs on the next turn of the loop
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    /// A language change replaces the content, which is what makes the strings created inside the
    /// builders — every one of them — get read again.
    func testALanguageChangeRebuildsTheContent() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let before = try XCTUnwrap(window.contentView)

        post(.terminalCheckoutLanguageChanged)

        let after = try XCTUnwrap(window.contentView)
        XCTAssertFalse(before === after, "the content view was not rebuilt, so nothing re-read a string")
    }

    /// And the ordinary refreshes do **not**. They run on window activation and on every socket
    /// request, so rebuilding there would take focus and scroll position away from the user
    /// several times a minute for no gain.
    func testAnOrdinaryRefreshDoesNotRebuild() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let before = try XCTUnwrap(window.contentView)

        post(.terminalCheckoutRequestHandled)
        post(.terminalCheckoutToolsChecked)

        XCTAssertTrue(before === window.contentView, "an ordinary refresh replaced the view tree")
    }

    /// The hazard a rebuild introduces: two of the stacks are **stored** and filled by their
    /// builders, so building a second time appends a second copy instead of replacing the first.
    /// Same shape as an observer registered once per redraw, and the reason `toolsList` has always
    /// cleared before filling.
    func testRebuildingDoesNotDoubleTheRefillableSections() throws {
        let controller = makeController()
        let before = controller.refillableSectionsForTesting.map(\.arrangedSubviews.count)
        XCTAssertFalse(before.contains(0), "the fixture is empty — this would pass without checking anything")

        post(.terminalCheckoutLanguageChanged)
        post(.terminalCheckoutLanguageChanged)

        XCTAssertEqual(controller.refillableSectionsForTesting.map(\.arrangedSubviews.count), before)
    }

    /// The field the user types into is **re-parented, not recreated** — it is a stored property,
    /// so the rebuild moves it into the new stack. That is what keeps a rebuild from being a reset.
    ///
    /// Measured, and it is the cost of replacing the view tree: **an in-progress edit ends.** The
    /// field survives with its value, but it is no longer the first responder afterwards. Today the
    /// only thing that posts this notification is the picker, and clicking a pop-up button already
    /// ends editing — so nothing reaches the case. A second trigger would, and this is where that
    /// gets noticed.
    func testARebuildReparentsTheFieldAndEndsItsEdit() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let field = try XCTUnwrap(
            window.contentView?.firstDescendant(where: { ($0 as? NSTextField)?.isEditable == true })
                as? NSTextField
        )
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(window.firstResponder === field.currentEditor(), "the fixture never started editing")

        post(.terminalCheckoutLanguageChanged)

        let after = window.contentView?.firstDescendant(where: { ($0 as? NSTextField)?.isEditable == true })
        XCTAssertTrue(field === after, "the field was recreated, so anything it held is gone")
        XCTAssertNotNil(field.window, "the field was dropped instead of re-parented")
        XCTAssertFalse(
            window.firstResponder === field.currentEditor(),
            "editing survived the rebuild — if that is now true, the residual above is stale"
        )
    }

    /// The formatter that used to be a `static let` pinned to `ko_KR`. The language is the cache
    /// key now, so two languages cannot share one instance — the defect was not the value but the
    /// key that omitted it.
    func testTheRelativeFormatterIsKeyedByLanguage() {
        let korean = SetupWindowController.relativeFormatter(for: "ko")
        let traditional = SetupWindowController.relativeFormatter(for: "zh-Hant")
        XCTAssertFalse(korean === traditional)
        XCTAssertEqual(korean.locale.identifier, "ko")
        XCTAssertEqual(traditional.locale.identifier, "zh-Hant")
        // Asking twice for the same language reuses it — the cache still has to be a cache
        XCTAssertTrue(traditional === SetupWindowController.relativeFormatter(for: "zh-Hant"))
        // Measured: the tags we resolve go into `Locale(identifier:)` unchanged, scripts included
        let hour = Date().addingTimeInterval(-3600)
        XCTAssertEqual(traditional.localizedString(for: hour, relativeTo: Date()), "1小時前")
        XCTAssertEqual(
            SetupWindowController.relativeFormatter(for: "zh-Hans")
                .localizedString(for: hour, relativeTo: Date()),
            "1小时前"
        )
    }
}

private extension NSView {
    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for view in subviews {
            if matches(view) { return view }
            if let found = view.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
