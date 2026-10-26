import AppKit

/// Autosave, link detection and when notes.json gets rewritten. Starts from an empty data folder.
func saveTests() {
    let indexURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAYMORE_DATA_DIR"]!)
        .appendingPathComponent("notes.json")
    let notes = NotesView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    let tv = notes.textView

    func links() -> [String] {
        var out: [String] = []
        let s = tv.textStorage!
        s.enumerateAttribute(.link, in: NSRange(location: 0, length: s.length)) { value, range, _ in
            if value != nil { out.append((s.string as NSString).substring(with: range)) }
        }
        return out
    }
    func type(_ s: String, at location: Int? = nil) {
        let r = location.map { NSRange(location: $0, length: 0) } ?? tv.selectedRange()
        tv.setSelectedRange(r)
        tv.insertText(s, replacementRange: r)
    }
    func replace(_ r: NSRange, with s: String) {
        tv.setSelectedRange(r)
        tv.insertText(s, replacementRange: r)
    }
    func indexModified() -> Date {
        (try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date) ?? .distantPast
    }

    pump()
    type("Title line\nsee https://example.com/a here\nplain line\n")
    pump(autosave)
    check("link detected on first save", links() == ["https://example.com/a"], links())

    // Only the edited paragraph is rescanned; the earlier link must survive.
    type("mail me at bob@example.org\n")
    pump(autosave)
    check("email detected, earlier link kept", links() == ["https://example.com/a", "bob@example.org"], links())

    replace((tv.string as NSString).range(of: "://"), with: " ")
    pump(autosave)
    check("broken link removed", links() == ["bob@example.org"], links())

    type("www.apple.com ", at: 0)
    type(" https://swift.org", at: (tv.string as NSString).length)
    pump(autosave)
    check("two edits in one save are both scanned",
          Set(links()) == ["www.apple.com", "bob@example.org", "https://swift.org"], links())

    type("\nnotes.md\n")
    pump(autosave)
    check("a file name is not a link", !links().contains("notes.md"), links())

    // notes.json: body edits leave it alone, title edits rewrite it, a flush writes pending dates.
    pump(0.3)
    let before = indexModified()
    pump(1.1) // file dates have 1 s resolution on some volumes
    type("more body text")
    pump(autosave)
    check("body edit leaves notes.json alone", indexModified() == before, (before, indexModified()))
    Store.shared.flushNotesIndex()
    check("flushNotesIndex writes pending dates", indexModified() > before, (before, indexModified()))
    let afterFlush = indexModified()
    pump(1.1)
    Store.shared.flushNotesIndex()
    check("second flush is a no-op", indexModified() == afterFlush)
    pump(1.1)
    replace(NSRange(location: 0, length: 0), with: "New ")
    pump(autosave)
    check("title edit rewrites notes.json", indexModified() > afterFlush)
    let saved = try? JSONDecoder().decode([NoteMeta].self, from: Data(contentsOf: indexURL))
    check("index has the new title", saved?.first?.title.hasPrefix("New www.apple.com") == true, saved?.first?.title ?? "nil")

    let file = Store.shared.noteURL(Store.shared.currentNoteID!)
    check("note file on disk matches the editor", (try? String(contentsOf: file, encoding: .utf8)) == tv.string)
}
