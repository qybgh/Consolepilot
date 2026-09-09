import AppKit

/// 窗口显示统一策略：只有用户主动触发（菜单/状态栏/快捷键/显式命令）才允许
/// 调用 `activate(ignoringOtherApps:)` 抢焦点；后台动作（Action 触发、通知、
/// 自动展示）一律只 orderFront，不激活应用，避免打断用户当前前台应用。
@MainActor
enum WindowActivationPolicy {
    enum Cause {
        /// 用户明确要求显示（菜单、状态栏、快捷键、显式 CLI 命令）。
        case userInitiated
        /// 后台动作要求展示结果（Action 完成、CLI/HTTP 自动推送），不抢焦点。
        case background
    }

    /// 按策略显示窗口：userInitiated 会激活应用；background 仅前置不激活。
    static func present(_ window: NSWindow?, cause: Cause) {
        guard let window else { return }
        switch cause {
        case .userInitiated:
            NSApp.unhide(nil)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        case .background:
            window.orderFrontRegardless()
        }
    }
}
