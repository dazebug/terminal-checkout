import AppKit
import Core

/// The setup window: installation, the terminal choice, the permissions and the test, in one screen.
/// The design is that the window *is* a terminal session — a section reads as a prompt (❯), and a
/// state reads the way an exit code does, through colour.
/// What is on screen follows the state: the card for a step that is done disappears, and that step
/// stays visible only as a dot on the pipeline strip.

/// Card width. File scope so the status-label factory below can use it before `self` exists.
let setupContentWidth: CGFloat = 560
/// Text width inside a card (`setupContentWidth` minus the card's 14pt insets on both sides).
let setupTextWidth: CGFloat = setupContentWidth - 28

struct FittedContentLayoutPass {
    let fittingSize: NSSize
    let targetSize: NSSize
    let lastRequestedSize: NSSize?
    let appliedContentSize: NSSize
    let requestedSize: Bool
}

/// The settings stack, which sizes its window to itself.
///
/// Why the stack and not the window controller: the size has three preconditions a caller has to
/// get right *every* time — apply the visibility changes, let the constraint pass settle, then
/// measure — and one that forgets leaves the window shorter than its content, at which point the
/// engine breaks a constraint and the cards overlap instead of merely clipping. Measuring at the
/// end of this view's own `layout()` satisfies all three by construction: that runs after the
/// pass, and any change to a card, a label or a section's `isHidden` already dirties this view.
/// A section added later is covered without anyone remembering the rule.
///
/// Why not hook the enclosing scroll view instead: flipping `isHidden` deep in the tree never
/// marks *it* dirty — its own frame does not change — so its `layout()` simply would not run
/// (measured: exactly one call, at construction). The dirty view is the one whose arrangement
/// changed, so that is the one that has to do the measuring.
///
/// The screen matters as much as the content: this window is `isMovableByWindowBackground`, so it
/// is easy to leave near the bottom edge, and a window that grows past the edge gets its frame
/// clamped by AppKit — handing the stack less height than it asked for. So growth is paired with
/// moving the window back inside the visible frame; and when the content genuinely cannot fit the
/// screen, the enclosing scroll view takes over rather than the layout being squeezed.
final class FittedContentStackView: NSStackView {
    /// The size we last asked the window for. Without it, a clamped request (content taller than
    /// the screen) would be re-issued on every pass and layout would never settle.
    private var lastRequestedSize: NSSize?
    /// Test-only observation. It is nil in the application, and never participates in layout.
    static var layoutProbeForTesting: ((FittedContentLayoutPass) -> Void)?
    /// Stands in for the screen so a test can exercise the clamp without depending on whichever
    /// display it happens to run on.
    /// Setting the stand-in after the first layout must schedule the pass that consumes it; a plain
    /// stored property would leave a clean tree measuring the real display until another change.
    var visibleFrameOverride: NSRect? {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        guard let window, window.contentView != nil else { return }
        var target = fittingSize
        let visible = visibleFrameOverride ?? (window.screen ?? NSScreen.main)?.visibleFrame
        if let visible { target.height = min(target.height, visible.height) }
        guard lastRequestedSize != target else {
            reportLayoutPass(
                fittingSize: fittingSize, targetSize: target, requestedSize: false, window: window
            )
            return
        }
        lastRequestedSize = target
        window.setContentSize(target)
        if let visible { Self.moveInside(visible, window) }
        reportLayoutPass(
            fittingSize: fittingSize, targetSize: target, requestedSize: true, window: window
        )
    }

    private func reportLayoutPass(
        fittingSize: NSSize, targetSize: NSSize, requestedSize: Bool, window: NSWindow
    ) {
        guard let probe = Self.layoutProbeForTesting else { return }
        probe(FittedContentLayoutPass(
            fittingSize: fittingSize,
            targetSize: targetSize,
            lastRequestedSize: lastRequestedSize,
            appliedContentSize: window.contentRect(forFrameRect: window.frame).size,
            requestedSize: requestedSize
        ))
    }

    /// `setContentSize` keeps the top-left corner fixed, so growing pushes the bottom edge down
    /// and off the screen. Slide the window back rather than letting AppKit clamp the height.
    private static func moveInside(_ visible: NSRect, _ window: NSWindow) {
        var frame = window.frame
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }
    }
}

