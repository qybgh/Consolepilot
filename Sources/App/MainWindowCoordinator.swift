import AppKit
import ConsolepilotCore

/// 主窗口协调器：持有跨窗口存活的引擎根视图（会话/配置/流/本地服务），
/// 并承担「显示主窗口 / 打开设置 / 快速提问 / 用量快照 / 退出前持久化」。
///
/// SwiftUI `WindowGroup` 的主窗口可被用户关闭、并在 Dock 重新唤起时由系统
/// 重建；引擎根视图不随窗口销毁，重建的窗口会重新挂载同一个根视图，
/// 从而既保持原生窗口生命周期，又不丢失会话与后台 Action 状态。
@MainActor
final class MainWindowCoordinator {
    private var rootViewStorage: ConsolepilotRootView?

    /// 引擎根视图：首次访问时创建，之后跨窗口关闭/重建存活。
    var rootView: ConsolepilotRootView {
        if let rootViewStorage { return rootViewStorage }
        let view = ConsolepilotRootView(frame: .zero)
        rootViewStorage = view
        return view
    }

    /// 引擎根视图是否已创建（避免「仅刷新菜单」等轻量路径误触发完整引擎）。
    var isRootViewCreated: Bool { rootViewStorage != nil }

    /// 由 SwiftUI 注入的「打开主窗口」动作（`openWindow(id: "main")`）；
    /// 主窗口被关闭后，经菜单/状态栏唤回时使用。
    var openMainWindow: (() -> Void)?

    // MARK: - 动作

    /// 用户主动唤回（菜单/状态栏）：窗口存在则前置（可激活），
    /// 不存在则让 SwiftUI 新建主窗口并挂载既有引擎。
    func showMainWindow() {
        if isRootViewCreated, let window = rootView.window {
            present(window)
        } else {
            openMainWindow?()
        }
    }

    /// 打开系统设置场景（SwiftUI `Settings`），用户主动触发。
    func openSettings() {
        // SwiftUI Settings 场景由 ⌘, 菜单项（系统自动生成）触发；这里等价于
        // 用户点按该菜单项，仅在找不到时退化为 sendAction 兜底。
        if let settingsItem = Self.settingsMenuItem() {
            NSApp.activate(ignoringOtherApps: true)
            if let menu = settingsItem.menu {
                menu.performActionForItem(at: menu.index(of: settingsItem))
            }
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    /// 退出前冲刷流式草稿并关闭本地服务（幂等；引擎未创建则无操作）。
    func persistActiveStreams() {
        guard isRootViewCreated else { return }
        rootView.persistActiveStreams()
    }

    func selectProfile(id: String) {
        guard isRootViewCreated else { return }
        rootView.selectProfile(id: id)
    }

    /// 快速提问：主窗口可见则直接弹输入框；否则先唤回主窗口，待窗口挂载
    /// （引擎就绪）后再弹出。
    func quickAsk() {
        if isRootViewCreated, let window = rootView.window, window.isVisible {
            presentQuickAsk(on: window)
            return
        }
        showMainWindow()
        Task { @MainActor in
            for _ in 0..<24 {
                if let window = self.rootView.window, window.isVisible {
                    self.presentQuickAsk(on: window)
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - 私有

    private func present(_ window: NSWindow) {
        // 窗口滑出可见屏幕时先移回可见区域。
        if let screen = NSScreen.main, !screen.visibleFrame.intersects(window.frame) {
            window.setFrameOrigin(
                NSPoint(
                    x: screen.visibleFrame.midX - window.frame.width / 2,
                    y: screen.visibleFrame.midY - window.frame.height / 2))
        }
        WindowActivationPolicy.present(window, cause: .userInitiated)
    }

    private func presentQuickAsk(on window: NSWindow) {
        guard isRootViewCreated else { return }
        let rootView = self.rootView
        let alert = NSAlert()
        alert.messageText = "快速提问"
        alert.informativeText = "输入问题后发送到当前 Consolepilot 会话。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "请输入问题"
        alert.accessoryView = field
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
            rootView.quickAsk(field.stringValue)
        }
    }

    /// 查找 SwiftUI 为 `Settings` 场景自动生成的主菜单项（标题随系统本地化，
    /// 键位固定为 ⌘,）。
    private static func settingsMenuItem() -> NSMenuItem? {
        NSApp.mainMenu?.items
            .compactMap { $0.submenu?.items.first { $0.keyEquivalent == "," } }
            .first
    }
}
