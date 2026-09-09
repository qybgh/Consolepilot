import AppKit
import UserNotifications

/// Action 完成/失败提示。通知正文只含状态与 Action 名，绝不含捕获正文或回复内容。
enum ActionNotifier {
    static func notify(title: String, failed: Bool) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = failed ? "执行失败，请在 Consolepilot 中查看详情" : "已完成"
            content.sound = .default
            center.add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
