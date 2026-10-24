import AppKit

/// Window listing archived tasks, newest first. Opened from the Archive menu and built on first use.
final class ArchiveWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let table = CardTableView()
    private let emptyLabel = NSTextField(labelWithString: "No archived tasks")

    private var items: [ArchivedTask] { Store.shared.archive }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = "Archive"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.columnBG
        window.minSize = NSSize(width: 300, height: 240)
        window.center()
        window.setFrameAutosaveName("ClayMoreArchive")
        super.init(window: window)

        let content = window.contentView!
        table.configureAsPlainList()
        table.dataSource = self
        table.delegate = self
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        let scroll = NSScrollView(frame: content.bounds.insetBy(dx: 8, dy: 8))
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = table
        scroll.configurePlain()
        content.addSubview(scroll)
        table.sizeLastColumnToFit() // the card column must span the window from the start

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: content.bounds.midY - 10, width: content.bounds.width, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        content.addSubview(emptyLabel)

        NotificationCenter.default.addObserver(forName: Store.archiveDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        table.reloadData()
        emptyLabel.isHidden = !items.isEmpty
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let card = tableView.reusableView(CardView.reuseID) { CardView() }
        card.task = items[row].task
        card.isDone = true
        card.needsDisplay = true
        return card
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PlainRowView() }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        CardView.height(for: items[row].task, width: tableView.bounds.width)
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard row >= 0 else { return }
        let archived = DateFormatter.localizedString(from: items[row].archived, dateStyle: .medium, timeStyle: .short)
        menu.addItem(withTitle: "Archived \(archived)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Restore to Done", action: #selector(menuRestore), keyEquivalent: "").target = self
        menu.addItem(Export.menuItem(target: self, action: #selector(menuExport)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete Permanently", action: #selector(menuDelete), keyEquivalent: "").target = self
    }

    @objc private func menuRestore() { Store.shared.restoreArchived(at: table.clickedRow) }

    @objc private func menuExport() {
        let task = items[table.clickedRow].task
        Export.save(Export.taskText(task, column: 2), name: task.title, from: window)
    }

    @objc private func menuDelete() {
        let index = table.clickedRow
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(items[index].task.title)” permanently?"
        alert.informativeText = "This can’t be undone."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { Store.shared.deleteArchived(at: index) }
        }
    }
}
