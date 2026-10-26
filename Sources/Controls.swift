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
        field.configureBare(font: font)
        return field
    }

    func configureBare(font: NSFont) {
        self.font = font
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        cell?.isScrollable = true
        cell?.wraps = false
    }
}

/// The search box at the top: drawn like the "Add task" inputs, with a hairline accent
/// outline while focused instead of the thick system focus ring.
final class SearchBox: FlippedView {
    let field = FocusTrackingField()
    var onClear: (() -> Void)?
    private let clearButton = NSButton()
    private var focused = false { didSet { needsDisplay = true } }

    private static let icon = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor])))

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.configureBare(font: .systemFont(ofSize: 13))
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
        field.onFocusChange = { [weak self] in self?.focused = $0 }
        addSubview(field)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear Search")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        clearButton.isBordered = false
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.refusesFirstResponder = true
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isHidden = true
        addSubview(clearButton)
        resizeSubviews(withOldSize: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows the clear button only when there is something to clear.
    func textChanged() { clearButton.isHidden = field.stringValue.isEmpty }

    @objc private func clearClicked() { onClear?() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let h: CGFloat = 17
        field.frame = NSRect(x: 30, y: floor((bounds.height - h) / 2), width: max(0, bounds.width - 30 - 28), height: h)
        clearButton.frame = NSRect(x: bounds.width - 26, y: floor((bounds.height - 20) / 2), width: 20, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        Draw.roundedBox(bounds, radius: 8, fill: Theme.inputBG, stroke: focused ? .controlAccentColor : Theme.cardBorder)
        if let icon = Self.icon {
            let s = icon.size
            icon.draw(in: NSRect(x: 11, y: floor((bounds.height - s.height) / 2), width: s.width, height: s.height))
        }
    }

    // Clicking anywhere in the box (the icon, the padding) starts typing instead of dragging the window.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }
}

/// Text field that reports when it gains and loses keyboard focus.
final class FocusTrackingField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
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