/// Every status line in the window is built here.
///
/// Declaring one with `NSTextField(labelWithString:)` and styling it later is how
/// `accessibilityStatusLabel` ended up in the wrong font and unable to wrap: it sat in the same
/// property block as its four siblings but was missed by the styling loop in `buildContent`, so a
/// long status clipped at the card edge instead of flowing onto a second line. Styling at
/// construction removes the chance to forget.
func makeStatusLabel(font: NSFont) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = font
    label.usesSingleLineMode = false
    label.cell?.wraps = true
    label.cell?.isScrollable = false
    label.maximumNumberOfLines = 0
    label.preferredMaxLayoutWidth = setupTextWidth
    return label
}

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let manifestStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private let extensionStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private let installFeedbackLabel = makeStatusLabel(font: Theme.ui(11.5))
    private let permissionStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private let accessibilityStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private let testResultLabel = makeStatusLabel(font: Theme.mono(11.5))
    /// Kept as a list so a test can assert the whole family is styled — the defect this replaces
    /// was one member silently missing out.
    /// The two stacks that are **filled** rather than created — a rebuild appends to them unless
    /// the builders clear first, which is the one way replacing the view tree can double a window
    var refillableSectionsForTesting: [NSStackView] { [permissionSection, accessibilitySection] }

    var statusLabelsForTesting: [NSTextField] {
        [
            manifestStatusLabel, extensionStatusLabel, installFeedbackLabel,
            permissionStatusLabel, accessibilityStatusLabel, testResultLabel,
        ]
    }
    /// Stored because `refresh()` toggles its enabled state, so the rebuild **re-parents** it and
    /// a title set here would be the one string in this window that kept its old language. The
    /// title is set in the builder instead, where a rebuild reads it again — and it lives in
    /// exactly one place, so a rebuild has one site to update rather than two to keep in step.
    private let requestPermissionButton = NSButton(title: "", target: nil, action: nil)
    private var itermRadio: NSButton!
    private var weztermRadio: NSButton!
    private var warpRadio: NSButton!
    private var terminalNoteLabel: NSTextField!
    /// On screen only while the terminal is iTerm2 **and** the permission is not granted — an
    /// iTerm2 that is not installed lands there too, so the section stays up. WezTerm needs no TCC
    /// permission at all, which is why it has no section of its own.
    private let permissionSection = NSStackView()
    /// On screen only while the terminal is Warp and the Accessibility permission is not granted
    private let accessibilitySection = NSStackView()
    private let pipeline = PipelineStripView()
    private let cursor = BlinkCursorView()

    /// The scroll view's document — what the window height is measured from.
    private(set) var rootStack: FittedContentStackView!
    private var chromeCard: NSView!
    private var extensionCard: NSView!
    private var toolsCard: NSView!
    private let toolsList = NSStackView()
    /// Where repositories are cloned. Stays visible like the terminal card — it is a setting the
    /// user may want to change, not an install step that completes and disappears.
    private var baseDirCard: NSView!
    private let baseDirField = NSTextField(string: "")
    /// **What this window last put in that field**, which is how it can tell its own text from the
    /// user's. Anything else in there is a draft — typed and not stored, because an unusable path is
    /// deliberately never stored — and a draft is not something a redraw may throw away. `nil` until
    /// the first draw, so the first one happens.
    private var drawnBaseDirectory: String?
    private let baseDirStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private var guideBlock: NSView!
    private var utilityRow: NSView!
    private var languagePopUp: NSPopUpButton!
    private var languageRestartButton: NSButton!
    private var languageNoteLabel: NSTextField!
    private var languageObserver: NSObjectProtocol?
    /// `reshowInstall` forces the extension card back on screen. Closing the window clears it
    /// (`windowWillClose`), so the next time the window opens the state decides again.
    private var forceShowInstall = false
    private var requestObserver: (any NSObjectProtocol)?
    private var toolsObserver: (any NSObjectProtocol)?

    /// What breaks without the tool — the sentence a user judges "do I need to install this?" by.
    /// Only `z` splits on whether a base directory is configured: with one, the entry clause falls
    /// back to `cd`/`clone`, so "every button fails" stops being true. The severity verdict itself
    /// lives in Core (`toolIsCritical`) so it can be pinned by a test; only the copy is here.
    private func toolAdvice(
        baseDirectoryConfigured: Bool
    ) -> [(name: String, critical: Bool, advice: String)] {
        [
            (
                "z", toolIsCritical("z", baseDirectoryConfigured: baseDirectoryConfigured),
                // Two complete messages rather than a shared opening plus two tails: a
                // sentence assembled from pieces cannot be reordered by a translator, and three of
                // these did share an opening clause
                localized(
                    baseDirectoryConfigured
                        ? "app.tools.z.adviceWithBaseDir" : "app.tools.z.adviceNoBaseDir"
                )
            ),
            (
                "gh", false,
                localized("app.tools.gh.advice")
            ),
            (
                "claude", false,
                localized("app.tools.claude.advice")
            ),
        ]
    }

    private let terminalRadioWidth: CGFloat = 120
    /// Shown on screen **and** run in the user's terminal, which is why it is a `ShellPayload`
    /// and not a catalogue key: a translated apostrophe breaks the `echo '…'` quoting and the test
    /// button reports a shell error instead of opening a tab. The type is what enforces it —
    /// `localized(…)` returns a `String`, and `ShellPayload` cannot be built from one.
    private let testCommand: ShellPayload = "echo 'Terminal Checkout: connection OK'"

    /// Called when the window closes — `AppDelegate` uses it to hide the app from the Dock again
    var onClose: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = localized("app.window.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // A terminal is dark, so this window is pinned to dark whatever the system appearance is.
        // Not a preference: `Theme`'s colours are fixed values rather than dynamic ones, and in a
        // light appearance they would not follow
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.isMovableByWindowBackground = true
        self.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        updateTerminalControls()
        refresh()
        // Settle the layout before centring: the window is sized from inside the layout pass, so
        // centring the initial 600x640 frame would leave it off-centre once the real height lands.
        window.contentView?.layoutSubtreeIfNeeded()
        window.center()
        cursor.start()
        requestObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutRequestHandled, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // The tool check opens a login shell, so it finishes after this window is already up
        toolsObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutToolsChecked, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Our own strings do not wait for a restart — a language change redraws this window
        languageObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildForLanguageChange() }
    }

    deinit {
        for observer in [requestObserver, toolsObserver, languageObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cursor.start()
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        cursor.stop()
        forceShowInstall = false
        guideBlock.isHidden = true
        installFeedbackLabel.isHidden = true
        testResultLabel.isHidden = true
        onClose?()
    }

    /// **The window is built once, and `refresh()` rewrites only the status lines.** Everything
    /// else — card titles, section headings, help paragraphs, button and radio titles, the picker's
    /// `auto` entry — is created in `buildContent()` and never touched again, so a language change
    /// would leave the whole window in the old language while three labels moved. A lookup function
    /// alone does not switch anything: the lookup has to be reached again, and nothing reaches it.
    ///
    /// Rebuilding the content is the mechanism, rather than a second pass that re-sets each string:
    /// a re-set pass has to name every string, so it is wrong the moment a new string is added,
    /// and it would be wrong silently. This is correct for strings that do not exist yet.
    ///
    /// It runs **only on a language change**, not on every `refresh()` — refresh runs on window
    /// activation and on every socket request, and replacing the view tree that often would fight
    /// the user for focus and for their place in the window.
    ///
    /// State survives because the views that hold it are stored properties: the base-directory
    /// field, the status labels and the pipeline strip are re-parented into the new stack rather
    /// than recreated, so what the user has typed is still there afterwards.
    ///
    /// **What does not survive on its own is where the user was.** The scroll origin lives in the
    /// scroll view being replaced, and the first responder is dropped the moment its view leaves
    /// the window — so a language change scrolled the window back to the top and took the focus
    /// away, in the one interaction this whole feature is entered through. `SetupWindowPlace`
    /// carries both across in terms that a rebuilt tree can still answer.
    func rebuildForLanguageChange() {
        guard let window = window else { return }
        let place = capturePlace(in: window)
        window.contentView = buildContent()
        window.contentView?.layoutSubtreeIfNeeded()
        refresh()
        // Restored after `refresh()`, not before: refresh rewrites the status lines, and one that
        // wraps onto a second line moves every card below it. Measuring against a document that is
        // about to change height would put the user a status line away from where they were.
        window.contentView?.layoutSubtreeIfNeeded()
        restore(place, in: window)
    }

    /// Where the user was, in terms that outlive the views that held it: **a role and a card**,
    /// never a view and never a bare number of points from the top.
    private struct SetupWindowPlace {
        /// The control that had focus. A field being edited answers with its field editor, so the
        /// selection is carried too — `makeFirstResponder` on a text field selects the whole value,
        /// and restoring focus without the range would leave the next keystroke replacing the path
        /// the user was halfway through fixing.
        var focusedRole: NSUserInterfaceItemIdentifier?
        var selection: NSRange?
        /// The card at the top of the viewport, and how far into it the viewport began.
        var anchorRole: NSUserInterfaceItemIdentifier?
        var anchorOffset: CGFloat = 0
    }

    /// The card to measure from, which is the captured one unless `refresh()` has just collapsed it.
    ///
    /// **A hidden card keeps the frame it last had**, so it cannot be measured from — and skipping
    /// the restore because of that leaves the window at its first line, which is the whole defect
    /// this machinery exists for, in the one case it did not cover. So the search
    /// falls through to the next card **down the stack**, and "next" means next in the order the
    /// cards are added rather than nearest in points: when a card collapses, the one below it moves
    /// up into the space, so its top edge is about where the measurement was taken. Falling upwards
    /// is the last resort, for an anchor that was the last visible card.
    private func anchorToRestore(_ role: NSUserInterfaceItemIdentifier) -> NSView? {
        let cards = rootStack?.arrangedSubviews ?? []
        guard let index = cards.firstIndex(where: { $0.identifier == role }) else { return nil }
        return cards[index...].first(where: { !$0.isHidden && $0.frame.height > 0 })
            ?? cards[..<index].last(where: { !$0.isHidden && $0.frame.height > 0 })
    }

    private func capturePlace(in window: NSWindow) -> SetupWindowPlace {
        var place = SetupWindowPlace()
        let editor = window.firstResponder as? NSTextView
        let focused = (editor?.delegate as? NSView) ?? (window.firstResponder as? NSView)
        place.focusedRole = focused?.identifier
        place.selection = editor?.selectedRange

        guard let scroll = window.contentView as? NSScrollView, let stack = rootStack else { return place }
        let top = scroll.documentVisibleRect.maxY
        // The document view is **not flipped**, so the first card has the largest `y` and the top of
        // the viewport is `maxY` rather than `minY`. The anchor is the lowest card whose own top is
        // still at or above that line — the card the reader's eye is in. Hidden cards are skipped:
        // a collapsed one keeps a stale frame, and the rebuilt tree would put it somewhere else.
        let cards = stack.arrangedSubviews.filter { !$0.isHidden && $0.frame.height > 0 }
        let anchor = cards.filter { $0.frame.maxY >= top }.min(by: { $0.frame.maxY < $1.frame.maxY })
            ?? cards.max(by: { $0.frame.maxY < $1.frame.maxY })
        guard let anchor else { return place }
        place.anchorRole = anchor.identifier
        place.anchorOffset = anchor.frame.maxY - top
        return place
    }

    /// **What comes back is the anchor card's top edge and the distance below it**, not the line of
    /// text the reader was on: the words inside the card reflowed too, and nothing here can say
    /// where a particular sentence went. A translation is longer or shorter than the one it
    /// replaced, so the cards above the viewport are a different height afterwards and the old
    /// origin points at different content — which is why the measurement is taken from a card edge.
    /// `scrollOrigin` answers the one position the document may not have, above its first line.
    private func restore(_ place: SetupWindowPlace, in window: NSWindow) {
        if let scroll = window.contentView as? NSScrollView,
           let document = scroll.documentView,
           let role = place.anchorRole,
           let anchor = anchorToRestore(role) {
            let origin = scrollOrigin(
                anchorTop: anchor.frame.maxY, offset: place.anchorOffset,
                clip: scroll.contentView.bounds.height
            )
            document.scroll(NSPoint(x: 0, y: origin))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        guard let role = place.focusedRole,
              let control = window.contentView?.firstDescendant(withRole: role),
              window.makeFirstResponder(control) else { return }
        guard let selection = place.selection, let editor = (control as? NSControl)?.currentEditor() else { return }
        // The text can have changed under the cursor — a stored value drawn over a field that held
        // this window's own text — so the range is clamped to what is there now.
        //
        // **In the units `NSRange` is written in, which are UTF-16 and not characters.** `String.count`
        // counts what a reader would call characters, so for a path with an
        // emoji or a decomposed vowel in it the two disagree and clamping against the wrong one
        // moves the cursor to before where it was. Decomposition is not exotic here: this
        // repository already carries what re-encodes to NFD and what does not.
        let length = editor.string.utf16.count
        let location = min(selection.location, length)
        editor.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
    }

    // MARK: - Building the UI

    private func buildContent() -> NSView {
        let stack = FittedContentStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 20, bottom: 18, right: 20)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = Theme.bg.cgColor
        // The stand-in for the screen belongs to the display, not to this instance of the stack:
        // the screen does not change because the language did, and a rebuild that dropped it would
        // measure the next layout against the real display in the middle of a test that pinned one
        stack.visibleFrameOverride = rootStack?.visibleFrameOverride

        chromeCard = buildChromeCard()
        extensionCard = buildExtensionCard()
        baseDirCard = buildBaseDirCard()
        toolsCard = buildToolsCard()
        utilityRow = buildUtilityRow()

        // **Named, because a rebuild has to be able to find them again.** The scroll anchor is a
        // card, and a card's own text is the one thing a language change rewrites — so the name is
        // declared here rather than derived from anything drawn. Reordering this list moves the
        // cards and carries their names with them, which is what an index could not do.
        for (name, card) in [
            ("header", header()), ("pipeline", pipeline), ("chrome", chromeCard!),
            ("extension", extensionCard!), ("language", languageCard()), ("terminal", terminalCard()),
            ("baseDir", baseDirCard!), ("tools", toolsCard!), ("test", testCard()),
            ("utility", utilityRow!),
        ] {
            card.identifier = NSUserInterfaceItemIdentifier("card.\(name)")
            stack.addArrangedSubview(card)
            if card === pipeline { stack.setCustomSpacing(16, after: pipeline) }
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: setupContentWidth + 40).isActive = true

        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.bg
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay // no gutter, so the stack keeps its full width
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        rootStack = stack
        return scroll
    }

    private func header() -> NSView {
        let glyph = NSTextField(labelWithString: "❯_")
        glyph.font = Theme.mono(15, .semibold)
        glyph.textColor = Theme.accent

        let title = NSTextField(labelWithString: "Terminal Checkout")
        title.font = Theme.mono(16, .semibold)
        title.textColor = Theme.text

        let version = NSTextField(labelWithString: appVersion)
        version.font = Theme.mono(11)
        version.textColor = Theme.textFaint

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 7
        row.addView(glyph, in: .leading)
        row.addView(title, in: .leading)
        row.addView(cursor, in: .leading)
        row.addView(version, in: .trailing)
        row.widthAnchor.constraint(equalToConstant: setupContentWidth).isActive = true
        return row
    }

    // MARK: Cards — the setup steps (hidden once done)

    private func buildChromeCard() -> NSView {
        card(localized("app.card.chrome.title"), [
            manifestStatusLabel,
            buttonRow([button(localized("app.button.registerUpdate"), #selector(registerManifest))]),
        ])
    }

    private func buildExtensionCard() -> NSView {
        let installButton = button(localized("app.button.installInChrome"), #selector(installInChrome))
        installButton.keyEquivalent = "\r"
        installButton.bezelColor = Theme.actionGreen
        installButton.toolTip = Installer.extensionDirectory

        guideBlock = quoteBlock([
            localized("app.guide.step1"),
            localized("app.guide.step2"),
            localized("app.guide.step3"),
            localized("app.guide.step4"),
        ])
        guideBlock.isHidden = true
        installFeedbackLabel.isHidden = true

        return card(localized("app.card.extension.title"), [
            extensionStatusLabel,
            // The button's own label, not a second copy of it: quoting a label by hand is how a
            // body ends up naming a button that has since been renamed, and in five locales at once
            helpLabel(localized("app.card.extension.help", localized("app.button.installInChrome"))),
            buttonRow([installButton]),
            guideBlock,
            installFeedbackLabel,
        ])
    }

    /// Where repositories live. `z {repo}` silently does nothing when zoxide's DB has never
    /// recorded that repository (issue #30); with this set, the command falls back to
    /// `cd <base>/<repo>` and then to cloning. Validation, `~` expansion, and clause assembly all
    /// live in Core — this card stores the **normalized** result (echoed back into the field) and
    /// only words the rejection reasons.
    private func buildBaseDirCard() -> NSView {
        baseDirField.placeholderString = localized("app.baseDir.placeholder")
        baseDirField.font = Theme.mono(11.5)
        baseDirField.target = self
        baseDirField.action = #selector(baseDirectoryEdited)
        baseDirField.identifier = role(#selector(baseDirectoryEdited))
        // Save on focus loss as well as Enter — nobody should close the window wondering
        // whether it was saved
        baseDirField.cell?.sendsActionOnEndEditing = true
        baseDirField.widthAnchor.constraint(equalToConstant: setupTextWidth - 110).isActive = true

        let row = NSStackView(views: [baseDirField, button(localized("app.button.chooseFolder"), #selector(chooseBaseDirectory))])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return card(localized("app.card.baseDir.title"), [
            helpLabel(
                localized("app.card.baseDir.help")
            ),
            row,
            baseDirStatusLabel,
            // Saved button commands are never rewritten for the user, so someone upgrading from an
            // earlier version gets no fallback from setting the folder alone. The options page now
            // offers that rewrite itself (issue #31), so point at the notice rather than asking for
            // the old by-hand re-apply
            helpLabel(
                localized("app.card.baseDir.legacyNote")
            ),
        ])
    }

    /// The check on the tools a command calls. The login shell has to be asked rather than the
    /// app's own PATH — `z` is a shell function zoxide defines in an rc file, so looking for an
    /// executable of that name finds nothing.
    private func buildToolsCard() -> NSView {
        toolsList.orientation = .vertical
        toolsList.alignment = .leading
        toolsList.spacing = 6
        return card(localized("app.card.tools.title"), [
            helpLabel(localized("app.card.tools.help")),
            toolsList,
        ])
    }

    // MARK: Cards — always on screen (terminal choice, test)

    // MARK: Cards — language

    /// **This picker controls the app; Chrome controls the extension**: the setup window is here
    /// because it is what a user sees *before* the extension exists. The app defaults to macOS's
    /// language (or uses an explicit choice), while the extension reads Chrome's catalogue and is
    /// not synchronized with this picker.
    ///
    /// The entries are each written in their own language, which is what a language menu does
    /// everywhere: a user who has landed in a language they cannot read has to be able to find
    /// their way out of it. Only the `auto` line is in the window's language, and the catalogue
    /// provides it with the rest of this window.
    /// into the catalogue with the rest of this window.
    private func languageCard() -> NSView {
        languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopUp.addItem(withTitle: localized("app.language.followSystem"))
        languagePopUp.lastItem?.representedObject = automaticLocalePreference
        for tag in supportedLocales {
            languagePopUp.addItem(withTitle: languageMenuTitles[tag] ?? tag)
            languagePopUp.lastItem?.representedObject = tag
        }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)
        languagePopUp.identifier = role(#selector(languageChanged))

        // Half of the change lands now and half on the next launch, so the button that closes
        // that gap sits next to the control that opens it rather than in a menu somewhere
        languageRestartButton = button(localized("app.button.restartNow"), #selector(restartForLanguage))
        languageNoteLabel = helpLabel("", width: setupContentWidth - 28)

        let row = NSStackView(views: [languagePopUp, languageRestartButton])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        return card(localized("app.card.language.title"), [row, languageNoteLabel])
    }

    /// Each language in its own script. Not a catalogue lookup on purpose — these read the same
    /// whatever language the window is in, which is the point of a language menu.
    private var languageMenuTitles: [String: String] {
        ["en": "English", "ko": "한국어", "ja": "日本語", "zh-Hans": "简体中文", "zh-Hant": "繁體中文"]
    }

    @objc private func languageChanged() {
        guard let choice = languagePopUp.selectedItem?.representedObject as? String else { return }
        Settings.language = choice
        refresh()
    }

    /// **The picker asks, it does not decide.** Whether a restart is safe right now is
    /// `LocaleRestartGate`'s question, and its answer is "no claude input delivery is in flight" —
    /// restarting through one would cut it off and orphan a Warp helper whose only defence is its
    /// lifetime.
    ///
    /// A refusal is **not** a deferral: it changes the note and stops, leaving the user holding the
    /// trigger. Queueing the restart would need the queue to outlive a delivery that may never end,
    /// which is the same self-lifetime problem this gate exists to avoid.
    ///
    @objc private func restartForLanguage() {
        guard LocaleRestartGate.admitRestart() else {
            languageNoteLabel.stringValue = languageNote(.restartBlocked)
            return
        }
        let app = Bundle.main.bundlePath
        // A detached `open` after this process exits: relaunching from inside a terminating app
        // races the old instance's socket, and the new one would fail to bind
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", app]
        do {
            try task.run()
        } catch {
            // Nothing will come back to lift the admission, and an app that refuses every claude
            // input for the rest of its life is a worse outcome than the restart not happening
            LocaleRestartGate.withdrawAdmission()
            checkoutLog("the relaunch could not be started, so the app is not restarting — \(errorMessage(error))")
            languageNoteLabel.stringValue = languageNote(.restartFailed)
            return
        }
        NSApp.terminate(nil)
    }

    /// The note is a closed state, so a blocked restart and a failed relaunch cannot be requested
    /// together or silently collapse into the ordinary note.
    private enum LanguageNoteState {
        case ordinary
        case restartBlocked
        case restartFailed
    }

    private func languageNote(_ state: LanguageNoteState = .ordinary) -> String {
        switch state {
        case .restartFailed:
            return localized("app.language.restartFailed")
        case .restartBlocked:
            return localized("app.language.restartDeferred")
        case .ordinary:
            return localized("app.language.note")
        }
    }

    private func terminalCard() -> NSView {
        itermRadio = radio("iTerm2", installed: PermissionChecker.isITermInstalled)
        weztermRadio = radio("WezTerm", installed: PermissionChecker.isWezTermInstalled)
        warpRadio = radio("Warp", installed: PermissionChecker.isWarpInstalled)

        // Stacked vertically: three of them side by side do not fit the card's width
        let radioColumn = NSStackView(views: [itermRadio, weztermRadio, warpRadio])
        radioColumn.orientation = .vertical
        radioColumn.alignment = .leading
        radioColumn.spacing = 7
        radioColumn.widthAnchor.constraint(equalToConstant: terminalRadioWidth).isActive = true

        terminalNoteLabel = helpLabel("", width: setupContentWidth - 28 - terminalRadioWidth - 18)
        let radioRow = NSStackView(views: [radioColumn, terminalNoteLabel])
        radioRow.orientation = .horizontal
        radioRow.alignment = .top
        radioRow.spacing = 18

        buildPermissionSection()
        buildAccessibilitySection()
        return card(localized("app.card.terminal.title"), [radioRow, permissionSection, accessibilitySection])
    }

    private func radio(_ title: String, installed: Bool) -> NSButton {
        let button = NSButton(
            radioButtonWithTitle: installed ? title : localized("app.terminal.notInstalled", title),
            target: self, action: #selector(terminalChanged)
        )
        button.isEnabled = installed
        // The untranslated argument, not the drawn title: the drawn one is wrapped in a sentence
        // when the terminal is missing, and that sentence is in whatever language the window is in
        button.identifier = role(#selector(terminalChanged), title)
        return button
    }

    private func buildPermissionSection() {
        // Idempotent: it fills a **stored** stack, so building a second time would append a second
        // copy of everything rather than replace it. `toolsList` already clears for the same reason
        permissionSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        permissionSection.orientation = .vertical
        permissionSection.alignment = .leading
        permissionSection.spacing = 9
        permissionSection.addArrangedSubview(hairline())
        permissionSection.addArrangedSubview(sectionTitle(localized("app.section.itermPermission.title")))
        permissionSection.addArrangedSubview(helpLabel(
            localized("app.section.itermPermission.help")
        ))
        permissionSection.addArrangedSubview(permissionStatusLabel)
        requestPermissionButton.title = localized("app.button.requestItermPermission")
        requestPermissionButton.target = self
        requestPermissionButton.action = #selector(requestPermission)
        requestPermissionButton.identifier = role(#selector(requestPermission))
        requestPermissionButton.bezelStyle = .rounded
        permissionSection.addArrangedSubview(buttonRow([
            requestPermissionButton,
            button(localized("app.button.openSystemSettings"), #selector(openAutomationSettings)),
        ]))
    }

    /// The permission is what lets the app read the screen and check whether claude received the
    /// input. Submitting without that check records an input claude discarded during its
    /// initialisation as "delivered" (measured), so without the permission claude input is not
    /// delivered at all — and the wording keeps that apart from running a command, which needs
    /// nothing.
    private func buildAccessibilitySection() {
        // Idempotent: it fills a **stored** stack, so building a second time would append a second
        // copy of everything rather than replace it. `toolsList` already clears for the same reason
        accessibilitySection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        accessibilitySection.orientation = .vertical
        accessibilitySection.alignment = .leading
        accessibilitySection.spacing = 9
        accessibilitySection.addArrangedSubview(hairline())
        accessibilitySection.addArrangedSubview(sectionTitle(localized("app.section.accessibility.title")))
        accessibilitySection.addArrangedSubview(helpLabel(warpAccessibilityHelpText()))
        accessibilitySection.addArrangedSubview(accessibilityStatusLabel)
        accessibilitySection.addArrangedSubview(buttonRow([
            button(localized("app.button.requestAccessibility"), #selector(requestAccessibility)),
            button(localized("app.button.openSystemSettings"), #selector(openAccessibilitySettings)),
        ]))
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.ui(12, .semibold)
        label.textColor = Theme.text
        return label
    }

    private func testCard() -> NSView {
        let command = NSMutableAttributedString(
            string: "$ ", attributes: [.font: Theme.mono(11), .foregroundColor: Theme.textFaint]
        )
        command.append(NSAttributedString(
            string: testCommand.command,
            attributes: [.font: Theme.mono(11), .foregroundColor: Theme.text]
        ))
        let commandLabel = NSTextField(labelWithString: "")
        commandLabel.attributedStringValue = command

        let row = NSStackView(views: [chip(commandLabel), button(localized("app.button.runInTerminal"), #selector(testTerminal))])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        testResultLabel.isHidden = true

        return card(localized("app.card.test.title"), [row, testResultLabel])
    }

    /// Utilities that appear only once setup is done — before that the extension is not loaded and
    /// there is no options page to open. `refresh()` ties this row to the extension card, so it
    /// also goes away while the setup guide is deliberately back on screen.
    private func buildUtilityRow() -> NSView {
        buttonRow([
            button(localized("app.button.openOptionsPage"), #selector(openOptionsPage)),
            button(localized("app.button.showSetupGuide"), #selector(reshowInstall)),
        ])
    }

    // MARK: View factories

    private func card(_ title: String, _ content: [NSView]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.panel.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 9
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(promptRow(title))
        content.forEach { inner.addArrangedSubview($0) }

        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            box.widthAnchor.constraint(equalToConstant: setupContentWidth),
        ])
        return box
    }

    private func promptRow(_ title: String) -> NSView {
        let glyph = NSTextField(labelWithString: "❯")
        glyph.font = Theme.mono(13, .bold)
        glyph.textColor = Theme.accent
        let label = NSTextField(labelWithString: title)
        label.font = Theme.ui(13, .semibold)
        label.textColor = Theme.text
        let row = NSStackView(views: [glyph, label])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 7
        return row
    }

    private func helpLabel(_ text: String, width: CGFloat? = nil) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Theme.ui(11.5)
        label.textColor = Theme.textDim
        label.preferredMaxLayoutWidth = width ?? (setupContentWidth - 28)
        if let width {
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return label
    }

    /// The name a control answers to after the window has been rebuilt around it.
    ///
    /// **Derived from the action rather than declared**, so it cannot go stale on its own: a
    /// control that stopped having this action stopped being this control, and one that never had
    /// an action does nothing for anyone to focus. The qualifier is for the one case where a single
    /// action serves several controls — the terminal radios, told apart by a product name, which no
    /// language rewrites either. A control with no action is not one this window owns, and
    /// `testEveryControlTheWindowOwnsCarriesTheRoleItsActionNames` is the enumeration of the ones
    /// it does.
    private func role(_ action: Selector, _ qualifier: String? = nil) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier((["control", "\(action)"] + [qualifier].compactMap { $0 }).joined(separator: "."))
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.identifier = role(action)
        return button
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func chip(_ label: NSTextField) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.chipBg.cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5),
        ])
        return box
    }

    /// The quote block the setup steps are drawn in — a thin vertical bar down the left, so it
    /// reads like a heredoc
    private func quoteBlock(_ lines: [String]) -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.4).cgColor
        bar.layer?.cornerRadius = 1
        bar.translatesAutoresizingMaskIntoConstraints = false

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.translatesAutoresizingMaskIntoConstraints = false
        for line in lines {
            let label = NSTextField(wrappingLabelWithString: line)
            label.font = Theme.ui(11.5)
            label.textColor = Theme.textDim
            label.preferredMaxLayoutWidth = setupContentWidth - 28 - 14
            text.addArrangedSubview(label)
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        container.addSubview(text)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
            bar.widthAnchor.constraint(equalToConstant: 2),
            text.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            text.topAnchor.constraint(equalTo: container.topAnchor),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.border.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 1),
            line.widthAnchor.constraint(equalToConstant: setupContentWidth - 28),
        ])
        return line
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "v\($0)" } ?? "dev"
    }

    /// A formatter is expensive enough to keep, and keeping one is exactly how this line stayed
    /// Korean: it was a `static let` built once with `Locale(identifier: "ko_KR")`, so the language
    /// was frozen into the value and no lookup function could ever have thawed it. **The language
    /// is now part of the key.** A cache whose key omits the thing that varies is not a cache.
    ///
    /// Measured: `Locale(identifier:)` takes the tags we resolve as they are — `zh-Hans` gives
    /// 1小时前 and `zh-Hant` 1小時前, so no ICU-style rewriting is needed on the way in.
    private static var relativeFormatterCache: (tag: String, formatter: RelativeDateTimeFormatter)?

    static func relativeFormatter(for tag: String) -> RelativeDateTimeFormatter {
        if let cached = relativeFormatterCache, cached.tag == tag { return cached.formatter }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: tag)
        formatter.dateTimeStyle = .named
        relativeFormatterCache = (tag, formatter)
        return formatter
    }

    private func relative(_ date: Date) -> String {
        Self.relativeFormatter(for: AppLocalization.resolvedTag())
            .localizedString(for: date, relativeTo: Date())
    }

    // MARK: - The terminal choice

    @objc private func terminalChanged() {
        if weztermRadio.state == .on {
            select(terminal: .wezterm)
        } else if warpRadio.state == .on {
            select(terminal: .warp)
        } else {
            select(terminal: .iterm)
        }
    }

    /// Stores the choice and brings every dependent control back in sync. `terminalChanged` maps
    /// radio → terminal and `updateTerminalControls` maps terminal → radio, so this is the single
    /// place the two directions meet — and the seam tests drive the window through.
    func select(terminal: Terminal) {
        Settings.terminal = terminal
        updateTerminalControls()
        refresh()
    }

    private func updateTerminalControls() {
        switch Settings.terminal {
        case .iterm: itermRadio.state = .on
        case .wezterm: weztermRadio.state = .on
        case .warp: warpRadio.state = .on
        }
        // Scheduled claude input is delivered only once claude is up, so it takes a while — and
        // anything the user types in the meantime mixes into it
        // Two complete sentences, joined as sentences. Each part is a message
        // each part is a message a translator can write on its own, and neither is a clause of the other
        var note = localized("app.terminal.note.common")
        // Warp shows only the focused tab, so the app submits only while it can see its own
        if Settings.terminal == .warp {
            note += localized("app.terminal.note.warp")
        }
        terminalNoteLabel.stringValue = note
    }

    // MARK: - Refreshing the state

    private func refresh() {
        // The picker follows the stored value rather than its own last click: a second window, or a
        // value written before this launch, has to show through
        languagePopUp.selectItem(at: languagePickerIndex(
            stored: Settings.language, drawn: AppLocalization.resolvedTag(),
            entries: languagePopUp.itemArray.map { $0.representedObject as? String }
        ))
        // Any window may change the shared preference. Restart itself remains guarded by
        // `LocaleRestartGate`, which protects in-flight delivery rather than socket ownership.
        languagePopUp.isEnabled = true
        languageRestartButton.isEnabled = true
        languageNoteLabel.stringValue = languageNote()

        let manifest = Installer.manifestState()
        let folder = Installer.extensionState()
        let evidence = Settings.lastRequestAt

        // The Chrome connection: the card is hidden when it is fine — the app registers the
        // manifest on launch and heals it when the app has moved, so there is nothing to press
        if case .ok = manifest {
            chromeCard.isHidden = true
        } else {
            chromeCard.isHidden = false
            apply(manifest, to: manifestStatusLabel)
        }

        // The extension counts as done only when a request has actually arrived on the socket
        let extensionState: SetupState
        if case .error = folder {
            extensionState = folder
        } else if let evidence {
            extensionState = .ok(localized("app.status.extension.connected", relative(evidence)))
        } else {
            extensionState = .warning(localized("app.status.extension.waiting"))
        }
        apply(extensionState, to: extensionStatusLabel)
        extensionCard.isHidden = evidence != nil && !forceShowInstall
        utilityRow.isHidden = !extensionCard.isHidden

        updateBaseDirCard()
        updateToolsCard()

        let socketAlive = FileManager.default.fileExists(atPath: defaultSocketPath())

        var permission: SetupState?
        // A command still runs without Accessibility — only the claude input delivery is refused —
        // so this is a warning and not an error
        let accessibilityGranted = PermissionChecker.isAccessibilityGranted
        // The permission UI, per terminal. There is no `default`, so adding a terminal makes
        // "does this one need a permission section" a compile error here rather than a question
        // somebody has to remember to ask
        switch Settings.terminal {
        case .iterm:
            if PermissionChecker.isITermInstalled {
                let status = PermissionChecker.iTermAutomationStatus()
                permission = status.isGranted ? .ok(status.label) : .warning(status.label)
            } else {
                permission = .warning(localized("app.status.iterm.notInstalled"))
            }
            apply(permission!, to: permissionStatusLabel, format: "app.status.itermAutomation.format")
        case .wezterm:
            break // driven through the CLI, so no TCC permission is involved
        case .warp:
            apply(
                accessibilityGranted
                    ? .ok(localized("app.status.accessibility.granted"))
                    : .warning(localized("app.status.accessibility.denied")),
                to: accessibilityStatusLabel, format: "app.status.accessibility.format"
            )
        }
        var granted = false
        if let permission, case .ok = permission { granted = true }
        permissionSection.isHidden = Settings.terminal != .iterm || granted
        accessibilitySection.isHidden = Settings.terminal != .warp || accessibilityGranted

        pipeline.update(pipelineNodes(
            manifest: manifest, extensionState: extensionState,
            socketAlive: socketAlive, permission: permission,
            accessibilityGranted: accessibilityGranted
        ))
        // No resize call here on purpose: the content view resizes the window from inside its
        // own layout pass, which is the only moment the measurement is valid.
    }

    /// Redraws the base directory card from what is stored. The field is not touched while the
    /// user is typing in it — refresh() runs on every window activation and on every socket
    /// request, and overwriting a half-typed path would be maddening.
    ///
    /// **"Is being typed into" was a proxy for "holds the user's text", and the two came apart on
    /// the current path**. A language change through the picker ends the
    /// edit *before* the rebuild, so the field editor is gone by the time this runs and the
    /// condition let the stored value overwrite a draft the user had just been refused — type a
    /// path, change the language, lose the typing. The condition asks the question it meant to ask
    /// now: the field is redrawn only while it still holds **what this window put there**, which is
    /// true on every path rather than on the two it was written for.
    ///
    /// The original condition stays, and what it is left covering is narrow and real: the stored
    /// value changing *while* the field is open and untouched — a hand-edited plist, another
    /// instance — where the write would land in a live edit. It is not what protects the cursor;
    /// measured, writing the **same** value into a field being edited leaves the selection where it
    /// was.
    private func updateBaseDirCard() {
        let stored = Settings.baseDirectory
        let ours = drawnBaseDirectory == nil || baseDirField.stringValue == drawnBaseDirectory
        if window?.firstResponder !== baseDirField.currentEditor(), ours {
            baseDirField.stringValue = stored
            drawnBaseDirectory = stored
        }
        // A stored value can only be invalid if it was edited outside this window (a hand-edited
        // plist, an older build). Say so here rather than let every button fail unexplained.
        // `try?` would fold "threw" and "not configured" into the same nil, so catch explicitly.
        let resolved: String?
        do {
            resolved = try normalizedBaseDirectory(stored)
        } catch {
            apply(
                .error(localized("app.baseDir.storedInvalid", baseDirectoryReason(error))),
                to: baseDirStatusLabel
            )
            return
        }
        guard let normalized = resolved else {
            apply(
                .warning(localized("app.baseDir.notConfigured")),
                to: baseDirStatusLabel
            )
            return
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            apply(.ok(localized("app.baseDir.ok", normalized)), to: baseDirStatusLabel)
        } else {
            // clone creates the leading directories (measured), so a missing folder still works —
            // this only says so out loud, which is how a typo gets noticed
            apply(.warning(localized("app.baseDir.missingFolder", normalized)), to: baseDirStatusLabel)
        }
    }

    /// Only the missing tools get a line. Listing the ones that are there too would leave the card
    /// on screen in the state where nothing is wrong.
    private func updateToolsCard() {
        guard let availability = Settings.toolAvailability else {
            // No answer yet. The check runs in the background on every launch, and one that fails
            // leaves this nil rather than writing something — so "not yet" and "it did not answer"
            // arrive here as the same value
            toolsCard.isHidden = true
            return
        }
        // nil covers both "not configured" and "stored value is unusable" — in either case the
        // fallback cannot run, so z is back to being critical
        let configured = (try? normalizedBaseDirectory(Settings.baseDirectory)) != nil
        let missing = toolAdvice(baseDirectoryConfigured: configured)
            .filter { availability[$0.name] == false }
        let wrapperAdvice = claudeWrapperAdvice(
            available: availability, executable: Settings.toolExecutables
        )
        toolsCard.isHidden = missing.isEmpty && wrapperAdvice == nil
        toolsList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tool in missing {
            addToolLine("● \(tool.name) \(tool.advice)", critical: tool.critical)
        }
        if let wrapperAdvice { addToolLine("● \(wrapperAdvice)", critical: false) }
    }

    private func addToolLine(_ text: String, critical: Bool) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Theme.mono(11.5)
        label.textColor = critical ? Theme.err : Theme.warn
        label.preferredMaxLayoutWidth = setupContentWidth - 28
        toolsList.addArrangedSubview(label)
    }

    /// Internal rather than private so `testPipelineNodesAreLocalized` can read the strings this
    /// produces. Reaching them through the drawn view would mean walking a stack of labels, and a
    /// walk that stopped finding them would go quiet instead of failing.
    func pipelineNodes(
        manifest: SetupState, extensionState: SetupState,
        socketAlive: Bool, permission: SetupState?, accessibilityGranted: Bool
    ) -> [PipelineStripView.Node] {
        func color(_ state: SetupState) -> NSColor {
            switch state {
            case .ok: return Theme.ok
            case .warning: return Theme.warn
            case .error: return Theme.err
            }
        }
        let terminalName: String
        let terminalColor: NSColor
        let terminalDetail: String
        switch Settings.terminal {
        case .iterm:
            terminalName = "iTerm2"
            terminalColor = permission.map(color) ?? Theme.warn
            terminalDetail = localized(
                "app.status.itermAutomation.format", permission?.message ?? localized("app.status.unknown")
            )
        case .wezterm:
            terminalName = "WezTerm"
            let installed = PermissionChecker.isWezTermInstalled
            terminalColor = installed ? Theme.ok : Theme.err
            terminalDetail = localized(
                installed ? "app.pipeline.wezterm.available" : "app.pipeline.wezterm.notInstalled"
            )
        case .warp:
            terminalName = "Warp"
            if !PermissionChecker.isWarpInstalled {
                terminalColor = Theme.err
                terminalDetail = localized("app.pipeline.warp.notInstalled")
            } else if accessibilityGranted {
                terminalColor = Theme.ok
                terminalDetail = localized("app.pipeline.warp.ready")
            } else {
                // Buttons that schedule no claude input still work, so this is a warning
                terminalColor = Theme.warn
                terminalDetail = localized("app.pipeline.warp.noAccessibility")
            }
        }
        return [
            .init(
                label: localized("app.pipeline.node.extension"), color: color(extensionState),
                detail: extensionState.message
            ),
            .init(
                label: localized("app.pipeline.node.relay"), color: color(manifest),
                // The frame comes from the catalogue and only the payload is free. This one
                // was assembled here — `"Native Host: \(manifest.message)"` — which put an English
                // word in front of a translated status and, being a literal, was invisible to
                // the source gate: it counts `localized(…)` calls, not strings nobody localised.
                detail: localized("app.pipeline.relay.detail", manifest.message)
            ),
            .init(
                label: localized("app.pipeline.node.app"), color: socketAlive ? Theme.ok : Theme.err,
                detail: localized(
                    socketAlive ? "app.pipeline.socket.listening" : "app.pipeline.socket.missing"
                )
            ),
            .init(label: terminalName, color: terminalColor, detail: terminalDetail),
        ]
    }

    /// `format` is a **key**, not a prefix. Gluing a translated label in front of a translated
    /// status is the assembly rule against — in a language that puts the subject last, the pieces
    /// end up in the wrong order and no translator can fix it from inside either half. A whole
    /// message with `%@` can be written the way the language wants.
    private func apply(_ state: SetupState, to label: NSTextField, format: StaticString? = nil) {
        let body = format.map { localized($0, state.message) } ?? state.message
        label.stringValue = "● \(body)"
        switch state {
        case .ok: label.textColor = Theme.ok
        case .warning: label.textColor = Theme.warn
        case .error: label.textColor = Theme.err
        }
    }

    // MARK: - Actions

    @objc private func registerManifest() {
        do {
            try Installer.installManifest()
        } catch {
            showError(localized("app.alert.manifestFailed"), error)
        }
        refresh()
    }

    /// The install helper: prepare the folder (copy again when the copy is missing or stale) → put
    /// the path on the clipboard → open chrome://extensions
    @objc private func installInChrome() {
        if Installer.extensionCopyNeedsUpdate() {
            do {
                try Installer.installExtensionCopy()
            } catch {
                showError(localized("app.alert.extensionFolderFailed"), error)
                return
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Installer.extensionDirectory, forType: .string)
        openInChrome("chrome://extensions")
        guideBlock.isHidden = false
        installFeedbackLabel.stringValue = localized("app.install.feedback")
        installFeedbackLabel.textColor = Theme.accent
        installFeedbackLabel.isHidden = false
        refresh()
    }

    /// The localized wording for a rejection. Core hands back only the reason so each surface can
    /// word it its own way — the button response remains an English protocol diagnostic.
    private func baseDirectoryReason(_ error: Error) -> String {
        guard case CommandError.invalidBaseDirectory(let problem, _) = error else {
            return errorMessage(error)
        }
        switch problem {
        case .notAbsolute: return localized("app.baseDir.reason.notAbsolute")
        case .invalidCharacters: return localized("app.baseDir.reason.invalidCharacters")
        }
    }

    /// Saves what was typed. An unusable path is **not** stored — the text stays in the field so it
    /// can be fixed, and the status line says it wasn't saved. A valid one is stored normalized
    /// (`~` expanded, trailing slash gone) and echoed back, so the field shows what will actually
    /// run rather than what was typed.
    @objc private func baseDirectoryEdited() {
        let typed = baseDirField.stringValue
        do {
            let normalized = try normalizedBaseDirectory(typed)
            Settings.baseDirectory = normalized ?? ""
            baseDirField.stringValue = normalized ?? ""
            // Stored and echoed back, so what is in the field is this window's text again and a
            // redraw may replace it. The failure path below leaves it a draft on purpose
            drawnBaseDirectory = normalized ?? ""
        } catch {
            apply(
                .error(localized("app.baseDir.notSaved", baseDirectoryReason(error))),
                to: baseDirStatusLabel
            )
            // FittedContentStackView.layout() re-measures on the label change — no manual resize
            return
        }
        refresh()
    }

    @objc private func chooseBaseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("app.panel.choosePrompt")
        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.baseDirField.stringValue = url.path
            self.baseDirectoryEdited()
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    @objc private func openOptionsPage() {
        openInChrome(Installer.optionsPageURL)
    }

    @objc private func reshowInstall() {
        forceShowInstall = true
        guideBlock.isHidden = false
        refresh()
    }

    @objc private func requestPermission() {
        requestPermissionButton.isEnabled = false
        permissionStatusLabel.stringValue = "● " + localized("app.status.itermAutomation.waiting")
        permissionStatusLabel.textColor = Theme.textDim
        PermissionChecker.requestITermAutomation { [weak self] result in
            guard let self else { return }
            self.requestPermissionButton.isEnabled = true
            if case .failure(let error) = result {
                self.showError(localized("app.alert.permissionRequestFailed"), error)
            }
            self.refresh()
        }
    }

    @objc private func openAutomationSettings() {
        PermissionChecker.openAutomationSettings()
    }

    /// The Accessibility prompt grants nothing on the spot — it only points at System Settings —
    /// and it has no completion callback, so the state is read again when the window becomes key
    /// (`windowDidBecomeKey` → `refresh()`).
    @objc private func requestAccessibility() {
        PermissionChecker.requestAccessibility()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc private func testTerminal() {
        let terminal = Settings.terminal
        let command = testCommand.command
        testResultLabel.stringValue = localized("app.test.running")
        testResultLabel.textColor = Theme.textDim
        testResultLabel.isHidden = false
        DispatchQueue.global().async { [weak self] in
            var failure: Error?
            do {
                try runInTerminal(command: command, terminal: terminal)
            } catch {
                failure = error
            }
            DispatchQueue.main.async {
                if let failure {
                    self?.testResultLabel.stringValue = localized("app.test.failed", errorMessage(failure))
                    self?.testResultLabel.textColor = Theme.err
                } else {
                    self?.testResultLabel.stringValue = localized("app.test.succeeded")
                    self?.testResultLabel.textColor = Theme.textDim
                }
                self?.refresh()
            }
        }
    }

    // MARK: - Helpers

    private func openInChrome(_ urlString: String) {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
              let url = URL(string: urlString) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = errorMessage(error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// Where the viewport goes so the anchor card's **top edge** returns to the same line of the
/// window: `anchorTop` is that edge and `offset` is how far below it the viewport began. What that
/// preserves is the edge and the distance, which is all that survives a reflow — the text inside
/// the card was rewritten too, so no sentence has a place to be put back to.
///
/// **A free function because the arithmetic is the part worth testing**, and it needs no window.
/// Only the near end is clamped, and only that end can be reached: an anchor is a visible card
/// *inside* this document, so `anchorTop` never passes the document's own height and the answer
/// never passes its last scrollable line. Wanting to see above the first line is ordinary — any
/// card within one viewport of the top asks for it. Measured, and the reason this is arithmetic we
/// do rather than a request we make: `NSView.scroll(_:)` keeps a point past the end instead of
/// correcting it, so a target that could pass the end would leave the window on blank space.
func scrollOrigin(anchorTop: CGFloat, offset: CGFloat, clip: CGFloat) -> CGFloat {
    max(0, anchorTop - offset - clip)
}

/// What to say when claude can be called but does **not** resolve to an executable — an install
/// that is only a shell function or an alias.
///
/// The merge path launches `command claude`, which skips functions and aliases, so those setups
/// take the typed route instead. All the user sees otherwise is that delivery got slower, or — on
/// Warp without the Accessibility permission — that the button now refuses outright, with the
/// reason nowhere on screen.
///
/// Silent before the first check (nil) and silent when claude is missing altogether: the "missing"
/// line already says that one, and saying it twice reads as two different problems.
///
/// It does **not** name the cause as "a function or an alias": the same answer comes from a
/// relative `PATH` entry and from a file without the executable bit (both measured), and a card
/// that asserts the wrong cause sends people to fix the wrong thing.
/// Which entry the language picker points at.
///
/// Three cases, and the third is the one that had a defect. A stored preference that matches an
  /// entry selects it. A stored preference that matches nothing is a **third state** —
/// not `auto`, not a language we ship — and pointing at the first entry there would have the picker
/// claim "follow the system" while the window draws English. It points at the language actually
/// being drawn instead, which `resolveLocale` has already decided; picking anything writes a clean
/// value and the state is gone.
///
/// It takes the entries rather than reading the control so the three rows can be enumerated in a
/// test without a window, a `UserDefaults` write, or a language change on this machine.
func languagePickerIndex(stored: String, drawn: String, entries: [String?]) -> Int {
    entries.firstIndex { $0 == stored } ?? entries.firstIndex { $0 == drawn } ?? 0
}

func claudeWrapperAdvice(available: [String: Bool]?, executable: [String: Bool]?) -> String? {
    guard available?["claude"] == true, executable?["claude"] == false else { return nil }
    return localized("app.tools.claudeWrapper.advice")
}

/// What the Accessibility card says. It used to promise that the command would still run without
/// the permission and only the claude input would be missing — the app does the opposite: a button
/// whose inputs have to be typed is **refused before the tab is created** (`claudeInputBlocker`).
/// A card that contradicts the behaviour sends people looking for the wrong problem.
func warpAccessibilityHelpText() -> String {
    // The `**…**` and the backticks are gone: `NSTextField` renders neither, so they were
    // showing up as literal asterisks on screen — and translating them would have copied that into
    // five catalogues
    localized("app.section.accessibility.help")
}

private extension NSView {
    /// The view here that answers to a role — the question a rebuild asks about a control it has
    /// just replaced. Depth first, so a control inside a card is found without the caller knowing
    /// which card that is.
    func firstDescendant(withRole role: NSUserInterfaceItemIdentifier) -> NSView? {
        for view in subviews {
            if view.identifier == role { return view }
            if let found = view.firstDescendant(withRole: role) { return found }
        }
        return nil
    }
}
