import AppKit

@MainActor
final class FrontmostAppObserver {
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

struct FrontmostInfo: Sendable, Equatable {
    let appName: String?
    let bundleId: String?
    let windowTitle: String?
}
