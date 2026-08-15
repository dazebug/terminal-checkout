import AppKit
import Core

/// 설치·터미널 선택·권한·테스트를 한 화면에서 처리하는 설정 창.
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let manifestStatusLabel = NSTextField(labelWithString: "")
    private let extensionStatusLabel = NSTextField(labelWithString: "")
    private let extensionPathLabel = NSTextField(labelWithString: "")
    private let extensionIDLabel = NSTextField(labelWithString: "")
    private let installFeedbackLabel = NSTextField(labelWithString: "")
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let testResultLabel = NSTextField(labelWithString: "")
    private let requestPermissionButton = NSButton(title: "iTerm2 권한 요청", target: nil, action: nil)
    private var itermRadio: NSButton!
    private var weztermRadio: NSButton!
    /// iTerm2 선택 시에만 표시되는 권한 섹션 (WezTerm은 TCC 권한 불필요)
    private let permissionSection = NSStackView()

    /// 창이 닫힐 때 알림 (AppDelegate가 Dock 표시를 되돌리는 데 사용)
    var onClose: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Terminal Checkout 설정"
        self.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        updateTerminalControls()
        window.center()
        refresh()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - UI 구성

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        stack.addArrangedSubview(sectionLabel("Chrome 연결 (Native Host)"))
        stack.addArrangedSubview(helpLabel("Chrome이 이 앱에 요청을 전달할 수 있도록 Native Messaging host를 등록합니다. 앱 실행 시 자동으로 등록됩니다."))
        stack.addArrangedSubview(manifestStatusLabel)
        stack.addArrangedSubview(buttonRow([
            button("등록/업데이트", #selector(registerManifest)),
        ]))

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionLabel("확장 프로그램"))
        stack.addArrangedSubview(helpLabel("확장 프로그램 폴더를 준비하고 Chrome에 로드합니다. 확장 ID는 폴더 경로에서 계산됩니다."))
        stack.addArrangedSubview(extensionStatusLabel)
        extensionPathLabel.lineBreakMode = .byTruncatingMiddle
        extensionPathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        extensionPathLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(extensionPathLabel)
        extensionIDLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        extensionIDLabel.textColor = .secondaryLabelColor
        extensionIDLabel.isSelectable = true
        stack.addArrangedSubview(extensionIDLabel)

        let installButton = button("Chrome에 설치하기", #selector(installInChrome))
        installButton.keyEquivalent = "\r" // 주 버튼 강조
        stack.addArrangedSubview(buttonRow([
            installButton,
            button("확장 옵션 페이지 열기", #selector(openOptionsPage)),
        ]))
        stack.addArrangedSubview(helpLabel("""
        [Chrome에 설치하기]를 누르면 폴더 경로가 클립보드에 복사되고 chrome://extensions가 열립니다. 이어서:
        ① 우측 상단 「개발자 모드」 켜기
        ② 좌측 상단 「압축해제된 확장 프로그램을 로드합니다」 클릭
        ③ 파일 선택 창에서 ⇧⌘G → ⌘V(붙여넣기) → Enter → [선택]
        ④ 개발자 모드는 켜둔 채로 유지하세요 — 끄면 확장이 비활성화됩니다
        """))
        installFeedbackLabel.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(installFeedbackLabel)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionLabel("터미널"))
        stack.addArrangedSubview(helpLabel("checkout 명령을 실행할 터미널을 선택합니다."))
        itermRadio = NSButton(radioButtonWithTitle: "iTerm2", target: self, action: #selector(terminalChanged))
        weztermRadio = NSButton(radioButtonWithTitle: "WezTerm", target: self, action: #selector(terminalChanged))
        if !PermissionChecker.isITermInstalled {
            itermRadio.title = "iTerm2 (미설치)"
            itermRadio.isEnabled = false
        }
        if !PermissionChecker.isWezTermInstalled {
            weztermRadio.title = "WezTerm (미설치)"
            weztermRadio.isEnabled = false
        }
        let radioRow = NSStackView(views: [itermRadio, weztermRadio])
        radioRow.orientation = .horizontal
        radioRow.spacing = 16
        stack.addArrangedSubview(radioRow)

        permissionSection.orientation = .vertical
        permissionSection.alignment = .leading
        permissionSection.spacing = 14
        permissionSection.addArrangedSubview(separator())
        permissionSection.addArrangedSubview(sectionLabel("iTerm2 제어 권한"))
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
        stack.addArrangedSubview(permissionSection)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionLabel("동작 테스트"))
        stack.addArrangedSubview(helpLabel("선택한 터미널 새 탭에서 echo 명령이 실행되면 정상입니다."))
        stack.addArrangedSubview(buttonRow([
            button("터미널에서 테스트", #selector(testTerminal)),
        ]))
        testResultLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(testResultLabel)

        for label in [manifestStatusLabel, extensionStatusLabel, permissionStatusLabel] {
            label.font = .systemFont(ofSize: 13)
        }

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 600),
            extensionPathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])
        return stack
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func helpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 560
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

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return box
    }

    // MARK: - 터미널 선택

    @objc private func terminalChanged() {
        Settings.terminal = weztermRadio.state == .on ? "wezterm" : "iterm"
        updateTerminalControls()
        refresh()
    }

    /// 라디오 상태를 설정과 동기화하고, iTerm2 선택 시에만 권한 섹션을 표시한다
    private func updateTerminalControls() {
        (Settings.terminal == "wezterm" ? weztermRadio : itermRadio)?.state = .on
        permissionSection.isHidden = Settings.terminal != "iterm"
        if let window, let contentView = window.contentView {
            window.setContentSize(contentView.fittingSize)
        }
    }

    // MARK: - 상태 갱신

    private func refresh() {
        apply(Installer.manifestState(), to: manifestStatusLabel)
        apply(Installer.extensionState(), to: extensionStatusLabel)
        extensionPathLabel.stringValue = "폴더: \(Installer.extensionDirectory)"
        extensionIDLabel.stringValue = "확장 ID: \(Installer.currentExtensionID)"

        guard Settings.terminal == "iterm" else { return } // 권한 섹션이 숨겨져 있으면 확인 불필요
        if PermissionChecker.isITermInstalled {
            let status = PermissionChecker.iTermAutomationStatus()
            let state: SetupState = status.isGranted ? .ok(status.label) : .warning(status.label)
            apply(state, to: permissionStatusLabel, prefix: "iTerm2 자동화: ")
        } else {
            apply(.warning("iTerm2가 설치되어 있지 않음"), to: permissionStatusLabel, prefix: "iTerm2 자동화: ")
        }
    }

    private func apply(_ state: SetupState, to label: NSTextField, prefix: String = "") {
        switch state {
        case .ok(let message):
            label.stringValue = "● \(prefix)\(message)"
            label.textColor = .systemGreen
        case .warning(let message):
            label.stringValue = "● \(prefix)\(message)"
            label.textColor = .systemOrange
        case .error(let message):
            label.stringValue = "● \(prefix)\(message)"
            label.textColor = .systemRed
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
        installFeedbackLabel.stringValue = "경로가 클립보드에 복사되었고 Chrome이 열렸습니다. 위 ①→④ 순서대로 진행하세요."
        installFeedbackLabel.textColor = .systemBlue
        refresh()
    }

    @objc private func openOptionsPage() {
        openInChrome(Installer.optionsPageURL)
    }

    @objc private func requestPermission() {
        requestPermissionButton.isEnabled = false
        permissionStatusLabel.stringValue = "● iTerm2 자동화: 권한 프롬프트 응답 대기 중…"
        permissionStatusLabel.textColor = .secondaryLabelColor
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

    @objc private func testTerminal() {
        let terminal = Settings.terminal
        testResultLabel.stringValue = "실행 중…"
        DispatchQueue.global().async { [weak self] in
            var failure: Error?
            do {
                try runInTerminal(command: "echo 'Terminal Checkout: 연결 OK'", terminal: terminal)
            } catch {
                failure = error
            }
            DispatchQueue.main.async {
                if let failure {
                    self?.testResultLabel.stringValue = "실패: \(errorMessage(failure))"
                    self?.testResultLabel.textColor = .systemRed
                } else {
                    self?.testResultLabel.stringValue = "터미널에 새 탭이 열렸다면 성공입니다."
                    self?.testResultLabel.textColor = .secondaryLabelColor
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
