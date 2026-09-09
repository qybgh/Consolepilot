import AppKit
import ConsolepilotDomain
import ConsolepilotInfrastructure

/// Keeps NSSplitView's normal divider/layout behavior while allowing the
/// divider to disappear when the sidebar is hidden. Hiding a pane can leave
/// AppKit's divider painted at the old boundary; suppressing only that paint
/// avoids changing divider positions or persisted widths.
private final class SidebarSplitView: NSSplitView {
    var hidesDivider = false {
        didSet { if hidesDivider != oldValue { needsDisplay = true } }
    }

    override func drawDivider(in rect: NSRect) {
        guard !hidesDivider else { return }
        super.drawDivider(in: rect)
    }
}

/// Consolepilot 主窗口的 AppKit 根视图，负责布局与输入事件转发。
public final class ConsolepilotRootView: NSView, NSSplitViewDelegate {
    private enum PreferenceKey {
        static let sidebarVisible = "Consolepilot.sidebarVisible"
        static let sidebarWidth = "Consolepilot.sidebarWidth"
    }

    private let transcriptView: ChatTranscriptView
    private let inputView: TerminalNSTextView
    private let statusLabel: NSTextField
    private let renderer: TerminalRenderer
    private let theme: Theme
    private let splitView = SidebarSplitView()
    private let sidebarView = NSView()
    private let contentView = NSView()
    private let sidebarButton = NSButton()
    private let inputToggleButton = NSButton()
    private let sessionsStack = NSStackView()
    private var sessionStore: SessionStore?
    private var usageStore: UsageStore?
    private var coordinator: StreamCoordinator?
    private var configStore: ConfigStore?
    private var runtimeBindings: RuntimeBindings?
    private var localServer: LocalServer?
    private var actionRunner: ActionRunner?
    private var tailWatchers: [String: FileTailWatcher] = [:]
    private var tailSessions: [String: String] = [:]
    private let mockProvider = MockAIProvider()
    private var requestTasks: [String: Task<Void, Never>] = [:]
    private var actionTasks: [String: Task<Void, Never>] = [:]
    /// 统一取消（`StreamCoordinator.cancel`）的一次性派发任务，随流终态清理。
    private var cancelTasks: [String: Task<Void, Never>] = [:]
    private var pendingActionTask: Task<Void, Never>?
    private var inputHistory: [String] = []
    private var inputHistoryIndex: Int?
    private var selectedProfileId = "mock"
    /// 最后一次生成结果按会话保留，避免完成回调刚显示就被“就绪”状态覆盖。
    /// 新一轮生成开始后该会话的结果会被新的流状态替换。
    private var completionStatuses: [String: String] = [:]
    private static let inputHistoryKey = "Consolepilot.inputHistory"
    private var sidebarVisible = true
    /// Width retained across collapse/expand cycles. NSSplitView may temporarily
    /// compress a hidden subview; keeping this separately prevents that
    /// compressed frame from becoming the next persisted width.
    private var savedSidebarWidth: CGFloat = 180
    private var isProgrammaticSidebarChange = false
    private weak var inputBorderView: NSView?
    private var inputHeightConstraint: NSLayoutConstraint?
    private var inputCollapsedForAction = false
    /// Carbon delivers a hotkey event to Consolepilot itself. Keep the last
    /// externally activated application so selection capture still targets
    /// the app where the user made the selection, even when AppKit reports
    /// Consolepilot as frontmost during the callback.
    private var lastExternalProcessID: pid_t?
    private var frontmostObserverToken: NSObjectProtocol?
    private var localInterruptMonitor: Any?
    public var onProfilesChanged: (([(id: String, name: String)]) -> Void)?

    public override init(frame frameRect: NSRect) {
        theme = Theme.registry["tokyo-night"] ?? Theme.registry.values.first ?? Theme.fallback
        transcriptView = ChatTranscriptView(theme: theme)
        inputView = TerminalNSTextView(frame: .zero)
        statusLabel = NSTextField(labelWithString: "就绪 · Consolepilot")
        renderer = TerminalRenderer(transcriptView: transcriptView, theme: theme, scrollbackLines: 100_000)
        super.init(frame: frameRect)
        inputHistory = UserDefaults.standard.stringArray(forKey: Self.inputHistoryKey) ?? []
        configure()
        trackExternalFrontmostApplication()
        installLocalInterruptMonitor()
        configureMockRuntime()
    }

    required init?(coder: NSCoder) { nil }

