/// 人工对话（控制台 / CLI ask / HTTP ask）的统一用例契约。
///
/// 所有流式输出只经 StreamCoordinator；本协议描述会话层入口，P1 前不接线。
public struct ConversationRequest: Sendable, Equatable {
    public let text: String
    /// nil 表示新建会话。
    public let sessionId: String?
    public let profileId: String

    public init(text: String, sessionId: String?, profileId: String) {
        self.text = text
        self.sessionId = sessionId
        self.profileId = profileId
    }
}

public struct ConversationResponse: Sendable, Equatable {
    public let sessionId: String
    public let messageId: String

    public init(sessionId: String, messageId: String) {
        self.sessionId = sessionId
        self.messageId = messageId
    }
}

public protocol ConversationUseCase {
    /// 发送一轮对话并等待完成，返回承载结果的会话与消息标识。
    func send(_ request: ConversationRequest) async throws -> ConversationResponse
    /// 取消当前进行中的对话流（无进行中对话时为无操作）。
    func cancelCurrent() async throws
}
