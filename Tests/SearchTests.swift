import AppKit

/// The search filter: matching rules, hidden rows on the board and in the note list, and actions while filtered.
func searchTests() {
    Search.set("ISIK cafe")
    check("terms are folded", Search.terms == ["isik", "cafe"], Search.terms)
    check("Turkish ı/İ and accents match", Search.matches("Işık hızı", "Café") && Search.matches("İSİK CAFÉ"))
    check("every word is required", !Search.matches("Işık only"))
    Search.set("   ")
    check("a blank query is inactive", !Search.isActive)

    let board = BoardView(frame: NSRect(x: 0, y: 0, width: 700, height: 700))
    let notes = NotesView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 700), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.contentView = NSView()
    window.contentView!.addSubview(board)
    window.contentView!.addSubview(notes)
    var cleared = 0
    board.onAdd = {
        cleared += 1
        Search.set("")
        board.applySearch()
        notes.applySearch()
    }
    notes.onNewNote = board.onAdd

    let list = notes.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first!
    func visibleNotes() -> [String] {
        (0..<list.numberOfRows).filter { !list.hiddenRowIndexes.contains($0) }.map { Store.shared.notes[$0].title }
    }
    func visibleCards(_ c: Int) -> [String] {
        let t = board.columns[c].table
        return (0..<t.numberOfRows).filter { !t.hiddenRowIndexes.contains($0) }.map { Store.shared.columns[c][$0].title }
    }
    func search(_ q: String) {
        Search.set(q)
        board.applySearch()
        notes.applySearch()
    }

    pump()
    let allNotes = visibleNotes()
    search("export")
    check("cards are filtered", visibleCards(0) == [] && visibleCards(1) == ["Write release notes for v2.4"] && visibleCards(2) == [],
          (visibleCards(0), visibleCards(1), visibleCards(2)))
    check("notes are filtered by their text too",
          visibleNotes() == ["Weekly planning", "Design sync notes", "Interview questions"], visibleNotes())
    search("isik")
    check("dotless ı is found in a note", visibleNotes() == ["Interview questions"], visibleNotes())
    search("FABRICA")
    check("accent-insensitive note search", visibleNotes() == ["Trip to Lisbon"], visibleNotes())

    // ↩ opens the first match and selects the word.
    search("roadmap")
    check("one note matches", visibleNotes() == ["Weekly planning"], visibleNotes())
    check("openFirstMatch succeeds", notes.openFirstMatch(focusList: false))
    pump()
    let selection = notes.textView.selectedRange()
    check("the match is selected in the editor",
          (notes.textView.string as NSString).substring(with: selection) == "roadmap", selection)

    // Rows are hidden, not removed, so row-based actions still hit the right task.
    search("dentist")
    check("one card visible", visibleCards(0) == ["Call the dentist"], visibleCards(0))
    let row = Store.shared.columns[0].firstIndex { $0.title == "Call the dentist" }!
    board.delete(column: 0, row: row)
    check("deleting while filtered removes the right card",
          !Store.shared.columns[0].contains { $0.title == "Call the dentist" } && Store.shared.columns[0].count == 3,
          Store.shared.columns[0].map(\.title))
    check("the filter is re-applied after a reload", visibleCards(0) == [], visibleCards(0))

    search("passport")
    board.focus(column: 0)
    let todo = board.columns[0].table
    check("focus skips hidden cards",
          todo.selectedRow >= 0 && Store.shared.columns[0][todo.selectedRow].title == "Renew passport", todo.selectedRow)
    check("focusFirstMatch finds the card", board.focusFirstMatch())

    // Adding something clears the search so the new item shows.
    search("passport")
    board.createTask(fromNote: "Brand new task", column: 0, row: 0, focus: false)
    check("adding a task clears the search",
          cleared == 1 && !Search.isActive && visibleCards(0).contains("Brand new task"), (cleared, visibleCards(0)))
    search("export")
    notes.newNote()
    check("a new note clears the search",
          cleared == 2 && !Search.isActive && visibleNotes().count >= allNotes.count, visibleNotes())

    notes.textView.insertText("zebracorn", replacementRange: NSRange(location: 0, length: 0))
    notes.flush()
    search("zebracorn")
    check("freshly saved text is searchable", visibleNotes().count == 1, visibleNotes())
    search("")
    check("clearing shows everything",
          list.hiddenRowIndexes.isEmpty && board.columns.allSatisfy { $0.table.hiddenRowIndexes.isEmpty })
}
