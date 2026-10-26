import AppKit

/// Launches the real app (window and all) and clicks the search box through AppKit's own event routing,
/// which handles the title bar strip specially. The window shows briefly and takes focus.
func clickTests() {
    let delegate = AppDelegate()
    NSApp.setActivationPolicy(.regular) // a frontmost app with a key window, as when you click it
    NSApp.delegate = delegate

    func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        withExtendedLifetime(delegate) {}
        let window = NSApp.windows.first { $0.title == "ClayMore" }!
        let box = window.contentView!.subviews.compactMap { $0 as? SearchBox }.first!
        let searching = { (window.firstResponder as? NSTextView)?.delegate === box.field }
        let frame = box.convert(box.bounds, to: nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        check("launch puts the cursor in the note, not search", !searching())

        // Posted clicks are only dequeued by NSApp's own event loop, so each step returns to it
        // (pump() would spin a nested run loop that leaves them queued).
        click(window, at: NSPoint(x: frame.midX, y: frame.midY))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check("a click in the title bar strip focuses search", searching())
            window.makeFirstResponder(nil)
            click(window, at: NSPoint(x: frame.minX + 14, y: frame.midY)) // on the magnifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                check("a click on the icon focuses search too", searching())

                // Window coordinates run bottom-up: compare the gap above the box with the gap down to the panels.
                let content = window.contentView!.bounds.height
                check("the box sits midway between the window top and the panels",
                      abs((content - frame.maxY) - (frame.minY - (content - Theme.topInset))) < 1,
                      (content - frame.maxY, frame.minY - (content - Theme.topInset)))
                exit(failures == 0 ? 0 : 1)
            }
        }
    }
    NSApp.run()
}
