import AppKit

@MainActor
final class UsageWindowController: NSWindowController {
    private let textView = NSTextView(frame: .zero)
    private let snapshot: () -> String

    init(snapshot: @escaping () -> String) {
        self.snapshot = snapshot
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Consolepilot 用量统计"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        configure()
    }

    required init?(coder: NSCoder) { nil }

    private func configure() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let refresh = NSButton(title: "刷新统计", target: self, action: #selector(refreshSnapshot))
        refresh.translatesAutoresizingMaskIntoConstraints = false
        refresh.bezelStyle = .rounded
        content.addSubview(scroll)
        content.addSubview(refresh)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: refresh.topAnchor, constant: -8),
            refresh.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            refresh.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            refresh.widthAnchor.constraint(equalToConstant: 100),
        ])
    }

    func showWindow() {
        refreshSnapshot()
        window?.center()
        // 用量窗口只由用户主动打开（菜单/状态栏），可激活应用。
        WindowActivationPolicy.present(window, cause: .userInitiated)
    }

    @objc private func refreshSnapshot() {
        textView.string = "Consolepilot 用量统计（仅统计请求次数和 Token 用量）\n\n" + snapshot()
    }
}
