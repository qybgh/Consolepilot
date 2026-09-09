import SwiftUI

/// Consolepilot 的 SwiftUI 入口（P0-B 起替代 AppKit `ConsolepilotMain`）。
///
/// 场景结构：
/// - `WindowGroup("main")`：主窗口，内容为 `RootHostView`（经 NSViewRepresentable
///   承载既有 AppKit `ConsolepilotRootView`，引擎根视图由协调器持有、
///   跨窗口重建存活）。
/// - `Settings`：系统设置场景（⌘,），内容为 `SettingsEditorView` 的
///   representable 包装。
///
/// 主窗口关闭后由 SwiftUI 原生处理 Dock 重新唤起（重建窗口并重新挂载
/// 同一引擎），因此移除 File > New Window，保证始终只有一个主窗口。
/// 生命周期与菜单/状态栏接线全部在 `AppDelegate`（见 `AppDelegate.swift`）。
@main
struct ConsolepilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Consolepilot", id: "main") {
            RootHostView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            // 单主窗口应用：隐藏 File > New Window，避免多窗口各自承载引擎。
            CommandGroup(replacing: .newItem) {}
        }
        Settings {
            SettingsSceneView()
        }
    }
}
