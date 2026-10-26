import AppKit
import ServiceManagement

final class SplitView: NSSplitView {
    // Layer-backed split views draw the divider themselves (drawDivider isn't called), so keep it
    // invisible and let BoardView draw a separator limited to the panels' height.
    override var dividerColor: NSColor { Theme.windowBG }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSSplitViewDelegate, NSMenuItemValidation, NSSearchFieldDelegate {
    private var window: NSWindow!
    private var board: BoardView!
    private var notes: NotesView!
    private let searchField = NSSearchField()
    private var launchedAtLogin = false
    private var windowWasClosed = false
    private lazy var archiveWindow = ArchiveWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Login items are launched with keyAEPropData = keyAELaunchedAsLogInItem ('prdt' = 'lgit').
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: 0x7072_6474)?.enumCodeValue == 0x6C67_6974
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugHooks.beforeLaunch()
        #endif
        NSApp.mainMenu = MainMenu.build()

        let size = NSSize(width: 1280, height: 780)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "ClayMore"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.backgroundColor = Theme.windowBG
        window.minSize = NSSize(width: 920, height: 460)

        let boardWidth = floor(size.width * 0.55)
        board = BoardView(frame: NSRect(x: 0, y: 0, width: boardWidth, height: size.height))
        notes = NotesView(frame: NSRect(x: boardWidth + 1, y: 0, width: size.width - boardWidth - 1, height: size.height))
        let split = SplitView(frame: NSRect(origin: .zero, size: size))
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.addSubview(board)
        split.addSubview(notes)
        split.autosaveName = "ClayMoreSplit"
        // Selected note text → task at the top of Todo; focus stays in the note.
        notes.onCreateTask = { [weak self] text in self?.board.createTask(fromNote: text, column: 0, row: 0, focus: false) }
        // Anything new is shown, even if it wouldn't match the current search.
        notes.onNewNote = { [weak self] in self?.setSearch("") }
        board.onAdd = { [weak self] in self?.setSearch("") }
        // Root view: the split fills it, the search field floats in the title bar strip above it.
        let root = NSView(frame: split.frame)
        split.autoresizingMask = [.width, .height]
        root.addSubview(split)
        window.contentView = root
        setUpSearch(in: root)

        if !window.setFrameUsingName("ClayMoreMain") { window.center() }
        window.setFrameAutosaveName("ClayMoreMain")
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.windowWasClosed = true
        }

        window.makeFirstResponder(notes.textView)
        #if DEBUG
        if DebugHooks.simulateLoginLaunch { launchedAtLogin = true }
        #endif
        if launchedAtLogin {
            // Started with the Mac: stay out of the way, ready for ⌃⌥C / Dock click.
            NSApp.hide(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        HotKey.register { [weak self] in self?.toggleWindow() }

        #if DEBUG
        DebugHooks.afterLaunch(window: window)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindowReadyToType()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) { flush() }
    func applicationWillTerminate(_ notification: Notification) { flush() }

    private func flush() {
        notes.flush()
        Store.shared.flushNotesIndex()
        Store.shared.flushBoard()
    }

    // MARK: - Window

    private func toggleWindow() {
        if NSApp.isActive && window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            showWindowReadyToType()
        }
    }

    /// Every (re)open lands with the cursor in the note editor, so you can type immediately.
    /// After the window was closed, that's a blank note; the previous one stays in the list.
    private func showWindowReadyToType() {
        let reopening = windowWasClosed
        showWindow()
        if reopening { notes.newNote() } else { notes.focusEditor() }
    }

    private func showWindow() {
        windowWasClosed = false
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        480
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        splitView.bounds.width - 420 // note list + a usable editor
    }

    // MARK: - Search (centered in the title bar; filters notes and cards as you type)

    /// A plain field rather than an NSToolbar, which cost ~50 ms of launch time.
    private func setUpSearch(in root: NSView) {
        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self
        // Centered, level with the traffic lights.
        let height = searchField.intrinsicContentSize.height, width: CGFloat = 320
        var midY = root.bounds.height - 14
        if let close = window.standardWindowButton(.closeButton), let bar = close.superview {
            midY = bar.convert(close.frame, to: nil).midY
        }
        searchField.frame = NSRect(x: floor((root.bounds.width - width) / 2), y: floor(midY - height / 2), width: width, height: height)
        searchField.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        root.addSubview(searchField)
    }

    @objc private func searchChanged(_ sender: NSSearchField) { setSearch(sender.stringValue) }

    func setSearch(_ query: String) {
        if searchField.stringValue != query { searchField.stringValue = query }
        let wasActive = Search.isActive
        Search.set(query)
        guard wasActive || Search.isActive else { return }
        board.applySearch()
        notes.applySearch()
    }

    @objc func focusSearch(_ sender: Any?) {
        showWindow()
        window.makeFirstResponder(searchField)
    }

    // ↩ opens the first matching note (or selects the first card), ↓ goes to the results list, esc clears.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)):
            guard Search.isActive else { return false }
            if !notes.openFirstMatch(focusList: sel == #selector(NSResponder.moveDown(_:))) { _ = board.focusFirstMatch() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            setSearch("")
            notes.focusEditor()
            return true
        default:
            return false
        }
    }

    // MARK: - Launch at login (user-toggled from the ClayMore menu)

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleLaunchAtLogin(_:)):
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(createTaskFromSelection(_:)):
            return notes.canCreateTaskFromSelection
        case #selector(archiveDoneTasks(_:)):
            return !Store.shared.columns[2].isEmpty
        default:
            break
        }
        return true
    }

    // MARK: - Archive & selection → task

    @objc func showArchive(_ sender: Any?) {
        archiveWindow.reload()
        archiveWindow.showWindow(nil)
    }

    @objc func archiveDoneTasks(_ sender: Any?) { board.archiveDone() }

    @objc func createTaskFromSelection(_ sender: Any?) { notes.createTaskFromSelection() }

    // MARK: - Menu actions

    @objc func newTask(_ sender: Any?) {
        showWindow()
        board.columns[0].focusAddField()
    }

    @objc func newNote(_ sender: Any?) {
        showWindow()
        notes.newNote()
    }

    @objc func focusBoard(_ sender: Any?) { board.focus(column: 0) }
    @objc func focusNotes(_ sender: Any?) { notes.focusEditor() }
    @objc func biggerFont(_ sender: Any?) { notes.adjustFontSize(by: 1) }
    @objc func smallerFont(_ sender: Any?) { notes.adjustFontSize(by: -1) }
    @objc func resetFont(_ sender: Any?) { notes.adjustFontSize(by: 0) }
}
