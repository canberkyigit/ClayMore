import AppKit

/// Popover for editing a task's name, priority and description. Changes are committed when it closes.
final class TaskEditor: NSViewController, NSPopoverDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    var onCommit: ((UUID, String, String, Priority) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onClose: (() -> Void)?
    weak var popover: NSPopover?

    private let task: TaskItem
    private let focusDetail: Bool
    private var deleted = false
    private let titleField = NSTextField.bareInput(font: .systemFont(ofSize: 15, weight: .semibold))
    private let priorityControl = NSSegmentedControl(labels: Priority.allCases.map(\.title),
                                                     trackingMode: .selectOne, target: nil, action: nil)
    private let detailScroll = NSTextView.scrollableTextView()
    private var detailView: NSTextView { detailScroll.documentView as! NSTextView }

    init(task: TaskItem, focusDetail: Bool) {
        self.task = task
        self.focusDetail = focusDetail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let w: CGFloat = 340
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: 258))

        titleField.stringValue = task.title
        titleField.placeholderString = "Task name"
        titleField.delegate = self
        titleField.frame = NSRect(x: 16, y: 16, width: w - 32, height: 20)
        v.addSubview(titleField)

        priorityControl.selectedSegment = task.priority.rawValue
        priorityControl.segmentDistribution = .fillEqually
        priorityControl.frame = NSRect(x: 12, y: 48, width: w - 24, height: 24)
        v.addSubview(priorityControl)

        let tv = detailView
        tv.configurePlainText()
        tv.string = task.detail
        tv.font = .systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.delegate = self
        tv.setValue(NSAttributedString(string: "Description", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ]), forKey: "placeholderAttributedString")
        detailScroll.drawsBackground = true
        detailScroll.backgroundColor = Theme.inputBG
        detailScroll.wantsLayer = true
        detailScroll.layer?.cornerRadius = 8
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.frame = NSRect(x: 12, y: 82, width: w - 24, height: 134)
        v.addSubview(detailScroll)
        titleField.nextKeyView = tv

        let delete = NSButton(title: "", target: self, action: #selector(deleteTask))
        delete.isBordered = false
        delete.attributedTitle = NSAttributedString(string: "Delete", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.systemRed,
        ])
        delete.frame = NSRect(x: 14, y: 226, width: 50, height: 20)
        v.addSubview(delete)

        let hint = NSTextField(labelWithString: "esc or ⌘↩ to save")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .right
        hint.frame = NSRect(x: w - 196, y: 229, width: 180, height: 16)
        v.addSubview(hint)

        view = v
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if focusDetail {
            view.window?.makeFirstResponder(detailView)
        } else {
            view.window?.makeFirstResponder(titleField)
            titleField.currentEditor()?.selectedRange = NSRange(location: (titleField.stringValue as NSString).length, length: 0)
        }
    }

    @objc private func deleteTask() {
        deleted = true
        onDelete?(task.id)
        popover?.performClose(nil)
    }

    private func isCancel(_ sel: Selector) -> Bool {
        sel == #selector(NSResponder.cancelOperation(_:)) || sel == #selector(NSTextView.complete(_:))
    }

    // Return in the title saves; ⌘↩ or esc anywhere saves.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.insertNewline(_:)) || isCancel(sel) else { return false }
        popover?.performClose(nil)
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let cmdReturn = sel == #selector(NSResponder.insertNewline(_:))
            && NSApp.currentEvent?.modifierFlags.contains(.command) == true
        guard cmdReturn || isCancel(sel) else { return false }
        popover?.performClose(nil)
        return true
    }

    func popoverWillClose(_ notification: Notification) {
        guard !deleted else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detailView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = Priority(rawValue: priorityControl.selectedSegment) ?? .none
        onCommit?(task.id, title, detail, priority)
    }

    func popoverDidClose(_ notification: Notification) { onClose?() }
}
