/// 一次请求内的单条消息（角色 + 纯文本内容）。
public struct ChatMessage: Sendable, Equatable {
    public let role: MessageRole
    public let content: String

    public init(role: MessageRole, content: String) {
        self.role = role
        self.content = content
    }
}
