import AppKit
import Core

/// The schematic on the right side of the General pane. Later panes add their own render modes to
/// this view so the preview and the sentence under it stay driven by the same value model.
final class SetupWindowPreviewView: NSView {
    private(set) var model: SetupWindowGeneralPreview
    private(set) var effectDescription: String

    init(model: SetupWindowGeneralPreview) {
        self.model = model
        effectDescription = Self.description(for: model)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ model: SetupWindowGeneralPreview) {
        self.model = model
        effectDescription = Self.description(for: model)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let outer = bounds.insetBy(dx: 1, dy: 1)
        let frame = NSBezierPath(roundedRect: outer, xRadius: 10, yRadius: 10)
        Theme.panel.setFill()
        Theme.border.setStroke()
        frame.lineWidth = 1
        frame.fill()
        frame.stroke()

        let label = localized("app.setup.preview.general.mockWindow")
        (label as NSString).draw(
            in: NSRect(x: 14, y: 10, width: max(0, bounds.width - 28), height: 18),
            withAttributes: [
                .font: Theme.ui(11, .semibold),
                .foregroundColor: Theme.textDim,
            ]
        )

        if model.frontmostScreen == .existingScreen {
            drawTerminalWindow(in: terminalFrame(for: .newTerminalSession, behind: true))
            drawCurrentScreen(in: currentScreenFrame)
        } else {
            drawCurrentScreen(in: currentScreenFrame.offsetBy(dx: 0, dy: 3))
            drawTerminalWindow(in: terminalFrame(for: .newTerminalSession, behind: false))
        }
    }

    private var currentScreenFrame: NSRect {
        NSRect(x: 30, y: 52, width: max(110, bounds.width - 60), height: max(96, bounds.height - 67))
    }

    private func terminalFrame(for screen: SetupWindowFrontmostScreen, behind: Bool) -> NSRect {
        if behind {
            return NSRect(x: 13, y: 45, width: max(100, bounds.width - 42), height: max(92, bounds.height - 60))
        }
        return NSRect(x: 19, y: 38, width: max(108, bounds.width - 40), height: max(98, bounds.height - 51))
    }

