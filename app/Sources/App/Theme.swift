import AppKit

/// The setup window's visual system, built on one idea: the window *is* a terminal session.
/// Colour is never decoration — it is used only where it states a state, with the ANSI meanings
/// (green = fine, yellow = needs a look, red = error).
enum Theme {
    /// Three background layers: window < card < chip — the "screen within a screen" (a code chip)
    /// is the darkest
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
    /// The same green as the extension's buttons on a GitHub page — the two screens read as one product
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

/// The pipeline strip in the header: Chrome extension ── relay ── app ── terminal.
/// It draws the reason this app exists (the TCC permission split), and each dot lights up from the
/// real state rather than from a static picture.
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

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

/// The block cursor after the header title. It does not blink when the system's Reduce Motion
/// setting is on.
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
