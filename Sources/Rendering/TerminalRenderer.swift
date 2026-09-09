import AppKit
import ConsolepilotDomain

@MainActor
final class TerminalRenderer {
    private let textView: TerminalNSTextView?
    private let transcriptView: ChatTranscriptView?
    private var theme: Theme
    private let trimmer: ScrollbackTrimmer
    private var ansiParser = ANSIParser()

    init(textView: TerminalNSTextView, theme: Theme, scrollbackLines: Int) {
        self.textView = textView
        self.transcriptView = nil
        self.theme = theme
        self.trimmer = ScrollbackTrimmer(maxLines: scrollbackLines)
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        textView.textColor = theme.foreground
    }

    init(transcriptView: ChatTranscriptView, theme: Theme, scrollbackLines: Int) {
        self.textView = nil
        self.transcriptView = transcriptView
        self.theme = theme
        self.trimmer = ScrollbackTrimmer(maxLines: scrollbackLines)
    }

    func append(_ batch: TokenBatch) {
        if let transcriptView {
            transcriptView.append(batch.text)
            return
        }
        let shouldFollow = isPinnedToBottom
        let spans = ansiParser.consume(batch.text)
        guard let textView, let storage = textView.textStorage else { return }
        for span in spans {
            storage.append(NSAttributedString(string: span.text, attributes: attributes(for: span.attributes)))
        }
        trimmer.trim(storage)
        if shouldFollow { scrollToBottom() }
    }

    func appendHeader(_ header: MessageHeader) {
        if let transcriptView {
            transcriptView.startMessage(header)
            return
        }
        let shouldFollow = isPinnedToBottom
        guard let textView, let storage = textView.textStorage else { return }
        let source = header.sourceApp.map { " · \($0)" } ?? ""
        let line = "[\(header.timestamp.formatted(date: .omitted, time: .standard))] \(header.role.rawValue)\(source)\n"
        storage.append(NSAttributedString(string: line, attributes: [.foregroundColor: theme.foreground]))
        if shouldFollow { scrollToBottom() }
    }

    func finishStream(state: MessageState) {
        if let transcriptView {
            transcriptView.finishMessage()
            return
        }
        let shouldFollow = isPinnedToBottom
        guard let textView, let storage = textView.textStorage else { return }
        if state == .interrupted {
            storage.append(NSAttributedString(string: " ⚠\n", attributes: [.foregroundColor: NSColor.systemYellow]))
        } else if state == .failed {
            storage.append(NSAttributedString(string: " ✖\n", attributes: [.foregroundColor: NSColor.systemRed]))
        } else {
            storage.append(NSAttributedString(string: "\n", attributes: [.foregroundColor: theme.foreground]))
        }
        if shouldFollow { scrollToBottom() }
    }

    func clear() {
        transcriptView?.clear()
        textView?.textStorage?.setAttributedString(NSAttributedString())
    }

    func renderHistory(session: Session?, messages: [Message]) {
        if let transcriptView {
            transcriptView.renderHistory(session: session, messages: messages)
            return
        }
        clear()
        guard let session else { return }
        for message in messages {
            appendHeader(
                MessageHeader(
                    timestamp: message.createdAt, role: message.role, channel: session.channel,
                    model: session.model, sourceApp: session.sourceApp))
            append(TokenBatch(sessionId: session.id, text: message.content + "\n", deltaCount: 1))
        }
    }

    func renderStreamingDraft(session: Session, draft: StreamDraft) {
        transcriptView?.renderStreamingDraft(session: session, draft: draft)
    }

    func showStreamingLoading() {
        transcriptView?.showStreamingLoading()
    }

    func trimIfNeeded() { if let storage = textView?.textStorage { trimmer.trim(storage) } }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        textView?.backgroundColor = theme.background
        if let storage = textView?.textStorage {
            storage.addAttributes(
                [.foregroundColor: theme.foreground], range: NSRange(location: 0, length: storage.length))
        }
    }

    var isPinnedToBottom: Bool {
        if let transcriptView { return transcriptView.isPinnedToBottom }
        guard let textView, let scrollView = textView.enclosingScrollView else { return true }
        let visibleBottom = scrollView.contentView.bounds.maxY
        let documentBottom = documentHeight
        return documentBottom - visibleBottom <= 48
    }

    private func scrollToBottom() {
        guard let textView else { return }
        guard let scrollView = textView.enclosingScrollView else { return }
        scrollToBottom(in: scrollView)

        // NSTextView 会在当前事件循环末尾重新计算换行高度，再校准一次底部位置。
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let rendererHeight = Self.documentHeight(of: textView)
            Self.scrollToBottom(in: scrollView, documentHeight: rendererHeight)
        }
    }

    private var documentHeight: CGFloat {
        guard let textView else { return 0 }
        return Self.documentHeight(of: textView)
    }

    private static func documentHeight(of textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return textView.bounds.height
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).maxY + textView.textContainerInset.height * 2
        return max(textView.bounds.height, usedHeight)
    }

    private func scrollToBottom(in scrollView: NSScrollView) {
        Self.scrollToBottom(in: scrollView, documentHeight: documentHeight)
    }

    private static func scrollToBottom(in scrollView: NSScrollView, documentHeight: CGFloat) {
        let clipView = scrollView.contentView
        let targetY = max(0, documentHeight - clipView.bounds.height)
        let proposed = NSRect(
            x: clipView.bounds.minX, y: targetY,
            width: clipView.bounds.width, height: clipView.bounds.height)
        let constrained = clipView.constrainBoundsRect(proposed)
        clipView.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func attributes(for ansi: ANSIAttribute) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .foregroundColor: ansi.foreground.flatMap { theme.ansi.indices.contains($0) ? theme.ansi[$0] : nil }
                ?? theme.foreground
        ]
        if let background = ansi.background, theme.ansi.indices.contains(background) {
            result[.backgroundColor] = theme.ansi[background]
        }
        if ansi.bold { result[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold) }
        if ansi.underline { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return result
    }
}
