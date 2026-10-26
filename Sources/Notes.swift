import AppKit

/// Notes pane: a clickable list of notes on the left, a plain-text editor on the right.
/// A note's title is its first line; edits autosave and move the note to the top of its group (pinned / others).
final class NotesView: FlippedView, NSTextViewDelegate, NSTextStorageDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let textView: NSTextView
    private let editorScroll: NSScrollView
    private let list = NoteListTableView()
    private let listScroll = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton()
    /// Called with the selected text when the user turns it into a task.
    var onCreateTask: ((String) -> Void)?
    /// Called before a new note is shown, so an active search doesn't hide it.
    var onNewNote: (() -> Void)?
    private var currentID = UUID()
    private var pendingSave: DispatchWorkItem?
    private var selections: [UUID: NSRange] = [:]
    private var syncingSelection = false
    /// Text edited since the last link scan, kept as offsets from the start and from the end
    /// so later edits elsewhere don't invalidate it. Int.max = nothing to scan.
    private var linkScanStart = Int.max
    private var linkScanTail = Int.max

    private static let sidebarWidth: CGFloat = 176
    private static let fontSizeKey = "NotesFontSize"
    private static let defaultFontSize: CGFloat = 14
    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.2
        return p
    }()

    private var notes: [NoteMeta] { Store.shared.notes }

    override init(frame: NSRect) {
        editorScroll = NSTextView.scrollableTextView()
        textView = editorScroll.documentView as! NSTextView
        super.init(frame: frame)

        titleLabel.attributedStringValue = Theme.headerString("Notes")
        addSubview(titleLabel)

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Note")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.toolTip = "New Note (⇧⌘N)"
        addButton.target = self
        addButton.action = #selector(addClicked)
        addSubview(addButton)

        list.configureAsPlainList()
        list.notesView = self
        list.rowHeight = 36
        list.dataSource = self
        list.delegate = self
        list.setDraggingSourceOperationMask(.copy, forLocal: true) // drop on a column → task
        let menu = NSMenu()
        menu.delegate = self
        list.menu = menu
        listScroll.documentView = list
        listScroll.configurePlain()
        addSubview(listScroll)

        textView.configurePlainText()
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 16, height: 12) // first line level with the "NOTES" header
        textView.insertionPointColor = .controlAccentColor
        // Links keep the text cursor: a plain click edits, ⌘-click opens (see clickedOnLink).
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.iBeam,
        ]
        textView.defaultParagraphStyle = Self.paragraph
        textView.delegate = self
        textView.textStorage?.delegate = self
        editorScroll.configurePlain()
        editorScroll.wantsLayer = true // clip scrolled text to the panel's rounded corners
        editorScroll.layer?.cornerRadius = 12
        editorScroll.layer?.masksToBounds = true
        addSubview(editorScroll)

        resizeSubviews(withOldSize: .zero)

        let store = Store.shared
        let start = store.notes.first(where: { $0.id == store.currentNoteID }) ?? store.notes.first ?? store.createNote()
        showNote(start.id)
        // Every launch starts on a blank note; the last one stays in the list.
        if !editorIsEmpty { showNote(store.createNote().id) }
        reloadList()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout & drawing

    // Two rounded panels (note list, editor) spaced like the kanban columns.
    // The 12pt left margin mirrors the board's right margin around the split divider.
    private var listPanel: NSRect {
        NSRect(x: 12, y: Theme.topInset, width: Self.sidebarWidth, height: max(0, bounds.height - Theme.topInset - 12))
    }

    private var editorPanel: NSRect {
        let list = listPanel
        let x = list.maxX + 10
        return NSRect(x: x, y: list.minY, width: max(0, bounds.width - x - 12), height: list.height)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let list = listPanel
        titleLabel.frame = NSRect(x: list.minX + 14, y: list.minY + 12, width: 100, height: 16)
        addButton.frame = NSRect(x: list.maxX - 34, y: list.minY + 8, width: 24, height: 24)
        let listTop = list.minY + 38
        listScroll.frame = NSRect(x: list.minX, y: listTop, width: list.width, height: max(0, list.maxY - listTop - 6))
        editorScroll.frame = editorPanel
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.windowBG.setFill()
        dirtyRect.fill()
        Theme.columnBG.setFill()
        NSBezierPath(roundedRect: listPanel, xRadius: 12, yRadius: 12).fill()
        Theme.notesBG.setFill()
        NSBezierPath(roundedRect: editorPanel, xRadius: 12, yRadius: 12).fill()
    }

    // MARK: - Switching notes

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.font(size: Self.storedFontSize), .paragraphStyle: Self.paragraph, .foregroundColor: NSColor.labelColor]
    }

    /// Stops at the first visible character, so it's cheap enough to check on every keystroke.
    private var editorIsEmpty: Bool {
        !textView.string.contains { !$0.isWhitespace }
    }

    private func showNote(_ id: UUID) {
        currentID = id
        Store.shared.currentNoteID = id
        let text = Store.shared.noteText(id)
        let length = (text as NSString).length
        let attrs = baseAttributes
        textView.string = text
        textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: length))
        textView.typingAttributes = attrs
        var sel = selections[id] ?? NSRange(location: length, length: 0)
        if NSMaxRange(sel) > length { sel = NSRange(location: length, length: 0) }
        textView.setSelectedRange(sel)
        textView.scrollRangeToVisible(sel)
        // Drop the previous note's typing undo only; deleted notes and tasks stay undoable.
        if let storage = textView.textStorage { textView.undoManager?.removeAllActions(withTarget: storage) }
        // Off the launch path: the first frame doesn't wait for link detection.
        DispatchQueue.main.async { [weak self] in self?.detectLinks() }
    }

    private func open(_ id: UUID) {
        guard id != currentID else { return }
        // Saving moves the previous note to the top, so reload only after the switch.
        flush(reload: false)
        selections[currentID] = textView.selectedRange()
        let previous = currentID
        let dropPrevious = editorIsEmpty // blank notes vanish when you leave them
        showNote(id)
        if Search.isActive { revealFirstMatch() }
        if dropPrevious {
            Store.shared.deleteNote(previous)
            selections[previous] = nil
        }
        // Called from a selection callback; reload on the next turn.
        DispatchQueue.main.async { [weak self] in self?.reloadList() }
    }

    func newNote() {
        onNewNote?()
        if editorIsEmpty { focusEditor(); return }
        flush()
        selections[currentID] = textView.selectedRange()
        showNote(Store.shared.createNote().id)
        reloadList()
        focusEditor()
    }

    func focusEditor() { window?.makeFirstResponder(textView) }

    @objc private func addClicked() { newNote() }

    private func reloadList() {
        syncingSelection = true
        list.reloadData() // also unhides every row
        if let row = notes.firstIndex(where: { $0.id == currentID }) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            list.scrollRowToVisible(row)
        }
        syncingSelection = false
        applySearch()
    }

    // MARK: - Search

    /// Hides the notes the search doesn't match (title or text), and the open note while it's blank:
    /// a fresh note joins the list when it is first saved with a title. The open note stays in the editor either way.
    func applySearch() {
        // Row indexes below must match the store's; a reload re-applies the search.
        guard list.numberOfRows == notes.count else { reloadList(); return }
        let blank = editorIsEmpty
        let hidden = IndexSet(notes.indices.filter { row in
            let id = notes[row].id
            return (id == currentID && blank) || (Search.isActive && !matchesSearch(id))
        })
        let current = list.hiddenRowIndexes
        guard hidden != current else { return }
        syncingSelection = true
        list.unhideRows(at: current.subtracting(hidden), withAnimation: [])
        list.hideRows(at: hidden.subtracting(current), withAnimation: [])
        syncingSelection = false
    }

    private func matchesSearch(_ id: UUID) -> Bool {
        // The open note may have unsaved edits.
        Search.matches(folded: id == currentID ? Search.fold(textView.string) : Store.shared.searchText(ofNote: id))
    }

    /// Opens the first matching note at its first match (↩ / ↓ in the search field). False if no note matches.
    func openFirstMatch(focusList: Bool) -> Bool {
        guard let row = notes.indices.first(where: { !list.hiddenRowIndexes.contains($0) }) else { return false }
        let id = notes[row].id
        if id == currentID { revealFirstMatch() } else { open(id) }
        if focusList { window?.makeFirstResponder(list) } else { focusEditor() }
        return true
    }

    /// Selects and flashes the first search word in the open note.
    private func revealFirstMatch() {
        guard let term = Search.terms.first else { return }
        let range = (textView.string as NSString).range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        guard range.location != NSNotFound else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: - Deleting

    func deleteSelectedNote() {
        if list.selectedRow >= 0 { delete(notes[list.selectedRow].id) }
    }

    /// Deletes right away, no confirmation: ⌘Z brings the note back where it was.
    private func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let meta = notes[index]
        let text = latestText(of: id)
        let wasCurrent = id == currentID
        if wasCurrent {
            pendingSave?.cancel()
            pendingSave = nil
        }
        Store.shared.deleteNote(id)
        selections[id] = nil
        if wasCurrent { showNote((notes.first ?? Store.shared.createNote()).id) }
        reloadList()

        guard text.contains(where: { !$0.isWhitespace }) else { return } // nothing worth restoring
        undoManager?.registerUndo(withTarget: self) { view in
            Store.shared.restoreNote(meta, text: text, at: index)
            view.open(meta.id)
        }
        undoManager?.setActionName("Delete Note")
    }

    // MARK: - List

    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.reusableView(NoteCell.reuseID) { NoteCell() }
        cell.title = notes[row].title
        cell.pinned = notes[row].pinned
        cell.needsDisplay = true
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PlainRowView() }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(latestText(of: notes[row].id), forType: .claymoreNote)
        return item
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection, list.selectedRow >= 0 else { return }
        open(notes[list.selectedRow].id)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard list.clickedRow >= 0 else { return }
        let pinTitle = notes[list.clickedRow].pinned ? "Unpin" : "Pin to Top"
        menu.addItem(withTitle: pinTitle, action: #selector(menuTogglePin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show in Finder", action: #selector(menuShowInFinder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete Note", action: #selector(menuDelete), keyEquivalent: "").target = self
    }

    @objc private func menuDelete() { delete(notes[list.clickedRow].id) }

    @objc private func menuTogglePin() {
        Store.shared.togglePin(notes[list.clickedRow].id)
        reloadList()
    }

    /// Notes are already plain .txt files, so reveal the file instead of exporting a copy.
    @objc private func menuShowInFinder() {
        let id = notes[list.clickedRow].id
        if id == currentID { flush() } // may reorder the list, hence the id above
        let url = Store.shared.noteURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent()) // blank note, not written yet
        }
    }

    /// The open note may have unsaved edits, so read it from the editor rather than disk.
    private func latestText(of id: UUID) -> String {
        id == currentID ? textView.string : Store.shared.noteText(id)
    }

    // MARK: - Saving

    func textDidChange(_ notification: Notification) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(sync: false) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func flush(reload: Bool = true) {
        guard pendingSave != nil else { return }
        save(sync: true, reload: reload)
    }

    private func save(sync: Bool, reload: Bool = true) {
        pendingSave?.cancel()
        pendingSave = nil
        if Store.shared.saveNote(currentID, text: textView.string, sync: sync), reload { reloadList() }
        detectLinks()
    }

    // MARK: - Editing helpers

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        sel == #selector(NSResponder.insertNewline(_:)) && continueList()
    }

    /// Return on a list item starts the next one ("- ", "2. ", "- [ ] "); on an empty item it ends the list.
    private func continueList() -> Bool {
        let text = textView.string as NSString
        let cursor = textView.selectedRange()
        guard cursor.length == 0 else { return false }
        let line = text.lineRange(for: NSRange(location: cursor.location, length: 0))
        let beforeCursor = text.substring(with: NSRange(location: line.location, length: cursor.location - line.location))
        guard let item = ListItem(beforeCursor) else { return false }
        let lineEnd = NSMaxRange(line) - (text.substring(with: line).hasSuffix("\n") ? 1 : 0)
        let afterCursor = text.substring(with: NSRange(location: cursor.location, length: lineEnd - cursor.location))
        if item.isEmpty && afterCursor.trimmingCharacters(in: .whitespaces).isEmpty {
            textView.insertText("", replacementRange: NSRange(location: line.location, length: lineEnd - line.location))
        } else {
            textView.insertText("\n" + item.next, replacementRange: cursor)
        }
        return true
    }

    // Typing right after a link shouldn't extend it.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        textView.typingAttributes[.link] = nil
        return true
    }

    /// ⌘-click opens a link; a plain click just puts the cursor there, so links can be edited like any text.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { return false } // AppKit opens it
        textView.setSelectedRange(NSRange(location: charIndex, length: 0))
        return true
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        linkScanStart = min(linkScanStart, editedRange.location)
        linkScanTail = min(linkScanTail, textStorage.length - NSMaxRange(editedRange))
    }

    /// Makes URLs clickable; plain-text views don't detect links on their own.
    /// Only rescans the paragraphs edited since the last call, so long notes stay smooth.
    private func detectLinks() {
        guard let storage = textView.textStorage, let detector = Self.linkDetector, linkScanStart != .max else { return }
        let text = storage.string as NSString
        let start = min(linkScanStart, text.length)
        let end = max(start, text.length - linkScanTail)
        linkScanStart = .max
        linkScanTail = .max
        // URLs never span lines, so the edited paragraphs are all that can change.
        let range = text.paragraphRange(for: NSRange(location: start, length: end - start))
        // Skip the detector (and the relayout) when there's nothing that could be or was a link.
        let paragraphs = text.substring(with: range).lowercased()
        let mayHaveLinks = paragraphs.contains("://") || paragraphs.contains("www.") || paragraphs.contains("@")
        var hadLinks = false
        storage.enumerateAttribute(.link, in: range) { value, _, stop in
            if value != nil { hadLinks = true; stop.pointee = true }
        }
        guard mayHaveLinks || hadLinks else { return }
        storage.beginEditing()
        storage.removeAttribute(.link, range: range)
        if mayHaveLinks {
            detector.enumerateMatches(in: storage.string, range: range) { match, _, _ in
                guard let match, let url = match.url else { return }
                // Only real links, not file names that happen to end in a domain ("notes.md").
                let raw = text.substring(with: match.range).lowercased()
                guard raw.contains("://") || raw.hasPrefix("www.") || url.scheme == "mailto" else { return }
                storage.addAttribute(.link, value: url, range: match.range)
            }
        }
        storage.endEditing()
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        if view.selectedRange().length > 0 {
            let item = NSMenuItem(title: "Create Task", action: #selector(createTaskFromSelection), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    /// True when the editor has focus and text selected (enables ⌘T).
    var canCreateTaskFromSelection: Bool {
        window?.firstResponder === textView && textView.selectedRange().length > 0
    }

    @objc func createTaskFromSelection() {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        onCreateTask?((textView.string as NSString).substring(with: range))
    }

    // MARK: - Font size

    private static var storedFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: fontSizeKey)
        return v > 0 ? CGFloat(v) : defaultFontSize
    }

    private static func font(size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func adjustFontSize(by delta: CGFloat) {
        let size = delta == 0 ? Self.defaultFontSize : min(32, max(10, Self.storedFontSize + delta))
        UserDefaults.standard.set(Double(size), forKey: Self.fontSizeKey)
        textView.font = Self.font(size: size)
        textView.typingAttributes[.font] = textView.font
    }
}

final class NoteListTableView: NSTableView {
    weak var notesView: NotesView?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: notesView?.deleteSelectedNote() // delete, fwd-delete
        case 36, 76, 124: notesView?.focusEditor()    // return, enter, →
        default: super.keyDown(with: event)
        }
    }
}

