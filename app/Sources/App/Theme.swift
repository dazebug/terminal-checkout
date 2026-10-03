import AppKit

/// Fixed colors and type choices shared by the app's settings panes.
enum Theme {
    /// Window, panel and preview-chip surfaces use progressively darker backgrounds.
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
