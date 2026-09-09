import AppKit

/// 在 SwiftUI 自动生成的主菜单上追加 Consolepilot 专属入口。
///
/// P0-B 起主菜单由 SwiftUI `App` 的场景自动生成（设置 ⌘, / 编辑 / 窗口 /
/// 退出等系统项均由系统提供）。本类型只负责把 Profile 切换、用量统计、
/// 辅助功能设置与快速提问插入「应用菜单」，并维护 Profile 子菜单内容，
/// 从而保留既有 AppKit 菜单入口而无需整体替换 `NSApp.mainMenu`
/// （整体替换会断开 SwiftUI `Settings` 场景的 ⌘, 触发）。
///
/// SwiftUI 会在启动及场景变化（例如打开设置）时重置或重建应用菜单，清掉
/// 外部插入的菜单项。因此采用两层保障：
/// 1. 常驻维护任务每 0.5s 幂等补插一次（覆盖实例被替换/重置）；
/// 2. `menuWillOpen` 在用户展开菜单前即时补插（覆盖展示瞬间的缺失）。
@MainActor
enum ApplicationMenu {
    /// 当前挂载的「切换 Profile」子菜单；被 SwiftUI 重置后随旧菜单一起释放。
    private static weak var profileMenu: NSMenu?
    /// 常驻维护任务（应用生命周期内持有，退出即终止）。
    private static var upkeepTask: Task<Void, Never>?
    /// 应用菜单委托：菜单展开前重新确保自定义项存在。
    private static let installer = AppMenuInstaller()

    /// 启动常驻维护。在 `applicationDidFinishLaunching` 调用（幂等）。
    static func installAdditionalItems() {
        guard upkeepTask == nil else { return }
        upkeepTask = Task { @MainActor in
            while !Task.isCancelled {
                ensureInstalled()
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
        }
    }

    /// 刷新「切换 Profile」子菜单（配置加载/热重载后调用）。若自定义菜单项
    /// 尚未插入（菜单未就绪或曾被重置），先同步插入再填充。
    static func updateProfiles(_ profiles: [(id: String, name: String)]) {
        ensureInstalled()
        guard let profileMenu else { return }
        profileMenu.removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(
                title: profile.name, action: #selector(AppDelegate.selectProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id
            item.target = AppDelegate.shared
            profileMenu.addItem(item)
        }
    }

    /// 菜单就绪后补齐 RootView 已就绪但尚未同步的 Profile 列表。
    static func syncProfileMenuFromRootIfReady() {
        guard let delegate = AppDelegate.shared,
            delegate.mainWindowCoordinator.isRootViewCreated
        else { return }
        delegate.refreshProfileMenuFromRoot()
    }

    /// 幂等插入：应用菜单已挂载且不含自定义项时才插入，并保持委托在位。
    static func ensureInstalled() {
        guard let appMenu else { return }
        if appMenu.delegate !== installer {
            appMenu.delegate = installer
        }
        guard !appMenu.items.contains(where: { $0.title == "切换 Profile" }) else { return }

        let profiles = NSMenuItem(title: "切换 Profile", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "切换 Profile")
        profiles.submenu = submenu
        profileMenu = submenu

        let usage = NSMenuItem(
            title: "用量统计…", action: #selector(AppDelegate.openUsage), keyEquivalent: "")
        usage.target = AppDelegate.shared
        let ax = NSMenuItem(
            title: "打开辅助功能设置", action: #selector(AppDelegate.openAccessibilitySettings), keyEquivalent: "")
        ax.target = AppDelegate.shared
        let quickAsk = NSMenuItem(
            title: "快速提问…", action: #selector(AppDelegate.quickAsk), keyEquivalent: "")
        quickAsk.target = AppDelegate.shared

        if let servicesIndex = appMenu.items.firstIndex(where: { $0.title == "Services" }) {
            appMenu.insertItem(profiles, at: servicesIndex)
            appMenu.insertItem(usage, at: servicesIndex + 1)
            appMenu.insertItem(ax, at: servicesIndex + 2)
            appMenu.insertItem(quickAsk, at: servicesIndex + 3)
        } else {
            // 兜底：找不到系统 Services 项时直接追加到末尾。
            appMenu.addItem(.separator())
            appMenu.addItem(profiles)
            appMenu.addItem(usage)
            appMenu.addItem(ax)
            appMenu.addItem(quickAsk)
        }
    }

    private static var appMenu: NSMenu? {
        // SwiftUI 自动菜单的首项即应用菜单（标题随 App 名，可能为空串）。
        NSApp.mainMenu?.items.first?.submenu
    }
}

/// 应用菜单委托：SwiftUI 重置应用菜单内容后，用户下次展开菜单时重新补插。
@MainActor
private final class AppMenuInstaller: NSObject, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        ApplicationMenu.ensureInstalled()
        ApplicationMenu.syncProfileMenuFromRootIfReady()
    }
}
