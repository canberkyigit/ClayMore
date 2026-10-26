import Foundation

enum Priority: Int, Codable, CaseIterable {
    case none, low, medium, high

    var title: String { ["None", "Low", "Medium", "High"][rawValue] }
}

struct TaskItem: Codable {
    var id = UUID()
    var title: String
    var detail: String = ""
    var priority: Priority = .none
}

extension TaskItem {
    // Tolerates boards saved before a field existed (synthesized Codable would reject the whole file).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .none
    }
}

/// Index entry for a note; the text itself lives in notes/<id>.txt and is read only when opened.
struct NoteMeta: Codable {
    var id = UUID()
    var title = ""
    var modified = Date()
    var pinned = false
}

extension NoteMeta {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

struct ArchivedTask: Codable {
    var task: TaskItem
    var archived = Date()
}

/// Everything lives in memory; disk writes are debounced and happen off the main thread.
final class Store {
    static let shared = Store()
    static let columnTitles = ["Todo", "In Progress", "Done"]

    static let archiveDidChange = Notification.Name("ClayMoreArchiveDidChange")

    private(set) var columns: [[TaskItem]] = [[], [], []]
    /// Pinned notes first, then the rest; each group most recently modified first.
    private(set) var notes: [NoteMeta] = []

    private let dir: URL
    private let boardURL: URL
    private let notesDir: URL
    private let notesIndexURL: URL
    private let archiveURL: URL
    /// Loaded on first use, so the archive never costs launch time.
    private var archiveCache: [ArchivedTask]?
    private let io = DispatchQueue(label: "claymore.io", qos: .utility)
    private var pendingBoardSave: DispatchWorkItem?
    /// The index differs from disk only in modification dates; written on the next flush.
    private var notesIndexDirty = false
    /// Folded note text for search; built on the first search (never at launch), then kept current on save.
    private var searchTexts: [UUID: String]?

    private init() {
        let fm = FileManager.default
        var dataDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClayMore", isDirectory: true)
        #if DEBUG
        if let custom = ProcessInfo.processInfo.environment["CLAYMORE_DATA_DIR"] {
            dataDir = URL(fileURLWithPath: custom, isDirectory: true)
        }
        #endif
        dir = dataDir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        boardURL = dir.appendingPathComponent("board.json")
        notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        notesIndexURL = dir.appendingPathComponent("notes.json")
        archiveURL = dir.appendingPathComponent("archive.json")
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: boardURL) {
            if let saved = try? JSONDecoder().decode([[TaskItem]].self, from: data), saved.count == 3 {
                columns = saved
            } else {
                backUpUnreadable(boardURL)
            }
        }

        if let data = try? Data(contentsOf: notesIndexURL) {
            if let saved = try? JSONDecoder().decode([NoteMeta].self, from: data) {
                notes = saved
            } else {
                // Unreadable index: keep a copy and rebuild it from the note files themselves.
                backUpUnreadable(notesIndexURL)
                rebuildNotesIndex()
            }
        } else {
            // Migrate the single note.txt from v1.
            let legacy = dir.appendingPathComponent("note.txt")
            if let data = try? Data(contentsOf: legacy) {
                let meta = NoteMeta(title: Self.title(from: String(decoding: data, as: UTF8.self)))
                try? fm.moveItem(at: legacy, to: noteURL(meta.id))
                notes = [meta]
                writeNotesIndex(sync: true)
            }
        }
    }

    /// Keeps a copy of a file we couldn't parse, instead of overwriting it on the next save.
    private func backUpUnreadable(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let backup = dir.appendingPathComponent("\(name).unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    private func rebuildNotesIndex() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        notes = files.compactMap { url -> NoteMeta? in
            guard url.pathExtension == "txt", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return NoteMeta(id: id, title: Self.title(from: noteText(id)), modified: modified)
        }.sorted { $0.modified > $1.modified }
        writeNotesIndex(sync: true)
    }

    private func run(sync: Bool, _ work: @escaping () -> Void) {
        // Serial queue keeps a sync flush from being overwritten by an older async write.
        sync ? io.sync(execute: work) : io.async(execute: work)
    }

