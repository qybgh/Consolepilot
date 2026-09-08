import AppKit
import ConsolepilotCore

@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
    private let rootView: ConsolepilotRootView

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Consolepilot"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.center()
        rootView = ConsolepilotRootView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = rootView
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func persistActiveStreams() {
        rootView.persistActiveStreams()
    }

    func usageSummaryText() -> String { rootView.usageSummaryText() }

    func configuredProfiles() -> [(id: String, name: String)] { rootView.configuredProfiles() }

    func selectProfile(id: String) { rootView.selectProfile(id: id) }

    func quickAsk(_ prompt: String) { rootView.quickAsk(prompt) }

    func setProfilesChangedHandler(_ handler: @escaping ([(id: String, name: String)]) -> Void) {
        rootView.onProfilesChanged = handler
    }

    func showWindow() {
        guard let window else { return }
        NSApp.unhide(nil)
        if let screen = NSScreen.main, !screen.visibleFrame.intersects(window.frame) {
            let origin = NSPoint(
                x: screen.visibleFrame.midX - window.frame.width / 2,
                y: screen.visibleFrame.midY - window.frame.height / 2)
            window.setFrameOrigin(origin)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateLayoutMode(for width: CGFloat) {
        rootView.setCompactMode(width < 700)
    }

    func windowDidResize(_ notification: Notification) {
        guard let width = window?.contentView?.bounds.width else { return }
        updateLayoutMode(for: width)
    }
}
