import AppKit
import ConsolepilotCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ConsoleWindowController?
    private var localServer: LocalServer?
    private var settingsWindowController: SettingsWindowController?
    private var usageWindowController: UsageWindowController?
    private var menuBarController: MenuBarController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Persist any partially received responses before the process exits.
        // Streams are intentionally not resumed automatically; their durable
        // interrupted checkpoint remains visible after relaunch.
        windowController?.persistActiveStreams()
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = ConsoleWindowController()
        controller.showWindow()
        windowController = controller
        ApplicationMenu.updateProfiles(controller.configuredProfiles())
        controller.setProfilesChangedHandler { profiles in
            ApplicationMenu.updateProfiles(profiles)
        }
        menuBarController = MenuBarController(
            show: { [weak self] in self?.showMainWindow(nil) },
            settings: { [weak self] in self?.openSettings(nil) },
            quit: { NSApp.terminate(nil) })
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow(nil)
        }
        return true
    }

    @objc func showMainWindow(_ sender: Any?) {
        windowController?.showWindow()
    }

    @objc func openSettings(_ sender: Any? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow()
    }

    @objc func openAccessibilitySettings(_ sender: Any? = nil) {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc func openUsage(_ sender: Any? = nil) {
        guard let windowController else { return }
        if usageWindowController == nil {
            usageWindowController = UsageWindowController(snapshot: { [weak windowController] in
                windowController?.usageSummaryText() ?? "用量统计暂不可用"
            })
        }
        usageWindowController?.showWindow()
    }

    @objc func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        windowController?.selectProfile(id: id)
    }

    @objc func quickAsk(_ sender: Any? = nil) {
        guard let windowController, let window = windowController.window else { return }
        let alert = NSAlert()
        alert.messageText = "快速提问"
        alert.informativeText = "输入问题后发送到当前 Consolepilot 会话。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "请输入问题"
        alert.accessoryView = field
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak windowController, weak field] response in
            guard response == .alertFirstButtonReturn, let prompt = field?.stringValue else { return }
            windowController?.quickAsk(prompt)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

}
