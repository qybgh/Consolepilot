import AppKit
import XCTest

@testable import ConsolepilotLegacyUI

@MainActor
final class ScrollableTextViewTests: XCTestCase {
    func testScrollableDocumentConfigurationTracksViewportWidth() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        let contentView = window.contentView!
        let textView = NSTextView(frame: .zero)
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = textView
        textView.configureAsScrollableDocument()
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
        contentView.layoutSubtreeIfNeeded()

        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textView.autoresizingMask.contains(.width))
        XCTAssertTrue(textView.textContainer?.widthTracksTextView == true)
        XCTAssertEqual(textView.frame.width, scrollView.contentSize.width, accuracy: 0.5)
        XCTAssertGreaterThan(textView.frame.height, 0)
    }
}
