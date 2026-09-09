import AppKit

enum TerminalKeyCommand: Equatable {
    case interrupt, clear, historyPrev, historyNext, complete, submit, newline
}

final class TerminalNSTextView: NSTextView {
    var onKeyCommand: ((TerminalKeyCommand) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.keyCode == 8 {
            onKeyCommand?(.clear)
        } else if event.modifierFlags.contains(.shift), event.keyCode == 36 {
            onKeyCommand?(.newline)
        } else if event.keyCode == 36, !hasMarkedText() {
            onKeyCommand?(.submit)
        } else if event.keyCode == 48 {
            onKeyCommand?(.complete)
        } else if event.modifierFlags.contains(.option), event.keyCode == 126 {
            onKeyCommand?(.historyPrev)
        } else if event.modifierFlags.contains(.option), event.keyCode == 125 {
            onKeyCommand?(.historyNext)
        } else if event.modifierFlags.contains(.control),
            !event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.option),
            !event.modifierFlags.contains(.shift),
            event.keyCode == 8
        {
            onKeyCommand?(.interrupt)
        } else {
            super.keyDown(with: event)
        }
    }

    func setStreamingCursorVisible(_ visible: Bool) {
        insertionPointColor = visible ? .systemGreen : .clear
        needsDisplay = true
    }
}
