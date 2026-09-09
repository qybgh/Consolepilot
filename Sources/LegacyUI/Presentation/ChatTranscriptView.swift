import AppKit
import ConsolepilotDomain
import ConsolepilotInfrastructure
import CoreText

enum ChatBubbleWidthPolicy {
    static func resolve(
        containsLineBreak: Bool, intrinsicSingleLineWidth: CGFloat, maxWidth: CGFloat,
        minimumWidth: CGFloat = 112
    ) -> CGFloat {
        guard !containsLineBreak, intrinsicSingleLineWidth <= maxWidth else { return maxWidth }
        return min(maxWidth, max(minimumWidth, intrinsicSingleLineWidth))
    }
}

@MainActor
final class ChatTranscriptView: NSView {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private final class MessageBubbleView: NSView {
        override var isFlipped: Bool { true }

        // CopyButton 仅服务气泡内部复制交互，保持类内嵌套封装。
        // swiftlint:disable:next nesting
        private final class CopyButton: NSButton {
            private var trackingArea: NSTrackingArea?

            override func updateTrackingAreas() {
                if let trackingArea { removeTrackingArea(trackingArea) }
                let area = NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self,
                    userInfo: nil)
                addTrackingArea(area)
                trackingArea = area
                super.updateTrackingAreas()
            }

            override func mouseEntered(with event: NSEvent) {
                NSCursor.pointingHand.push()
            }