    private func drawTerminalWindow(in rect: NSRect) {
        let window = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        Theme.bg.setFill()
        Theme.border.setStroke()
        window.lineWidth = 1
        window.fill()
        window.stroke()

        let barHeight: CGFloat = 23
        let bar = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: barHeight), xRadius: 7, yRadius: 7)
        Theme.chipBg.setFill()
        bar.fill()
        drawWindowLights(at: NSPoint(x: rect.minX + 10, y: rect.minY + 8))

        let title = terminalName(model.terminal)
        (title as NSString).draw(
            in: NSRect(x: rect.minX + 45, y: rect.minY + 5, width: rect.width - 56, height: 14),
            withAttributes: [
                .font: Theme.ui(9, .medium),
                .foregroundColor: Theme.textFaint,
            ]
        )

        var content = NSRect(x: rect.minX + 8, y: rect.minY + barHeight + 5, width: rect.width - 16, height: rect.height - barHeight - 13)
        if model.destination == .newWorkspace {
            drawWorkspaceSidebar(in: &content)
        } else {
            drawTabStrip(in: &content)
        }
        drawTerminalPrompt(in: content)
    }

    private func drawWindowLights(at point: NSPoint) {
        let colors = [Theme.err, Theme.warn, Theme.ok]
        for (index, color) in colors.enumerated() {
            let circle = NSBezierPath(ovalIn: NSRect(x: point.x + CGFloat(index) * 8, y: point.y, width: 5, height: 5))
            color.setFill()
            circle.fill()
        }
    }

    private func drawTabStrip(in content: inout NSRect) {
        let height: CGFloat = 17
        let tabBar = NSBezierPath(roundedRect: NSRect(x: content.minX, y: content.minY, width: content.width, height: height), xRadius: 4, yRadius: 4)
        Theme.panel.setFill()
        tabBar.fill()
        drawText(
            localized("app.setup.preview.general.originalTab"),
            in: NSRect(x: content.minX + 7, y: content.minY + 2, width: content.width * 0.38, height: 12),
            color: Theme.textFaint
        )
        drawText(
            localized("app.setup.preview.general.newTab"),
            in: NSRect(x: content.minX + content.width * 0.43, y: content.minY + 2, width: content.width * 0.42, height: 12),
            color: Theme.text
        )
        content.origin.y += height + 4
        content.size.height -= height + 4
    }

    private func drawWorkspaceSidebar(in content: inout NSRect) {
        let width = min(62, max(48, content.width * 0.28))
        let sidebar = NSBezierPath(roundedRect: NSRect(x: content.minX, y: content.minY, width: width, height: content.height), xRadius: 4, yRadius: 4)
        Theme.panel.setFill()
        sidebar.fill()
        for row in 0..<2 {
            let y = content.minY + 10 + CGFloat(row) * 15
            let bar = NSBezierPath(roundedRect: NSRect(x: content.minX + 8, y: y, width: width - 16, height: 4), xRadius: 2, yRadius: 2)
            Theme.textFaint.withAlphaComponent(0.6).setFill()
            bar.fill()
        }
        let selected = NSBezierPath(roundedRect: NSRect(x: content.minX + 4, y: content.minY + 39, width: width - 8, height: 17), xRadius: 3, yRadius: 3)
        Theme.border.setFill()
        selected.fill()
        drawText(
            localized("app.cmux.placement.identity.alwaysNew"),
            in: NSRect(x: content.minX + 6, y: content.minY + 42, width: width - 12, height: 12),
            color: Theme.text
        )
        content.origin.x += width + 5
        content.size.width -= width + 5
    }

    private func drawTerminalPrompt(in rect: NSRect) {
        let terminal = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        Theme.chipBg.setFill()
        terminal.fill()
        drawText(
            ">_",
            in: NSRect(x: rect.minX + 9, y: rect.minY + 8, width: 22, height: 19),
            color: Theme.ok,
            font: Theme.mono(13, .semibold)
        )
        for index in 0..<3 {
            let width = max(24, rect.width * (index == 1 ? 0.47 : 0.65))
            let line = NSBezierPath(roundedRect: NSRect(x: rect.minX + 10, y: rect.minY + 35 + CGFloat(index) * 9, width: width, height: 2), xRadius: 1, yRadius: 1)
            Theme.textFaint.withAlphaComponent(index == 0 ? 0.65 : 0.35).setFill()
            line.fill()
        }
    }

    private func drawCurrentScreen(in rect: NSRect) {
        let screen = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        Theme.panel.setFill()
        Theme.border.setStroke()
        screen.lineWidth = 1
        screen.fill()
        screen.stroke()
        let title = localized("app.setup.preview.general.currentScreen")
        (title as NSString).draw(
            in: NSRect(x: rect.minX + 12, y: rect.minY + 11, width: rect.width - 24, height: 16),
            withAttributes: [
                .font: Theme.ui(10, .medium),
                .foregroundColor: Theme.textDim,
            ]
        )
        for index in 0..<3 {
            let width = rect.width * (index == 1 ? 0.49 : 0.72)
            let line = NSBezierPath(roundedRect: NSRect(x: rect.minX + 12, y: rect.minY + 39 + CGFloat(index) * 10, width: width, height: 2), xRadius: 1, yRadius: 1)
            Theme.textFaint.withAlphaComponent(0.5).setFill()
            line.fill()
        }
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor, font: NSFont = Theme.ui(8)) {
        (text as NSString).draw(
            in: rect,
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }

    private static func description(for model: SetupWindowGeneralPreview) -> String {
        let destination: String
        switch model.destination {
        case .newTab: destination = localized("app.setup.preview.general.destination.tab")
        case .newWorkspace: destination = localized("app.setup.preview.general.destination.workspace")
        }
        let frontmost: String
        switch model.frontmostScreen {
        case .newTerminalSession: frontmost = localized("app.setup.preview.general.frontmost.terminal")
        case .existingScreen: frontmost = localized("app.setup.preview.general.frontmost.current")
        }
        return localized("app.setup.preview.general.accessibility", destination, frontmost)
    }
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
