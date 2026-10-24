import AppKit

extension NSPasteboard.PasteboardType {
    static let claymoreTask = NSPasteboard.PasteboardType("com.claymore.task")
    /// Full text of a note dragged from the notes list.
    static let claymoreNote = NSPasteboard.PasteboardType("com.claymore.note")
}

/// A task card. Drawn directly (no subviews) so rows stay cheap to create and scroll.
final class CardView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("card")

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let detailFont = NSFont.systemFont(ofSize: 12)
    private static let padX: CGFloat = 12
    private static let padY: CGFloat = 9
    /// Space above and below the hairline between title and description.
    private static let dividerPad: CGFloat = 6
    private static let marginX: CGFloat = 2
    private static let marginY: CGFloat = 3
    private static let maxTitleLines: CGFloat = 4
    private static let maxDetailLines: CGFloat = 3
    private static let titleLine = NSLayoutManager().defaultLineHeight(for: titleFont)
    private static let detailLine = NSLayoutManager().defaultLineHeight(for: detailFont)

    var task = TaskItem(title: "")
    var isDone = false

    override var isFlipped: Bool { true }

    private static func displayTitle(_ t: TaskItem) -> String {
        t.title.isEmpty ? "Untitled" : t.title
    }

    private static func measure(_ s: String, font: NSFont, width: CGFloat, line: CGFloat, maxLines: CGFloat) -> CGFloat {
        let r = (s as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return min(ceil(r.height), ceil(line * maxLines))
    }

    private static func textWidth(_ rowWidth: CGFloat) -> CGFloat {
        max(40, rowWidth - 2 * marginX - 2 * padX)
    }

    static func height(for t: TaskItem, width: CGFloat) -> CGFloat {
        let w = textWidth(width)
        var h = 2 * marginY + 2 * padY
            + measure(displayTitle(t), font: titleFont, width: w, line: titleLine, maxLines: maxTitleLines)
        if !t.detail.isEmpty {
            h += 2 * dividerPad + 1 + measure(t.detail, font: detailFont, width: w, line: detailLine, maxLines: maxDetailLines)
        }
        return ceil(h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = isInSelectedRow
        let card = bounds.insetBy(dx: Self.marginX, dy: Self.marginY)
        Draw.roundedBox(card, radius: 9, fill: Theme.card,
                        stroke: selected ? .controlAccentColor : Theme.cardBorder, lineWidth: selected ? 1.5 : 1)
        if let color = Theme.priorityColor(task.priority) {
            color.setFill()
            let stripe = NSRect(x: card.minX + 5, y: card.minY + Self.padY, width: 3, height: card.height - 2 * Self.padY)
            NSBezierPath(roundedRect: stripe, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let w = Self.textWidth(bounds.width)
        let x = card.minX + Self.padX
        var y = card.minY + Self.padY

        let title = Self.displayTitle(task)
        var titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: (isDone || task.title.isEmpty) ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        if isDone { titleAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let th = Self.measure(title, font: Self.titleFont, width: w, line: Self.titleLine, maxLines: Self.maxTitleLines)
        Draw.text(title, in: NSRect(x: x, y: y, width: w, height: th), titleAttrs)

        guard !task.detail.isEmpty else { return }
        y += th + Self.dividerPad
        Theme.cardBorder.setFill()
        NSRect(x: x, y: y, width: w, height: 1).fill()
        y += 1 + Self.dividerPad
        let dh = Self.measure(task.detail, font: Self.detailFont, width: w, line: Self.detailLine, maxLines: Self.maxDetailLines)
        Draw.text(task.detail, in: NSRect(x: x, y: y, width: w, height: dh),
                  [.font: Self.detailFont, .foregroundColor: NSColor.secondaryLabelColor])
    }
}

final class CardTableView: NSTableView {
    weak var column: ColumnView?

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 51, 117: column?.deleteSelected()                         // delete, fwd-delete
        case 36, 76: column?.editSelected()                            // return, enter
        case 123: cmd ? column?.shiftSelected(-1) : column?.focusNeighbor(-1) // ←
        case 124: cmd ? column?.shiftSelected(1) : column?.focusNeighbor(1)   // →
        case 126 where selectedRow <= 0: column?.focusAddField()       // ↑ at top
        case 53: deselectAll(nil)                                      // esc
        default: super.keyDown(with: event)
        }
    }

    // Card heights depend on width, so re-measure when the column is resized.
    // Deferred: the table may be mid-layout when its frame changes.
    private var heightsPending = false

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        guard widthChanged, numberOfRows > 0, !heightsPending else { return }
        heightsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            heightsPending = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                self.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<self.numberOfRows))
            }
        }
    }
}
