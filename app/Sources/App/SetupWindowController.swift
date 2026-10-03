import AppKit
import Carbon.HIToolbox
import Core

/// Settings document width.
let setupContentWidth: CGFloat = 720

/// The settings stack, which sizes its window to itself.
///
/// Why the stack and not the window controller: the size has three preconditions a caller has to
/// get right *every* time — apply the visibility changes, let the constraint pass settle, then
/// measure — and one that forgets leaves the window shorter than its content, at which point the
/// panes overlap instead of merely clipping. Measuring at the end of this view's own `layout()`
/// satisfies all three by construction: that runs after the pass, and any change to a pane, label
/// or section's `isHidden` already dirties this view. A section added later is covered without
/// anyone remembering the rule.
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
    private var lastVisibleFrame: NSRect?
    private var windowUpdateScheduled = false
    private var deferredWindowUpdateAllowed = true
    /// The window controller owns this decision because rebuilding the document creates a new
    /// stack without creating a new window. The callbacks are configured by `buildContent()` and
    /// keep the stack from mistaking its first update for the window's first measured placement.
    var shouldCenterAfterFirstWindowUpdate: (() -> Bool)?
    var didCenterAfterFirstWindowUpdate: (() -> Void)?
    private var afterWindowUpdate: (() -> Void)?
    /// Stands in for the visible frame used for both clamp measurement and window placement, so a
    /// test can exercise one complete layout cycle without depending on whichever display it runs
    /// on. The value captured by `layout()` is the rect passed to both center and clamp.
    /// Setting the stand-in after the first layout must schedule the pass that consumes it; a plain
    /// stored property would leave a clean tree measuring the real display until another change.
    var visibleFrameOverride: NSRect? {
        didSet { needsLayout = true }
    }

    /// Geometry can be unchanged while the main-queue update or a rebuild's restore callback is
    /// still waiting. The shared test settle reads these two and the view's own `needsLayout`
    /// before declaring a fixed point — a new deferred mechanism has to join that set, because
    /// unchanged geometry has already been mistaken for a settled tree once per signal.
    var deferredWindowUpdatePendingForTesting: Bool { windowUpdateScheduled }
    var deferredWindowCompletionPendingForTesting: Bool { afterWindowUpdate != nil }

    override func layout() {
        super.layout()
        guard let window, window.contentView != nil else { return }
        var target = fittingSize
        // Do not read NSScreen.main here. init uses it once to put the window on its launch
        // screen; after that, a nil window.screen means the window is not currently on any
        // display. There is no cycle-owned visible rect to capture in this pass, and choosing
        // another main screen here would reintroduce the split-screen decision this path removes.
        // The deferred application has a separate recovery fallback for that transient state.
        let visible = visibleFrameOverride ?? window.screen?.visibleFrame
        if let visible {
            target.height = min(target.height, maximumContentHeight(target, visibleHeight: visible.height, window: window))
        }
        // A screen can change without changing the clamped size; placement still has to consume
        // the new visible rect rather than letting the size early return discard it.
        let visibleFrameChanged = lastVisibleFrame != visible
        guard lastRequestedSize != target || visibleFrameChanged else {
            if !windowUpdateScheduled, let completion = afterWindowUpdate {
                afterWindowUpdate = nil
                completion()
            }
            return
        }
        lastRequestedSize = target
        lastVisibleFrame = visible
        scheduleWindowUpdate()
    }

    /// Apply the measured size after this layout pass has returned. At the point where `layout()`
    /// runs, the scroll view has already laid itself out against the old window size; applying a
    /// 155pt shrink there produced `win=702` with `clip=547`. `enclosingScrollView?.tile()` and
    /// `needsLayout = true` were both measured and left that stale clip unchanged, so the window
    /// update has to happen on the next main-queue turn instead.
    private func scheduleWindowUpdate() {
        guard !windowUpdateScheduled else { return }
        windowUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowUpdateScheduled = false
            guard self.deferredWindowUpdateAllowed else {
                self.lastRequestedSize = nil
                self.lastVisibleFrame = nil
                return
            }
            guard let window = self.window,
                  window.contentView != nil,
                  let requestedTarget = self.lastRequestedSize
            else {
                self.afterWindowUpdate = nil
                return
            }

            let visible: NSRect?
            if let override = self.visibleFrameOverride {
                visible = override
            } else if let screen = window.screen {
                let currentVisibleFrame = screen.visibleFrame
                if let captured = self.lastVisibleFrame, captured != currentVisibleFrame {
                    // A display can disappear after measurement and before this block runs. Do
                    // not apply a rect that no longer describes the window's screen; the screen
                    // parameter observer has already made the next layout responsible for a new
                    // cycle, and this guard covers the interval before that layout is delivered.
                    self.lastVisibleFrame = nil
                    self.needsLayout = true
                    return
                }
                if self.lastVisibleFrame == nil { self.lastVisibleFrame = currentVisibleFrame }
                visible = currentVisibleFrame
            } else {
                // A window can be between displays while the screen-parameter notification is
                // being delivered. Recover it using the current main screen only at application
                // time; init's launch-screen choice remains a one-time decision.
                self.lastVisibleFrame = nil
                visible = NSScreen.main?.visibleFrame
            }

            let centerAfterUpdate = self.shouldCenterAfterFirstWindowUpdate?() == true
            let originBeforeResize = window.frame.origin
            var target = requestedTarget
            if let visible {
                target.height = min(
                    target.height,
                    self.maximumContentHeight(target, visibleHeight: visible.height, window: window)
                )
            }
            window.setContentSize(target)
            if centerAfterUpdate, let visible {
                Self.centerInside(visible, window)
                self.didCenterAfterFirstWindowUpdate?()
            } else {
                // AppKit preserves the top edge when setContentSize changes height. After the
                // window's first measured placement, keep its origin and let only the visible-frame
                // clamp move it if the resized window would otherwise leave the screen.
                window.setFrameOrigin(originBeforeResize)
            }
            if let visible { Self.moveInside(visible, window) }

            let completion = self.afterWindowUpdate
            self.afterWindowUpdate = nil
            if let completion {
                // The replacement scroll view must answer to its new clip size before the
                // language-change anchor and first responder are restored.
                window.contentView?.layoutSubtreeIfNeeded()
                completion()
            }
        }
    }

    /// A closed window may still be retained by its controller while a queued update is waiting.
    /// Drop that update's state so reopening the same controller measures a fresh window.
    func suspendDeferredWindowUpdates() {
        deferredWindowUpdateAllowed = false
        lastRequestedSize = nil
        lastVisibleFrame = nil
        afterWindowUpdate = nil
    }

    func resumeDeferredWindowUpdates() {
        deferredWindowUpdateAllowed = true
        lastRequestedSize = nil
        lastVisibleFrame = nil
        needsLayout = true
    }

    /// A screen-parameter change invalidates the visible rect captured by the previous layout
    /// cycle. The next cycle must ask `window.screen` again instead of applying coordinates from a
    /// display that may no longer exist.
    func invalidateVisibleFrame() {
        lastVisibleFrame = nil
        needsLayout = true
    }

    /// Run after the next stack measurement. If the window size changes, wait for the deferred
    /// resize and clip layout; if not, the measurement confirms the current size first.
    func afterNextWindowUpdate(_ completion: @escaping () -> Void) {
        afterWindowUpdate = completion
        needsLayout = true
    }

    /// `setContentSize` keeps the top-left corner fixed, so growing pushes the bottom edge down
    /// and off the screen. Slide the window back rather than letting AppKit clamp the height.
    /// Centering and clamping both consume the visible rect captured by the same layout pass.
    /// Calling `NSWindow.center()` here would choose `NSScreen.main` again and could place the
    /// window on a different display before `moveInside` reads the captured rect.
    static func centerInside(_ visible: NSRect, _ window: NSWindow) {
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }
    }

    static func moveInside(_ visible: NSRect, _ window: NSWindow) {
        var frame = window.frame
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }
    }

    private func maximumContentHeight(_ contentSize: NSSize, visibleHeight: CGFloat, window: NSWindow) -> CGFloat {
        let contentRect = NSRect(origin: .zero, size: contentSize)
        let frameHeight = window.frameRect(forContentRect: contentRect).height
        let chromeHeight = frameHeight - contentSize.height
        return max(0, visibleHeight - chromeHeight)
    }
}