    private func installLocalInterruptMonitor() {
        localInterruptMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                event.window === self.window,
                event.modifierFlags.contains(.control),
                !event.modifierFlags.contains(.command),
                !event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.shift),
                // For Control-C AppKit may expose either the printable
                // character or the ETX control character. The hardware
                // key code is stable across both representations.
                event.keyCode == 8,
                let currentId = self.sessionStore?.currentId,
                self.coordinator?.isStreaming(sessionId: currentId) == true
            else { return event }
            self.handle(.interrupt)
            return nil
        }
    }

    private func trackExternalFrontmostApplication() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ownPID
        {
            lastExternalProcessID = app.processIdentifier
        }
        frontmostObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.processIdentifier != ownPID
            else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.lastExternalProcessID = pid
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(inputView)
    }

    public func toggleSidebar() {
        setSidebarVisible(!sidebarVisible, animated: true)
    }

    public func setCompactMode(_ compact: Bool) {
        if compact, sidebarVisible {
            setSidebarVisible(false, animated: true)
        }
    }

    /// Flush in-flight assistant drafts before the application terminates.
    /// The coordinator also checkpoints periodically, but this final synchronous
    /// flush covers a termination that happens between two stream batches.
    public func persistActiveStreams() {
        coordinator?.persistActiveDrafts()
        runtimeBindings?.shutdown()
        for watcher in tailWatchers.values { Task { await watcher.stop() } }
        if let localServer { Task { await localServer.stop() } }
    }

    /// Text snapshot consumed by the lightweight menu-bar usage panel.
    public func usageSummaryText() -> String {
        guard let usageStore else { return "用量统计暂不可用" }
        func line(_ title: String, _ period: UsagePeriod) -> String {
            let summary = usageStore.summary(period: period)
            return
                "\(title)：\(summary.requestCount) 次请求 · 输入 Token \(summary.inputTokens)"
                + " · 输出 Token \(summary.outputTokens)"
        }
        return [
            line("今日", .today),
            line("近 7 天", .week),
            line("全部", .all),
        ].joined(separator: "\n")
    }

    public func configuredProfiles() -> [(id: String, name: String)] {
        guard let configStore, !configStore.current.profiles.isEmpty else { return [("mock", "本地 Mock")] }
        return configStore.current.profiles.map { ($0.id, "\($0.id) · \($0.provider.rawValue)") }
    }

    public func selectProfile(id: String) {
        guard id == "mock" || configStore?.current.profile(id: id) != nil else { return }
        selectedProfileId = id
        statusLabel.stringValue = "已切换 Profile：\(id)"
    }

    public func quickAsk(_ prompt: String) {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        submit(value)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor
        configureSplitView()
        configureSidebar()
        configureContent()

        inputView.onKeyCommand = { [weak self] command in self?.handle(command) }
    }

    private func configureSplitView() {
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        splitView.addSubview(sidebarView)
        splitView.addSubview(contentView)
        let storedWidth = UserDefaults.standard.double(forKey: PreferenceKey.sidebarWidth)
        savedSidebarWidth = clampedSidebarWidth(storedWidth > 0 ? CGFloat(storedWidth) : 180)
        let width = savedSidebarWidth
        sidebarView.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        contentView.frame = NSRect(
            x: width + splitView.dividerThickness, y: 0,
            width: max(0, bounds.width - width - splitView.dividerThickness), height: bounds.height)
        sidebarVisible = UserDefaults.standard.object(forKey: PreferenceKey.sidebarVisible) as? Bool ?? true
        splitView.hidesDivider = !sidebarVisible
        sidebarView.isHidden = !sidebarVisible
        splitView.adjustSubviews()
        if sidebarVisible {
            restoreSidebarWidth()
        }
    }

    private func configureSidebar() {
        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor =
            theme.background.blended(withFraction: 0.08, of: .white)?.cgColor
        let title = NSTextField(labelWithString: "SESSIONS")
        title.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        title.textColor = theme.foreground.withAlphaComponent(0.65)
        title.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(title)
        let clearButton = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: "清空全部会话") ?? NSImage(),
            target: self, action: #selector(confirmDeleteAllSessions))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.contentTintColor = theme.foreground.withAlphaComponent(0.62)
        clearButton.toolTip = "清空全部会话"
        sidebarView.addSubview(clearButton)
        let newButton = NSButton(title: "+ 新建会话", target: self, action: #selector(createNewSession))
        newButton.translatesAutoresizingMaskIntoConstraints = false
        newButton.isBordered = false
        newButton.alignment = .left
        newButton.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        newButton.attributedTitle = NSAttributedString(
            string: "+ 新建会话",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: theme.foreground.withAlphaComponent(0.9),
            ])
        sidebarView.addSubview(newButton)

        sessionsStack.translatesAutoresizingMaskIntoConstraints = false
        sessionsStack.orientation = .vertical
        sessionsStack.alignment = .leading
        sessionsStack.spacing = 4
        sidebarView.addSubview(sessionsStack)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 16),
            clearButton.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            newButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            newButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            sessionsStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 10),
            sessionsStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -10),
            sessionsStack.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: 8),
        ])
    }

    private func configureContent() {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = theme.background.cgColor
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        configureSidebarButton()
        toolbar.addSubview(sidebarButton)
        configureInputToggleButton()
        toolbar.addSubview(inputToggleButton)
        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        let inputBorder = makeInputView()
        inputBorderView = inputBorder

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = theme.foreground.withAlphaComponent(0.65)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(toolbar)
        contentView.addSubview(transcriptView)
        contentView.addSubview(inputBorder)
        contentView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),
            sidebarButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            sidebarButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            inputToggleButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            inputToggleButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            transcriptView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            transcriptView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            transcriptView.bottomAnchor.constraint(equalTo: inputBorder.topAnchor, constant: -8),

            inputBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            inputBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            inputBorder.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -5),

            statusLabel.leadingAnchor.constraint(equalTo: inputBorder.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: inputBorder.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
        inputHeightConstraint = inputBorder.heightAnchor.constraint(equalToConstant: 88)
        inputHeightConstraint?.isActive = true
        updateInputToggleButton()
    }

    private func configureInputToggleButton() {
        inputToggleButton.translatesAutoresizingMaskIntoConstraints = false
        inputToggleButton.bezelStyle = .accessoryBarAction
        inputToggleButton.isBordered = false
        inputToggleButton.contentTintColor = theme.foreground.withAlphaComponent(0.75)
        inputToggleButton.target = self
        inputToggleButton.action = #selector(toggleInputFromButton)
        inputToggleButton.toolTip = "展开对话输入框"
        inputToggleButton.isHidden = true
    }

    private func configureSidebarButton() {
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarButton.bezelStyle = .accessoryBarAction
        sidebarButton.isBordered = false
        sidebarButton.image = NSImage(
            systemSymbolName: "sidebar.left", accessibilityDescription: "显示或隐藏会话侧栏")
        sidebarButton.contentTintColor = theme.foreground.withAlphaComponent(0.75)
        sidebarButton.toolTip = sidebarVisible ? "隐藏会话侧栏" : "显示会话侧栏"
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebarFromButton)
    }

    private func makeInputView() -> NSView {
        let scrollView = NSScrollView()
        configureTerminalScrollView(scrollView, hasVerticalScroller: true)
        configureDocumentTextView(inputView)
        inputView.isEditable = true
        inputView.isRichText = false
        inputView.drawsBackground = true
        inputView.backgroundColor = theme.background.blended(withFraction: 0.025, of: .white) ?? theme.background
        inputView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        inputView.textColor = theme.foreground
        inputView.insertionPointColor = theme.cursor
        inputView.textContainerInset = NSSize(width: 12, height: 8)
        scrollView.documentView = inputView

        let border = NSView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.backgroundColor = theme.background.cgColor
        border.layer?.borderWidth = 1
        border.layer?.borderColor = theme.foreground.withAlphaComponent(0.2).cgColor
        border.layer?.cornerRadius = 5
        border.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: border.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: border.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: border.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: border.bottomAnchor),
        ])
        return border
    }

    private func configureTerminalScrollView(
        _ scrollView: NSScrollView, hasVerticalScroller: Bool
    ) {
        scrollView.hasVerticalScroller = hasVerticalScroller
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        if hasVerticalScroller {
            scrollView.verticalScroller = OverlayScroller()
        }
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
    }

    private func configureDocumentTextView(_ textView: NSTextView) {
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
    }

    @objc private func toggleSidebarFromButton() {
        toggleSidebar()
    }

    @objc private func toggleInputFromButton() {
        setInputCollapsed(!inputCollapsedForAction, animated: true)
    }

    private func setInputCollapsed(_ collapsed: Bool, animated: Bool) {
        guard inputCollapsedForAction != collapsed || inputHeightConstraint?.constant == nil else {
            updateInputToggleButton()
            return
        }
        inputCollapsedForAction = collapsed
        let changes = { [self] in
            inputHeightConstraint?.constant = collapsed ? 0 : 88
            inputBorderView?.isHidden = collapsed
            updateInputToggleButton()
            layoutSubtreeIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                changes()
            }
        } else {
            changes()
        }
    }

    private func updateInputToggleButton() {
        inputToggleButton.isHidden = !inputCollapsedForAction
        inputToggleButton.image = NSImage(
            systemSymbolName: inputCollapsedForAction ? "chevron.up" : "chevron.down",
            accessibilityDescription: inputCollapsedForAction ? "展开对话输入框" : "收起对话输入框")
        inputToggleButton.toolTip = inputCollapsedForAction ? "展开对话输入框" : "收起对话输入框"
    }

    private func setSidebarVisible(_ visible: Bool, animated: Bool) {
        if visible == sidebarVisible {
            if visible { restoreSidebarWidth() }
            return
        }

        // Capture the last real, user-sized width before NSSplitView gets a
        // chance to compress the hidden subview.
        if !visible, sidebarView.frame.width >= 140 {
            savedSidebarWidth = clampedSidebarWidth(sidebarView.frame.width)
            UserDefaults.standard.set(Double(savedSidebarWidth), forKey: PreferenceKey.sidebarWidth)
        }
        sidebarVisible = visible
        UserDefaults.standard.set(visible, forKey: PreferenceKey.sidebarVisible)
        let changes = { [self] in
            isProgrammaticSidebarChange = true
            defer { isProgrammaticSidebarChange = false }
            splitView.hidesDivider = !visible
            sidebarView.isHidden = !visible
            splitView.adjustSubviews()
            if visible {
                restoreSidebarWidth()
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                changes()
            }
        } else {
            changes()
        }
        sidebarButton.toolTip = visible ? "隐藏会话侧栏" : "显示会话侧栏"
    }

    public func splitView(
        _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        140
    }

    public func splitView(
        _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        min(320, splitView.bounds.width * 0.45)
    }

    public func splitViewDidResizeSubviews(_ notification: Notification) {
        guard sidebarVisible, !isProgrammaticSidebarChange, sidebarView.frame.width >= 140 else { return }
        savedSidebarWidth = clampedSidebarWidth(sidebarView.frame.width)
        UserDefaults.standard.set(Double(savedSidebarWidth), forKey: PreferenceKey.sidebarWidth)
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        // During initialization Auto Layout has not assigned splitView its
        // final bounds yet. Do not interpret that transient zero width as a
        // real narrow window, otherwise a persisted width would be reduced to
        // the minimum on every launch.
        let availableWidth = splitView.bounds.width
        let maxWidth =
            availableWidth > 1
            ? min(320, max(140, availableWidth * 0.45))
            : 320
        return min(max(width, 140), maxWidth)
    }

    /// Restore explicitly after NSSplitView has laid out its children. Calling
    /// this twice is intentional: the first pass establishes the new layout,
    /// while the second pass wins over any compression performed by
    /// `adjustSubviews()` when the sidebar was hidden.
    private func restoreSidebarWidth() {
        guard sidebarVisible, !sidebarView.isHidden else { return }
        let target = clampedSidebarWidth(savedSidebarWidth)
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(target, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(target, ofDividerAt: 0)
    }

    private func configureMockRuntime() {
        do {
            let store = try ConfigStore()
            configStore = store
            selectedProfileId = store.current.profiles.first?.id ?? "mock"
            preloadProviderSecrets(store.current)
            store.onChange = { [weak self] _ in
                // Runtime consumers can subscribe here as they are wired in;
                // keep the current UI responsive while configuration reloads.
                guard let self else { return }
                if let first = store.current.profiles.first,
                    store.current.profile(id: self.selectedProfileId) == nil
                {
                    self.selectedProfileId = first.id
                }
                self.onProfilesChanged?(self.configuredProfiles())
                self.statusLabel.stringValue = "配置已热重载 · Consolepilot"
            }
            try store.startWatching()
            // Register configured Action shortcuts in the running App. Carbon
            // delivers the event without stealing focus, so the capture layer
            // can still read the selection from the previously frontmost App.
            let bindings = RuntimeBindings(configStore: store, systemHotkeys: true) { [mockProvider] kind in
                // Keep the default configuration entirely local. Once a
                // profile points at a non-loopback URL, bind the corresponding
                // production SSE provider; the profile's SecretResolver path
                // still controls whether a request may access its API key.
                let hasRemoteProfile = store.current.profiles.contains {
                    $0.provider == kind && !Self.isLoopback($0.baseURL)
                }
                // Real network access is opt-in. Acceptance builds stay on the
                // deterministic Mock provider unless the user explicitly sets
                // CONSOLEPILOT_ENABLE_REAL_PROVIDER=1 in the launching shell.
                guard hasRemoteProfile, store.current.general.allowRealProvider else { return mockProvider }
                switch kind {
                case .openai: return OpenAICompatibleProvider()
                case .anthropic: return AnthropicProvider()
                }
            }
            bindings.onAction = { [weak self] actionID in
                guard let self else { return }
                // Snapshot the source process synchronously while Carbon is
                // dispatching the hotkey. Waiting until the async Action task
                // starts can make Consolepilot appear frontmost, especially
                // when launched through LaunchServices (`open`).
                let sourcePID =
                    self.lastExternalProcessID
                    ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
                let sourcePIDText = sourcePID.map(String.init) ?? "none"
                Log.debug(
                    "Action 触发：id=\(actionID) sourcePID=\(sourcePIDText)", category: .capture)
                self.statusLabel.stringValue = "正在执行 Action：\(actionID) · 捕获选中文字…"
                let task = Task { @MainActor [weak self] in
                    guard let self, let actionRunner = self.actionRunner else { return }
                    do {
                        try await actionRunner.run(actionId: actionID, sourcePID: sourcePID)
                    } catch let error as ConfigError {
                        self.statusLabel.stringValue = error.userMessage
                    } catch let error as CaptureError {
                        self.statusLabel.stringValue = error.userMessage
                    } catch {
                        self.statusLabel.stringValue = "Action 执行失败：\(error.localizedDescription)"
                    }
                }
                self.pendingActionTask = task
            }
            runtimeBindings = bindings
        } catch {
            statusLabel.stringValue = "配置无效 · 请检查 ~/.config/consolepilot/config.toml"
        }
        do {
            let database = try AppDatabase()
            let sessions = try SessionStore(database: database)
            let usage = UsageStore(database: database)
            sessionStore = sessions
            usageStore = usage
            transcriptView.onLoadEarlier = { [weak sessions] in
                sessions?.loadEarlierMessages() ?? []
            }
            let streamCoordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
            streamCoordinator.onDelta = { [weak self] sessionId, batch in
                guard let self, sessionStore?.currentId == sessionId else { return }
                renderer.append(batch)
            }
            streamCoordinator.onStarted = { [weak self] sessionId, _ in
                guard let self, sessionStore?.currentId == sessionId else { return }
                statusLabel.stringValue = "已连接 Provider · 等待首字节…"
            }
            streamCoordinator.onFirstDelta = { [weak self] sessionId, latency in
                guard let self, sessionStore?.currentId == sessionId else { return }
                statusLabel.stringValue = "正在流式生成 · 首字节 \(Self.formatDuration(latency))"
            }
            streamCoordinator.onFinishReason = { [weak self] sessionId, reason in
                guard let self, sessionStore?.currentId == sessionId else { return }
                if reason == "length" {
                    statusLabel.stringValue = "回复达到 maxTokens 上限 · 可继续追问"
                } else {
                    statusLabel.stringValue = "Provider 完成 · finish_reason=\(reason)"
                }
            }
            streamCoordinator.onCompleted = {
                [weak self] sessionId, state, characterCount, reason, firstDeltaLatency, totalDuration in
                guard let self else { return }
                let suffix = reason.map { " · finish_reason=\($0)" } ?? ""
                let firstByte = firstDeltaLatency.map { Self.formatDuration($0) } ?? "—"
                let stateText: String
                switch state {
                case .complete: stateText = "完成"
                case .interrupted: stateText = "中断"
                case .failed: stateText = "失败"
                }
                let status =
                    "回复\(stateText) · \(characterCount) 字符 · 首字 \(firstByte) · 总耗时 "
                    + Self.formatDuration(totalDuration) + suffix
                completionStatuses[sessionId] = status
                actionTasks.removeValue(forKey: sessionId)
                cancelTasks.removeValue(forKey: sessionId)
                if sessionStore?.currentId == sessionId {
                    statusLabel.stringValue = status
                }
            }
            streamCoordinator.onFinish = { [weak self] sessionId, state in
                guard let self, sessionStore?.currentId == sessionId else { return }
                renderer.finishStream(state: state)
                // Action/CLI streams are not represented in requestTasks; defer
                // the state refresh until StreamCoordinator removes its context.
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.updateSessionUIState()
                    self?.reloadSessionButtons()
                }
            }
            coordinator = streamCoordinator
            if let configStore {
                actionRunner = ActionRunner(
                    config: configStore, capture: TextCaptureService(config: configStore.current.capture),
                    secrets: SecretResolver(),
                    providerResolver: { [weak self] kind in self?.runtimeBindings?.provider(for: kind) },
                    coordinator: streamCoordinator, sessionStore: sessions, localProvider: mockProvider)
                actionRunner?.onSessionCreated = { [weak self] id in
                    guard let self else { return }
                    self.prepareActionSession(id)
                    if let task = self.pendingActionTask {
                        self.actionTasks[id] = task
                        self.pendingActionTask = nil
                    }
                }
            }
            reloadSessionButtons()
            if let currentId = sessions.currentId {
                showSession(currentId)
            } else {
                renderer.appendHeader(
                    MessageHeader(
                        timestamp: Date(), role: .system, channel: .console, model: "mock-stream-v1",
                        sourceApp: nil))
                renderer.append(
                    TokenBatch(
                        sessionId: "welcome",
                        text: "Consolepilot Mock 验收模式已启动\n输入消息后按 Enter，不会消耗 API Token。\n",
                        deltaCount: 1))
            }
            updateReadyStatus()
            if let configStore { startLocalServerIfConfigured(store: configStore) }
        } catch {
            statusLabel.stringValue = "数据库初始化失败"
            renderer.append(TokenBatch(sessionId: "error", text: "初始化失败：\(error)\n", deltaCount: 1))
        }
    }

    private func startLocalServerIfConfigured(store: ConfigStore) {
        guard !store.current.server.authTokenRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            let secret = try SecretResolver().resolve(store.current.server.authTokenRef)
            guard !secret.isEmpty else { return }
            let cli = ClosureCLIRouter { [weak self] path, body in
                guard let self else { return (503, Data("Consolepilot unavailable".utf8)) }
                return await self.handleLocalCommand(path: path, body: body)
            }
            let push = ClosurePushRouter { [weak self] body in
                await MainActor.run {
                    guard let self else { return (503, Data("Consolepilot unavailable".utf8)) }
                    return self.handleLocalPush(body: body)
                }
            }
            let server = LocalServer(
                port: store.current.general.port,
                maxBodyBytes: store.current.server.maxBodyBytes,
                authToken: secret,
                cli: cli,
                push: push)
            localServer = server
            Task { [weak self] in
                do {
                    try await server.start()
                    await MainActor.run {
                        self?.statusLabel.stringValue = "本地服务已启动 · 127.0.0.1:\(store.current.general.port)"
                    }
                } catch {
                    await MainActor.run { self?.statusLabel.stringValue = "本地服务未启动 · 端口或鉴权配置不可用" }
                }
            }
        } catch {
            statusLabel.stringValue = "本地服务未启动 · 可在配置中设置 server.authToken"
        }
    }

    /// Resolve remote Provider secrets during App startup so Keychain consent
    /// is requested before the first conversation rather than mid-request.
    private func preloadProviderSecrets(_ config: AppConfig) {
        let resolver = SecretResolver()
        var missing: [String] = []
        for profile in config.profiles where !Self.isLoopback(profile.baseURL) {
            do { _ = try resolver.resolve(profile.apiKeyRef) } catch { missing.append(profile.id) }
        }
        if !missing.isEmpty {
            statusLabel.stringValue = "Provider 密钥待配置：\(missing.joined(separator: ", "))"
        }
    }

    private func handleLocalCommand(path: String, body: Data) async -> (status: Int, body: Data) {
        switch path {
        case "/ask":
            guard let payload = try? JSONDecoder().decode(LocalPrompt.self, from: body), !payload.prompt.isEmpty
            else { return (400, Data("需要 prompt".utf8)) }
            let response = await performExternalAsk(payload.prompt)
            return (200, Data(response.utf8))
        case "/open":
            // `/open` 是用户显式命令（CLI/HTTP），语义等价 userInitiated：
            // 允许激活。P0-B 的 WindowActivationPolicy 位于 App 层，Core 不
            // 反向依赖；P1-A 把本视图迁入 App 层后统一走策略入口。
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return (200, Data("ok".utf8))
        case "/run":
            guard let payload = try? JSONDecoder().decode(LocalAction.self, from: body),
                !payload.actionId.isEmpty
            else { return (400, Data("需要 actionId".utf8)) }
            if payload.actionId == "ask", configStore?.current.action(id: "ask") == nil {
                let response = await performExternalAsk(payload.input ?? "")
                return (200, Data(response.utf8))
            }
            guard let actionRunner else { return (503, Data("ActionRunner 未就绪".utf8)) }
            do {
                try await actionRunner.run(actionId: payload.actionId, overrideInput: payload.input)
                if let id = sessionStore?.sessions.first(where: { $0.actionId == payload.actionId })?.id {
                    showSession(id)
                }
                return (202, Data("accepted".utf8))
            } catch {
                let message = (error as? ConfigError)?.userMessage ?? "请求执行失败"
                return (422, Data(message.utf8))
            }
        case "/tail":
            guard let payload = try? JSONDecoder().decode(LocalTail.self, from: body), !payload.path.isEmpty
            else { return (400, Data("需要 path".utf8)) }
            do {
                try startTail(path: payload.path)
            } catch {
                return (422, Data("无法尾随文件：\(error.localizedDescription)".utf8))
            }
            return (202, Data("accepted".utf8))
        default:
            return (404, Data("Not Found".utf8))
        }
    }

    private func handleLocalPush(body: Data) -> (status: Int, body: Data) {
        guard let payload = try? JSONDecoder().decode(LocalPrompt.self, from: body), !payload.prompt.isEmpty
        else { return (400, Data("需要 prompt".utf8)) }
        let session = sessionStore?.create(
            channel: .push, title: "HTTP 推送",
            meta: SessionMeta(
                actionId: nil, profileId: "mock", provider: .openai, model: "mock-stream-v1", sourceApp: nil))
        if let session {
            sessionStore?.appendMessage(Message(sessionId: session.id, role: .tool, content: payload.prompt))
        }
        reloadSessionButtons()
        return (202, Data("accepted".utf8))
    }

    private struct LocalPrompt: Codable, Sendable {
        let prompt: String
    }

    private struct LocalAction: Codable, Sendable {
        let actionId: String
        let input: String?
    }
    private struct LocalTail: Codable, Sendable { let path: String }

    private func startTail(path: String) throws {
        guard tailWatchers[path] == nil else { return }
        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: expandedPath])
        }
        let watcher = FileTailWatcher(
            config: TailConfig(path: expandedPath, enabled: true, format: .text, fromEnd: true),
            onLine: { [weak self] line in
                Task { @MainActor [weak self] in self?.ingestTailLine(line, path: path) }
            })
        tailWatchers[path] = watcher
        Task { try? await watcher.start() }
    }

    private func ingestTailLine(_ line: String, path: String) {
        guard let sessionStore else { return }
        let session: Session
        if let id = tailSessions[path], let existing = sessionStore.session(id: id) {
            session = existing
        } else {
            session = sessionStore.create(
                channel: .tail, title: "日志尾随",
                meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
            tailSessions[path] = session.id
        }
        sessionStore.appendMessage(Message(sessionId: session.id, role: .tool, content: line))
        reloadSessionButtons()
        // Re-render the active tail session so each newly completed line is
        // visible immediately; the session itself is reused per file path.
        showSession(session.id)
    }

    private func performExternalAsk(_ prompt: String) async -> String {
        guard let sessionStore, let coordinator else { return "Consolepilot 尚未就绪" }
        let session = sessionStore.create(
            channel: .cli, title: Self.title(for: prompt),
            meta: SessionMeta(
                actionId: nil, profileId: "mock", provider: .openai, model: "mock-stream-v1", sourceApp: nil))
        sessionStore.appendMessage(Message(sessionId: session.id, role: .user, content: prompt))
        showSession(session.id)
        renderer.appendHeader(
            MessageHeader(
                timestamp: Date(), role: .assistant, channel: session.channel,
                model: session.model, sourceApp: session.sourceApp))
        renderer.showStreamingLoading()
        let profile = Profile(
            id: "mock", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!, model: "mock-stream-v1",
            apiKeyRef: "", temperature: 0, maxTokens: 4096, timeoutSec: 30, priceInput: 0, priceOutput: 0)
        let request = ChatRequest(
            profile: profile, apiKey: "", systemPrompt: nil, messages: [ChatMessage(role: .user, content: prompt)],
            overrides: nil)
        await coordinator.consume(mockProvider.stream(request), into: session.id)
        reloadSessionButtons()
        return sessionStore.messages.last(where: { $0.sessionId == session.id && $0.role == .assistant })?.content ?? ""
    }

    @objc private func createNewSession() {
        guard let sessionStore else { return }
        let session = sessionStore.create(
            channel: .console, title: "新会话",
            meta: SessionMeta(
                actionId: nil, profileId: "mock", provider: .openai, model: "mock-stream-v1",
                sourceApp: nil))
        setInputCollapsed(false, animated: false)
        renderer.renderHistory(session: session, messages: [])
        reloadSessionButtons()
        updateReadyStatus()
        window?.makeFirstResponder(inputView)
    }

    @objc private func selectSession(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        showSession(id)
    }

    private func showSession(_ id: String) {
        guard let sessionStore else { return }
        sessionStore.select(id)
        let session = sessionStore.session(id: id)
        setInputCollapsed(session?.channel == .action, animated: false)
        // An active stream has a durable checkpoint in the history plus its
        // authoritative in-memory draft. Render only the latter; otherwise a
        // session switch produces two assistant bubbles (the old checkpoint
        // and the live response) and can make the live bubble appear truncated.
        let activeDraft: StreamDraft?
        if coordinator?.isStreaming(sessionId: id) == true {
            activeDraft = coordinator?.draft(sessionId: id)
        } else {
            activeDraft = nil
        }
        let history =
            activeDraft.map { draft in
                sessionStore.messages.filter { $0.id != draft.messageId }
            } ?? sessionStore.messages
        renderer.renderHistory(session: session, messages: history)
        if let session, let draft = activeDraft {
            renderer.renderStreamingDraft(session: session, draft: draft)
        }
        reloadSessionButtons()
        updateSessionUIState()
    }

    /// ActionRunner persists the user's prompt before starting the provider.
    /// Create the live assistant bubble immediately after selecting that
    /// session so deltas have a visible destination while the stream runs.
    private func prepareActionSession(_ id: String) {
        guard let session = sessionStore?.session(id: id) else { return }
        showSession(id)
        // Action shortcuts originate in another App. Do not activate or make
        // Consolepilot key here: the source App must remain frontmost and the
        // main screen must not reveal the background action. A visible window
        // on the user's secondary display still updates immediately.
        renderer.appendHeader(
            MessageHeader(
                timestamp: Date(), role: .assistant, channel: session.channel,
                model: session.model, sourceApp: session.sourceApp))
        // Action requests run independently from the console input. Keep the
        // composer collapsed so long answers have the full vertical viewport;
        // the toolbar chevron can expand it when manual input is needed.
        statusLabel.stringValue = "Action 会话已创建 · 正在请求 Provider…"
    }

    private func reloadSessionButtons() {
        for view in sessionsStack.arrangedSubviews {
            sessionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let sessionStore else { return }
        for session in sessionStore.sessions {
            let selected = session.id == sessionStore.currentId
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            let button = NSButton(
                title: selected ? "▸ \(session.title)" : "  \(session.title)", target: self,
                action: #selector(selectSession(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(session.id)
            button.bezelStyle = .inline
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: selected ? .semibold : .regular)
            button.lineBreakMode = .byTruncatingTail
            button.attributedTitle = NSAttributedString(
                string: selected ? "▸ \(session.title)" : "  \(session.title)",
                attributes: [
                    .font: NSFont.monospacedSystemFont(
                        ofSize: 11, weight: selected ? .semibold : .regular),
                    .foregroundColor: theme.foreground.withAlphaComponent(selected ? 0.95 : 0.65),
                ])
            button.translatesAutoresizingMaskIntoConstraints = false
            let deleteButton = NSButton(
                image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "删除会话") ?? NSImage(),
                target: self, action: #selector(confirmDeleteSession(_:)))
            deleteButton.identifier = NSUserInterfaceItemIdentifier(session.id)
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            deleteButton.isBordered = false
            deleteButton.contentTintColor = theme.foreground.withAlphaComponent(0.48)
            deleteButton.toolTip = "删除会话"
            row.addSubview(button)
            row.addSubview(deleteButton)
            sessionsStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: sessionsStack.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: 26),
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                button.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
                deleteButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                deleteButton.widthAnchor.constraint(equalToConstant: 22),
            ])
        }
    }

    @objc private func confirmDeleteSession(_ sender: NSButton) {
        guard requestTasks.isEmpty else {
            statusLabel.stringValue = "请先中断当前生成，再删除会话"
            return
        }
        guard let id = sender.identifier?.rawValue,
            let title = sessionStore?.session(id: id)?.title
        else { return }
        presentConfirmation(
            title: "删除会话？", message: "“\(title)”及其全部消息将被永久删除。",
            confirmTitle: "删除"
        ) { [weak self] in
            guard let self else { return }
            sessionStore?.delete(id)
            reloadAfterSessionDeletion()
        }
    }

    @objc private func confirmDeleteAllSessions() {
        guard requestTasks.isEmpty else {
            statusLabel.stringValue = "请先中断当前生成，再清空会话"
            return
        }
        guard sessionStore?.sessions.isEmpty == false else { return }
        presentConfirmation(
            title: "清空全部会话？", message: "全部会话及消息将被永久删除，此操作无法撤销。",
            confirmTitle: "清空全部"
        ) { [weak self] in
            guard let self else { return }
            sessionStore?.deleteAll()
            reloadAfterSessionDeletion()
        }
    }

    private func presentConfirmation(
        title: String, message: String, confirmTitle: String, action: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        if let window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { action() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }

    private func reloadAfterSessionDeletion() {
        reloadSessionButtons()
        if let currentId = sessionStore?.currentId {
            showSession(currentId)
        } else {
            renderer.renderHistory(session: nil, messages: [])
            statusLabel.stringValue = "就绪 · 尚无会话"
        }
        window?.makeFirstResponder(inputView)
    }

    private func submit(_ text: String) {
        if text.first == "/" {
            if handleSlashCommand(text) { return }
        }
        guard let sessionStore, let coordinator else { return }
        if inputHistory.last != text {
            inputHistory.append(text)
            if inputHistory.count > 100 { inputHistory.removeFirst(inputHistory.count - 100) }
            UserDefaults.standard.set(inputHistory, forKey: Self.inputHistoryKey)
        }
        inputHistoryIndex = nil
        let session: Session
        if let currentId = sessionStore.currentId, let current = sessionStore.session(id: currentId) {
            session = current
        } else {
            session = sessionStore.create(
                channel: .console, title: Self.title(for: text),
                meta: SessionMeta(
                    actionId: nil, profileId: selectedProfile().id, provider: selectedProfile().provider,
                    model: selectedProfile().model,
                    sourceApp: nil))
        }
        if session.title == "新会话" {
            sessionStore.rename(session.id, to: Self.title(for: text))
        }
        let message = Message(sessionId: session.id, role: .user, content: text)
        completionStatuses.removeValue(forKey: session.id)
        sessionStore.appendMessage(message)
        renderer.appendHeader(
            MessageHeader(
                timestamp: message.createdAt, role: .user, channel: .console, model: selectedProfile().model,
                sourceApp: nil))
        renderer.append(TokenBatch(sessionId: session.id, text: text, deltaCount: 1))
        renderer.appendHeader(
            MessageHeader(
                timestamp: Date(), role: .assistant, channel: .console, model: selectedProfile().model,
                sourceApp: nil))
        renderer.showStreamingLoading()
        inputView.string = ""
        inputView.isEditable = false
        statusLabel.stringValue = "Mock 正在流式生成 · 可切换会话 · ⌃C 中断"
        reloadSessionButtons()
        let profile = selectedProfile()
        let history = sessionStore.messages.map { ChatMessage(role: $0.role, content: $0.content) }
        let apiKey: String
        do {
            apiKey = try SecretResolver().resolve(profile.apiKeyRef)
        } catch {
            statusLabel.stringValue = "Profile \(profile.id) 密钥不可用：\(error.localizedDescription)"
            inputView.isEditable = true
            return
        }
        let request = ChatRequest(
            profile: profile, apiKey: apiKey, systemPrompt: nil, messages: history, overrides: nil)
        let sessionId = session.id
        requestTasks[sessionId] = Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = self.runtimeBindings?.provider(for: profile.provider) ?? self.mockProvider
            await coordinator.consume(provider.stream(request), into: sessionId)
            requestTasks.removeValue(forKey: sessionId)
            reloadSessionButtons()
            if sessionStore.currentId == sessionId {
                updateSessionUIState()
                window?.makeFirstResponder(inputView)
            }
        }
    }

    /// Lightweight command router for the console input. Commands never leave
    /// the process and therefore remain safe while the default provider is Mock.
    private func handleSlashCommand(_ line: String) -> Bool {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let command = parts.first?.lowercased() else { return false }
        switch command {
        case "/code", "/long":
            return false
        case "/help":
            renderer.clear()
            renderer.appendHeader(
                MessageHeader(timestamp: Date(), role: .system, channel: .console, model: nil, sourceApp: nil))
            renderer.append(
                TokenBatch(
                    sessionId: "command", text: "/new 新建会话\n/clear 清空当前显示\n/stop 中断当前生成\n/sessions 显示会话数\n/help 显示帮助\n",
                    deltaCount: 1))
            statusLabel.stringValue = "命令已执行 · /help"
        case "/clear":
            renderer.clear()
            statusLabel.stringValue = "终端已清屏"
        case "/new":
            createNewSession()
        case "/sessions":
            let count = sessionStore?.sessions.count ?? 0
            statusLabel.stringValue = "当前共有 \(count) 个会话"
        case "/stop":
            stopCurrentGeneration()
        default:
            statusLabel.stringValue = "未知命令：\(command) · 输入 /help 查看帮助"
        }
        return true
    }

    /// 停止当前会话的流。统一取消经 `StreamCoordinator.cancel(sessionId:)`
    /// （先同步保留已收内容，再终止执行任务）；UI 层任务句柄同步清理。
    private func stopCurrentGeneration() {
        guard let currentId = sessionStore?.currentId,
            coordinator?.isStreaming(sessionId: currentId) == true
        else {
            statusLabel.stringValue = "当前没有进行中的生成"
            return
        }
        stopGeneration(sessionId: currentId)
    }

    private func stopGeneration(sessionId: String) {
        cancelTasks[sessionId]?.cancel()
        cancelTasks[sessionId] = Task { @MainActor [weak self] in
            await self?.coordinator?.cancel(sessionId: sessionId)
        }
        requestTasks[sessionId]?.cancel()
        requestTasks.removeValue(forKey: sessionId)
        actionTasks[sessionId]?.cancel()
        actionTasks.removeValue(forKey: sessionId)
        statusLabel.stringValue = "已中断 · 已收内容将保留"
        updateSessionUIState()
        reloadSessionButtons()
    }

    private func updateSessionUIState() {
        guard let currentId = sessionStore?.currentId else {
            inputView.isEditable = true
            updateReadyStatus()
            return
        }
        let streaming =
            requestTasks[currentId] != nil
            || coordinator?.isStreaming(sessionId: currentId) == true
        inputView.isEditable = !streaming
        if streaming {
            statusLabel.stringValue = "Mock 正在流式生成 · 可切换会话 · ⌃C 中断"
        } else {
            updateReadyStatus()
        }
    }

    private func updateReadyStatus() {
        if let currentId = sessionStore?.currentId,
            let completionStatus = completionStatuses[currentId]
        {
            statusLabel.stringValue = completionStatus
            return
        }
        let count = usageStore?.summary(period: .all).requestCount ?? 0
        statusLabel.stringValue = "就绪 · Profile \(selectedProfileId) · 已完成 \(count) 次请求"
    }

    private func selectedProfile() -> Profile {
        if let profile = configStore?.current.profile(id: selectedProfileId) { return profile }
        return Profile(
            id: "mock", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!,
            model: "mock-stream-v1", apiKeyRef: "", temperature: 0, maxTokens: 4096,
            timeoutSec: 30, priceInput: 0, priceOutput: 0)
    }

    private static func title(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "新会话"
        return String(line.prefix(20))
    }

    private static func formatDuration(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Int(Double(components.attoseconds) / 1_000_000_000_000_000)
        return "\(components.seconds).\(String(format: "%03d", milliseconds))s"
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func handle(_ command: TerminalKeyCommand) {
        switch command {
        case .submit:
            let text = inputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            guard let currentId = sessionStore?.currentId else {
                submit(text)
                return
            }
            guard coordinator?.isStreaming(sessionId: currentId) != true else { return }
            submit(text)
        case .newline:
            inputView.insertNewline(nil)
        case .clear:
            renderer.clear()
            statusLabel.stringValue = "终端已清屏"
        case .interrupt:
            stopCurrentGeneration()
        case .complete:
            statusLabel.stringValue = "暂无补全候选"
        case .historyPrev:
            navigateInputHistory(direction: -1)
        case .historyNext:
            navigateInputHistory(direction: 1)
        }
    }

    private func navigateInputHistory(direction: Int) {
        guard !inputHistory.isEmpty else { return }
        let current = inputHistoryIndex ?? inputHistory.count
        let next = min(max(current + direction, 0), inputHistory.count)
        inputHistoryIndex = next == inputHistory.count ? nil : next
        inputView.string = next == inputHistory.count ? "" : inputHistory[next]
        inputView.setSelectedRange(NSRange(location: inputView.string.utf16.count, length: 0))
        window?.makeFirstResponder(inputView)
    }
}