    // MARK: - Board

    func locate(_ id: UUID) -> (column: Int, row: Int)? {
        for c in 0..<columns.count {
            if let r = columns[c].firstIndex(where: { $0.id == id }) { return (c, r) }
        }
        return nil
    }

    @discardableResult
    func add(_ title: String, to column: Int) -> TaskItem {
        let task = TaskItem(title: title)
        columns[column].insert(task, at: 0)
        boardChanged()
        return task
    }

    func insert(_ task: TaskItem, column: Int, row: Int) {
        columns[column].insert(task, at: min(row, columns[column].count))
        boardChanged()
    }

    @discardableResult
    func remove(column: Int, row: Int) -> TaskItem {
        let task = columns[column].remove(at: row)
        boardChanged()
        return task
    }

    /// Returns the source column and the final row in the destination column.
    func move(_ id: UUID, to column: Int, row: Int) -> (from: Int, row: Int)? {
        guard let src = locate(id) else { return nil }
        let task = columns[src.column].remove(at: src.row)
        var dst = row
        if src.column == column && src.row < dst { dst -= 1 }
        dst = max(0, min(dst, columns[column].count))
        columns[column].insert(task, at: dst)
        boardChanged()
        return (src.column, dst)
    }

    /// Returns the column that changed, or nil if nothing changed.
    func update(_ id: UUID, title: String, detail: String, priority: Priority) -> Int? {
        guard let (c, r) = locate(id) else { return nil }
        let t = columns[c][r]
        guard t.title != title || t.detail != detail || t.priority != priority else { return nil }
        columns[c][r].title = title
        columns[c][r].detail = detail
        columns[c][r].priority = priority
        boardChanged()
        return c
    }

    private func boardChanged() {
        pendingBoardSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeBoard(sync: false) }
        pendingBoardSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func flushBoard() {
        guard let work = pendingBoardSave else { return }
        work.cancel()
        writeBoard(sync: true)
    }

    private func writeBoard(sync: Bool) {
        pendingBoardSave = nil
        guard let data = try? JSONEncoder().encode(columns) else { return }
        let url = boardURL
        run(sync: sync) { _ = try? data.write(to: url, options: .atomic) }
    }

    // MARK: - Notes

