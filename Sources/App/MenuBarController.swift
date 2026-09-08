import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem

    init(show: @escaping () -> Void, settings: @escaping () -> Void, quit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Consolepilot")
        statusItem.button?.toolTip = "Consolepilot"
        let menu = NSMenu(title: "Consolepilot")
        let showItem = menu.addItem(withTitle: "显示 Consolepilot", action: #selector(showMain), keyEquivalent: "")
        showItem.target = self
        let settingsItem = menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出 Consolepilot", action: #selector(terminate), keyEquivalent: "q")
        quitItem.target = self
        self.showAction = show
        self.settingsAction = settings
        self.quitAction = quit
        statusItem.menu = menu
    }

    private var showAction: () -> Void = {}
    private var settingsAction: () -> Void = {}
    private var quitAction: () -> Void = {}

    @objc private func showMain() { showAction() }
    @objc private func openSettings() { settingsAction() }
    @objc private func terminate() { quitAction() }
}
