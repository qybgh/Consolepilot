import AppKit
@preconcurrency import ApplicationServices

struct AccessibilityCapture {
    func selectedText() throws -> String {
        guard AXIsProcessTrusted() else { throw CaptureError.noPermission }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw CaptureError.allStrategiesFailed }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let focused = value else {
            throw CaptureError.allStrategiesFailed
        }
        let focusedElement = unsafeBitCast(focused, to: AXUIElement.self)
        var selected: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, &selected)
        guard selectedStatus == .success, let text = selected as? String, !text.isEmpty else {
            throw CaptureError.emptySelection
        }
        return text
    }

    func focusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused) == .success,
            let window = focused
        else { return nil }
        let windowElement = unsafeBitCast(window, to: AXUIElement.self)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        return title as? String
    }
}
