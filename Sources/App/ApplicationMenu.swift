import AppKit

@MainActor
enum ApplicationMenu {
    private static weak var profileMenu: NSMenu?
    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func applicationMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Consolepilot")
        item.submenu = menu
        menu.addItem(
            withTitle: "关于 Consolepilot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "设置…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        menu.addItem(
            withTitle: "打开辅助功能设置", action: #selector(AppDelegate.openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(
            withTitle: "用量统计…", action: #selector(AppDelegate.openUsage), keyEquivalent: "")
        let profiles = NSMenuItem(title: "切换 Profile", action: nil, keyEquivalent: "")
        let profileSubmenu = NSMenu(title: "切换 Profile")
        profiles.submenu = profileSubmenu
        profileMenu = profileSubmenu
        menu.addItem(profiles)
        menu.addItem(
            withTitle: "快速提问…", action: #selector(AppDelegate.quickAsk), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "隐藏 Consolepilot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 Consolepilot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    static func updateProfiles(_ profiles: [(id: String, name: String)]) {
        guard let profileMenu else { return }
        profileMenu.removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(
                title: profile.name, action: #selector(AppDelegate.selectProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id
            item.target = NSApp.delegate
            profileMenu.addItem(item)
        }
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        item.submenu = menu
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "窗口")
        item.submenu = menu
        menu.addItem(
            withTitle: "显示主窗口", action: Selector(("showMainWindow:")), keyEquivalent: "0")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(
            withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = menu
        return item
    }
}
