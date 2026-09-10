import AppKit

extension NSTextView {
    /// Configures this text view to track an enclosing scroll view's viewport.
    /// AppKit on macOS 15 no longer reliably sizes a zero-frame document view on its own.
    package func configureAsScrollableDocument() {
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
    }
}
