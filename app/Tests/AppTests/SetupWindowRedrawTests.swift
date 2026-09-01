import AppKit
import Core
import XCTest
@testable import App

/// **When the window redraws**, which is a different question from what it draws. A lookup function
/// alone switches nothing: this window
/// is built once and `refresh()` rewrites only the status lines, so every title, heading, help
/// paragraph and button label keeps the language it was created in until something builds them
/// again.
///
/// **What these tests never write is `Settings.language`.** Its setter stores and posts, and
/// running that against `.standard` would rewrite the language of the app installed on this
/// machine — so the notification is posted directly, which is the same thing the setter does and
/// nothing more. The settings they *do* write — the terminal, the base directory, the tool answers
/// and the last request time, which are what decides which cards a redraw hides — are saved and put
/// back: measured, a `UserDefaults.standard` write from `swift test` lands in the runner's own
/// domain (`com.apple.dt.xctest.tool`) rather than the app's, so the save-and-restore is about
/// keeping the cases in this file independent of each other.
final class SetupWindowRedrawTests: XCTestCase {
    private var savedTerminal: Terminal!
    private var savedBaseDirectory: String!
    private var savedResources: String?
    private var savedAvailability: [String: Bool]?
    private var savedExecutables: [String: Bool]?
    private var savedLastRequestAt: Date?

    override func setUp() {
        super.setUp()
        savedTerminal = Settings.terminal
        savedBaseDirectory = Settings.baseDirectory
        savedAvailability = Settings.toolAvailability
        savedExecutables = Settings.toolExecutables
        savedLastRequestAt = Settings.lastRequestAt
        // The window has to be drawn from the real catalogues here, not from raw keys: two of these
        // cases are about **where** things end up, and a key is shorter than the sentence it stands
        // for — the same reason the layout tests read the source tree (`swift test` has no bundle).
        savedResources = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = SetupWindowLayoutTests.sourceResources
    }

    override func tearDown() {
        Settings.terminal = savedTerminal
        Settings.baseDirectory = savedBaseDirectory
        Settings.toolAvailability = savedAvailability
        Settings.toolExecutables = savedExecutables
        Settings.lastRequestAt = savedLastRequestAt
        AppLocalization.resourcesPath = savedResources
        AppLocalization.tagOverrideForTesting = nil
        super.tearDown()
    }

    private func makeController() -> SetupWindowController {
        let controller = SetupWindowController()
        _ = controller.window
        return controller
    }

