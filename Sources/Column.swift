import AppKit

final class ColumnView: FlippedView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    let index: Int
    unowned let board: BoardView
    let table = CardTableView()
    let addField = NSTextField.bareInput(font: .systemFont(ofSize: 13))
    private let scroll = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    private var tasks: [TaskItem] { Store.shared.columns[index] }

    init(index: Int, board: BoardView) {
        self.index = index
        self.board = board
        super.init(frame: .zero)

        titleLabel.attributedStringValue = Theme.headerString(Store.columnTitles[index])
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        addSubview(titleLabel)
        addSubview(countLabel)

        addField.placeholderAttributedString = NSAttributedString(string: "+  Add task", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
        addField.delegate = self
        addSubview(addField)

        table.configureAsPlainList()
        table.column = self
        table.allowsTypeSelect = false
        table.registerForDraggedTypes([.claymoreTask, .claymoreNote])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu

        scroll.documentView = table
        scroll.configurePlain()
        addSubview(scroll)

        updateCount()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout & drawing

    private var inputRect: NSRect { NSRect(x: 8, y: 36, width: bounds.width - 16, height: 30) }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let w = bounds.width
        titleLabel.frame = NSRect(x: 28, y: 12, width: w - 76, height: 16)
        countLabel.frame = NSRect(x: w - 52, y: 12, width: 38, height: 16)
        let input = inputRect
        addField.frame = NSRect(x: input.minX + 10, y: input.minY + 7, width: input.width - 20, height: 17)
        scroll.frame = NSRect(x: 6, y: input.maxY + 6, width: w - 12, height: max(0, bounds.height - input.maxY - 10))
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.columnBG.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        Theme.accents[index].setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: 16, width: 8, height: 8)).fill()
        Theme.inputBG.setFill()
        NSBezierPath(roundedRect: inputRect, xRadius: 8, yRadius: 8).fill()

        if tasks.isEmpty {
            let s = NSAttributedString(string: index == 0 ? "Nothing to do 🎉" : "Drop tasks here", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            let size = s.size()
            s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: inputRect.maxY + 28))
        }
    }

    // MARK: - Data

    func reload() {
        table.reloadData()
        updateCount()
        needsDisplay = true
    }

    private func updateCount() {
        countLabel.stringValue = tasks.isEmpty ? "" : "\(tasks.count)"
    }

    func select(row: Int, focus: Bool) {
        guard row >= 0, row < table.numberOfRows else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        if focus { window?.makeFirstResponder(table) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tasks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let card = tableView.reusableView(CardView.reuseID) { CardView() }
        card.task = tasks[row]
        card.isDone = index == 2
        card.needsDisplay = true
        return card
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PlainRowView() }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        CardView.height(for: tasks[row], width: tableView.bounds.width)
    }

    // MARK: - Drag & drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(tasks[row].id.uuidString, forType: .claymoreTask)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard let type = info.draggingPasteboard.availableType(from: [.claymoreTask, .claymoreNote]) else { return [] }
        if op == .on { tableView.setDropRow(row, dropOperation: .above) }
        return type == .claymoreNote ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let pb = info.draggingPasteboard
        if let note = pb.string(forType: .claymoreNote) {
            return board.createTask(fromNote: note, column: index, row: row)
        }
        guard let s = pb.string(forType: .claymoreTask), let id = UUID(uuidString: s) else { return false }
        board.moveTask(id, to: index, row: row)
        return true
    }

    // MARK: - Actions

    @objc private func doubleClicked() {
        if table.clickedRow >= 0 { board.edit(column: index, row: table.clickedRow) } else { focusAddField() }
    }

    func editSelected() {
        if table.selectedRow >= 0 { board.edit(column: index, row: table.selectedRow) }
    }

    func deleteSelected() {
        if table.selectedRow >= 0 { board.delete(column: index, row: table.selectedRow) }
    }

    func shiftSelected(_ delta: Int) {
        let target = index + delta
        guard table.selectedRow >= 0, (0..<3).contains(target) else { return }
        board.moveTask(tasks[table.selectedRow].id, to: target, row: 0)
    }

    func focusNeighbor(_ delta: Int) { board.focus(column: index + delta) }

    func focusAddField() { window?.makeFirstResponder(addField) }

    // MARK: - Quick add field

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            let title = addField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return true }
            addField.stringValue = ""
            Store.shared.add(title, to: index)
            reload()
            // ⌘↩ adds and opens the editor to write a description.
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                board.edit(column: index, row: 0, focusDetail: true)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
            addField.stringValue = ""
            board.focus(column: index)
            return true
        case #selector(NSResponder.moveDown(_:)):
            if !tasks.isEmpty { select(row: max(0, table.selectedRow), focus: true) }
            return true
        default:
            return false
        }
    }

    // MARK: - Context menu

    private var isDoneColumn: Bool { index == 2 }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        if row >= 0 {
            menu.addItem(withTitle: "Edit", action: #selector(menuEdit), keyEquivalent: "").target = self
            menu.addItem(.separator())
            for c in 0..<3 where c != index {
                let item = menu.addItem(withTitle: "Move to \(Store.columnTitles[c])", action: #selector(menuMove(_:)), keyEquivalent: "")
                item.target = self
                item.tag = c
            }
            menu.addItem(.separator())
            menu.addItem(Export.menuItem(target: self, action: #selector(menuExport)))
            if isDoneColumn {
                menu.addItem(withTitle: "Archive", action: #selector(menuArchive), keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete", action: #selector(menuDelete), keyEquivalent: "").target = self
        }
        // Right-click anywhere in Done (card or empty space) to clear it.
        if isDoneColumn && !tasks.isEmpty {
            if row >= 0 { menu.addItem(.separator()) }
            menu.addItem(withTitle: "Archive All Done Tasks", action: #selector(menuArchiveAll), keyEquivalent: "").target = self
        }
    }

    @objc private func menuArchive() { board.archive(column: index, row: table.clickedRow) }
    @objc private func menuArchiveAll() { board.archiveDone() }

    @objc private func menuExport() {
        let task = tasks[table.clickedRow]
        Export.save(Export.taskText(task, column: index), name: task.title, from: window)
    }

    @objc private func menuEdit() { board.edit(column: index, row: table.clickedRow) }
    @objc private func menuMove(_ sender: NSMenuItem) { board.moveTask(tasks[table.clickedRow].id, to: sender.tag, row: 0) }
    @objc private func menuDelete() { board.delete(column: index, row: table.clickedRow) }
}
