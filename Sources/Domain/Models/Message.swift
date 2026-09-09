import Foundation

/// 消息领域实体（纯值类型；持久化映射见 `MessageRecord`）。
struct Message: Identifiable, Sendable, Equatable {
    let id: String
    let sessionId: String
    let role: MessageRole
    var content: String
    var state: MessageState
    let createdAt: Date

    init(
        id: String = UUID().uuidString, sessionId: String, role: MessageRole, content: String,
        state: MessageState = .complete, createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.state = state
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Sendable, CaseIterable { case system, user, assistant, tool }
enum MessageState: String, Sendable { case complete, interrupted, failed }

struct MessageHeader: Sendable, Equatable {
    let timestamp: Date
    let role: MessageRole
    let channel: SessionChannel
    let model: String?
    let sourceApp: String?
}
