import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

enum Theme {
    /// Height reserved for the transparent title bar (traffic lights).
    static let topInset: CGFloat = 38

    static let windowBG = NSColor.dynamic(light: 0xF2F2F5, dark: 0x131417)
    static let columnBG = NSColor.dynamic(light: 0xE8E8ED, dark: 0x1B1C20)
    static let inputBG = NSColor.dynamic(light: 0xF6F6F9, dark: 0x222328)
    static let card = NSColor.dynamic(light: 0xFFFFFF, dark: 0x27282E)
    static let cardBorder = NSColor.dynamic(light: 0xDADAE0, dark: 0x32333A)
    /// Note editor panel: white paper in light mode, a column-like panel in dark mode.
    static let notesBG = NSColor.dynamic(light: 0xFFFFFF, dark: 0x1B1C20)
    static let divider = NSColor.dynamic(light: 0xD2D2D8, dark: 0x34353C)

    static let accents: [NSColor] = [
        NSColor(hex: 0x5B8DEF), // Todo
        NSColor(hex: 0xF0A33A), // In Progress
        NSColor(hex: 0x3FBF7F), // Done
    ]

    /// Card stripe color per priority; `.none` draws nothing.
    static func priorityColor(_ p: Priority) -> NSColor? {
        switch p {
        case .none: nil
        case .low: NSColor(hex: 0x8E8E93)
        case .medium: NSColor(hex: 0xF29B38)
        case .high: NSColor(hex: 0xE5484D)
        }
    }

    static func headerString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
        ])
    }
}

/// Top-down coordinate container for manual layout.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
