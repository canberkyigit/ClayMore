import AppKit

// Helpers shared by the suites. They drive the app's real views and store, not mocks.

var failures = 0

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> Any = "") {
    print(ok ? "  ✓" : "  ✗", name, ok ? "" : "→ \(detail())")
    if !ok { failures += 1 }
}

/// Lets queued work run: debounced saves, deferred list reloads, link detection.
func pump(_ seconds: Double = 0.2) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Longer than the editor's 0.5 s autosave debounce.
let autosave = 0.8

/// A small board and set of notes, written before the store first loads.
enum SampleData {
    static func write(to dir: URL) {
        let fm = FileManager.default
        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let board: [[TaskItem]] = [
            [TaskItem(title: "Plan sprint review", detail: "Collect demos from each team", priority: .high),
             TaskItem(title: "Renew passport", priority: .medium),
             TaskItem(title: "Call the dentist"),
             TaskItem(title: "Read DDIA chapter 5", detail: "Replication & leader election", priority: .low)],
            [TaskItem(title: "Write release notes for v2.4", detail: "Highlight the new export flow", priority: .high),
             TaskItem(title: "Refactor settings screen")],
            [TaskItem(title: "Morning workout"),
             TaskItem(title: "Fix flaky login test", detail: "Raised the timeout to 10s")],
        ]
        try? JSONEncoder().encode(board).write(to: dir.appendingPathComponent("board.json"))

        let notes: [(text: String, pinned: Bool)] = [
            ("Weekly planning\n\n- Ship the export flow\n- Review the hiring pipeline\n- [x] Book flights for the offsite\n- [ ] Draft the Q4 roadmap\n\nRefs\n- https://developer.apple.com/documentation/appkit\n", true),
            ("Reading list\n\nDesigning Data-Intensive Applications\nThe Pragmatic Programmer\n", true),
            ("Design sync notes\n\nExport dialog needs a progress state.\n", false),
            ("Gift ideas\n\nKitap, kahve makinesi\n", false),
            ("Trip to Lisbon\n\nFlights booked. Café list: Fábrica, Copenhagen Coffee Lab\n", false),
            ("Interview questions\n\nHow would you design the export pipeline?\nIşık hızında ne yapardın?\n", false),
        ]
        var index: [NoteMeta] = []
        for (i, note) in notes.enumerated() {
            let meta = NoteMeta(title: Store.title(from: note.text),
                                modified: Date(timeIntervalSinceReferenceDate: 800_000_000 - Double(i)), pinned: note.pinned)
            try? Data(note.text.utf8).write(to: notesDir.appendingPathComponent(meta.id.uuidString + ".txt"))
            index.append(meta)
        }
        try? JSONEncoder().encode(index).write(to: dir.appendingPathComponent("notes.json"))
    }
}
