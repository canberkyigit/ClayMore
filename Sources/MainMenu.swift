import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.tag = tag
            return i
        }

        @discardableResult
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let holder = NSMenuItem()
            holder.submenu = m
            main.addItem(holder)
            return m
        }

        submenu("ClayMore", [
            item("About ClayMore", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Launch at Login", #selector(AppDelegate.toggleLaunchAtLogin(_:))),
            .separator(),
            item("Hide ClayMore", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit ClayMore", #selector(NSApplication.terminate(_:)), "q"),
        ])

        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(NSTextView.performTextFinderAction(_:)), "f",
                 tag: NSTextFinder.Action.showFindInterface.rawValue),
            item("Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g",
                 tag: NSTextFinder.Action.nextMatch.rawValue),
            item("Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g", [.command, .shift],
                 tag: NSTextFinder.Action.previousMatch.rawValue),
            .separator(),
            item("Create Task from Selection", #selector(AppDelegate.createTaskFromSelection(_:)), "t"),
        ])

        submenu("Go", [
            item("New Task", #selector(AppDelegate.newTask(_:)), "n"),
            item("New Note", #selector(AppDelegate.newNote(_:)), "n", [.command, .shift]),
            item("Board", #selector(AppDelegate.focusBoard(_:)), "b"),
            item("Notes", #selector(AppDelegate.focusNotes(_:)), "j"),
        ])

        submenu("Archive", [
            item("Show Archive", #selector(AppDelegate.showArchive(_:)), "a", [.command, .shift]),
            item("Archive Done Tasks", #selector(AppDelegate.archiveDoneTasks(_:))),
        ])

        submenu("View", [
            item("Bigger Note Text", #selector(AppDelegate.biggerFont(_:)), "+"),
            item("Smaller Note Text", #selector(AppDelegate.smallerFont(_:)), "-"),
            item("Default Note Text", #selector(AppDelegate.resetFont(_:)), "0"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        NSApp.windowsMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])

        return main
    }
}