/// The frame is wider than its alignment rect, so wrapping uses the alignment width.
final class SetupWindowWrappingLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureWrapping()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureWrapping()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = alignmentRect(forFrame: NSRect(origin: .zero, size: newSize)).width
        guard width > 0, abs(preferredMaxLayoutWidth - width) > 0.5 else { return }
        preferredMaxLayoutWidth = width
        invalidateIntrinsicContentSize()
    }

    private func configureWrapping() {
        usesSingleLineMode = false
        cell?.wraps = true
        cell?.isScrollable = false
        lineBreakStrategy = .standard
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        maximumNumberOfLines = 0
        isBezeled = false
        isBordered = false
        isEditable = false
        isSelectable = false
        drawsBackground = false
    }
}

func makeSetupWindowWrappingLabel(_ text: String = "") -> SetupWindowWrappingLabel {
    let label = SetupWindowWrappingLabel(frame: .zero)
    label.stringValue = text
    return label
}

func languagePickerIndex(stored: String, drawn: String, entries: [String?]) -> Int {
    entries.firstIndex { $0 == stored } ?? entries.firstIndex { $0 == drawn } ?? 0
}

func scrollOrigin(anchorTop: CGFloat, offset: CGFloat, clip: CGFloat) -> CGFloat {
    max(0, anchorTop - offset - clip)
}

private enum SetupWindowPane: String, CaseIterable {
    case general
    case github
    case slack

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("setup.pane.\(rawValue)")
    }

    var title: String {
        switch self {
        case .general: return localized("app.setup.toolbar.general")
        case .github: return localized("app.setup.toolbar.github")
        case .slack: return localized("app.setup.toolbar.slack")
        }
    }
}

private struct SetupWindowEnvironment {
    let manifest: SetupWindowManifestStatus
    let extensionFolder: SetupWindowExtensionFolderStatus
    let snapshot: SetupWindowSnapshot
    let presentation: SetupWindowPresentation
}

struct SetupWindowControllerEffects {
    let writeClipboard: (String) -> Bool
    let fileExists: (URL) -> Bool
    let openURL: (URL) -> Bool
    let runTerminal: (String, Terminal) throws -> Void

    static let live = SetupWindowControllerEffects(
        writeClipboard: { value in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(value, forType: .string)
        },
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        openURL: { NSWorkspace.shared.open($0) },
        runTerminal: { command, terminal in
            _ = try runInTerminal(command: command, terminal: terminal)
        }
    )
}

final class SetupWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSTextFieldDelegate {
    private var slackHotKey: SlackThreadHotKeyManaging!
    private var slackLoginItem: LoginItemManaging!
    private var hotKeyRecordingMonitor: Any?
    private var isRecordingHotKey = false
    private var hotKeyNeedsModifier = false
    private var lastSlackLoginItemFailure: Error?
    private var lastSlackRequestFailure: Error?
    private var slackRequestFailuresByOrder: [Int: Error] = [:]
    private var openingReasons: [SetupWindowOpeningReason] = []
    private var nextReasonOrder = 0
    private var selectedPane: SetupWindowPane = .general
    private var languageChange = SetupWindowGeneralLanguageChange.unchanged
    private var terminalTestResult = SetupWindowGeneralTerminalTestResult.notRun
    private var terminalTestAttempt = 0
    private var guideWasReopened = false
    private var guideStepsExpanded = false
    private var installFeedback: String?
    private var cmuxFeedback: SetupWindowCmuxActionResult?
    private var effects = SetupWindowControllerEffects.live
    private var isRebuildingForLanguageChange = false
    private var hasCenteredMeasuredWindow = false
    private var windowHasClosed = false
    private var manifestStatusProvider: (() -> SetupWindowManifestStatus)?
    private var extensionFolderStatusProvider: (() -> SetupWindowExtensionFolderStatus)?

    private var languageObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var requestObserver: NSObjectProtocol?
    private var toolsObserver: NSObjectProtocol?
    private var toolbar: NSToolbar!
    private var slackToolbarItem: NSToolbarItem?
    private var helpPopover: NSPopover?

    private(set) var rootStack: FittedContentStackView!
    private(set) var sharedPanel: SetupWindowSharedPanel!
    private(set) var generalPane: SetupWindowGeneralPane!
    private(set) var githubPane: SetupWindowGitHubPane!
    private(set) var slackPane: SetupWindowSlackPane!

