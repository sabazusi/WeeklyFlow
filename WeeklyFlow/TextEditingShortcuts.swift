import AppKit

final class TextEditingShortcuts {
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handle(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private static func handle(_ event: NSEvent) -> NSEvent? {
        guard let editor = (event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder) as? NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return event }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (key, modifiers) {
        case ("a", .command), ("a", .control): editor.selectAll(nil)
        case ("c", .command), ("c", .control): editor.copy(nil)
        case ("v", .command), ("v", .control): editor.paste(nil)
        case ("x", .command), ("x", .control): editor.cut(nil)
        case ("z", .command), ("z", .control):
            guard let undoManager = editor.undoManager, undoManager.canUndo else { return event }
            undoManager.undo()
        case ("z", [.command, .shift]), ("z", [.control, .shift]), ("y", .control):
            guard let undoManager = editor.undoManager, undoManager.canRedo else { return event }
            undoManager.redo()
        default: return event
        }
        return nil
    }
}
