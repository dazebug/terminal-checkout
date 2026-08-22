import AppKit
import Core

/// 설치·터미널 선택·권한·테스트를 한 화면에서 처리하는 설정 창.
/// 디자인: 설정 창 자체가 터미널 세션 — 섹션은 프롬프트(❯), 상태는 종료 코드처럼 색으로 읽힌다.
/// 노출은 상태 기반: 완료된 설정 항목의 카드는 사라지고 파이프라인 스트립의 점으로만 남는다.
/// Card width. File scope so the status-label factory below can use it before `self` exists.
let setupContentWidth: CGFloat = 560
/// Text width inside a card (`setupContentWidth` minus the card's 14pt insets on both sides).
let setupTextWidth: CGFloat = setupContentWidth - 28

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
    /// Stands in for the screen so a test can exercise the clamp without depending on whichever
    /// display it happens to run on.
    var visibleFrameOverride: NSRect?

    override func layout() {
        super.layout()
        guard let window, window.contentView != nil else { return }
        var target = fittingSize
        let visible = visibleFrameOverride ?? (window.screen ?? NSScreen.main)?.visibleFrame
        if let visible { target.height = min(target.height, visible.height) }
        guard lastRequestedSize != target else { return }
        lastRequestedSize = target
        window.setContentSize(target)
        if let visible { Self.moveInside(visible, window) }
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
    /// exactly one place, so item 11 has one site to move rather than two to keep in step.
    private let requestPermissionButton = NSButton(title: "", target: nil, action: nil)
    private var itermRadio: NSButton!
    private var weztermRadio: NSButton!
    private var warpRadio: NSButton!
    private var terminalNoteLabel: NSTextField!
    /// iTerm2 선택 + 권한 미허용일 때만 표시 (WezTerm은 TCC 권한 불필요)
    private let permissionSection = NSStackView()
    /// Warp 선택 + 손쉬운 사용 미허용일 때만 표시
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
    private let baseDirStatusLabel = makeStatusLabel(font: Theme.mono(11.5))
    private var guideBlock: NSView!
    private var utilityRow: NSView!
    private var languagePopUp: NSPopUpButton!
    private var languageRestartButton: NSButton!
    private var languageNoteLabel: NSTextField!
    private var languageObserver: NSObjectProtocol?
    /// [설치 안내 다시 보기]로 확장 카드를 강제 표시 (창 닫으면 초기화)
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
                baseDirectoryConfigured
                    ? "명령을 찾을 수 없습니다 — 저장소 기본 폴더로 대신 이동하므로 버튼은 동작합니다. "
                        + "zoxide를 설치하면 기본 폴더 밖의 저장소로도 점프합니다(brew install zoxide)."
                    : "명령을 찾을 수 없습니다 — 기본 command가 z로 시작하므로 모든 버튼이 실패합니다. "
                        + "brew install zoxide 후 ~/.zshrc에 eval \"$(zoxide init zsh)\"를 추가하거나, "
                        + "아래 「저장소 기본 폴더」를 설정하세요."
            ),
            (
                "gh", false,
                "명령을 찾을 수 없습니다 — 이슈 버튼의 gh 프리셋과 저장소 기본 폴더의 clone 단계가 실패합니다. "
                    + "brew install gh 후 gh auth login."
            ),
            (
                "claude", false,
                "명령을 찾을 수 없습니다 — claude 입력을 예약한 버튼이 입력을 전달하지 못합니다."
            ),
        ]
    }

    private let terminalRadioWidth: CGFloat = 120
    private let testCommand = "echo 'Terminal Checkout: 연결 OK'"

    /// 창이 닫힐 때 알림 (AppDelegate가 Dock 표시를 되돌리는 데 사용)
    var onClose: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Terminal Checkout 설정"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 터미널은 어둡다 — 시스템 모드와 무관하게 다크로 고정 (레이어 색이 정적이므로 필수)
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
        // 도구 확인은 로그인 셸을 띄우느라 창보다 늦게 끝난다
        toolsObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutToolsChecked, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // 우리 문자열은 재시작을 기다리지 않는다(D14) — 언어가 바뀌면 이 창이 다시 그린다
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
    /// would leave the whole window in the old language while three labels moved. That is the shape
    /// round 1 meant by "a lookup function alone does not switch anything": the lookup has to be
    /// *reached* again, and nothing reaches it.
    ///
    /// Rebuilding the content is the mechanism, rather than a second pass that re-sets each string:
    /// a re-set pass has to name every string, so it is wrong the moment item 10 or 11 adds one,
    /// and it would be wrong silently. This is correct for strings that do not exist yet.
    ///
    /// It runs **only on a language change**, not on every `refresh()` — refresh runs on window
    /// activation and on every socket request, and replacing the view tree that often would fight
    /// the user for focus and for their place in the window.
    ///
    /// State survives because the views that hold it are stored properties: the base-directory
    /// field, the status labels and the pipeline strip are re-parented into the new stack rather
    /// than recreated, so what the user has typed is still there afterwards.
    func rebuildForLanguageChange() {
        guard let window = window else { return }
        window.contentView = buildContent()
        window.contentView?.layoutSubtreeIfNeeded()
        refresh()
    }

    // MARK: - UI 구성

    private func buildContent() -> NSView {
        let stack = FittedContentStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 20, bottom: 18, right: 20)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = Theme.bg.cgColor

        chromeCard = buildChromeCard()
        extensionCard = buildExtensionCard()
        baseDirCard = buildBaseDirCard()
        toolsCard = buildToolsCard()
        utilityRow = buildUtilityRow()

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(pipeline)
        stack.setCustomSpacing(16, after: pipeline)

        stack.addArrangedSubview(chromeCard)
        stack.addArrangedSubview(extensionCard)
        stack.addArrangedSubview(languageCard())
        stack.addArrangedSubview(terminalCard())
        stack.addArrangedSubview(baseDirCard)
        stack.addArrangedSubview(toolsCard)
        stack.addArrangedSubview(testCard())
        stack.addArrangedSubview(utilityRow)

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

    // MARK: 카드 — 설정 단계 (완료되면 숨김)

    private func buildChromeCard() -> NSView {
        card("Chrome 연결 (Native Host)", [
            manifestStatusLabel,
            buttonRow([button("등록/업데이트", #selector(registerManifest))]),
        ])
    }

    private func buildExtensionCard() -> NSView {
        let installButton = button("Chrome에 설치하기", #selector(installInChrome))
        installButton.keyEquivalent = "\r"
        installButton.bezelColor = Theme.actionGreen
        installButton.toolTip = Installer.extensionDirectory

        guideBlock = quoteBlock([
            "① 우측 상단 「개발자 모드」 켜기",
            "② 좌측 상단 「압축해제된 확장 프로그램을 로드합니다」 클릭",
            "③ 파일 선택 창에서 ⇧⌘G → ⌘V(붙여넣기) → Enter → [선택]",
            "④ 개발자 모드는 켜둔 채로 유지하세요 — 끄면 확장이 비활성화됩니다",
        ])
        guideBlock.isHidden = true
        installFeedbackLabel.isHidden = true

        return card("확장 프로그램", [
            extensionStatusLabel,
            helpLabel("[Chrome에 설치하기]를 누르면 확장 폴더 경로가 클립보드에 복사되고 chrome://extensions가 열립니다."),
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
        baseDirField.placeholderString = "예: ~/Codes"
        baseDirField.font = Theme.mono(11.5)
        baseDirField.target = self
        baseDirField.action = #selector(baseDirectoryEdited)
        // Save on focus loss as well as Enter — nobody should close the window wondering
        // whether it was saved
        baseDirField.cell?.sendsActionOnEndEditing = true
        baseDirField.widthAnchor.constraint(equalToConstant: setupTextWidth - 110).isActive = true

        let row = NSStackView(views: [baseDirField, button("폴더 선택…", #selector(chooseBaseDirectory))])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return card("저장소 기본 폴더", [
            helpLabel(
                "저장소들을 클론해 두는 최상위 폴더입니다. z가 이동에 실패하면(zoxide 기록이 없거나 "
                    + "zoxide를 안 쓰는 경우) 이 폴더 아래의 저장소로 이동하고, 없으면 gh로 clone합니다. "
                    + "비워 두면 지금까지와 똑같이 z로만 이동합니다."
            ),
            row,
            baseDirStatusLabel,
            // Saved button commands are never rewritten for the user, so someone upgrading from an
            // earlier version gets no fallback from setting the folder alone. The options page now
            // offers that rewrite itself (issue #31), so point at the notice rather than asking for
            // the old by-hand re-apply
            helpLabel(
                "이전 버전부터 쓰던 버튼은 저장해 둔 command를 그대로 유지합니다 — 폴더만 지정해서는 "
                    + "폴백이 걸리지 않습니다. 확장 옵션 페이지를 열면 위쪽에 업데이트 표시가 뜨고, "
                    + "버튼별로 확인한 뒤 저장하면 반영됩니다."
            ),
        ])
    }

    /// 명령이 부르는 도구 확인. 앱의 PATH가 아니라 로그인 셸에 물어야 한다 —
    /// z는 zoxide가 rc에서 정의하는 셸 함수라 실행 파일 탐색으로는 찾을 수 없다.
    private func buildToolsCard() -> NSView {
        toolsList.orientation = .vertical
        toolsList.alignment = .leading
        toolsList.spacing = 6
        return card("명령이 부르는 도구", [
            helpLabel("버튼의 command와 claude 입력이 부르는 도구를 로그인 셸에서 확인했습니다."),
            toolsList,
        ])
    }

    // MARK: 카드 — 상시 (터미널 선택·테스트)

    // MARK: 카드 — 언어

    /// **The app owns the language and the extension follows** (D8): the picker is here because the
    /// setup window is what a user sees *before* the extension exists, so an extension-side picker
    /// would have no answer at the one moment it is first needed.
    ///
    /// The entries are each written in their own language, which is what a language menu does
    /// everywhere: a user who has landed in a language they cannot read has to be able to find
    /// their way out of it. Only the `auto` line is in the window's language, and item 11 moves it
    /// into the catalogue with the rest of this window.
    private func languageCard() -> NSView {
        languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopUp.addItem(withTitle: "시스템 언어를 따름")
        languagePopUp.lastItem?.representedObject = automaticLocalePreference
        for tag in supportedLocales {
            languagePopUp.addItem(withTitle: languageMenuTitles[tag] ?? tag)
            languagePopUp.lastItem?.representedObject = tag
        }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)

        // Half of the change lands now and half on the next launch (D14), so the button that closes
        // that gap sits next to the control that opens it rather than in a menu somewhere
        languageRestartButton = button("지금 다시 시작", #selector(restartForLanguage))
        languageNoteLabel = helpLabel("", width: setupContentWidth - 28)

        let row = NSStackView(views: [languagePopUp, languageRestartButton])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        return card("언어", [row, languageNoteLabel])
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

    /// **The picker asks, it does not decide.** Whether a restart is safe right now is item 13's
    /// question — there is asynchronous claude input delivery in flight to consider, and a Warp
    /// helper whose only defence is its lifetime. Until that lands the gate answers yes, and the
    /// hole is deliberate rather than forgotten: the seam is here so item 13 has one place to fill.
    @objc private func restartForLanguage() {
        guard LocaleRestartGate.isSafeNow() else {
            languageNoteLabel.stringValue = languageNote(restartBlocked: true)
            return
        }
        let app = Bundle.main.bundlePath
        // A detached `open` after this process exits: relaunching from inside a terminating app
        // races the old instance's socket, and the new one would fail to bind
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", app]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func languageNote(restartBlocked: Bool = false) -> String {
        if restartBlocked {
            return "claude 입력을 전달하는 중이라 지금은 다시 시작하지 않습니다. 전달이 끝난 뒤 다시 눌러 주세요."
        }
        return "앱이 그리는 문자열은 즉시 바뀝니다. 시스템 대화상자(파일 선택·경고)는 다음 실행부터 이 언어로 뜹니다."
    }

    private func terminalCard() -> NSView {
        itermRadio = radio("iTerm2", installed: PermissionChecker.isITermInstalled)
        weztermRadio = radio("WezTerm", installed: PermissionChecker.isWezTermInstalled)
        warpRadio = radio("Warp", installed: PermissionChecker.isWarpInstalled)

        // 세로 배치 — 셋을 가로로 늘어놓으면 카드 폭에 눌린다
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
        return card("터미널", [radioRow, permissionSection, accessibilitySection])
    }

    private func radio(_ title: String, installed: Bool) -> NSButton {
        let button = NSButton(
            radioButtonWithTitle: installed ? title : "\(title) (미설치)",
            target: self, action: #selector(terminalChanged)
        )
        button.isEnabled = installed
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
        permissionSection.addArrangedSubview(sectionTitle("iTerm2 제어 권한"))
        permissionSection.addArrangedSubview(helpLabel(
            "iTerm2 제어(Apple Events) 권한을 이 앱에만 부여합니다. Chrome에는 아무 권한도 필요 없습니다."
        ))
        permissionSection.addArrangedSubview(permissionStatusLabel)
        requestPermissionButton.title = "iTerm2 권한 요청"
        requestPermissionButton.target = self
        requestPermissionButton.action = #selector(requestPermission)
        requestPermissionButton.bezelStyle = .rounded
        permissionSection.addArrangedSubview(buttonRow([
            requestPermissionButton,
            button("시스템 설정 열기", #selector(openAutomationSettings)),
        ]))
    }

    /// 화면을 읽어 "claude가 그 입력을 받았는지" 확인하는 데 쓴다. 확인 없이 제출하면 claude가
    /// 초기화 중 버린 입력이 "전달됨"으로 기록되므로(실측), 이 권한 없이는 claude 입력을
    /// 전달하지 않는다 — 명령 실행과는 무관하다는 것을 문구로 갈라 준다.
    private func buildAccessibilitySection() {
        // Idempotent: it fills a **stored** stack, so building a second time would append a second
        // copy of everything rather than replace it. `toolsList` already clears for the same reason
        accessibilitySection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        accessibilitySection.orientation = .vertical
        accessibilitySection.alignment = .leading
        accessibilitySection.spacing = 9
        accessibilitySection.addArrangedSubview(hairline())
        accessibilitySection.addArrangedSubview(sectionTitle("Warp claude 입력 (손쉬운 사용)"))
        accessibilitySection.addArrangedSubview(helpLabel(warpAccessibilityHelpText()))
        accessibilitySection.addArrangedSubview(accessibilityStatusLabel)
        accessibilitySection.addArrangedSubview(buttonRow([
            button("손쉬운 사용 권한 요청", #selector(requestAccessibility)),
            button("시스템 설정 열기", #selector(openAccessibilitySettings)),
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
            string: testCommand, attributes: [.font: Theme.mono(11), .foregroundColor: Theme.text]
        ))
        let commandLabel = NSTextField(labelWithString: "")
        commandLabel.attributedStringValue = command

        let row = NSStackView(views: [chip(commandLabel), button("터미널에서 실행", #selector(testTerminal))])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        testResultLabel.isHidden = true

        return card("동작 테스트", [row, testResultLabel])
    }

    /// 설정 완료 후에만 보이는 유틸리티 (설정 중에는 확장이 로드되기 전이라 옵션 페이지가 없다)
    private func buildUtilityRow() -> NSView {
        buttonRow([
            button("확장 옵션 페이지 열기", #selector(openOptionsPage)),
            button("설치 안내 다시 보기", #selector(reshowInstall)),
        ])
    }

    // MARK: 뷰 팩토리

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

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
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

    /// 안내 절차용 인용 블록 — 왼쪽에 가는 세로 바를 세운 heredoc 느낌
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

    // MARK: - 터미널 선택

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
        // 예약한 claude 입력은 claude가 뜬 뒤에야 전달되므로 시간이 걸린다 —
        // 그 사이 사용자가 끼어들면 입력이 섞인다
        var note = "GitHub 버튼을 누르면 새 탭에서 명령이 돌고, 예약한 claude 입력은 "
            + "claude가 뜬 뒤에 전달됩니다. 그동안 그 탭에 키를 누르지 말고 기다리세요."
        // Warp는 화면을 "포커스된 탭"만 보여 주므로, 앱이 자기 탭을 확인할 수 있을 때만 제출한다
        if Settings.terminal == .warp {
            note += " Warp는 그 탭을 보고 있는 동안에만 전달됩니다 — 다른 탭으로 옮기면 "
                + "멈췄다가 돌아오면 이어집니다."
        }
        terminalNoteLabel.stringValue = note
    }

    // MARK: - 상태 갱신

    private func refresh() {
        // The picker follows the stored value rather than its own last click: a second window, or a
        // value written before this launch, has to show through
        let language = Settings.language
        let index = languagePopUp.itemArray.firstIndex {
            $0.representedObject as? String == language
        }
        languagePopUp.selectItem(at: index ?? 0)
        languageNoteLabel.stringValue = languageNote()

        let manifest = Installer.manifestState()
        let folder = Installer.extensionState()
        let evidence = Settings.lastRequestAt

        // Chrome 연결: 정상이면 카드를 숨긴다 (앱 실행 시 자동 등록·자가 치유되므로 버튼도 불필요)
        if case .ok = manifest {
            chromeCard.isHidden = true
        } else {
            chromeCard.isHidden = false
            apply(manifest, to: manifestStatusLabel)
        }

        // 확장: 소켓으로 요청이 실제 도착했을 때만 완료로 본다
        let extensionState: SetupState
        if case .error = folder {
            extensionState = folder
        } else if let evidence {
            extensionState = .ok("연결 확인됨 — 마지막 요청 \(relative(evidence))")
        } else {
            extensionState = .warning("Chrome에서의 첫 요청 대기 중 — 설치 후 GitHub PR 페이지에서 버튼을 누르면 완료됩니다")
        }
        apply(extensionState, to: extensionStatusLabel)
        extensionCard.isHidden = evidence != nil && !forceShowInstall
        utilityRow.isHidden = !extensionCard.isHidden

        updateBaseDirCard()
        updateToolsCard()

        let socketAlive = FileManager.default.fileExists(atPath: defaultSocketPath())

        var permission: SetupState?
        // 손쉬운 사용이 없어도 명령 실행은 된다(claude 입력 전달만 막힌다) — 오류가 아니라 경고로 다룬다
        let accessibilityGranted = PermissionChecker.isAccessibilityGranted
        // 터미널별 권한 UI — 케이스를 추가하면 "이 터미널에 권한 섹션이 필요한가"가 여기서
        // 컴파일 에러로 강제된다
        switch Settings.terminal {
        case .iterm:
            if PermissionChecker.isITermInstalled {
                let status = PermissionChecker.iTermAutomationStatus()
                permission = status.isGranted ? .ok(status.label) : .warning(status.label)
            } else {
                permission = .warning("iTerm2가 설치되어 있지 않음")
            }
            apply(permission!, to: permissionStatusLabel, prefix: "iTerm2 자동화: ")
        case .wezterm:
            break // CLI 실행이라 TCC 권한이 필요 없다
        case .warp:
            apply(
                accessibilityGranted
                    ? .ok("허용됨")
                    : .warning("허용 안 됨 — claude 입력이 예약된 버튼은 거절됩니다"),
                to: accessibilityStatusLabel, prefix: "손쉬운 사용: "
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
    private func updateBaseDirCard() {
        let stored = Settings.baseDirectory
        if window?.firstResponder !== baseDirField.currentEditor() {
            baseDirField.stringValue = stored
        }
        // A stored value can only be invalid if it was edited outside this window (a hand-edited
        // plist, an older build). Say so here rather than let every button fail unexplained.
        // `try?` would fold "threw" and "not configured" into the same nil, so catch explicitly.
        let resolved: String?
        do {
            resolved = try normalizedBaseDirectory(stored)
        } catch {
            apply(
                .error("저장된 값이 올바르지 않습니다(\(baseDirectoryReason(error))) — 다시 지정해 주세요"),
                to: baseDirStatusLabel
            )
            return
        }
        guard let normalized = resolved else {
            apply(
                .warning("설정하지 않음 — z로만 이동합니다. zoxide 기록에 없는 저장소에서는 명령이 아무것도 하지 않습니다"),
                to: baseDirStatusLabel
            )
            return
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            apply(.ok("\(normalized) — z가 실패하면 여기로 이동하고, 저장소가 없으면 clone합니다"), to: baseDirStatusLabel)
        } else {
            // clone creates the leading directories (measured), so a missing folder still works —
            // this only says so out loud, which is how a typo gets noticed
            apply(.warning("\(normalized) — 아직 없는 폴더입니다. clone할 때 만들어집니다"), to: baseDirStatusLabel)
        }
    }

    /// 없는 도구만 줄로 남긴다 — 준비된 도구까지 나열하면 정상 상태에서도 카드가 계속 떠 있게 된다.
    private func updateToolsCard() {
        guard let availability = Settings.toolAvailability else {
            toolsCard.isHidden = true // 아직 확인 전 (백그라운드에서 진행 중)
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

    private func pipelineNodes(
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
            terminalDetail = "iTerm2 자동화: \(permission?.message ?? "상태 미확인")"
        case .wezterm:
            terminalName = "WezTerm"
            let installed = PermissionChecker.isWezTermInstalled
            terminalColor = installed ? Theme.ok : Theme.err
            terminalDetail = installed ? "WezTerm CLI 사용 가능 — TCC 권한 불필요" : "WezTerm이 설치되어 있지 않음"
        case .warp:
            terminalName = "Warp"
            if !PermissionChecker.isWarpInstalled {
                terminalColor = Theme.err
                terminalDetail = "Warp가 설치되어 있지 않음"
            } else if accessibilityGranted {
                terminalColor = Theme.ok
                terminalDetail = "Tab Config로 새 탭 — pane 안 헬퍼로 claude 입력 전달"
            } else {
                // claude 입력이 없는 버튼은 그대로 도므로 오류가 아니라 경고다
                terminalColor = Theme.warn
                terminalDetail = "손쉬운 사용 권한 없음 — claude 입력이 예약된 버튼은 탭을 열지 않고 거절됨"
            }
        }
        return [
            .init(label: "Chrome 확장", color: color(extensionState), detail: extensionState.message),
            .init(label: "relay", color: color(manifest), detail: "Native Host: \(manifest.message)"),
            .init(
                label: "앱", color: socketAlive ? Theme.ok : Theme.err,
                detail: socketAlive ? "소켓 서버 대기 중 (host.sock)" : "소켓 파일 없음 — 앱을 재시작해 보세요"
            ),
            .init(label: terminalName, color: terminalColor, detail: terminalDetail),
        ]
    }

    private func apply(_ state: SetupState, to label: NSTextField, prefix: String = "") {
        label.stringValue = "● \(prefix)\(state.message)"
        switch state {
        case .ok: label.textColor = Theme.ok
        case .warning: label.textColor = Theme.warn
        case .error: label.textColor = Theme.err
        }
    }

    // MARK: - 액션

    @objc private func registerManifest() {
        do {
            try Installer.installManifest()
        } catch {
            showError("Native Host 등록 실패", error)
        }
        refresh()
    }

    /// 설치 도우미: 폴더 준비(사본이 없거나 낡았으면 갱신) → 경로 클립보드 복사 → chrome://extensions 열기
    @objc private func installInChrome() {
        if Installer.extensionCopyNeedsUpdate() {
            do {
                try Installer.installExtensionCopy()
            } catch {
                showError("확장 프로그램 폴더 준비 실패", error)
                return
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Installer.extensionDirectory, forType: .string)
        openInChrome("chrome://extensions")
        guideBlock.isHidden = false
        installFeedbackLabel.stringValue = "경로가 클립보드에 복사되었고 Chrome이 열렸습니다. 위 ①→④ 순서대로 진행하세요."
        installFeedbackLabel.textColor = Theme.accent
        installFeedbackLabel.isHidden = false
        refresh()
    }

    /// The Korean wording for a rejection. Core hands back only the reason so each surface can word
    /// it its own way — the button response is English, this window is Korean until #24 lands.
    private func baseDirectoryReason(_ error: Error) -> String {
        guard case CommandError.invalidBaseDirectory(let problem, _) = error else {
            return errorMessage(error)
        }
        switch problem {
        case .notAbsolute: return "절대 경로가 아닙니다"
        case .invalidCharacters: return "공백이나 한글 등 셸에서 안전하지 않은 문자가 있습니다"
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
        } catch {
            apply(
                .error("저장하지 않았습니다 — \(baseDirectoryReason(error))"),
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
        panel.prompt = "선택"
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
        permissionStatusLabel.stringValue = "● iTerm2 자동화: 권한 프롬프트 응답 대기 중…"
        permissionStatusLabel.textColor = Theme.textDim
        PermissionChecker.requestITermAutomation { [weak self] result in
            guard let self else { return }
            self.requestPermissionButton.isEnabled = true
            if case .failure(let error) = result {
                self.showError("권한 요청 실패", error)
            }
            self.refresh()
        }
    }

    @objc private func openAutomationSettings() {
        PermissionChecker.openAutomationSettings()
    }

    /// 손쉬운 사용 프롬프트는 그 자리에서 허용되지 않고 시스템 설정으로 안내만 한다 —
    /// 완료 콜백이 없어 창이 다시 키가 될 때(windowDidBecomeKey → refresh) 상태를 다시 읽는다
    @objc private func requestAccessibility() {
        PermissionChecker.requestAccessibility()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc private func testTerminal() {
        let terminal = Settings.terminal
        let command = testCommand
        testResultLabel.stringValue = "실행 중…"
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
                    self?.testResultLabel.stringValue = "실패: \(errorMessage(failure))"
                    self?.testResultLabel.textColor = Theme.err
                } else {
                    self?.testResultLabel.stringValue = "터미널에 새 탭이 열렸다면 성공입니다."
                    self?.testResultLabel.textColor = Theme.textDim
                }
                self?.refresh()
            }
        }
    }

    // MARK: - 헬퍼

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

/// What to say when claude can be called but does **not** resolve to an executable — an install
/// that is only a shell function or an alias.
///
/// The merge path launches `command claude`, which skips functions and aliases, so those setups
/// take the typed route instead. All the user sees otherwise is that delivery got slower, or — on
/// Warp without the Accessibility permission — that the button now refuses outright, with the
/// reason nowhere on screen (independent reviewer, round 7).
///
/// Silent before the first check (nil) and silent when claude is missing altogether: the "missing"
/// line already says that one, and saying it twice reads as two different problems.
///
/// It does **not** name the cause as "a function or an alias": the same answer comes from a
/// relative `PATH` entry and from a file without the executable bit (both measured), and a card
/// that asserts the wrong cause sends people to fix the wrong thing (round 8).
func claudeWrapperAdvice(available: [String: Bool]?, executable: [String: Bool]?) -> String? {
    guard available?["claude"] == true, executable?["claude"] == false else { return nil }
    return "claude를 실행 파일로 찾지 못해 claude 입력을 병합하지 못합니다"
        + " (함수·별칭으로만 설치됐거나, PATH에 상대 경로 항목이 있거나, 실행 권한이 없는 경우입니다)"
        + " — 입력은 세션에 타이핑으로 전달되고, Warp에서는 손쉬운 사용 권한이 필요해집니다."
}

/// What the Accessibility card says. It used to promise that the command would still run without
/// the permission and only the claude input would be missing — the app does the opposite: a button
/// whose inputs have to be typed is **refused before the tab is created** (`claudeInputBlocker`).
/// A card that contradicts the behaviour sends people looking for the wrong problem (round 8).
func warpAccessibilityHelpText() -> String {
    "claude가 입력을 받은 것을 Warp 화면에서 확인하는 데 씁니다. 허용하지 않으면 claude 입력이 "
        + "예약된 버튼은 탭을 열지 않고 거절됩니다 — **기본 프리셋 3종이 전부 여기 해당합니다**"
        + "(`!` 입력은 claude 셸 모드에 타이핑해야 실행되기 때문입니다). claude 입력이 없는 버튼과 "
        + "평문 한 줄만 예약한 버튼은 권한 없이 그대로 동작합니다. 전달 중에는 그 탭을 보고 있어야 합니다."
}