    var onClose: (() -> Void)?
    var selectedPaneForTesting: String { selectedPane.rawValue }
    var isRecordingHotKeyForTesting: Bool { isRecordingHotKey }
    var sharedPanelForTesting: SetupWindowSharedPanel { sharedPanel }
    var generalPaneForTesting: SetupWindowGeneralPane { generalPane }
    var githubPaneForTesting: SetupWindowGitHubPane { githubPane }
    var slackPaneForTesting: SetupWindowSlackPane { slackPane }
    var wrappingStatusLabelsForTesting: [NSTextField] {
        sharedPanel.wrappingStatusLabelsForTesting
            + generalPane.wrappingStatusLabelsForTesting
            + githubPane.wrappingStatusLabelsForTesting
            + slackPane.wrappingStatusLabelsForTesting
    }
    var cmuxPlacementNameFieldForTesting: NSTextField { githubPane.workspaceNameField }

    private let testCommand: ShellPayload = "echo 'Terminal Checkout: connection OK'"

    convenience init(
        slackHotKey: SlackThreadHotKeyManaging,
        loginItem: LoginItemManaging,
        openingBlocker: ClaudeInputBlocker? = nil,
        slackRequestFailure: Error? = nil,
        manifestStatusProvider: (() -> SetupWindowManifestStatus)? = nil,
        extensionFolderStatusProvider: (() -> SetupWindowExtensionFolderStatus)? = nil,
        effects: SetupWindowControllerEffects = .live
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let launchVisibleFrame = NSScreen.main?.visibleFrame
        window.title = localized("app.setup.toolbar.general")
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.isMovableByWindowBackground = true
        self.init(window: window)
        self.slackHotKey = slackHotKey
        self.slackLoginItem = loginItem
        self.manifestStatusProvider = manifestStatusProvider
        self.extensionFolderStatusProvider = extensionFolderStatusProvider
        self.effects = effects
        if let openingBlocker { appendOpeningReason(.claudeInputRejected(blocker: openingBlocker, arrivalOrder: nextArrival())) }
        if let slackRequestFailure {
            lastSlackRequestFailure = slackRequestFailure
            let arrivalOrder = nextArrival()
            slackRequestFailuresByOrder[arrivalOrder] = slackRequestFailure
            appendOpeningReason(.slackThreadRequestFailed(
                detail: slackThreadRequestErrorMessage(slackRequestFailure), arrivalOrder: arrivalOrder
            ))
            selectedPane = .slack
        } else if openingBlocker != nil {
            selectedPane = .general
        }
        slackHotKey.onStateChange = { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        window.delegate = self
        if let launchVisibleFrame {
            FittedContentStackView.centerInside(launchVisibleFrame, window)
            FittedContentStackView.moveInside(launchVisibleFrame, window)
        }
        configureToolbar()
        let environment = currentEnvironment()
        window.contentView = buildContent(using: environment)
        refresh()
        observeScreenParameters()
        window.contentView?.layoutSubtreeIfNeeded()
        requestObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutRequestHandled, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        toolsObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutToolsChecked, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildForLanguageChange() }
    }

    deinit {
        stopObservingScreenParameters()
        for observer in [requestObserver, toolsObserver, languageObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        if let hotKeyRecordingMonitor { NSEvent.removeMonitor(hotKeyRecordingMonitor) }
    }

    private func configureToolbar() {
        toolbar = NSToolbar(identifier: "terminal-checkout.setup-window")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
        toolbar.selectedItemIdentifier = selectedPane.toolbarIdentifier
        updateWindowTitle()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SetupWindowPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SetupWindowPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SetupWindowPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SetupWindowPane.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.target = self
        item.action = #selector(selectToolbarPane(_:))
        switch pane {
        case .general:
            item.image = NSApp.applicationIconImage
        case .github:
            item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: pane.title)
        case .slack:
            slackToolbarItem = item
            item.image = slackToolbarImage(hasFailure: lastSlackRequestFailure != nil)
            item.toolTip = lastSlackRequestFailure == nil
                ? pane.title : localized("app.setup.toolbar.slack.failure")
        }
        return item
    }

    @objc private func selectToolbarPane(_ sender: NSToolbarItem) {
        guard let pane = SetupWindowPane.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else { return }
        selectPane(pane)
    }

    private func selectPane(_ pane: SetupWindowPane) {
        let endedRecording = selectedPane == .slack && pane != .slack && isRecordingHotKey
        if endedRecording { endHotKeyRecording() }
        selectedPane = pane
        toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
        updateWindowTitle()
        applyPaneVisibility()
        if endedRecording { refresh() }
    }

    private func updateWindowTitle() {
        window?.title = selectedPane.title
    }

