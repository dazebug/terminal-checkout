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
    var statusLabelsForTesting: [NSTextField] {
        [
            manifestStatusLabel, extensionStatusLabel, installFeedbackLabel,
            permissionStatusLabel, accessibilityStatusLabel, testResultLabel,
        ]
    }
    private let requestPermissionButton = NSButton(title: "iTerm2 권한 요청", target: nil, action: nil)
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
    private var guideBlock: NSView!
    private var utilityRow: NSView!
    /// [설치 안내 다시 보기]로 확장 카드를 강제 표시 (창 닫으면 초기화)
    private var forceShowInstall = false
    private var requestObserver: (any NSObjectProtocol)?
    private var toolsObserver: (any NSObjectProtocol)?

    /// 없을 때 무엇이 깨지는지 — 사용자가 설치 여부를 판단할 근거가 되는 문장.
    /// z는 기본 명령의 첫 단어라 없으면 모든 버튼이 실패하므로 오류로 다룬다.
    private let toolAdvice: [(name: String, critical: Bool, advice: String)] = [
        (
            "z", true,
            "명령을 찾을 수 없습니다 — 기본 command가 z로 시작하므로 모든 버튼이 실패합니다. "
                + "brew install zoxide 후 ~/.zshrc에 eval \"$(zoxide init zsh)\"를 추가하세요."
        ),
        (
            "gh", false,
            "명령을 찾을 수 없습니다 — 이슈 버튼의 gh 프리셋이 실패합니다. brew install gh 후 gh auth login."
        ),
        (
            "claude", false,
            "명령을 찾을 수 없습니다 — claude 입력을 예약한 버튼이 입력을 전달하지 못합니다."
        ),
    ]

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
    }

    deinit {
        for observer in [requestObserver, toolsObserver].compactMap({ $0 }) {
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
        toolsCard = buildToolsCard()
        utilityRow = buildUtilityRow()

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(pipeline)
        stack.setCustomSpacing(16, after: pipeline)

        stack.addArrangedSubview(chromeCard)
        stack.addArrangedSubview(extensionCard)
        stack.addArrangedSubview(terminalCard())
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
        permissionSection.orientation = .vertical
        permissionSection.alignment = .leading
        permissionSection.spacing = 9
        permissionSection.addArrangedSubview(hairline())
        permissionSection.addArrangedSubview(sectionTitle("iTerm2 제어 권한"))
        permissionSection.addArrangedSubview(helpLabel(
            "iTerm2 제어(Apple Events) 권한을 이 앱에만 부여합니다. Chrome에는 아무 권한도 필요 없습니다."
        ))
        permissionSection.addArrangedSubview(permissionStatusLabel)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private func relative(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
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
                    : .warning("허용 안 됨 — 명령은 실행되지만 claude 입력은 전달되지 않습니다"),
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

    /// 없는 도구만 줄로 남긴다 — 준비된 도구까지 나열하면 정상 상태에서도 카드가 계속 떠 있게 된다.
    private func updateToolsCard() {
        guard let availability = Settings.toolAvailability else {
            toolsCard.isHidden = true // 아직 확인 전 (백그라운드에서 진행 중)
            return
        }
        let missing = toolAdvice.filter { availability[$0.name] == false }
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
                // 명령 실행은 되므로 오류가 아니라 경고다 — claude 입력만 막힌다
                terminalColor = Theme.warn
                terminalDetail = "손쉬운 사용 권한 없음 — 명령은 실행되고 claude 입력은 전달되지 않음"
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
        + "예약된 버튼은 탭을 열지 않고 거절됩니다(입력이 전부 병합되는 버튼과 claude 입력이 없는 "
        + "버튼은 그대로 동작합니다). 전달 중에는 그 탭을 보고 있어야 합니다."
}
