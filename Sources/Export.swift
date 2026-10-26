import AppKit

/// "Save as .txt…" for tasks (context menus).
enum Export {
    static func menuItem(target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "Save as .txt…", action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    static func taskText(_ t: TaskItem, column: Int) -> String {
        var meta = "Status: \(Store.columnTitles[column])"
        if t.priority != .none { meta += " · Priority: \(t.priority.title)" }
        return [t.title, meta, t.detail].filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    }

    static func save(_ text: String, name: String, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(name) + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    private static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }
}
