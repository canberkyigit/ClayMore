import AppKit

// Shared setup for the few control styles ClayMore uses, so every list, input and editor looks the same.

extension NSTableView {
    /// Single-column, headerless, transparent list (task cards, note titles).
    func configureAsPlainList() {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.resizingMask = .autoresizingMask
        addTableColumn(col)
        headerView = nil
        style = .plain
        backgroundColor = .clear
        intercellSpacing = .zero
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        focusRingType = .none
    }

    func reusableView<T: NSView>(_ id: NSUserInterfaceItemIdentifier, make: () -> T) -> T {
        if let view = makeView(withIdentifier: id, owner: nil) as? T { return view }
        let view = make()
        view.identifier = id
        return view
    }
}

extension NSScrollView {
    /// Transparent, auto-hiding vertical scroller; ignores the transparent title bar's insets.
    func configurePlain() {
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
    }
}

extension NSTextField {
    /// Single-line input with no border, background or focus ring.
    static func bareInput(font: NSFont) -> NSTextField {
        let field = NSTextField()
        field.font = font
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }
}

extension NSTextView {
    /// Plain text with every "smart" substitution off.
    func configurePlainText() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
    }
}

extension NSView {
    /// For cells hosted in a `PlainRowView`, which leaves selection drawing to them.
    var isInSelectedRow: Bool { (superview as? NSTableRowView)?.isSelected == true }
}

/// Row view that leaves all drawing (including selection) to its cell.
final class PlainRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet { subviews.forEach { $0.needsDisplay = true } }
    }
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
}

enum Draw {
    /// Rounded box with a hairline border, inset so the stroke stays crisp.
    static func roundedBox(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor, lineWidth: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// Wrapped text clipped to `rect`, with an ellipsis on the last visible line.
    static func text(_ s: String, in rect: NSRect, _ attributes: [NSAttributedString.Key: Any]) {
        (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}
