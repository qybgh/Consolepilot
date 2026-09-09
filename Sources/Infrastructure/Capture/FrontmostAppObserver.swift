import AppKit
import ConsolepilotDomain

@MainActor
package final class FrontmostAppObserver {
    package init() {}
    func processIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func snapshot() -> FrontmostInfo {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostInfo(
            appName: app?.localizedName, bundleId: app?.bundleIdentifier,
            windowTitle: PermissionChecker.hasAccessibility ? AccessibilityCapture().focusedWindowTitle() : nil)
    }
}
