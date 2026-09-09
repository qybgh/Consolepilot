import AppKit
import ConsolepilotCore

/// 应用生命周期桥接：持有主窗口协调器、菜单栏与用量窗口，并把 AppKit
/// 菜单/状态栏入口转发到 SwiftUI 场景。
///
/// P0-B 起窗口由 SwiftUI `WindowGroup` 创建与重建；`MainWindowCoordinator`
/// 持有跨窗口存活的引擎根视图，负责「显示主窗口 / 打开设置 / 快速提问 /
/// 用量统计 / 退出前持久化」。Dock 重新唤起交给 SwiftUI 原生处理（重建
/// 主窗口并重新挂载同一引擎），不再自建窗口，避免出现重复窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 当前 AppDelegate 实例。SwiftUI 生命周期下 `NSApp.delegate` 是 SwiftUI
    /// 内部的代理对象，无法直接转型访问；菜单目标与 representable 经此访问。
    static weak var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    /// 主窗口协调器（持有跨窗口存活的引擎根视图）。
    let mainWindowCoordinator = MainWindowCoordinator()
    private var menuBarController: MenuBarController?
    private var usageWindowController: UsageWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationMenu.installAdditionalItems()
        menuBarController = MenuBarController(
            show: { [weak self] in self?.showMainWindow(nil) },
            settings: { [weak self] in self?.openSettings(nil) },
            quit: { NSApp.terminate(nil) })
    }

    /// 由 `RootHostView` 在根视图挂载到窗口时调用。幂等：同一引擎根视图
    /// 每次（重新）挂载只建立一次 Profile 回调，并刷新一次菜单内容。
    func registerRootView(_ rootView: ConsolepilotRootView) {
        if rootView.onProfilesChanged == nil {
            rootView.onProfilesChanged = { [weak self] profiles in
                self?.refreshProfileMenu(profiles)
            }
        }
        refreshProfileMenu(rootView.configuredProfiles())
    }

    private func refreshProfileMenu(_ profiles: [(id: String, name: String)]) {
        ApplicationMenu.updateProfiles(profiles)
    }

    /// 菜单就绪后由 ApplicationMenu 回调，补齐根视图已就绪的 Profile 列表。
    /// 引擎尚未创建时跳过（不为此触发完整引擎初始化）。
    func refreshProfileMenuFromRoot() {
        guard mainWindowCoordinator.isRootViewCreated else { return }
        ApplicationMenu.updateProfiles(mainWindowCoordinator.rootView.configuredProfiles())
    }

    // MARK: - 生命周期

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 退出前冲刷流式草稿；流不自动恢复，中断检查点在重启后仍可见。
        mainWindowCoordinator.persistActiveStreams()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 主窗口 / 设置 / 用量 / Profile 动作

    @objc func showMainWindow(_ sender: Any?) {
        mainWindowCoordinator.showMainWindow()
    }

    @objc func openSettings(_ sender: Any? = nil) {
        mainWindowCoordinator.openSettings()
    }

    @objc func openAccessibilitySettings(_ sender: Any? = nil) {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc func openUsage(_ sender: Any? = nil) {
        guard mainWindowCoordinator.isRootViewCreated else { return }
        if usageWindowController == nil {
            usageWindowController = UsageWindowController(snapshot: { [weak self] in
                guard let self, self.mainWindowCoordinator.isRootViewCreated else {
                    return "用量统计暂不可用"
                }
                return self.mainWindowCoordinator.rootView.usageSummaryText()
            })
        }
        usageWindowController?.showWindow()
    }

    @objc func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        mainWindowCoordinator.selectProfile(id: id)
    }

    @objc func quickAsk(_ sender: Any? = nil) {
        mainWindowCoordinator.quickAsk()
    }
}
