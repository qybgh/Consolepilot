import AppKit
import ConsolepilotCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let textView = NSTextView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存更改", target: nil, action: nil)
    private let discardButton = NSButton(title: "放弃更改", target: nil, action: nil)
    private let reloadButton = NSButton(title: "重新读取", target: nil, action: nil)
    private var configURL: URL?
    private var isDirty = false
    private var isLoading = false
    private var hasPresentedWindow = false
    private let referenceMarker = "# --- Consolepilot 高级配置参考（可复制后取消注释） ---"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 420, height: 360)
        window.title = "Consolepilot 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        configure()
        loadConfig()
    }

    required init?(coder: NSCoder) { nil }

    private func configure() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

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

        content.addSubview(editorScroll)
        content.addSubview(saveButton)
        content.addSubview(discardButton)
        content.addSubview(reloadButton)
        content.addSubview(statusLabel)
        let buttonStack = NSStackView(views: [saveButton, discardButton, reloadButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        content.addSubview(buttonStack)
        saveButton.removeFromSuperview()
        discardButton.removeFromSuperview()
        reloadButton.removeFromSuperview()
        buttonStack.addArrangedSubview(saveButton)
        buttonStack.addArrangedSubview(discardButton)
        buttonStack.addArrangedSubview(reloadButton)
        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            editorScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            editorScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            editorScroll.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -8),
            buttonStack.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            statusLabel.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: editorScroll.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            statusLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func showWindow() {
        if !isDirty { loadConfig() }
        // Force the first layout pass before ordering the window front. This
        // avoids a partially painted text view until the first click/scroll.
        window?.contentView?.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
        if let window { fitWindowToVisibleScreen(window, centerInitially: !hasPresentedWindow) }
        window?.makeKeyAndOrderFront(nil)
        window?.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(textView)
        hasPresentedWindow = true
    }

    private func fitWindowToVisibleScreen(_ window: NSWindow, centerInitially: Bool) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        window.minSize = NSSize(
            width: min(window.minSize.width, visible.width),
            height: min(window.minSize.height, visible.height))
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        if centerInitially {
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
        } else {
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
        }
        window.setFrame(frame, display: false)
    }

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
            // Validation errors leave the editor open and preserve the draft.
            window?.makeKeyAndOrderFront(nil)
            window?.displayIfNeeded()
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
        window?.title = isDirty ? "Consolepilot 设置 · 未保存" : "Consolepilot 设置"
    }

    private func glossaryText() -> NSAttributedString {
        let text = """
            # Consolepilot 配置（中文说明）
            # [general] 通用设置
            # 端口、主题、不透明度、置顶、字体、字号、滚动缓冲、登录启动、呼出快捷键
            # [server] 本地服务设置：鉴权引用和请求体上限
            # [capture] 文本捕获设置：策略顺序、剪贴板等待、恢复和长度限制
            # [[profiles]] Provider：id、provider、baseURL、model、apiKey、temperature、maxTokens、timeoutSec、
            # priceInput、priceOutput
            # [[actions]] Action：id、name、hotkey、profile、systemPrompt、userPrompt、input、attachTo、autoShow、
            # notifyOnDone、overrides
            # [[tails]] 日志尾随：path、enabled、format、fromEnd
            # 密钥只能使用 ${keychain:name} 或 ${env:VAR}，禁止明文写入。
            # 右侧是标准文本编辑器，可鼠标点击、拖选、复制粘贴、撤销并滚动。
            """
        let result = NSMutableAttributedString(string: text)
        result.addAttributes(
            [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1)],
            range: NSRange(location: 0, length: result.length))
        return result
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "设置尚未保存"
        alert.informativeText = "关闭前要放弃当前修改吗？"
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "继续编辑")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