/// One row in the notes list, drawn directly.
final class NoteCell: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("note")
    private static let font = NSFont.systemFont(ofSize: 13)
    private static let selectedFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: selectedFont)

    private static let pinImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.tertiaryLabelColor])))

    var title = ""
    var pinned = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let selected = isInSelectedRow
        let rect = bounds.insetBy(dx: 8, dy: 3)
        Draw.roundedBox(rect, radius: 7, fill: selected ? Theme.card : .clear,
                        stroke: selected ? .controlAccentColor : Theme.cardBorder)
        var textWidth = rect.width - 20
        if pinned, let pin = Self.pinImage {
            let size = pin.size
            pin.draw(in: NSRect(x: rect.maxX - 10 - size.width, y: floor((bounds.height - size.height) / 2),
                                width: size.width, height: size.height))
            textWidth -= size.width + 6
        }
        let text = title.isEmpty ? "New Note" : title
        let color: NSColor = title.isEmpty ? .tertiaryLabelColor : selected ? .labelColor : .secondaryLabelColor
        let h = Self.lineHeight
        Draw.text(text, in: NSRect(x: rect.minX + 10, y: floor((bounds.height - h) / 2), width: textWidth, height: h),
                  [.font: selected ? Self.selectedFont : Self.font, .foregroundColor: color])
    }
}

/// A list marker at the start of a line: "-", "- ", "* ", "• ", "1. ", "1) ", optionally followed by "[ ] ".
/// "-" needs no space after it ("-item"), but "--" / "---" are not lists.
private struct ListItem {
    let next: String     // marker for the following line
    let isEmpty: Bool    // the line holds only the marker

    // 1 indent, 2 bullet, 3 space after bullet, 4 number, 5 "." or ")", 6 checkbox
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*•])(?!-)([ \t]*)|(\d{1,3})([.)])[ \t]+)(\[[ xX]\][ \t]*)?"#)

    init?(_ line: String) {
        let ns = line as NSString
        guard let m = Self.pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let marker: String
        if let bullet = group(2) {
            let space = group(3) ?? ""
            if bullet != "-" && space.isEmpty { return nil } // "*bold*" is not a list
            // Bullets continue as "-", keeping the user's spacing ("-item" → "-", "- item" → "- ").
            marker = space.isEmpty ? "-" : "- "
        } else {
            marker = "\((Int(group(4) ?? "") ?? 0) + 1)\(group(5) ?? ".") "
        }
        next = (group(1) ?? "") + marker + (group(6) != nil ? "[ ] " : "")
        isEmpty = m.range.length == ns.length
    }
}