    private func slackToolbarImage(hasFailure: Bool) -> NSImage? {
        let accessibility = hasFailure
            ? localized("app.setup.toolbar.slack.failure")
            : localized("app.setup.toolbar.slack")
        // NSToolbarItem.badge is macOS 26-only; the app targets macOS 13, so draw the dot into this image.
        guard let symbol = NSImage(
            systemSymbolName: "bubble.left.and.bubble.right",
            accessibilityDescription: accessibility
        ) else { return nil }
        guard hasFailure else { return symbol }
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            symbol.draw(in: rect.insetBy(dx: 2, dy: 2))
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 8, y: rect.minY, width: 8, height: 8))
            Theme.err.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibility
        return image
    }

    private func updateSlackToolbarIndicator(_ presentation: SetupWindowPresentation) {
        guard let item = slackToolbarItem else { return }
        item.image = slackToolbarImage(hasFailure: presentation.slackToolbarHasFailureDot)
        item.toolTip = presentation.slackToolbarHasFailureDot
            ? localized("app.setup.toolbar.slack.failure") : localized("app.setup.toolbar.slack")
    }

    private func observeScreenParameters() {
        guard screenParametersObserver == nil else { return }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.windowHasClosed else { return }
            self.rootStack?.invalidateVisibleFrame()
        }
    }

    private func stopObservingScreenParameters() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if windowHasClosed {
            windowHasClosed = false
            observeScreenParameters()
            rootStack?.resumeDeferredWindowUpdates()
        }
        refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        if isRecordingHotKey { endHotKeyRecording() }
    }

    func windowWillClose(_ notification: Notification) {
        if isRecordingHotKey { endHotKeyRecording() }
        windowHasClosed = true
        stopObservingScreenParameters()
        rootStack?.suspendDeferredWindowUpdates()
        guideWasReopened = false
        guideStepsExpanded = false
        installFeedback = nil
        openingReasons.removeAll {
            if case .claudeInputRejected = $0 { return true }
            return false
        }
        onClose?()
    }

    private func currentEnvironment() -> SetupWindowEnvironment {
        let manifest = manifestStatusProvider?() ?? Installer.setupWindowManifestStatus()
        let folder = extensionFolderStatusProvider?() ?? Installer.setupWindowExtensionFolderStatus()
        let terminal = Settings.terminal
        let installations = [
            SetupWindowTerminalInstallation(terminal: .iterm, isInstalled: PermissionChecker.isITermInstalled),
            SetupWindowTerminalInstallation(terminal: .wezterm, isInstalled: PermissionChecker.isWezTermInstalled),
            SetupWindowTerminalInstallation(terminal: .warp, isInstalled: PermissionChecker.isWarpInstalled),
            SetupWindowTerminalInstallation(terminal: .cmux, isInstalled: PermissionChecker.isCmuxInstalled(channel: .stable)),
            SetupWindowTerminalInstallation(terminal: .cmuxNightly, isInstalled: PermissionChecker.isCmuxInstalled(channel: .nightly)),
        ]
        let iTermStatus = terminal == .iterm ? PermissionChecker.iTermAutomationStatus() : nil
        let stableSocket = terminal == .cmux ? PermissionChecker.cmuxSocketStatus(channel: .stable) : nil
        let nightlySocket = terminal == .cmuxNightly ? PermissionChecker.cmuxSocketStatus(channel: .nightly) : nil
        let rawBaseDirectory = Settings.baseDirectory
        let baseDirectory: SetupWindowBaseDirectoryStatus
        do {
            if let normalized = try normalizedBaseDirectory(rawBaseDirectory) {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory)
                baseDirectory = .normalized(normalized, directoryExists: exists && isDirectory.boolValue)
            } else {
                baseDirectory = .unconfigured
            }
        } catch {
            baseDirectory = .invalidStoredValue
        }
        let tools = Settings.toolAvailability.map {
            SetupWindowToolResults(available: $0, executable: Settings.toolExecutables ?? [:])
        }
        let currentLanguageOpeningReasons = openingReasons.map { reason -> SetupWindowOpeningReason in
            guard case .slackThreadRequestFailed(_, let arrivalOrder) = reason,
                  let failure = slackRequestFailuresByOrder[arrivalOrder] else { return reason }
            return .slackThreadRequestFailed(
                detail: slackThreadRequestErrorMessage(failure), arrivalOrder: arrivalOrder
            )
        }
        let socket: SetupWindowAppSocketStatus = FileManager.default.fileExists(atPath: defaultSocketPath())
            ? .listening : .unavailable
        let snapshot = SetupWindowSnapshot(
            manifest: manifest,
            extensionFolder: folder,
            lastRequestAt: Settings.lastRequestAt,
            appSocket: socket,
            selectedTerminal: terminal,
            terminalInstallations: installations,
            iTermAutomation: iTermStatus,
            cmuxStableSocket: stableSocket,
            cmuxNightlySocket: nightlySocket,
            warpAccessibilityGranted: PermissionChecker.isAccessibilityGranted,
            tools: tools,
            baseDirectory: baseDirectory,
            openingReasons: currentLanguageOpeningReasons,
            slackRequestFailureIsActive: lastSlackRequestFailure != nil,
            tabActivation: Settings.tabActivation,
            cmuxIdentityMode: Settings.cmuxPlacementIdentityMode,
            cmuxFixedName: Settings.cmuxPlacementFixedName,
            cmuxArrangement: Settings.cmuxPlacementArrangement,
            guideWasReopened: guideWasReopened
        )
        return SetupWindowEnvironment(
            manifest: manifest,
            extensionFolder: folder,
            snapshot: snapshot,
            presentation: SetupWindowPresentationModel.make(from: snapshot)
        )
    }

    private func refresh() {
        guard sharedPanel != nil else { return }
        var environment = currentEnvironment()
        openingReasons.removeAll { reason in
            guard case .claudeInputRejected(let blocker, _) = reason else { return false }
            return !environment.snapshot.isClaudeBlockerActive(blocker) || !blocker.setupWindowCanHelp
        }
        if environment.snapshot.openingReasons.count != openingReasons.count {
            environment = currentEnvironment()
        }
        let presentation = environment.presentation
        sharedPanel.update(
            presentation,
            manifest: environment.manifest,
            extensionFolder: environment.extensionFolder,
            installStepsExpanded: guideStepsExpanded,
            installFeedback: installFeedback,
            cmuxActionResult: cmuxFeedback
        )
        let generalState = makeGeneralState(environment)
        generalPane.update(generalState)
        githubPane.update(makeGitHubState(environment))
        slackPane.update(makeSlackState(environment))
        updateSlackToolbarIndicator(presentation)
        applyPaneVisibility()
        updateWindowTitle()
    }

    private func makeGeneralState(_ environment: SetupWindowEnvironment) -> SetupWindowGeneralPaneState {
        let snapshot = environment.snapshot
        let manifestStatus: SetupWindowGeneralIndicator
        switch snapshot.manifest {
        case .registered:
            manifestStatus = .init(text: localized("app.status.manifest.registered"), tone: .success)
        case .notRegistered:
            manifestStatus = .init(text: localized("app.setup.install.nativeHost.problem.notRegistered"), tone: .error)
        case .wrongRelayPath:
            manifestStatus = .init(text: localized("app.setup.install.nativeHost.problem.wrongPath"), tone: .warning)
        case .wrongExtensionID:
            manifestStatus = .init(text: localized("app.setup.install.nativeHost.problem.wrongExtensionID"), tone: .warning)
        }
        let socketStatus = snapshot.appSocket == .listening
            ? SetupWindowGeneralIndicator(text: localized("app.setup.severity.success"), tone: .success)
            : SetupWindowGeneralIndicator(text: localized("app.setup.problem.socket.cause"), tone: .error)
        return SetupWindowGeneralPaneState(
            presentation: environment.presentation,
            appVersion: appVersion,
            requestRelativeTime: snapshot.lastRequestAt.map(relative),
            terminalInstallations: snapshot.terminalInstallations,
            nativeHostStatus: manifestStatus,
            appSocketStatus: socketStatus,
            terminalStatus: terminalIndicator(snapshot),
            tools: snapshot.tools,
            savedTabActivation: Settings.tabActivation,
            terminalTestResult: terminalTestResult,
            storedLanguage: Settings.language,
            resolvedLanguage: AppLocalization.resolvedTag(),
            languageChange: languageChange,
            cmuxFeedback: cmuxFeedback
        )
    }

    private func terminalIndicator(_ snapshot: SetupWindowSnapshot) -> SetupWindowGeneralIndicator {
        let terminal = snapshot.selectedTerminal
        guard snapshot.isInstalled(terminal) != false else {
            if terminal.cmuxChannel != nil {
                return .init(text: localized("app.setup.general.status.cmux.notInstalled"), tone: .error)
            }
            return .init(text: localized("app.setup.general.status.terminalNotInstalled"), tone: .error)
        }
        switch terminal {
        case .iterm:
            guard let status = snapshot.iTermAutomation else {
                return .init(text: localized("app.setup.general.status.iterm.checkFailed"), tone: .warning)
            }
            switch status {
            case .granted:
                return .init(text: localized("app.setup.general.status.iterm.automationAllowed"), tone: .success)
            case .denied:
                return .init(text: localized("app.setup.general.status.iterm.permissionDenied"), tone: .error)
            case .notDetermined:
                return .init(text: localized("app.setup.general.status.iterm.permissionNeeded"), tone: .warning)
            case .targetNotRunning:
                return .init(text: localized("app.setup.general.status.iterm.cannotCheck"), tone: .warning)
            case .unknown:
                return .init(text: localized("app.setup.general.status.iterm.checkFailed"), tone: .warning)
            }
        case .wezterm:
            return .init(text: localized("app.setup.general.status.wezterm.noPermissionNeeded"), tone: .success)
        case .warp:
            return snapshot.warpAccessibilityGranted
                ? .init(text: localized("app.setup.general.status.warp.accessibilityAllowed"), tone: .success)
                : .init(text: localized("app.setup.general.status.warp.accessibilityMissing"), tone: .warning)
        case .cmux, .cmuxNightly:
            guard let channel = terminal.cmuxChannel,
                  let status = snapshot.cmuxSocketStatus(for: channel) else {
                return .init(text: localized("app.setup.general.status.cmux.checkFailed"), tone: .warning)
            }
            switch status {
            case .reachable:
                return .init(text: localized("app.setup.general.status.cmux.reachable"), tone: .success)
            case .notInstalled:
                return .init(text: localized("app.setup.general.status.cmux.notInstalled"), tone: .error)
            case .denied:
                return .init(text: localized("app.setup.general.status.cmux.accessDenied"), tone: .error)
            case .notRunning:
                return .init(text: localized("app.setup.general.status.cmux.notRunning"), tone: .warning)
            case .failed:
                return .init(text: localized("app.setup.general.status.cmux.checkFailed"), tone: .warning)
            }
        }
    }

    private func makeGitHubState(_ environment: SetupWindowEnvironment) -> SetupWindowGitHubPaneState {
        let draftProblem = baseDirectoryProblem(githubPane?.baseDirectoryField.stringValue ?? Settings.baseDirectory)
        let storedProblem = baseDirectoryProblem(Settings.baseDirectory)
        return SetupWindowGitHubPaneState(
            presentation: environment.presentation,
            baseDirectory: Settings.baseDirectory,
            baseDirectoryDraftProblem: draftProblem,
            storedBaseDirectoryProblem: storedProblem,
            cmuxIdentityMode: Settings.cmuxPlacementIdentityMode,
            cmuxFixedName: Settings.cmuxPlacementFixedName
        )
    }

    private func makeSlackState(_ environment: SetupWindowEnvironment) -> SetupWindowSlackPaneState {
        let workDirectory = slackPane?.workDirectoryField.stringValue ?? Settings.slackThreadWorkDirectory
        let instruction = slackPane?.instructionField.stringValue ?? Settings.slackThreadInstruction
        let notice = slackValidationNotice(workDirectory: workDirectory, instruction: instruction)
        let combination = slackHotKey.combination
        let display = combination?.displayString(keyLabel: hotKeyKeyLabel(combination!.keyCode))
        let status: Int32?
        if case .failed(_, let code) = slackHotKey.state { status = code } else { status = nil }
        return SetupWindowSlackPaneState(
            presentation: environment.presentation,
            storedWorkDirectory: Settings.slackThreadWorkDirectory,
            storedInstruction: Settings.slackThreadInstruction,
            validationNotice: notice,
            hotKeyDisplayString: display,
            isRecordingHotKey: isRecordingHotKey,
            needsModifierWarning: hotKeyNeedsModifier,
            registrationFailureStatus: status,
            loginItemStatus: slackLoginItem.status,
            loginItemFailureMessage: lastSlackLoginItemFailure.map(slackLoginItemFailureMessage)
        )
    }

    private func slackValidationNotice(workDirectory: String, instruction: String) -> SetupWindowSlackValidationNotice? {
        do {
            _ = try validateSlackThreadSettings(workDirectory: workDirectory, instruction: instruction)
            return nil
        } catch let error as SlackThreadRequestError {
            switch error {
            case .invalidInstruction:
                return .instruction(slackThreadRequestErrorMessage(error))
            default:
                return .workDirectory(slackThreadRequestErrorMessage(error))
            }
        } catch {
            return .workDirectory(slackThreadRequestErrorMessage(error))
        }
    }

    private func baseDirectoryProblem(_ value: String) -> BaseDirectoryProblem? {
        do {
            _ = try normalizedBaseDirectory(value)
            return nil
        } catch CommandError.invalidBaseDirectory(let problem, _) {
            return problem
        } catch {
            return nil
        }
    }

    private func buildContent(using environment: SetupWindowEnvironment) -> NSView {
        let stack = FittedContentStackView()
        stack.shouldCenterAfterFirstWindowUpdate = { [weak self] in self.map { !$0.hasCenteredMeasuredWindow } ?? false }
        stack.didCenterAfterFirstWindowUpdate = { [weak self] in self?.hasCenteredMeasuredWindow = true }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        // The document view is sized by its fitting content and these explicit scroll-content
        // constraints. Translating its initial zero frame would add a zero-height autoresizing
        // constraint and leave the window with only its title bar and toolbar.
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A standard title bar and preference toolbar own the chrome above this document; 12pt is the content separation after them.
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 16, right: 0)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = Theme.bg.cgColor
        stack.visibleFrameOverride = rootStack?.visibleFrameOverride
        stack.widthAnchor.constraint(equalToConstant: setupContentWidth).isActive = true

        sharedPanel = SetupWindowSharedPanel(
            presentation: environment.presentation,
            manifest: environment.manifest,
            extensionFolder: environment.extensionFolder,
            cmuxActionResult: cmuxFeedback,
            target: self,
            selectors: sharedPanelSelectors
        )
        generalPane = SetupWindowGeneralPane(
            state: makeGeneralState(environment), target: self, selectors: generalPaneSelectors
        )
        githubPane = SetupWindowGitHubPane(
            state: makeGitHubState(environment), target: self, selectors: githubPaneSelectors
        )
        slackPane = SetupWindowSlackPane(
            state: makeSlackState(environment), target: self, selectors: slackPaneSelectors
        )
        for (identifier, view) in [
            ("panel.shared", sharedPanel as NSView),
            ("pane.general", generalPane as NSView),
            ("pane.github", githubPane as NSView),
            ("pane.slack", slackPane as NSView),
        ] {
            view.identifier = NSUserInterfaceItemIdentifier(identifier)
            stack.addArrangedSubview(view)
        }
        rootStack = stack
        applyPaneVisibility()

        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.bg
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        return scroll
    }

    private var sharedPanelSelectors: [SetupWindowSharedPanelAction: Selector] {
        [
            .registerManifest: #selector(registerManifest),
            .installInChrome: #selector(installInChrome),
            .requestPermission: #selector(requestPermission),
            .openAutomationSettings: #selector(openAutomationSettings),
            .requestAccessibility: #selector(requestAccessibility),
            .openAccessibilitySettings: #selector(openAccessibilitySettings),
            .openCmuxConfig: #selector(openCmuxConfig),
            .refreshCmuxStatus: #selector(refreshCmuxStatus),
            .restartApp: #selector(restartApp),
            .openTerminalSettings: #selector(openTerminalSettings),
            .openSlackSettings: #selector(openSlackSettings),
            .openBaseDirectorySettings: #selector(openBaseDirectorySettings),
            .showZoxideInstallHelp: #selector(showZoxideInstallHelp(_:)),
            .showGhInstallHelp: #selector(showGhInstallHelp(_:)),
            .showClaudeInstallHelp: #selector(showClaudeInstallHelp(_:)),
            .showAppInstallHelp: #selector(showAppInstallHelp(_:)),
            .dismissSetupGuide: #selector(dismissSetupGuide),
        ]
    }

    private var generalPaneSelectors: [SetupWindowGeneralAction: Selector] {
        [
            .terminalChanged: #selector(terminalChanged(_:)),
            .tabActivationChanged: #selector(tabActivationChanged(_:)),
            .testTerminal: #selector(testTerminal),
            .languageChanged: #selector(languageChanged(_:)),
            .restartForLanguage: #selector(restartForLanguage),
            .openOptionsPage: #selector(openOptionsPage),
            .reshowInstall: #selector(reshowInstall),
            .openCmuxConfig: #selector(openCmuxConfig),
            .refreshCmuxStatus: #selector(refreshCmuxStatus),
        ]
    }

    private var githubPaneSelectors: [SetupWindowGitHubAction: Selector] {
        [
            .chooseBaseDirectory: #selector(chooseBaseDirectory),
            .baseDirectoryEdited: #selector(baseDirectoryEdited),
            .cmuxPlacementArrangementChanged: #selector(cmuxPlacementArrangementChanged(_:)),
            .cmuxPlacementIdentityChanged: #selector(cmuxPlacementIdentityChanged(_:)),
            .cmuxPlacementNameEdited: #selector(cmuxPlacementNameEdited),
        ]
    }

    private var slackPaneSelectors: [SetupWindowSlackAction: Selector] {
        [
            .slackThreadSettingsEdited: #selector(slackThreadSettingsEdited),
            .chooseSlackWorkDirectory: #selector(chooseSlackWorkDirectory),
            .recordSlackHotKey: #selector(recordSlackHotKey),
            .clearSlackHotKey: #selector(clearSlackHotKey),
            .slackLoginItemToggled: #selector(slackLoginItemToggled),
        ]
    }

    private func applyPaneVisibility() {
        guard rootStack != nil else { return }
        generalPane?.isHidden = selectedPane != .general
        githubPane?.isHidden = selectedPane != .github
        slackPane?.isHidden = selectedPane != .slack
        rootStack?.needsLayout = true
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "v\($0)" } ?? "dev"
    }

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
        Self.relativeFormatter(for: AppLocalization.resolvedTag()).localizedString(for: date, relativeTo: Date())
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

    private func nextArrival() -> Int {
        defer { nextReasonOrder += 1 }
        return nextReasonOrder
    }

    private func appendOpeningReason(_ reason: SetupWindowOpeningReason) {
        openingReasons.append(reason)
    }

    func presentClaudeInputRejection(_ blocker: ClaudeInputBlocker) {
        guard blocker.setupWindowCanHelp else { return }
        appendOpeningReason(.claudeInputRejected(blocker: blocker, arrivalOrder: nextArrival()))
        selectPane(.general)
        refresh()
        rootStack.afterNextWindowUpdate { [weak self] in self?.revealNewestOpeningReason() }
    }

    func presentSlackThreadRequestFailure(_ error: Error) {
        lastSlackRequestFailure = error
        let arrivalOrder = nextArrival()
        slackRequestFailuresByOrder[arrivalOrder] = error
        appendOpeningReason(.slackThreadRequestFailed(
            detail: slackThreadRequestErrorMessage(error), arrivalOrder: arrivalOrder
        ))
        selectPane(.slack)
        refresh()
        rootStack.afterNextWindowUpdate { [weak self] in self?.revealNewestOpeningReason() }
    }

    private func revealNewestOpeningReason() {
        guard let window,
              let scrollView = window.contentView as? NSScrollView,
              let document = scrollView.documentView else { return }

        // The newest reason is the first block at the top of the document, so scroll to the top.
        let clipHeight = scrollView.contentView.bounds.height
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? 0 : max(0, document.bounds.height - clipHeight)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clearSlackThreadRequestFailure() {
        lastSlackRequestFailure = nil
        slackRequestFailuresByOrder.removeAll()
        openingReasons.removeAll {
            if case .slackThreadRequestFailed = $0 { return true }
            return false
        }
        refresh()
    }

    func refreshForTesting() { refresh() }

    func selectTerminalForTesting(_ terminal: Terminal) {
        Settings.terminal = terminal
        refresh()
    }

    private func anchorToRestore(_ role: NSUserInterfaceItemIdentifier) -> NSView? {
        let views = rootStack?.arrangedSubviews ?? []
        guard let index = views.firstIndex(where: { $0.identifier == role }) else { return nil }
        return views[index...].first(where: { !$0.isHidden && $0.frame.height > 0 })
            ?? views[..<index].last(where: { !$0.isHidden && $0.frame.height > 0 })
    }

    private struct SetupWindowPlace {
        var focusedRole: NSUserInterfaceItemIdentifier?
        var selection: NSRange?
        var anchorRole: NSUserInterfaceItemIdentifier?
        var anchorOffset: CGFloat = 0
    }

    private func capturePlace(in window: NSWindow) -> SetupWindowPlace {
        var place = SetupWindowPlace()
        let editor = window.firstResponder as? NSTextView
        let focused = (editor?.delegate as? NSView) ?? (window.firstResponder as? NSView)
        place.focusedRole = focused?.identifier
        place.selection = editor?.selectedRange
        guard let scroll = window.contentView as? NSScrollView,
              let rootStack else { return place }
        let top = scroll.documentVisibleRect.maxY
        let visible = rootStack.arrangedSubviews.filter { !$0.isHidden && $0.frame.height > 0 }
        let anchor = visible.filter { $0.frame.maxY >= top }.min { $0.frame.maxY < $1.frame.maxY }
            ?? visible.max { $0.frame.maxY < $1.frame.maxY }
        if let anchor {
            place.anchorRole = anchor.identifier
            place.anchorOffset = anchor.frame.maxY - top
        }
        return place
    }

    private func restore(_ place: SetupWindowPlace, in window: NSWindow) {
        if let scroll = window.contentView as? NSScrollView,
           let document = scroll.documentView,
           let role = place.anchorRole,
           let anchor = anchorToRestore(role) {
            let origin = scrollOrigin(anchorTop: anchor.frame.maxY, offset: place.anchorOffset,
                                      clip: scroll.contentView.bounds.height)
            document.scroll(NSPoint(x: 0, y: origin))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        guard let role = place.focusedRole,
              let control = window.contentView?.firstDescendant(withRole: role),
              window.makeFirstResponder(control) else { return }
        guard let selection = place.selection,
              let editor = (control as? NSControl)?.currentEditor() else { return }
        let length = editor.string.utf16.count
        let location = min(selection.location, length)
        editor.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
    }

    func rebuildForLanguageChange() {
        guard let window else { return }
        let place = capturePlace(in: window)
        let drafts = (githubPane.baseDirectoryField.stringValue,
                      githubPane.workspaceNameField.stringValue,
                      slackPane.workDirectoryField.stringValue,
                      slackPane.instructionField.stringValue)
        let oldStack = rootStack
        let environment = currentEnvironment()
        isRebuildingForLanguageChange = true
        defer { isRebuildingForLanguageChange = false }
        window.contentView = buildContent(using: environment)
        githubPane.baseDirectoryField.stringValue = drafts.0
        githubPane.workspaceNameField.stringValue = drafts.1
        slackPane.workDirectoryField.stringValue = drafts.2
        slackPane.instructionField.stringValue = drafts.3
        configureToolbar()
        refresh()
        window.contentView?.layoutSubtreeIfNeeded()
        rootStack.visibleFrameOverride = oldStack?.visibleFrameOverride
        rootStack.afterNextWindowUpdate { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.restore(place, in: window)
        }
    }

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        Settings.terminal = Terminal(storedValue: raw)
        refresh()
    }

    @objc private func tabActivationChanged(_ sender: NSSegmentedControl) {
        guard Settings.terminal != .warp else { return }
        Settings.tabActivation = sender.selectedSegment == 1 ? .background : .foreground
        refresh()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let choice = sender.selectedItem?.representedObject as? String else { return }
        guard choice != Settings.language else { return }
        languageChange = .changed
        Settings.language = choice
    }

    @objc private func restartForLanguage() {
        guard LocaleRestartGate.admitRestart() else {
            languageChange = .restartBlocked
            refresh()
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            LocaleRestartGate.withdrawAdmission()
            checkoutLog("the relaunch could not be started, so the app is not restarting — \(errorMessage(error))")
            languageChange = .restartFailed
            refresh()
            return
        }
        NSApp.terminate(nil)
    }

    @objc private func registerManifest() {
        do { try Installer.installManifest() }
        catch { showError(localized("app.alert.manifestFailed"), error) }
        refresh()
    }

    @objc private func installInChrome() {
        if Installer.extensionCopyNeedsUpdate() {
            do { try Installer.installExtensionCopy() }
            catch {
                showError(localized("app.alert.extensionFolderFailed"), error)
                return
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Installer.extensionDirectory, forType: .string)
        openInChrome("chrome://extensions")
        guideStepsExpanded = true
        installFeedback = localized("app.setup.install.chrome.feedback")
        refresh()
    }

    @objc private func dismissSetupGuide() {
        guideWasReopened = false
        guideStepsExpanded = false
        installFeedback = nil
        refresh()
    }

    @objc private func reshowInstall() {
        guideWasReopened = true
        guideStepsExpanded = false
        refresh()
    }

    @objc private func openOptionsPage() { openInChrome(Installer.optionsPageURL) }

    @objc private func baseDirectoryEdited() {
        let typed = githubPane.baseDirectoryField.stringValue
        do {
            let normalized = try normalizedBaseDirectory(typed)
            Settings.baseDirectory = normalized ?? ""
            githubPane.baseDirectoryField.stringValue = normalized ?? ""
        } catch {
            refresh()
            return
        }
        refresh()
    }

    @objc private func chooseBaseDirectory() {
        chooseDirectory { [weak self] path in
            guard let self else { return }
            self.githubPane.baseDirectoryField.stringValue = path
            self.baseDirectoryEdited()
        }
    }

    @objc private func chooseSlackWorkDirectory() {
        chooseDirectory { [weak self] path in
            guard let self else { return }
            self.slackPane.workDirectoryField.stringValue = path
            Settings.slackThreadWorkDirectory = path
            self.refresh()
        }
    }

    private func chooseDirectory(_ completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localized("app.panel.choosePrompt")
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url.path)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(panel.runModal()) }
    }

    @objc private func cmuxPlacementArrangementChanged(_ sender: NSSegmentedControl) {
        let values: [CmuxPlacementArrangement] = [.panePerItem, .tabPerItem, .workspacePerItem]
        guard values.indices.contains(sender.selectedSegment) else { return }
        Settings.cmuxPlacementArrangement = values[sender.selectedSegment].rawValue
        refresh()
    }

    @objc private func cmuxPlacementIdentityChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment == 0 || sender.selectedSegment == 1 else { return }
        Settings.cmuxPlacementIdentityMode = sender.selectedSegment == 1 ? "fixed-name" : "always-new"
        refresh()
    }

    @objc private func cmuxPlacementNameEdited() {
        guard !isRebuildingForLanguageChange else { return }
        Settings.cmuxPlacementFixedName = githubPane.workspaceNameField.stringValue
        refresh()
    }

    @objc private func slackThreadSettingsEdited() {
        Settings.slackThreadWorkDirectory = slackPane.workDirectoryField.stringValue
        Settings.slackThreadInstruction = slackPane.instructionField.stringValue
        refresh()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isRebuildingForLanguageChange, let field = notification.object as? NSTextField else { return }
        if field === slackPane.workDirectoryField {
            Settings.slackThreadWorkDirectory = field.stringValue
            refresh()
        } else if field === slackPane.instructionField {
            Settings.slackThreadInstruction = field.stringValue
            refresh()
        }
    }

    @objc private func recordSlackHotKey() {
        guard !isRecordingHotKey else { endHotKeyRecording(); refresh(); return }
        isRecordingHotKey = true
        hotKeyNeedsModifier = false
        slackHotKey.suspend()
        hotKeyRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleHotKeyRecordingEvent(event)
        }
        refresh()
    }

    func handleHotKeyRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecordingHotKey else { return event }
        let modifiers = hotKeyModifiers(from: event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            endHotKeyRecording()
            refresh()
            return nil
        }
        guard let combination = HotKeyCombination(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            hotKeyNeedsModifier = true
            refresh()
            return nil
        }
        Settings.slackThreadHotKey = combination
        slackHotKey.apply(combination)
        endHotKeyRecording()
        refresh()
        return nil
    }

    private func endHotKeyRecording() {
        if let hotKeyRecordingMonitor { NSEvent.removeMonitor(hotKeyRecordingMonitor) }
        hotKeyRecordingMonitor = nil
        isRecordingHotKey = false
        slackHotKey.resume()
    }

    @objc private func clearSlackHotKey() {
        Settings.slackThreadHotKey = nil
        slackHotKey.apply(nil)
        refresh()
    }

    @objc private func slackLoginItemToggled() {
        do {
            try slackLoginItem.setEnabled(slackPane.loginItemCheckbox.state == .on)
            lastSlackLoginItemFailure = nil
        } catch {
            lastSlackLoginItemFailure = error
            checkoutLog("login item change failed — \((error as NSError).localizedDescription)")
        }
        refresh()
    }

    @objc private func requestPermission() {
        PermissionChecker.requestITermAutomation { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result { self.showError(localized("app.alert.permissionRequestFailed"), error) }
            self.refresh()
        }
    }

    @objc private func openAutomationSettings() { PermissionChecker.openAutomationSettings() }
    @objc private func requestAccessibility() { PermissionChecker.requestAccessibility(); refresh() }
    @objc private func openAccessibilitySettings() { PermissionChecker.openAccessibilitySettings() }
    @objc private func refreshCmuxStatus() {
        cmuxFeedback = nil
        refresh()
    }

    @objc private func openCmuxConfig() {
        guard effects.writeClipboard(CmuxConfigHelp.cmuxConfigClipboardFragment()) else {
            cmuxFeedback = .clipboardWriteFailed
            refresh()
            return
        }
        let configURL = CmuxConfigHelp.defaultConfigURL()
        let target = CmuxConfigHelp.cmuxConfigRevealTarget(
            configURL: configURL,
            fileExists: effects.fileExists(configURL),
            directoryExists: effects.fileExists(configURL.deletingLastPathComponent())
        )
        switch target {
        case .file(let url):
            cmuxFeedback = effects.openURL(url) ? .fileOpened : .openFailed
        case .directory(let url):
            cmuxFeedback = effects.openURL(url) ? .directoryOpened : .openFailed
        case .nothing:
            cmuxFeedback = .targetUnavailable
        }
        refresh()
    }

    @objc private func testTerminal() {
        let terminal = Settings.terminal
        let command = testCommand.command
        terminalTestAttempt += 1
        let attempt = terminalTestAttempt
        terminalTestResult = .running(terminal)
        refresh()
        let runTerminal = effects.runTerminal
        DispatchQueue.global().async { [weak self] in
            var failure: Error?
            do { try runTerminal(command, terminal) } catch { failure = error }
            DispatchQueue.main.async {
                guard let self, self.terminalTestAttempt == attempt else { return }
                if let failure { self.terminalTestResult = .failed(terminal, localizedErrorMessage(failure)) }
                else { self.terminalTestResult = .succeeded(terminal) }
                self.refresh()
            }
        }
    }

    @objc private func openTerminalSettings() {
        selectPane(.general)
        window?.makeFirstResponder(generalPane.terminalPopup)
    }

    @objc private func openSlackSettings() {
        selectPane(.slack)
        window?.makeFirstResponder(slackPane.workDirectoryField)
    }

    @objc private func openBaseDirectorySettings() {
        selectPane(.github)
        window?.makeFirstResponder(githubPane.baseDirectoryField)
    }

    @objc private func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        do { try task.run(); NSApp.terminate(nil) }
        catch { showError(localized("app.language.restartFailed"), error) }
    }

    @objc private func showZoxideInstallHelp(_ sender: NSButton) {
        showInstallHelp(from: sender, command: "brew install zoxide",
                        detail: localized("app.setup.problem.zoxide.effect"))
    }

    @objc private func showGhInstallHelp(_ sender: NSButton) {
        showInstallHelp(from: sender, command: "brew install gh",
                        detail: localized("app.setup.problem.gh.effect"))
    }

    @objc private func showClaudeInstallHelp(_ sender: NSButton) {
        showInstallHelp(from: sender, command: "brew install --cask claude-code",
                        detail: localized("app.setup.problem.claudeUnavailable.cause"))
    }

    @objc private func showAppInstallHelp(_ sender: NSButton) {
        showInstallHelp(from: sender, command: "./install.sh",
                        detail: localized("app.setup.problem.warpHelperUnavailable.cause"))
    }

    private func showInstallHelp(from sender: NSButton, command: String, detail: String) {
        let controller = NSViewController()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let description = makeSetupWindowWrappingLabel(detail)
        description.font = Theme.ui(12)
        description.textColor = Theme.text
        description.maximumNumberOfLines = 0
        let commandLabel = NSTextField(labelWithString: command)
        commandLabel.font = Theme.mono(12)
        commandLabel.textColor = Theme.text
        stack.addArrangedSubview(description)
        stack.addArrangedSubview(commandLabel)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 92))
        root.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12),
        ])
        controller.view = root
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = root.frame.size
        helpPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func openInChrome(_ urlString: String) {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
              let url = URL(string: urlString) else { NSSound.beep(); return }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = localizedErrorMessage(error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

private extension NSView {
    func firstDescendant(withRole role: NSUserInterfaceItemIdentifier) -> NSView? {
        for view in subviews {
            if view.identifier == role { return view }
            if let found = view.firstDescendant(withRole: role) { return found }
        }
        return nil
    }
}
