import AppKit

/// 只绘制滑块、不绘制系统轨道背景，适合深色终端界面。
final class OverlayScroller: NSScroller {
    override var isOpaque: Bool { false }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 3, dy: 1)
        guard !knobRect.isEmpty else { return }
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 4, yRadius: 4).fill()
    }
}
