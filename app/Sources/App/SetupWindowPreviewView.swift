import AppKit
import Core

/// The schematic on the right side of the General pane. Later panes add their own render modes to
/// this view so the preview and the sentence under it stay driven by the same value model.
final class SetupWindowPreviewView: NSView {
    private var generalModel: SetupWindowGeneralPreview?
    private var githubModel: SetupWindowGitHubPreview?
    private var slackModel: SetupWindowSlackPreview?
    private(set) var effectDescription: String

    init(model: SetupWindowGeneralPreview) {
        generalModel = model
        githubModel = nil
        slackModel = nil
        effectDescription = Self.description(for: model)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
    }

    init(githubModel: SetupWindowGitHubPreview) {
        self.generalModel = nil
        self.githubModel = githubModel
        self.slackModel = nil
        effectDescription = Self.description(for: githubModel)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
    }

    init(slackModel: SetupWindowSlackPreview) {
        generalModel = nil
        githubModel = nil
        self.slackModel = slackModel
        effectDescription = Self.description(for: slackModel)
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
        generalModel = model
        githubModel = nil
        slackModel = nil
        effectDescription = Self.description(for: model)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
        needsDisplay = true
    }

    func update(githubModel: SetupWindowGitHubPreview) {
        generalModel = nil
        self.githubModel = githubModel
        slackModel = nil
        effectDescription = Self.description(for: githubModel)
        setAccessibilityLabel(effectDescription)
        setAccessibilityHelp(effectDescription)
        needsDisplay = true
    }

