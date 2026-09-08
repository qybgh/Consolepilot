import AppKit
@preconcurrency import Carbon.HIToolbox

@MainActor
struct SimulatedCopyCapture {
    func copyAndRead(wait: Duration, restore: Bool, targetPID: pid_t? = nil) async throws -> String {
        guard !SecureInputDetector.isActive else { throw CaptureError.secureInputActive }
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let originalChangeCount = pasteboard.changeCount
        let targetPID = targetPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        Log.debug("模拟复制开始：pid=\(targetPID.map(String.init) ?? "none") changeCount=\(originalChangeCount)", category: .capture)
        defer {
            if restore { snapshot.restore(to: pasteboard) }
        }

        // Send a real key-down/key-up pair. Some AppKit clients ignore two
        // events posted back-to-back, so leave a small gap between them. The
        // event is posted globally and never activates Consolepilot, keeping
        // the user's current App and screen undisturbed.
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        else { throw CaptureError.noPermission }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        func postPair(to pid: pid_t?) async throws {
            if let pid {
                keyDown.postToPid(pid)
            } else {
                keyDown.post(tap: .cghidEventTap)
            }
            // Keep the key held long enough for Electron, browser and remote
            // desktop clients to observe the modifier transition.
            try await Task.sleep(for: .milliseconds(12))
            if let pid {
                keyUp.postToPid(pid)
            } else {
                keyUp.post(tap: .cghidEventTap)
            }
        }

        try await postPair(to: targetPID)

        // A number of Electron/web clients update NSPasteboard lazily. Keep
        // the configured delay as the lower bound, but allow up to 500 ms for
        // the targeted copy to arrive before reporting an empty selection.
        // If a target process rejects PID-directed events, retry once through
        // the HID tap. This still leaves the original App frontmost and is
        // transparent to the user; the changeCount guard below prevents stale
        // clipboard contents from being accepted.
        let primaryDeadline = ContinuousClock.now + .milliseconds(180)
        while pasteboard.changeCount == originalChangeCount && ContinuousClock.now < primaryDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if pasteboard.changeCount == originalChangeCount, targetPID != nil {
            Log.debug("目标进程未响应，回退 HID 投递", category: .capture)
            try await postPair(to: nil)
        }
        let deadline = ContinuousClock.now + max(wait, .milliseconds(500))
        while pasteboard.changeCount == originalChangeCount && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // A failed synthetic ⌘C leaves the previous clipboard untouched. Do
        // not mistake that stale value for the currently selected text.
        guard pasteboard.changeCount != originalChangeCount else {
            Log.warn("模拟复制未改变剪贴板：changeCount=\(originalChangeCount)", category: .capture)
            throw CaptureError.emptySelection
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            Log.warn("模拟复制已改变剪贴板但没有字符串内容", category: .capture)
            throw CaptureError.emptySelection
        }
        Log.debug("模拟复制成功：字符数=\(text.count)", category: .capture)
        return text
    }
}
