import Foundation

/// 消息领域实体（纯值类型；持久化映射见 `MessageRecord`）。
public struct Message: Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionId: String
    public let role: MessageRole
    public var content: String
    public var state: MessageState
    public let createdAt: Date

    public init(
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

public enum MessageRole: String, Sendable, CaseIterable { case system, user, assistant, tool }
public enum MessageState: String, Sendable { case complete, interrupted, failed }

public struct MessageHeader: Sendable, Equatable {
    public let timestamp: Date
    public let role: MessageRole
    public let channel: SessionChannel
    public let model: String?
    public let sourceApp: String?

    public init(
        timestamp: Date, role: MessageRole, channel: SessionChannel, model: String?, sourceApp: String?
    ) {
        self.timestamp = timestamp
        self.role = role
        self.channel = channel
        self.model = model
        self.sourceApp = sourceApp
    }
}
