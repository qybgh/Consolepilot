import AppKit
import ConsolepilotDomain
import ConsolepilotInfrastructure
import SwiftUI

/// SwiftUI `Settings` 场景内容：承载 TOML 配置编辑器。
struct SettingsSceneView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let editor = SettingsEditorView(
            frame: NSRect(origin: .zero, size: SettingsWindowLayout.preferredContentSize))
        context.coordinator.editor = editor
        return editor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        weak var editor: SettingsEditorView?
    }
}

/// Settings 窗口在窄屏/小屏上的尺寸适配规则（纯计算，便于单元测试）。
enum SettingsWindowLayout {
    /// 屏幕可见区域四周预留的边距。
    static let margin: CGFloat = 16
    /// 编辑器理想内容尺寸（宽屏下的初始尺寸）。
    static let preferredContentSize = NSSize(width: 880, height: 640)
    /// 编辑器可接受的最小内容尺寸（保证按钮区/状态栏不丢失）。
    static let minimumContentSize = NSSize(width: 420, height: 320)

    /// 可见区域内可容纳的最大内容尺寸。
    static func availableContentSize(in visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: max(0, visibleFrame.width - margin * 2),
            height: max(0, visibleFrame.height - margin * 2))
    }

    /// 目标内容尺寸：屏幕放得下用 `ideal`；放不下收敛到 `available`；
    /// 任何情况下不小于 `minimum`（除非 `available` 本身更小）。
    static func fittedContentSize(ideal: NSSize, available: NSSize, minimum: NSSize) -> NSSize {
        NSSize(
            width: min(max(ideal.width, minimum.width), available.width),
            height: min(max(ideal.height, minimum.height), available.height))
    }
}

/// TOML 配置编辑器：由原 AppKit 设置窗口内容抽取，去掉窗口级
/// 职责（显示/激活），供 SwiftUI Settings 场景直接承载。负责在窗口挂载、
/// 成为 key 或更换屏幕时，把窗口尺寸收敛到当前屏幕可见区域（窄屏/竖屏
/// 下按钮与滚动条不落到屏幕外）。
@MainActor
final class SettingsEditorView: NSView, NSTextViewDelegate {
    private let textView = NSTextView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存更改", target: nil, action: nil)
    private let discardButton = NSButton(title: "放弃更改", target: nil, action: nil)
    private let reloadButton = NSButton(title: "重新读取", target: nil, action: nil)
    private var configURL: URL?
    private var isDirty = false
    private var isLoading = false
    private let referenceMarker = "# --- Consolepilot 高级配置参考（可复制后取消注释） ---"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        configureSubviews()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        // SwiftUI 以理想尺寸决定 Settings 窗口的初始大小；若布局发生在窗口
        // 已挂载且屏幕放不下理想尺寸时（窄屏/竖屏），直接返回收敛后的尺寸，
        // 避免窗口首帧就超出屏幕。
        guard let window, let screen = window.screen else {
            return SettingsWindowLayout.preferredContentSize
        }
        let available = SettingsWindowLayout.availableContentSize(in: screen.visibleFrame)
        return SettingsWindowLayout.fittedContentSize(
            ideal: SettingsWindowLayout.preferredContentSize,
            available: available,
            minimum: SettingsWindowLayout.minimumContentSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservation()
        // 每次（重新）挂载到窗口时：无未保存草稿则读取磁盘配置，保证与
        // 主窗口的热重载一致；存在未保存草稿则保留，避免覆盖用户编辑。
        if window != nil, !isDirty {
            loadConfig()
        }
        // SwiftUI 完成首帧布局后再收敛一次尺寸（此刻窗口可能尚未可见，
        // 之后的收敛以成为 key / 换屏通知为准）。
        Task { @MainActor in
            self.fitToVisibleScreenIfNeeded()
        }
    }

