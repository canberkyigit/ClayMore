import AppKit

/// The quiet note list, undoable deletes, editable links and the slim task editor.
func uxTests() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 700), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let board = BoardView(frame: NSRect(x: 0, y: 0, width: 700, height: 700))
    let notes = NotesView(frame: NSRect(x: 700, y: 0, width: 600, height: 700))
    window.contentView = NSView()
    window.contentView!.addSubview(board)
    window.contentView!.addSubview(notes)
    window.makeFirstResponder(notes.textView)
    let undo = window.undoManager!
    let store = Store.shared
    let list = notes.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first!
    func visibleTitles() -> [String] {
        (0..<list.numberOfRows).filter { !list.hiddenRowIndexes.contains($0) }.map { store.notes[$0].title }
    }
    func row(_ title: String) -> Int { store.notes.firstIndex { $0.title == title }! }
    func open(_ title: String) {
        list.selectRowIndexes(IndexSet(integer: row(title)), byExtendingSelection: false)
        pump()
    }
    pump()

    // The blank note every launch opens stays out of the list until it has a title.
    let current = store.notes.firstIndex { $0.id == store.currentNoteID }!
    check("the blank current note is hidden", list.hiddenRowIndexes.contains(current) && store.notes[current].title.isEmpty)
    check("the list shows only real notes", !visibleTitles().contains(""), visibleTitles())
    notes.textView.insertText("Groceries\nmilk", replacementRange: notes.textView.selectedRange())
    pump(autosave)
    check("the note joins the list once saved", visibleTitles().contains("Groceries"), visibleTitles())

    // Deleting asks nothing; ⌘Z puts the note back in place with its text.
    let giftIndex = row("Gift ideas")
    let giftID = store.notes[giftIndex].id
    open("Gift ideas")
    notes.deleteSelectedNote()
    pump()
    check("deleted without a dialog", !store.notes.contains { $0.id == giftID } && window.attachedSheet == nil)
    check("undo is offered", undo.canUndo && undo.undoActionName == "Delete Note", undo.undoActionName)
    open("Trip to Lisbon")
    check("undo survives switching notes", undo.canUndo && undo.undoActionName == "Delete Note", undo.undoActionName)
    undo.undo()
    pump(0.6)
    check("undo restores the note in place", store.notes.firstIndex { $0.id == giftID } == giftIndex, store.notes.map(\.title))
    check("the restored note is open with its text",
          store.currentNoteID == giftID && notes.textView.string.contains("kahve"), notes.textView.string)
    check("the restored text is on disk",
          (try? String(contentsOf: store.noteURL(giftID), encoding: .utf8))?.contains("kahve") == true)
    // It used to come back empty, then get dropped as a blank note when you left it.
    open("Reading list")
    check("the restored note survives leaving it", store.notes.contains { $0.id == giftID }, store.notes.map(\.title))

    let dentist = store.columns[0].firstIndex { $0.title == "Call the dentist" }!
    board.delete(column: 0, row: dentist)
    open("Design sync notes")
    undo.undo()
    check("card delete undo survives switching notes", store.columns[0].contains { $0.title == "Call the dentist" })

    // A plain click on a link moves the cursor; only ⌘-click opens it.
    let tv = notes.textView
    open("Weekly planning")
    pump()
    let link = (tv.string as NSString).range(of: "https://developer").location
    check("the link is detected", tv.textStorage!.attribute(.link, at: link + 3, effectiveRange: nil) != nil)
    let handled = notes.textView(tv, clickedOnLink: URL(string: "https://developer.apple.com")!, at: link + 5)
    check("a plain click puts the cursor there instead of opening",
          handled && tv.selectedRange() == NSRange(location: link + 5, length: 0), tv.selectedRange())
    check("links keep the text cursor", (tv.linkTextAttributes?[.cursor] as? NSCursor) == NSCursor.iBeam)

    // The task editor: title, priority and description only.
    let editor = TaskEditor(task: TaskItem(title: "T"), focusDetail: false)
    editor.loadView()
    let buttons = editor.view.subviews.filter { $0 is NSButton }
    let labels = editor.view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isEditable }
    check("the task editor has no Delete button or hint", buttons.isEmpty && labels.isEmpty, (buttons, labels))
}
