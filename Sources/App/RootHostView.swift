import AppKit
import ConsolepilotCore
import SwiftUI

/// SwiftUI 主窗口内容：把协调器持有的引擎根视图挂载到当前窗口。
///
/// `WindowGroup` 每次（重）建主窗口都会调用本 representable；根视图由
/// `MainWindowCoordinator` 单例持有，关闭窗口不会销毁引擎，重建的窗口
/// 会再次挂载同一个根视图（会话/配置/流状态不变）。
struct RootHostView: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> NSView {
        // 记录「打开主窗口」动作：主窗口被关闭后，菜单/状态栏仍可唤回。
        AppDelegate.shared?.mainWindowCoordinator.openMainWindow = { openWindow(id: "main") }
        return RootViewWrapper()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 包装视图：在加入窗口（SwiftUI 完成布局）后把引擎根视图铺满并注册一次。
@MainActor
private final class RootViewWrapper: NSView {
    private var didAttach = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        attachIfNeeded()
        if let rootView = subviews.first {
            rootView.frame = bounds
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    private func attachIfNeeded() {
        guard !didAttach, window != nil else { return }
        didAttach = true
        guard let appDelegate = AppDelegate.shared else { return }
        let rootView = appDelegate.mainWindowCoordinator.rootView
        if rootView.superview !== self {
            rootView.frame = bounds
            addSubview(rootView)
        }
        appDelegate.registerRootView(rootView)
    }
}