            override func mouseExited(with event: NSEvent) {
                NSCursor.pop()
            }

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .pointingHand)
            }
        }

        let role: MessageRole
        private let roleLabel = NSTextField(labelWithString: "")
        private let copyButton = CopyButton()
        // NSTextField 使用 NSTextLayer，会把超长消息作为一整块 backing store
        // 反复栅格化。NSTextView 的 TextKit 存储支持增量追加，并会按可见区域绘制。
        private let bodyView = NSTextView(frame: .zero)
        private var rawContent = ""
        private let theme: Theme
        private var cachedWidth: CGFloat = -1
        private var cachedSize: NSSize = .zero
        private var isWaitingForFirstDelta = false
        // 气泡内部左右统一留白。复制按钮位于头部行后，正文无需再为右下角
        // 控件预留整列，文本列可尽量占满气泡宽度、减少窄屏下的换行。
        private let horizontalPadding: CGFloat = 10

        init(header: MessageHeader, theme: Theme) {
            role = header.role
            self.theme = theme
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 10
            layer?.backgroundColor = Self.background(for: role, theme: theme).cgColor

            let time = header.timestamp.formatted(date: .omitted, time: .shortened)
            roleLabel.stringValue = "\(Self.displayName(for: role)) · \(time)"
            roleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            roleLabel.textColor = Self.accent(for: role, theme: theme)
            copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc", accessibilityDescription: "复制消息")
            copyButton.imagePosition = .imageOnly
            copyButton.isBordered = false
            copyButton.bezelStyle = .inline
            copyButton.contentTintColor = theme.foreground.withAlphaComponent(0.5)
            copyButton.toolTip = "复制消息"
            copyButton.target = self
            copyButton.action = #selector(copyMessage)
            bodyView.isEditable = false
            bodyView.isSelectable = true
            bodyView.drawsBackground = false
            bodyView.textContainerInset = .zero
            bodyView.textContainer?.lineFragmentPadding = 0
            bodyView.textContainer?.widthTracksTextView = false
            bodyView.textContainer?.heightTracksTextView = false
            bodyView.isHorizontallyResizable = false
            // 内容写入时视图仍可能是零宽；若允许自动纵向扩张，TextKit 会按
            // 近乎逐字换行的高度扩张，并把这个过大的旧布局带进完成态。
            bodyView.isVerticallyResizable = false
            bodyView.textColor = theme.foreground
            addSubview(roleLabel)
            addSubview(bodyView)
            addSubview(copyButton)
        }

        required init?(coder: NSCoder) { nil }

        func appendStreaming(_ text: String) {
            if isWaitingForFirstDelta {
                bodyView.textStorage?.setAttributedString(NSAttributedString())
            }
            isWaitingForFirstDelta = false
            rawContent.append(text)
            bodyView.textStorage?.append(
                NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: theme.foreground,
                    ]))
            cachedWidth = -1
        }

        func showLoading() {
            guard rawContent.isEmpty else { return }
            isWaitingForFirstDelta = true
            bodyView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: "正在连接 Provider…",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: theme.foreground.withAlphaComponent(0.55),
                    ]))
            cachedWidth = -1
        }

        func setCompletedContent(_ text: String, cache: CompletedMessageCache) {
            rawContent = text
            bodyView.textStorage?.setAttributedString(cache.attributed)
            cachedWidth = -1
        }

        func finishMarkdown() {
            isWaitingForFirstDelta = false
            bodyView.textStorage?.setAttributedString(
                MarkdownMessageRenderer.render(rawContent, theme: theme))
            cachedWidth = -1
        }

        func sizeThatFits(maxWidth: CGFloat) -> NSSize {
            if abs(cachedWidth - maxWidth) < 0.5 { return cachedSize }
            let content = bodyView.textStorage ?? NSTextStorage()
            let width: CGFloat
            let containsLineBreak = content.string.contains("\n")
            if !containsLineBreak {
                let line = CTLineCreateWithAttributedString(content)
                let intrinsicWidth =
                    ceil(
                        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
                    + horizontalPadding * 2 + 2
                // 只有真正能放进一行的短消息才按内容收缩；一旦需要换行，
                // 直接使用固定的完整可用宽度，避免长对话留下无意义的侧边空白。
                width = ChatBubbleWidthPolicy.resolve(
                    containsLineBreak: false, intrinsicSingleLineWidth: intrinsicWidth,
                    maxWidth: maxWidth)
            } else {
                width = ChatBubbleWidthPolicy.resolve(
                    containsLineBreak: true, intrinsicSingleLineWidth: 0, maxWidth: maxWidth)
            }
            let bodyWidth = max(1, width - horizontalPadding * 2)
            guard let textContainer = bodyView.textContainer,
                let layoutManager = bodyView.layoutManager
            else { return NSSize(width: width, height: 58) }
            textContainer.containerSize = NSSize(
                width: bodyWidth, height: CGFloat.greatestFiniteMagnitude)
            // NSTextStorage append already invalidates only the changed tail.
            // Invalidating the entire document for every streaming batch makes
            // long replies O(n²) and blocks the main actor while the network
            // stream continues in the background.
            layoutManager.ensureLayout(for: textContainer)
            let textHeight = layoutManager.usedRect(for: textContainer).height
            cachedWidth = maxWidth
            // Copy 按钮位于头部行，不占用正文区域；高度只需容纳正文与少量
            // 上下呼吸空间，不为右下角控件预留额外整行。
            cachedSize = NSSize(width: width, height: max(58, ceil(textHeight) + 40))
            return cachedSize
        }

        override func layout() {
            super.layout()
            roleLabel.frame = NSRect(
                x: horizontalPadding, y: 10,
                width: max(1, bounds.width - horizontalPadding - 34), height: 15)
            bodyView.frame = NSRect(
                x: horizontalPadding, y: 31,
                width: max(1, bounds.width - horizontalPadding * 2),
                height: max(1, bounds.height - 40))
            copyButton.frame = NSRect(
                x: bounds.width - horizontalPadding - 18, y: 9, width: 18, height: 18)
        }

        @objc private func copyMessage() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawContent, forType: .string)
            copyButton.image = NSImage(
                systemSymbolName: "checkmark", accessibilityDescription: "已复制")
            copyButton.toolTip = "已复制"
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(resetCopyButton), object: nil)
            perform(#selector(resetCopyButton), with: nil, afterDelay: 1.2)
        }

        @objc private func resetCopyButton() {
            copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc", accessibilityDescription: "复制消息")
            copyButton.toolTip = "复制消息"
        }

        private static func displayName(for role: MessageRole) -> String {
            switch role {
            case .user: "你"
            case .assistant: "Consolepilot"
            case .system: "系统"
            case .tool: "工具"
            }
        }

        private static func accent(for role: MessageRole, theme: Theme) -> NSColor {
            theme.roleColors[role] ?? theme.foreground.withAlphaComponent(0.7)
        }

        private static func background(for role: MessageRole, theme: Theme) -> NSColor {
            switch role {
            case .user: NSColor.systemBlue.withAlphaComponent(0.24)
            case .assistant: theme.foreground.withAlphaComponent(0.07)
            case .system, .tool: theme.foreground.withAlphaComponent(0.04)
            }
        }
    }

    private final class CompletedMessageCache {
        let attributed: NSAttributedString

        init(attributed: NSAttributedString) { self.attributed = attributed }
    }

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private var bubbles: [MessageBubbleView] = []
    private var activeBubble: MessageBubbleView?
    private var pendingStreamingText = ""
    private var streamingFlushTask: Task<Void, Never>?
    private var currentSession: Session?
    private var lastLayoutWidth: CGFloat = -1
    private var isHandlingScroll = false
    private var isReplacingHistory = false
    private var completedMessageCache: [String: CompletedMessageCache] = [:]
    private var completedMessageCacheOrder: [String] = []
    var onLoadEarlier: (() -> [Message])?
    private let theme: Theme
    private let gap: CGFloat = 12
    private let inset: CGFloat = 12

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = OverlayScroller()
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { nil }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let width = scrollView.contentSize.width
        if abs(lastLayoutWidth - width) >= 0.5 {
            lastLayoutWidth = width
            layoutBubbles(from: 0)
        }
    }

    var isPinnedToBottom: Bool {
        let clip = scrollView.contentView.bounds
        return documentView.frame.height - clip.maxY <= 48
    }

    func startMessage(_ header: MessageHeader) {
        let follow = isPinnedToBottom
        flushPendingStreamingText()
        activeBubble?.finishMarkdown()
        let bubble = MessageBubbleView(header: header, theme: theme)
        bubbles.append(bubble)
        documentView.addSubview(bubble)
        activeBubble = bubble
        layoutBubbles(from: bubbles.count - 1)
        if follow { scrollToBottom() }
    }

    func append(_ text: String) {
        // StreamCoordinator already coalesces provider deltas into ~17 ms
        // batches. A second timer here can postpone the first visible bytes
        // and starve long replies when TextKit is laying out a growing bubble.
        pendingStreamingText.append(text)
        flushPendingStreamingText()
    }

    func finishMessage() {
        let follow = isPinnedToBottom
        flushPendingStreamingText()
        activeBubble?.finishMarkdown()
        activeBubble = nil
        if !bubbles.isEmpty { layoutBubbles(from: bubbles.count - 1) }
        if follow { scrollToBottom() }
    }

    func clear() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        pendingStreamingText.removeAll(keepingCapacity: true)
        for bubble in bubbles { bubble.removeFromSuperview() }
        bubbles.removeAll()
        activeBubble = nil
        currentSession = nil
        documentView.frame = NSRect(
            x: 0, y: 0, width: max(1, scrollView.contentSize.width),
            height: scrollView.contentSize.height)
    }

    func renderHistory(session: Session?, messages: [Message]) {
        isReplacingHistory = true
        clear()
        guard let session else {
            isReplacingHistory = false
            return
        }
        currentSession = session
        for message in messages {
            let bubble = MessageBubbleView(
                header: MessageHeader(
                    timestamp: message.createdAt, role: message.role, channel: session.channel,
                    model: session.model, sourceApp: session.sourceApp),
                theme: theme)
            bubble.setCompletedContent(message.content, cache: cache(for: message))
            bubbles.append(bubble)
            documentView.addSubview(bubble)
        }
        layoutBubbles(from: 0)
        scrollToBottom()
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = 1
        }
        DispatchQueue.main.async { [weak self] in self?.isReplacingHistory = false }
    }

    func renderStreamingDraft(session: Session, draft: StreamDraft) {
        let bubble = MessageBubbleView(
            header: MessageHeader(
                timestamp: draft.startedAt, role: .assistant, channel: session.channel,
                model: session.model, sourceApp: session.sourceApp),
            theme: theme)
        bubble.appendStreaming(draft.text)
        bubbles.append(bubble)
        documentView.addSubview(bubble)
        activeBubble = bubble
        layoutBubbles(from: bubbles.count - 1)
        scrollToBottom()
    }

    func showStreamingLoading() {
        activeBubble?.showLoading()
        if !bubbles.isEmpty { layoutBubbles(from: bubbles.count - 1) }
    }

    private func prependHistory(_ messages: [Message]) {
        guard let currentSession, !messages.isEmpty else { return }
        let oldHeight = documentView.frame.height
        let oldOriginY = scrollView.contentView.bounds.minY
        let additions = messages.map { message in
            let bubble = MessageBubbleView(
                header: MessageHeader(
                    timestamp: message.createdAt, role: message.role, channel: currentSession.channel,
                    model: currentSession.model, sourceApp: currentSession.sourceApp),
                theme: theme)
            bubble.setCompletedContent(message.content, cache: cache(for: message))
            documentView.addSubview(bubble)
            return bubble
        }
        bubbles.insert(contentsOf: additions, at: 0)
        layoutBubbles(from: 0)
        let heightDelta = documentView.frame.height - oldHeight
        isHandlingScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: oldOriginY + heightDelta))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isHandlingScroll = false
    }

    private func layoutBubbles(from requestedIndex: Int) {
        let viewportWidth = max(1, scrollView.contentSize.width)
        let maxBubbleWidth = max(1, viewportWidth - inset * 2)
        let startIndex = min(max(0, requestedIndex), bubbles.count)
        var cursorY = startIndex == 0 ? inset : bubbles[startIndex - 1].frame.maxY + gap
        for bubble in bubbles.dropFirst(startIndex) {
            let size = bubble.sizeThatFits(maxWidth: maxBubbleWidth)
            let originX = bubble.role == .user ? viewportWidth - inset - size.width : inset
            bubble.frame = NSRect(x: originX, y: cursorY, width: size.width, height: size.height)
            cursorY += size.height + gap
        }
        let height = max(scrollView.contentSize.height, cursorY + inset - gap)
        documentView.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: height)
    }

    private func cache(for message: Message) -> CompletedMessageCache {
        if let cached = completedMessageCache[message.id] { return cached }
        let cached = CompletedMessageCache(
            attributed: MarkdownMessageRenderer.render(message.content, theme: theme))
        completedMessageCache[message.id] = cached
        completedMessageCacheOrder.append(message.id)
        if completedMessageCacheOrder.count > 256 {
            let expired = completedMessageCacheOrder.removeFirst()
            completedMessageCache.removeValue(forKey: expired)
        }
        return cached
    }

    private func scrollToBottom() {
        let clip = scrollView.contentView
        let targetY = max(0, documentView.frame.height - clip.bounds.height)
        isHandlingScroll = true
        clip.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(clip)
        isHandlingScroll = false
    }

    private func flushPendingStreamingText() {
        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        guard !pendingStreamingText.isEmpty else { return }
        let text = pendingStreamingText
        pendingStreamingText.removeAll(keepingCapacity: true)
        let follow = isPinnedToBottom
        activeBubble?.appendStreaming(text)
        if !bubbles.isEmpty { layoutBubbles(from: bubbles.count - 1) }
        if follow { scrollToBottom() }
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard !isHandlingScroll, !isReplacingHistory,
            scrollView.contentView.bounds.minY <= 36
        else { return }
        isHandlingScroll = true
        let older = onLoadEarlier?() ?? []
        if !older.isEmpty { prependHistory(older) }
        isHandlingScroll = false
    }
}