    func update(slackModel: SetupWindowSlackPreview) {
        generalModel = nil
        githubModel = nil
        self.slackModel = slackModel
        effectDescription = Self.description(for: slackModel)
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

        let label: String
        if generalModel != nil {
            label = localized("app.setup.preview.general.mockWindow")
        } else if githubModel != nil {
            label = localized("app.setup.preview.github.windowCaption")
        } else {
            label = localized("app.setup.preview.slack.windowCaption")
        }
        (label as NSString).draw(
            in: NSRect(x: 14, y: 10, width: max(0, bounds.width - 28), height: 18),
            withAttributes: [
                .font: Theme.ui(11, .semibold),
                .foregroundColor: Theme.textDim,
            ]
        )

        if let generalModel {
            if generalModel.frontmostScreen == .existingScreen {
                drawTerminalWindow(
                    in: terminalFrame(for: .newTerminalSession, behind: true), model: generalModel
                )
                drawCurrentScreen(in: currentScreenFrame)
            } else {
                drawCurrentScreen(in: currentScreenFrame.offsetBy(dx: 0, dy: 3))
                drawTerminalWindow(
                    in: terminalFrame(for: .newTerminalSession, behind: false), model: generalModel
                )
            }
        } else if let githubModel {
            drawGitHubPreview(githubModel)
        } else if let slackModel {
            drawSlackPreview(slackModel)
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

    private func drawTerminalWindow(in rect: NSRect, model: SetupWindowGeneralPreview) {
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

    private static func description(for model: SetupWindowGitHubPreview) -> String {
        localized(
            "app.setup.preview.github.accessibility",
            setupWindowGitHubEffectSentence(model.effectSentence)
        )
    }

    private static func description(for model: SetupWindowSlackPreview) -> String {
        let destination = model.destination == .newWorkspace
            ? localized("app.setup.preview.general.destination.workspace")
            : localized("app.setup.preview.general.destination.tab")
        return localized("app.setup.preview.slack.accessibility", destination)
    }

    private func drawSlackPreview(_ model: SetupWindowSlackPreview) {
        let rect = NSRect(
            x: 18, y: 35, width: max(145, bounds.width - 36), height: max(132, bounds.height - 47)
        )
        let window = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        Theme.bg.setFill()
        Theme.border.setStroke()
        window.lineWidth = 1
        window.fill()
        window.stroke()

        let barHeight: CGFloat = 22
        let bar = NSBezierPath(roundedRect: NSRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: barHeight
        ), xRadius: 7, yRadius: 7)
        Theme.chipBg.setFill()
        bar.fill()
        drawWindowLights(at: NSPoint(x: rect.minX + 10, y: rect.minY + 8))
        drawText(
            terminalName(model.terminal),
            in: NSRect(x: rect.minX + 42, y: rect.minY + 4, width: rect.width - 50, height: 14),
            color: Theme.textFaint,
            font: Theme.ui(8, .medium)
        )

        var content = NSRect(
            x: rect.minX + 7, y: rect.minY + barHeight + 5,
            width: rect.width - 14, height: rect.height - barHeight - 12
        )
        if model.destination == .newWorkspace {
            drawWorkspaceSidebar(in: &content)
        } else {
            drawTabStrip(in: &content)
        }

        let prompt = NSBezierPath(roundedRect: content, xRadius: 4, yRadius: 4)
        Theme.chipBg.setFill()
        prompt.fill()
        drawText(
            localized("app.setup.slack.workDirectory.label"),
            in: NSRect(x: content.minX + 8, y: content.minY + 5, width: content.width - 16, height: 13),
            color: Theme.textFaint,
            font: Theme.ui(8)
        )
        drawText(
            ">_",
            in: NSRect(x: content.minX + 8, y: content.minY + 22, width: 22, height: 16),
            color: Theme.ok,
            font: Theme.mono(10, .semibold)
        )
        let commandStyle = NSMutableParagraphStyle()
        commandStyle.lineBreakMode = .byWordWrapping
        (localized("app.setup.preview.slack.command") as NSString).draw(
            in: NSRect(x: content.minX + 8, y: content.minY + 42, width: content.width - 16, height: 27),
            withAttributes: [
                .font: Theme.mono(7),
                .foregroundColor: Theme.text,
                .paragraphStyle: commandStyle,
            ]
        )
        for index in 0..<2 {
            let line = NSBezierPath(roundedRect: NSRect(
                x: content.minX + 9,
                y: content.minY + 73 + CGFloat(index) * 9,
                width: content.width * (index == 0 ? 0.68 : 0.44),
                height: 2
            ), xRadius: 1, yRadius: 1)
            Theme.textFaint.withAlphaComponent(0.42).setFill()
            line.fill()
        }
    }

    private func drawGitHubPreview(_ model: SetupWindowGitHubPreview) {
        let rect = NSRect(
            x: 9, y: 30, width: max(150, bounds.width - 18), height: max(130, bounds.height - 40)
        )
        let window = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        Theme.bg.setFill()
        Theme.border.setStroke()
        window.lineWidth = 1
        window.fill()
        window.stroke()

        let barHeight: CGFloat = 22
        let bar = NSBezierPath(roundedRect: NSRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: barHeight
        ), xRadius: 7, yRadius: 7)
        Theme.chipBg.setFill()
        bar.fill()
        drawWindowLights(at: NSPoint(x: rect.minX + 10, y: rect.minY + 8))
        drawText(
            localized("app.setup.preview.github.listWindow"),
            in: NSRect(x: rect.minX + 42, y: rect.minY + 4, width: rect.width - 50, height: 14),
            color: Theme.textFaint,
            font: Theme.ui(8, .medium)
        )

        var content = NSRect(
            x: rect.minX + 7, y: rect.minY + barHeight + 5,
            width: rect.width - 14, height: rect.height - barHeight - 12
        )
        switch model.destination {
        case .newTabPerRow:
            drawGitHubTabs(in: &content, includesOriginalTab: true, rowNumbers: model.rowNumbers)
            drawGitHubRowPane(in: content, row: model.rowNumbers.first ?? 1)
        case .cmux(let arrangement, _, let preservesExistingPaneAndTab):
            let name = githubNamedWorkspace(in: model)
            drawGitHubWorkspaceSidebar(
                in: &content,
                arrangement: arrangement,
                namedWorkspace: name
            )
            switch arrangement {
            case .panePerItem:
                drawGitHubPanes(
                    in: content,
                    rowNumbers: model.rowNumbers,
                    preservesExistingPane: preservesExistingPaneAndTab
                )
            case .tabPerItem:
                drawGitHubTabs(
                    in: &content,
                    includesOriginalTab: preservesExistingPaneAndTab,
                    rowNumbers: model.rowNumbers
                )
                drawGitHubRowPane(in: content, row: model.rowNumbers.first ?? 1)
            case .workspacePerItem:
                drawGitHubRowPane(in: content, row: model.rowNumbers.first ?? 1)
            }
        }
    }

    private func githubNamedWorkspace(in model: SetupWindowGitHubPreview) -> String? {
        guard case .githubCmuxBatch(_, _, .fixedName(let name)) = model.effectSentence else {
            return nil
        }
        return name
    }

    private func drawGitHubWorkspaceSidebar(
        in content: inout NSRect,
        arrangement: CmuxPlacementArrangement,
        namedWorkspace: String?
    ) {
        let width = min(65, max(52, content.width * 0.31))
        let sidebar = NSBezierPath(roundedRect: NSRect(
            x: content.minX, y: content.minY, width: width, height: content.height
        ), xRadius: 4, yRadius: 4)
        Theme.panel.setFill()
        sidebar.fill()

        let oldWorkspace = NSBezierPath(roundedRect: NSRect(
            x: content.minX + 6, y: content.minY + 8, width: width - 12, height: 14
        ), xRadius: 3, yRadius: 3)
        Theme.textFaint.withAlphaComponent(0.22).setFill()
        oldWorkspace.fill()
        drawText(
            "…",
            in: NSRect(x: content.minX + 10, y: content.minY + 8, width: width - 20, height: 12),
            color: Theme.textFaint
        )

        if arrangement == .workspacePerItem {
            for (index, number) in [1, 2, 3].enumerated() {
                drawWorkspaceRow(
                    number: number,
                    name: nil,
                    selected: index == 0,
                    in: NSRect(
                        x: content.minX + 4, y: content.minY + 29 + CGFloat(index) * 21,
                        width: width - 8, height: 17
                    )
                )
            }
        } else {
            drawWorkspaceRow(
                number: nil,
                name: namedWorkspace,
                selected: true,
                in: NSRect(x: content.minX + 4, y: content.minY + 29, width: width - 8, height: 18)
            )
        }
        content.origin.x += width + 5
        content.size.width -= width + 5
    }

    private func drawWorkspaceRow(number: Int?, name: String?, selected: Bool, in rect: NSRect) {
        if selected {
            let row = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            Theme.border.setFill()
            row.fill()
        } else {
            let row = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 6), xRadius: 2, yRadius: 2)
            Theme.textFaint.withAlphaComponent(0.4).setFill()
            row.fill()
        }
        let title = name ?? number.map { "\($0)" }
            ?? localized("app.cmux.placement.identity.alwaysNew")
        drawText(title, in: rect.insetBy(dx: 4, dy: 2), color: selected ? Theme.text : Theme.textFaint)
    }

    private func drawGitHubTabs(in content: inout NSRect, includesOriginalTab: Bool, rowNumbers: [Int]) {
        let height: CGFloat = 18
        let tabBar = NSBezierPath(roundedRect: NSRect(
            x: content.minX, y: content.minY, width: content.width, height: height
        ), xRadius: 4, yRadius: 4)
        Theme.panel.setFill()
        tabBar.fill()
        var x = content.minX + 5
        if includesOriginalTab {
            drawText(
                localized("app.setup.preview.general.originalTab"),
                in: NSRect(x: x, y: content.minY + 3, width: 42, height: 11),
                color: Theme.textFaint
            )
            x += 44
        }
        let availableWidth = max(24, (content.maxX - x - 5) / CGFloat(max(1, rowNumbers.count)))
        for (index, number) in rowNumbers.enumerated() {
            let isSelected = index == 0
            if isSelected {
                let selected = NSBezierPath(roundedRect: NSRect(
                    x: x, y: content.minY + 1, width: availableWidth, height: height - 2
                ), xRadius: 3, yRadius: 3)
                Theme.border.setFill()
                selected.fill()
            }
            drawText(
                "\(number)",
                in: NSRect(x: x + 4, y: content.minY + 3, width: max(12, availableWidth - 7), height: 11),
                color: isSelected ? Theme.text : Theme.textFaint
            )
            x += availableWidth
        }
        content.origin.y += height + 4
        content.size.height -= height + 4
    }

    private func drawGitHubPanes(in rect: NSRect, rowNumbers: [Int], preservesExistingPane: Bool) {
        let rows = preservesExistingPane ? [0] + rowNumbers : rowNumbers
        let columns = 2
        let cellWidth = max(32, (rect.width - 4) / CGFloat(columns))
        let cellHeight = max(28, (rect.height - 4) / 2)
        for (index, row) in rows.enumerated() {
            let column = index % columns
            let line = index / columns
            let cellRect = NSRect(
                x: rect.minX + CGFloat(column) * cellWidth,
                y: rect.minY + CGFloat(line) * cellHeight,
                width: cellWidth - 3,
                height: cellHeight - 3
            )
            let cell = NSBezierPath(roundedRect: cellRect, xRadius: 4, yRadius: 4)
            (row == 0 ? Theme.panel : Theme.chipBg).setFill()
            Theme.border.setStroke()
            cell.lineWidth = 1
            cell.fill()
            cell.stroke()
            let label = row == 0
                ? localized("app.setup.preview.github.originalPane")
                : "\(row)"
            drawText(
                label,
                in: NSRect(x: cellRect.minX + 6, y: cellRect.minY + 5, width: cellRect.width - 12, height: 12),
                color: row == 0 ? Theme.textFaint : Theme.text
            )
            if row == 0 {
                drawText(
                    localized("app.setup.preview.github.kept"),
                    in: NSRect(x: cellRect.minX + 6, y: cellRect.minY + 18, width: cellRect.width - 12, height: 12),
                    color: Theme.textFaint
                )
            } else {
                drawPrompt(in: NSRect(
                    x: cellRect.minX + 5, y: cellRect.minY + 19, width: 24, height: 16
                ))
            }
        }
    }

    private func drawGitHubRowPane(in rect: NSRect, row: Int) {
        let pane = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        Theme.chipBg.setFill()
        pane.fill()
        drawText(
            "\(row)",
            in: NSRect(x: rect.minX + 8, y: rect.minY + 7, width: 24, height: 13),
            color: Theme.text,
            font: Theme.ui(9, .medium)
        )
        drawPrompt(in: NSRect(x: rect.minX + 8, y: rect.minY + 24, width: 28, height: 18))
        for index in 0..<2 {
            let line = NSBezierPath(roundedRect: NSRect(
                x: rect.minX + 9, y: rect.minY + 48 + CGFloat(index) * 9,
                width: rect.width * (index == 0 ? 0.7 : 0.47), height: 2
            ), xRadius: 1, yRadius: 1)
            Theme.textFaint.withAlphaComponent(0.4).setFill()
            line.fill()
        }
    }

    private func drawPrompt(in rect: NSRect) {
        drawText(">_", in: rect, color: Theme.ok, font: Theme.mono(11, .semibold))
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