    /// A window whose content is taller than its screen, which is the only state in which there is
    /// a scroll position to lose. The override stands in for the display so the case does not
    /// depend on whichever one the suite runs on — the same seam the layout tests use.
    private func makeScrollingController() throws -> (SetupWindowController, NSWindow, NSScrollView) {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let expectedContentHeight = controller.rootStack.fittingSize.height / 2
        controller.rootStack.visibleFrameOverride =
            NSRect(x: 0, y: 0, width: 1600, height: expectedContentHeight)
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))
        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        let actualWindowContentHeight = window.contentRect(forFrameRect: window.frame).height
        let actualClipHeight = scroll.contentView.bounds.height
        print(
            "SETUP_REDRAW_FIXTURE windowContentHeight=\(actualWindowContentHeight) "
                + "clipHeight=\(actualClipHeight) documentHeight=\(document.frame.height) "
                + "expectedContentHeight=\(expectedContentHeight)"
        )
        XCTAssertEqual(
            actualWindowContentHeight, expectedContentHeight, accuracy: 0.5,
            "the fixture window did not apply the requested half-height"
        )
        XCTAssertEqual(
            actualClipHeight, actualWindowContentHeight, accuracy: 0.5,
            "the fixture clip did not follow the applied window height"
        )
        XCTAssertGreaterThan(
            document.frame.height, actualClipHeight,
            "the fixture does not scroll, so it cannot lose a scroll position"
        )
        return (controller, window, scroll)
    }

    private func post(_ name: Notification.Name, in window: NSWindow) {
        NotificationCenter.default.post(name: name, object: nil)
        // The observer and the deferred window-size application both settle on the main loop.
        _ = SetupWindowTestSupport.settle(window)
    }

    /// A language change replaces the content, which is what makes the strings created inside the
    /// builders — every one of them — get read again.
    func testALanguageChangeRebuildsTheContent() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let before = try XCTUnwrap(window.contentView)

        post(.terminalCheckoutLanguageChanged, in: window)

        let after = try XCTUnwrap(window.contentView)
        XCTAssertFalse(before === after, "the content view was not rebuilt, so nothing re-read a string")
    }

    /// And the ordinary refreshes do **not**. They run on window activation and on every socket
    /// request, and a rebuild is not free even now that it carries the user's place across it: the
    /// field editor is torn down and put back, and what returns is found again by role rather than
    /// kept. Several times a minute, for strings that did not change.
    func testAnOrdinaryRefreshDoesNotRebuild() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let before = try XCTUnwrap(window.contentView)

        post(.terminalCheckoutRequestHandled, in: window)
        post(.terminalCheckoutToolsChecked, in: window)

        XCTAssertTrue(before === window.contentView, "an ordinary refresh replaced the view tree")
    }

    /// The hazard a rebuild introduces: two of the stacks are **stored** and filled by their
    /// builders, so building a second time appends a second copy instead of replacing the first.
    /// Same shape as an observer registered once per redraw, and the reason `toolsList` has always
    /// cleared before filling.
    func testRebuildingDoesNotDoubleTheRefillableSections() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let before = controller.refillableSectionsForTesting.map(\.arrangedSubviews.count)
        XCTAssertFalse(before.contains(0), "the fixture is empty — this would pass without checking anything")

        post(.terminalCheckoutLanguageChanged, in: window)
        post(.terminalCheckoutLanguageChanged, in: window)

        XCTAssertEqual(controller.refillableSectionsForTesting.map(\.arrangedSubviews.count), before)
    }

    /// The field the user types into is **re-parented, not recreated** — it is a stored property,
    /// so the rebuild moves it into the new stack. That is what keeps a rebuild from being a reset.
    ///
    /// And the edit itself survives now. Removing a field from a window ends its edit and discards
    /// the field editor, so this used to be recorded as the cost of replacing the view tree; the
    /// insertion point goes with it, and `makeFirstResponder` on a text field selects the whole
    /// value, so restoring focus without the range would leave the next keystroke replacing the
    /// path the user was halfway through fixing.
    func testARebuildReparentsTheFieldAndKeepsTheEditWhereItWas() throws {
        Settings.baseDirectory = NSTemporaryDirectory()
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let field = try XCTUnwrap(
            window.contentView?.firstDescendant(role: "control.baseDirectoryEdited")
                as? NSTextField
        )
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor(), "the fixture never started editing")
        XCTAssertGreaterThan(editor.string.count, 4, "the fixture has no text to put a cursor into")
        editor.selectedRange = NSRange(location: 4, length: 0)

        post(.terminalCheckoutLanguageChanged, in: window)

        let after = window.contentView?.firstDescendant(role: "control.baseDirectoryEdited")
        XCTAssertTrue(field === after, "the field was recreated, so anything it held is gone")
        XCTAssertNotNil(field.window, "the field was dropped instead of re-parented")
        XCTAssertTrue(
            window.firstResponder === field.currentEditor(), "the edit ended at the rebuild"
        )
        XCTAssertEqual(
            field.currentEditor()?.selectedRange, NSRange(location: 4, length: 0),
            "the edit came back with the whole value selected, which the next keystroke would replace"
        )
    }

    /// **The draft nobody stored is still the user's text.** An unusable path is deliberately not
    /// saved — it stays in the field so it can be fixed — and `refresh()` runs after the rebuild,
    /// where `updateBaseDirCard` draws the stored value over any field that is not being edited.
    /// Changing the language *through the picker* ends the edit first, so that condition holds and
    /// the typing is gone: type a path, change the language, lose it.
    func testALanguageChangeKeepsTheDraftNobodyStored() throws {
        Settings.baseDirectory = NSTemporaryDirectory()
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let field = try XCTUnwrap(
            window.contentView?.firstDescendant(role: "control.baseDirectoryEdited")
                as? NSTextField
        )
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        try XCTUnwrap(field.currentEditor()).string = "not a path"
        // The way the picker ends it: focus moves, the edit is committed, and the value is refused
        let picker = try XCTUnwrap(window.contentView?.firstDescendant(role: "control.languageChanged"))
        XCTAssertTrue(window.makeFirstResponder(picker))
        XCTAssertEqual(field.stringValue, "not a path", "the fixture never left a draft in the field")
        XCTAssertNotEqual(Settings.baseDirectory, "not a path", "the fixture stored it, so nothing is at risk")

        post(.terminalCheckoutLanguageChanged, in: window)

        XCTAssertEqual(
            field.stringValue, "not a path",
            "the redraw replaced what the user typed with the stored value"
        )
    }

    /// **`NSRange` counts UTF-16, and a `String` counts what people call characters.** A path with
    /// an emoji or a decomposed character in it makes the two differ, so clamping the restored
    /// selection against `String.count` lands the cursor before where it was. This repository knows
    /// the neighbouring hazard already — which carriers re-encode to NFD — so a decomposed path
    /// here is not exotic.
    func testTheRestoredSelectionIsClampedInTheUnitsItIsMeasuredIn() throws {
        // Stored rather than typed, which is the state a hand-edited plist leaves: the field draws
        // it, the status line says it is unusable, and none of that moves the cursor
        Settings.baseDirectory = "/tmp/🙂/notes"
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let field = try XCTUnwrap(
            window.contentView?.firstDescendant(role: "control.baseDirectoryEdited")
                as? NSTextField
        )
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        XCTAssertEqual(editor.string, "/tmp/🙂/notes", "the fixture drew something else")
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        XCTAssertNotEqual(end.location, editor.string.count, "the fixture has no character that counts twice")
        editor.selectedRange = end

        post(.terminalCheckoutLanguageChanged, in: window)

        XCTAssertEqual(
            field.currentEditor()?.selectedRange, end,
            "the cursor came back before where it was, by the width of what the two units disagree on"
        )
    }

    /// **The anchor card can be gone by the time the position is restored.** `refresh()` decides
    /// which cards are hidden, and it runs after the rebuild — so a card that was the anchor can be
    /// collapsed a moment later, and skipping the restore leaves the window at its first line,
    /// which is this item's whole defect in the one case its fix did not cover.
    func testAHiddenAnchorFallsBackToTheCardBelowIt() throws {
        Settings.lastRequestAt = nil // nothing has connected yet, so the extension card is showing
        let (controller, window, scroll) = try makeScrollingController()
        let card = try XCTUnwrap(controller.rootStack.firstDescendant(role: "card.extension"))
        XCTAssertFalse(card.isHidden, "the fixture never showed the card it is about to hide")
        let clipHeight = scroll.contentView.bounds.height
        try XCTUnwrap(scroll.documentView).scroll(NSPoint(x: 0, y: card.frame.maxY - clipHeight - 20))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(
            card.frame.maxY - scroll.documentVisibleRect.maxY, 20, accuracy: 0.5,
            "the fixture did not land where it meant to"
        )

        // A request arrives, so the card this position is anchored to collapses during `refresh()`
        Settings.lastRequestAt = Date()
        post(.terminalCheckoutLanguageChanged, in: window)

        let after = try XCTUnwrap(window.contentView as? NSScrollView)
        XCTAssertTrue(
            try XCTUnwrap(controller.rootStack.firstDescendant(role: "card.extension")).isHidden,
            "the fixture did not hide the anchor, so it is not testing the fallback"
        )
        // The card below it moved up into the space, so its top is where the measurement was taken
        let neighbour = try XCTUnwrap(controller.rootStack.firstDescendant(role: "card.language"))
        XCTAssertEqual(
            neighbour.frame.maxY - after.documentVisibleRect.maxY, 20, accuracy: 0.5,
            "a hidden anchor dropped the position instead of falling through to the card below it"
        )
    }

    /// **Focus is restored by finding the control again, not by keeping a pointer to it.** Every
    /// control in this window except the field is built anew by `buildContent()`, so the object
    /// that had focus does not exist afterwards — what survives a rebuild is the role, and the role
    /// is what the identifier carries.
    func testALanguageChangeKeepsTheFocusedControl() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let picker = try XCTUnwrap(window.contentView?.firstDescendant(role: "control.languageChanged"))
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(picker))

        post(.terminalCheckoutLanguageChanged, in: window)

        let after = try XCTUnwrap(window.contentView?.firstDescendant(role: "control.languageChanged"))
        XCTAssertFalse(picker === after, "the fixture stopped rebuilding this control")
        XCTAssertTrue(
            window.firstResponder === after,
            "the language picker lost focus to the redraw its own use causes"
        )
    }

    /// The scroll position, when the window is tall enough to have one. Same language, so the
    /// document is the same height and the answer is exact.
    func testALanguageChangeKeepsTheScrollPosition() throws {
        let (_, window, scroll) = try makeScrollingController()
        try XCTUnwrap(scroll.documentView).scroll(NSPoint(x: 0, y: 120))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.documentVisibleRect.origin.y, 120, accuracy: 0.5, "the fixture did not scroll")

        post(.terminalCheckoutLanguageChanged, in: window)

        let after = try XCTUnwrap(window.contentView as? NSScrollView)
        XCTAssertFalse(scroll === after, "the fixture stopped rebuilding the content")
        XCTAssertEqual(
            after.documentVisibleRect.origin.y, 120, accuracy: 0.5,
            "the language change scrolled the window away from where the user was"
        )
    }

    /// The window is movable by its background, so replacing the document for a language change
    /// must not spend the new stack's first update re-centering a window the user already placed.
    func testALanguageChangeKeepsTheWindowOrigin() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 2000)
        controller.rootStack.visibleFrameOverride = visible
        _ = try XCTUnwrap(SetupWindowTestSupport.settle(window))

        let placedOrigin = NSPoint(x: visible.minX + 40, y: visible.minY + 40)
        window.setFrameOrigin(placedOrigin)
        XCTAssertEqual(window.frame.origin.x, placedOrigin.x, accuracy: 0.5)
        XCTAssertEqual(window.frame.origin.y, placedOrigin.y, accuracy: 0.5)

        post(.terminalCheckoutLanguageChanged, in: window)

        XCTAssertEqual(
            window.frame.origin.x, placedOrigin.x, accuracy: 0.5,
            "the language change re-centered a window the user had moved"
        )
        XCTAssertEqual(
            window.frame.origin.y, placedOrigin.y, accuracy: 0.5,
            "the language change re-centered a window the user had moved"
        )
    }

    /// **What "the same place" means when the text reflows.** A translation is longer or shorter
    /// than the sentence it replaces, so the document is a different height afterwards and no
    /// absolute offset can mean the same thing. What is kept is **a card's top edge and the
    /// distance below it** — not the sentence or the line that was there, which the translation
    /// rewrote.
    func testTheAnchorCardsEdgeAndOffsetSurviveAReflow() throws {
        AppLocalization.tagOverrideForTesting = "ko"
        let (controller, window, scroll) = try makeScrollingController()
        let heightBefore = try XCTUnwrap(scroll.documentView).frame.height
        let card = try XCTUnwrap(controller.rootStack.firstDescendant(role: "card.terminal"))
        // Put that card's top a little above the top of the viewport
        let clipHeight = scroll.contentView.bounds.height
        try XCTUnwrap(scroll.documentView).scroll(NSPoint(x: 0, y: card.frame.maxY - clipHeight - 30))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offsetBefore = card.frame.maxY - scroll.documentVisibleRect.maxY
        let originBefore = scroll.documentVisibleRect.origin.y
        XCTAssertEqual(offsetBefore, 30, accuracy: 0.5, "the fixture did not land where it meant to")

        AppLocalization.tagOverrideForTesting = "en"
        post(.terminalCheckoutLanguageChanged, in: window)

        let after = try XCTUnwrap(window.contentView as? NSScrollView)
        let cardAfter = try XCTUnwrap(controller.rootStack.firstDescendant(role: "card.terminal"))
        XCTAssertNotEqual(
            try XCTUnwrap(after.documentView).frame.height, heightBefore,
            "the document did not change height, so this case is not about a reflow any more"
        )
        XCTAssertEqual(
            cardAfter.frame.maxY - after.documentVisibleRect.maxY, offsetBefore, accuracy: 0.5,
            "the anchor edge is no longer the same distance above the top of the viewport"
        )
        // ...and an absolute restore would have been a different answer, which is why this is
        // anchored to a card rather than to a number of points from the top
        XCTAssertNotEqual(after.documentVisibleRect.origin.y, originBefore, accuracy: 0.5)
        // The invariant that lets the arithmetic clamp one end and not the other: an anchor is a
        // card inside this document, so what comes back is a position the document really has
        XCTAssertGreaterThanOrEqual(after.documentVisibleRect.origin.y, 0)
        XCTAssertLessThanOrEqual(
            after.documentVisibleRect.maxY, try XCTUnwrap(after.documentView).frame.height + 0.5,
            "the restore scrolled past the end of the document"
        )
    }

    /// The arithmetic, including the end the window cases cannot stage: a shipped language moves
    /// the document by tens of points, and asking to scroll above the first line takes a card
    /// within one viewport of the top.
    func testWhereTheViewportGoesToPutTheAnchorBack() {
        // The ordinary answer: the card's top ends up `offset` below the top edge of the viewport
        XCTAssertEqual(scrollOrigin(anchorTop: 600, offset: 30, clip: 400), 170)
        // A card near the top of the document — there is nothing above the first line to show, so
        // the answer is the first line rather than a negative one
        XCTAssertEqual(scrollOrigin(anchorTop: 380, offset: 30, clip: 400), 0)
        XCTAssertEqual(scrollOrigin(anchorTop: 300, offset: 0, clip: 400), 0)
    }

    /// The assumption the two restores rest on, asserted rather than trusted: **a control this
    /// window owns answers to the role its own action names, and no two share one.** Without it a
    /// control added later would silently lose its focus across a rebuild, or take the focus meant
    /// for another.
    ///
    /// **The gate recomputes the role rather than checking that there is one**.
    /// Non-empty and unique was weaker than the sentence it stood for: a hardcoded identifier that
    /// named nothing in particular passed it, and then the invariant — *derived from the action, so
    /// it cannot go stale on its own* — was true of the code and not of the check. Here that is a
    /// one-line recomputation, so the check says what the sentence says. (The attribute lint next
    /// door is the opposite case: what it would take to close is a parser, and a lint
    /// stops short of one.)
    func testEveryControlTheWindowOwnsCarriesTheRoleItsActionNames() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        var owned: [NSControl] = []
        collectControls(try XCTUnwrap(window.contentView), owned: controller, into: &owned)
        XCTAssertGreaterThan(owned.count, 10, "the scan found almost nothing — check the walk")
        var roles: Set<String> = []
        for control in owned {
            let action = try XCTUnwrap(control.action, "a control this window owns does nothing: \(type(of: control))")
            let role = try XCTUnwrap(
                control.identifier?.rawValue,
                "a control with no role: \(type(of: control)) \(action)"
            )
            // The rule the code writes: `control.<action>`, plus `.<qualifier>` where one action
            // serves several controls (the terminal radios, told apart by a product name)
            let derived = "control.\(action)"
            XCTAssertTrue(
                role == derived || role.hasPrefix("\(derived)."),
                "\(role) is not the role \(action) names — a role that is written rather than derived goes stale silently"
            )
            XCTAssertTrue(roles.insert(role).inserted, "two controls answer to \(role)")
        }
    }

    private func collectControls(_ view: NSView, owned by: AnyObject, into out: inout [NSControl]) {
        if let control = view as? NSControl, control.target as AnyObject? === by { out.append(control) }
        for subview in view.subviews { collectControls(subview, owned: by, into: &out) }
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

    /// The same question the window asks itself after a rebuild: which view here has this role?
    func firstDescendant(role: String) -> NSView? {
        firstDescendant(where: { $0.identifier?.rawValue == role })
    }
}