    // MARK: - 窗口尺寸适配（窄屏/小屏）

    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    /// 跟随窗口的「成为 key / 更换屏幕」通知，及时把窗口收敛进可见区域。
    private func updateWindowObservation() {
        guard let window else {
            removeWindowObservation()
            return
        }
        guard observedWindow !== window else { return }
        removeWindowObservation()
        observedWindow = window
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.fitToVisibleScreenIfNeeded()
                    // SwiftUI 可能在窗口成为 key 后才按理想尺寸重建 frame，
                    // 延迟再收敛一次，避免被覆盖。
                    do {
                        try await Task.sleep(for: .milliseconds(400))
                    } catch {
                        return
                    }
                    self?.fitToVisibleScreenIfNeeded()
                }
            },
            center.addObserver(
                forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.fitToVisibleScreenIfNeeded()
                }
            },
        ]
    }

    private func removeWindowObservation() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        observedWindow = nil
    }

    /// 当窗口超出所在屏幕可见区域（窄屏/竖屏/小屏）时，把内容尺寸收敛到
    /// 可见区域并整体移回屏幕内（顶部对齐，保证标题栏可拖拽）。宽屏或
    /// 用户已手动调小时不干预。
    private func fitToVisibleScreenIfNeeded() {
        guard let window, window.isVisible else { return }
        guard let screen = window.screen ?? Self.screenContaining(window) else { return }
        let visibleFrame = screen.visibleFrame
        let available = SettingsWindowLayout.availableContentSize(in: visibleFrame)
        let currentContent = window.contentRect(forFrameRect: window.frame).size
        guard currentContent.width > available.width || currentContent.height > available.height else {
            return
        }
        let contentSize = SettingsWindowLayout.fittedContentSize(
            ideal: SettingsWindowLayout.preferredContentSize,
            available: available,
            minimum: SettingsWindowLayout.minimumContentSize)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.maxY - frame.height
        window.setFrame(frame, display: true)
        // 允许用户在窄屏上继续缩小（SwiftUI 默认最小尺寸可能大于可见区域）。
        window.contentMinSize = SettingsWindowLayout.fittedContentSize(
            ideal: SettingsWindowLayout.minimumContentSize,
            available: available,
            minimum: .zero)
    }

    private static func screenContaining(_ window: NSWindow) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(window.frame) }
    }

    // MARK: - 子视图布局

    private func configureSubviews() {
        let editorScroll = NSScrollView()
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.documentView = textView
        editorScroll.hasVerticalScroller = true
        // Long TOML values remain reachable on narrow screens. Normal prose
        // still wraps to the viewport; the horizontal scroller is a fallback
        // for exceptionally long URLs or unbroken values.
        editorScroll.hasHorizontalScroller = true
        editorScroll.horizontalScrollElasticity = .none
        editorScroll.autohidesScrollers = true
        editorScroll.scrollerStyle = .overlay
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder

        textView.delegate = self
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        // TOML requires straight ASCII quotes. Disable AppKit smart
        // substitutions so editing never changes `"` into curly quotes.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        textView.insertionPointColor = NSColor.systemTeal
        textView.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping

        for button in [saveButton, discardButton, reloadButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            button.controlSize = .regular
            // Keep the action bar stable; intrinsic button widths can otherwise
            // expand when the status label or window size changes.
            button.widthAnchor.constraint(equalToConstant: 116).isActive = true
        }
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveConfig)
        discardButton.target = self
        discardButton.action = #selector(discardChanges)
        reloadButton.target = self
        reloadButton.action = #selector(reloadConfig)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let buttonStack = NSStackView(views: [saveButton, discardButton, reloadButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        addSubview(editorScroll)
        addSubview(buttonStack)
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            editorScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            editorScroll.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            editorScroll.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -8),
            buttonStack.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            statusLabel.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: editorScroll.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            statusLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    // MARK: - 配置读写

    func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }
        isDirty = true
        updateButtonState()
    }

    private func loadConfig() {
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try LocalServerClientConfiguration.resolveURL()
            configURL = url
            var content = try String(contentsOf: url, encoding: .utf8)
            if !content.contains(referenceMarker) {
                content += "\n\n" + advancedReference
            }
            textView.string = content
            isDirty = false
            statusLabel.stringValue = "当前配置：\(url.path)"
            updateButtonState()
        } catch {
            let message = Self.userFacingConfigError("读取配置失败", error)
            statusLabel.stringValue = message
            statusLabel.toolTip = message
        }
    }

    @objc private func reloadConfig() { loadConfig() }
    @objc private func discardChanges() { loadConfig() }

    @objc private func saveConfig() {
        guard let url = configURL else { return }
        do {
            // Force a native UTF-8-backed String before validation. This avoids
            // TOMLDecoder 0.3's unsafe handling of bridged NSTextView strings.
            guard let content = String(bytes: Array(textView.string.utf8), encoding: .utf8) else { return }
            try LocalServerClientConfiguration.validate(content)
            try content.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            statusLabel.stringValue = "已保存并通过校验，配置将自动热重载"
            updateButtonState()
        } catch {
            let message = Self.userFacingConfigError("保存失败", error)
            statusLabel.stringValue = message
            statusLabel.toolTip = message
            updateButtonState()
        }
    }

    private static func userFacingConfigError(_ prefix: String, _ error: Error) -> String {
        if let configError = error as? ConfigError {
            return "\(prefix)：\(configError.userMessage)"
        }
        return "\(prefix)：\(error.localizedDescription)"
    }

    private func updateButtonState() {
        saveButton.isEnabled = isDirty
        discardButton.isEnabled = isDirty
        reloadButton.isEnabled = !isDirty
    }

    private var advancedReference: String {
        """
        \(referenceMarker)
        # Profile：每个 [[profiles]] 至少需要 id、provider、baseURL、model、apiKey。
        # provider 可选 openai / anthropic；远程 apiKey 必须使用 ${keychain:name} 或 ${env:VAR}。
        # [[profiles]]
        # id = "openai"
        # provider = "openai"
        # baseURL = "https://api.openai.com/v1"
        # model = "gpt-4o-mini"
        # apiKey = "${keychain:openai}"
        # temperature = 0.3
        # maxTokens = 4096
        # timeoutSec = 120
        # priceInput = 0.0
        # priceOutput = 0.0

        # Action：提示词中的 {{input}} 会替换为捕获或命令输入。
        # [[actions]]
        # id = "summarize"
        # name = "总结选中文本"
        # hotkey = "cmd+shift+s"
        # profile = "openai"
        # systemPrompt = "你是一个简洁的助手。"
        # userPrompt = "请总结以下内容：{{input}}"
        # input = "selection"
        # attachTo = "newSession"
        # autoShow = true
        # notifyOnDone = false
        # [actions.overrides]
        # temperature = 0.2
        # maxTokens = 1200
        # model = "gpt-4o-mini"

        # Tail：enabled=true 的日志会在 App 中持续写入日志会话。
        # [[tails]]
        # path = "~/Library/Logs/my-app.log"
        # enabled = true
        # format = "text"
        # fromEnd = true
        """
    }
}