    var currentNoteID: UUID? {
        get { UserDefaults.standard.string(forKey: "CurrentNote").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "CurrentNote") }
    }

    func noteURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent(id.uuidString + ".txt")
    }

    func noteText(_ id: UUID) -> String {
        guard let data = try? Data(contentsOf: noteURL(id)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Top of the note's group: index 0 for pinned notes, right after the pinned block otherwise.
    private func topIndex(pinned: Bool) -> Int {
        pinned ? 0 : notes.filter(\.pinned).count
    }

    func createNote() -> NoteMeta {
        let meta = NoteMeta()
        notes.insert(meta, at: topIndex(pinned: false))
        writeNotesIndex(sync: false)
        return meta
    }

    func togglePin(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var meta = notes.remove(at: i)
        meta.pinned.toggle()
        notes.insert(meta, at: topIndex(pinned: meta.pinned))
        writeNotesIndex(sync: false)
    }

    /// Saves the text and moves the note to the top of its group. Returns true if the list changed.
    @discardableResult
    func saveNote(_ id: UUID, text: String, sync: Bool) -> Bool {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return false }
        var meta = notes.remove(at: i)
        let title = Self.title(from: text)
        let top = topIndex(pinned: meta.pinned)
        let listChanged = i != top || meta.title != title
        meta.title = title
        meta.modified = Date()
        notes.insert(meta, at: top)

        if searchTexts != nil { searchTexts?[id] = Search.fold(text) }

        let data = Data(text.utf8)
        let url = noteURL(id)
        run(sync: sync) { _ = try? data.write(to: url, options: .atomic) }
        // Typing that doesn't change the title or order only touches the note's own file.
        if listChanged || sync { writeNotesIndex(sync: sync) } else { notesIndexDirty = true }
        return listChanged
    }

    func flushNotesIndex() {
        if notesIndexDirty { writeNotesIndex(sync: true) }
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        searchTexts?[id] = nil
        let url = noteURL(id)
        io.async { _ = try? FileManager.default.removeItem(at: url) }
        writeNotesIndex(sync: false)
    }

    /// Puts a deleted note back (undo), at its old place within its group.
    func restoreNote(_ meta: NoteMeta, text: String, at index: Int) {
        let pinnedCount = topIndex(pinned: false)
        let range = meta.pinned ? 0...pinnedCount : pinnedCount...notes.count
        notes.insert(meta, at: min(max(index, range.lowerBound), range.upperBound))
        if searchTexts != nil { searchTexts?[meta.id] = Search.fold(text) }
        let data = Data(text.utf8)
        let url = noteURL(meta.id)
        // Sync: the note is reopened right away and read back from this file.
        run(sync: true) { _ = try? data.write(to: url, options: .atomic) }
        writeNotesIndex(sync: false)
    }

    private func writeNotesIndex(sync: Bool) {
        notesIndexDirty = false
        guard let data = try? JSONEncoder().encode(notes) else { return }
        let url = notesIndexURL
        run(sync: sync) { _ = try? data.write(to: url, options: .atomic) }
    }

    /// A note's saved text, folded for `Search`.
    func searchText(ofNote id: UUID) -> String {
        if let text = searchTexts?[id] { return text }
        if searchTexts == nil { searchTexts = [:] }
        let text = Search.fold(noteText(id))
        searchTexts?[id] = text
        return text
    }

    /// Splits a note into a task: its title line and everything after it.
    static func taskParts(fromNote text: String) -> (title: String, detail: String) {
        var lines = text.components(separatedBy: .newlines)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        guard !lines.isEmpty else { return ("", "") }
        lines.removeFirst()
        return (title(from: text), lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// First non-empty line, without leading markdown-ish markers or a checkbox.
    static func title(from text: String) -> String {
        let strip = CharacterSet(charactersIn: "#*->•").union(.whitespaces)
        var title = ""
        text.enumerateLines { line, stop in
            var t = line.trimmingCharacters(in: strip)
            for box in ["[ ]", "[x]", "[X]"] where t.hasPrefix(box) {
                t = String(t.dropFirst(box.count)).trimmingCharacters(in: .whitespaces)
            }
            if !t.isEmpty {
                title = String(t.prefix(80))
                stop = true
            }
        }
        return title
    }

    // MARK: - Archive

    /// Newest first.
    var archive: [ArchivedTask] {
        if let cached = archiveCache { return cached }
        var loaded: [ArchivedTask] = []
        if let data = try? Data(contentsOf: archiveURL) {
            if let saved = try? JSONDecoder().decode([ArchivedTask].self, from: data) {
                loaded = saved
            } else {
                backUpUnreadable(archiveURL)
            }
        }
        archiveCache = loaded
        return loaded
    }

    private func setArchive(_ items: [ArchivedTask]) {
        archiveCache = items
        if let data = try? JSONEncoder().encode(items) {
            let url = archiveURL
            run(sync: false) { _ = try? data.write(to: url, options: .atomic) }
        }
        NotificationCenter.default.post(name: Self.archiveDidChange, object: nil)
    }

    func archiveTask(column: Int, row: Int) {
        let task = remove(column: column, row: row)
        setArchive([ArchivedTask(task: task)] + archive)
    }

    /// Moves every task in Done to the archive. Returns how many were archived.
    @discardableResult
    func archiveDone() -> Int {
        let done = columns[2]
        guard !done.isEmpty else { return 0 }
        columns[2] = []
        boardChanged()
        let now = Date()
        setArchive(done.map { ArchivedTask(task: $0, archived: now) } + archive)
        return done.count
    }

    /// Puts an archived task back at the top of Done.
    func restoreArchived(at index: Int) {
        var items = archive
        let item = items.remove(at: index)
        insert(item.task, column: 2, row: 0)
        setArchive(items)
    }

    func deleteArchived(at index: Int) {
        var items = archive
        items.remove(at: index)
        setArchive(items)
    }
}
