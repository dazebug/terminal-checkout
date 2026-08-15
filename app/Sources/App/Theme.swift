import AppKit

/// 설정 창의 시각 시스템 — "설정 창 = 터미널 세션" 컨셉.
/// 색은 장식이 아니라 상태를 말할 때만 쓴다 (ANSI 의미색: 초록=정상, 노랑=확인 필요, 빨강=오류).
enum Theme {
    /// 배경 3단 레이어: 창 < 카드 < 칩 — "화면 속 화면"(코드 칩)이 가장 어둡다
    static let bg = hex(0x14161C)
    static let panel = hex(0x1B1E26)
    static let chipBg = hex(0x0E1014)
    static let border = hex(0x2A2F3A)

    static let text = hex(0xDEE3EC)
    static let textDim = hex(0x8B93A3)
    static let textFaint = hex(0x6B7484)

    static let ok = hex(0x4EC97B)
    static let warn = hex(0xE0B14E)
    static let err = hex(0xE06C75)
    static let accent = hex(0x56C2DC)
    /// GitHub 페이지에 삽입되는 확장 버튼과 같은 초록 — 두 화면의 브랜드 연속성
    static let actionGreen = hex(0x238636)

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    private static func hex(_ rgb: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 헤더의 파이프라인 스트립: Chrome 확장 ── relay ── 앱 ── 터미널.
/// 이 앱이 존재하는 이유(TCC 권한 분리 구조)를 그대로 그린 것이며, 각 점은 실제 상태로 점등된다.
final class PipelineStripView: NSView {
    struct Node {
        let label: String
        let color: NSColor
        let detail: String
    }

    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 미지원") }

    func update(_ nodes: [Node]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, node) in nodes.enumerated() {
            if index > 0 {
                let connector = NSTextField(labelWithString: "──")
                connector.font = Theme.mono(10)
                connector.textColor = Theme.textFaint
                stack.addArrangedSubview(connector)
            }
            stack.addArrangedSubview(nodeView(node))
        }
    }

    private func nodeView(_ node: Node) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = node.color.cgColor
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
        ])

        let label = NSTextField(labelWithString: node.label)
        label.font = Theme.mono(11)
        label.textColor = Theme.textDim

        let row = NSStackView(views: [dot, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.toolTip = node.detail
        return row
    }
}

/// 헤더 타이틀 뒤의 블록 커서. 시스템 '동작 줄이기' 설정 시 깜빡이지 않는다.
final class BlinkCursorView: NSTextField {
    private var timer: Timer?

    convenience init() {
        self.init(labelWithString: "▊")
        font = Theme.mono(15, .semibold)
        textColor = Theme.accent
    }

    func start() {
        stop()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.alphaValue = self.alphaValue < 0.5 ? 1 : 0.12
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        alphaValue = 1
    }
}
