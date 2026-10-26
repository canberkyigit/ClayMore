import AppKit

final class BoardView: FlippedView {
    private(set) var columns: [ColumnView] = []
    private var popover: NSPopover?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for i in 0..<3 {
            let c = ColumnView(index: i, board: self)
            columns.append(c)
            addSubview(c)
        }
        resizeSubviews(withOldSize: .zero)
        // Archiving and restoring change the Done column.
        NotificationCenter.default.addObserver(forName: Store.archiveDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.columns[2].reload()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let left: CGFloat = 12, right: CGFloat = 12, gap: CGFloat = 10, bottom: CGFloat = 12
        let w = floor((bounds.width - left - right - 2 * gap) / 3)
        let h = max(0, bounds.height - Theme.topInset - bottom)
        for (i, c) in columns.enumerated() {
            c.frame = NSRect(x: left + CGFloat(i) * (w + gap), y: Theme.topInset, width: w, height: h)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.windowBG.setFill()
        dirtyRect.fill()
        // Board | Notes separator, right next to the (invisible) split divider, spanning the panels only.
        Theme.divider.setFill()
        NSRect(x: bounds.maxX - 1, y: Theme.topInset, width: 1, height: max(0, bounds.height - Theme.topInset - 12)).fill()
    }

    // MARK: - Focus

    func focus(column c: Int) {
        guard (0..<3).contains(c) else { return }
        let col = columns[c]
        let selected = col.table.selectedRow
        if selected >= 0 && !col.table.hiddenRowIndexes.contains(selected) {
            col.select(row: selected, focus: true)
        } else if let row = col.firstVisibleRow {
            col.select(row: row, focus: true)
        } else {
            col.focusAddField()
        }
    }

    // MARK: - Search

    /// Called before a task is added, so an active search doesn't hide the new card.
    var onAdd: (() -> Void)?

    func applySearch() { columns.forEach { $0.applySearch() } }

    /// Selects the first matching card (↩ / ↓ in the search field when no note matches).
    func focusFirstMatch() -> Bool {
        guard let col = columns.first(where: { $0.firstVisibleRow != nil }), let row = col.firstVisibleRow else { return false }
        col.select(row: row, focus: true)
        return true
    }

    // MARK: - Mutations

    func moveTask(_ id: UUID, to column: Int, row: Int) {
        guard let result = Store.shared.move(id, to: column, row: row) else { return }
        columns[result.from].reload()
        if result.from != column { columns[column].reload() }
        columns[column].select(row: result.row, focus: true)
    }

    /// Creates a task from note text (a dropped note or a selection); the note itself is kept.
    @discardableResult
    func createTask(fromNote text: String, column c: Int, row: Int, focus: Bool = true) -> Bool {
        let parts = Store.taskParts(fromNote: text)
        guard !parts.title.isEmpty else { return false }
        onAdd?()
        Store.shared.insert(TaskItem(title: parts.title, detail: parts.detail), column: c, row: row)
        columns[c].reload()
        columns[c].select(row: min(row, columns[c].table.numberOfRows - 1), focus: focus)
        return true
    }

    func archive(column c: Int, row: Int) {
        Store.shared.archiveTask(column: c, row: row)
        columns[c].select(row: min(row, columns[c].table.numberOfRows - 1), focus: false)
    }

    func archiveDone() { Store.shared.archiveDone() }

    func delete(column c: Int, row: Int) {
        let task = Store.shared.remove(column: c, row: row)
        columns[c].reload()
        columns[c].select(row: min(row, columns[c].table.numberOfRows - 1), focus: false)
        undoManager?.registerUndo(withTarget: self) { board in
            Store.shared.insert(task, column: c, row: row)
            board.columns[c].reload()
            board.columns[c].select(row: row, focus: true)
        }
        undoManager?.setActionName("Delete Task")
    }

    // MARK: - Editing

    func edit(column c: Int, row: Int, focusDetail: Bool = false) {
        guard row >= 0, row < Store.shared.columns[c].count else { return }
        popover?.close()

        let editor = TaskEditor(task: Store.shared.columns[c][row], focusDetail: focusDetail)
        editor.onCommit = { [weak self] id, title, detail, priority in
            if let changed = Store.shared.update(id, title: title, detail: detail, priority: priority) {
                self?.columns[changed].reload()
            }
        }
        editor.onClose = { [weak self] in self?.popover = nil }

        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        p.contentViewController = editor
        p.delegate = editor
        editor.popover = p
        popover = p

        let table = columns[c].table
        table.scrollRowToVisible(row)
        p.show(relativeTo: table.rect(ofRow: row), of: table, preferredEdge: .maxX)
    }
}
