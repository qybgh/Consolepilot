/// 人工对话（控制台 / CLI ask / HTTP ask）的统一用例契约。
///
/// 所有流式输出只经 StreamCoordinator；本协议描述会话层入口，P1 前不接线。
struct ConversationRequest: Sendable, Equatable {
    let text: String
    /// nil 表示新建会话。
    let sessionId: String?
    let profileId: String
}

struct ConversationResponse: Sendable, Equatable {
    let sessionId: String
    let messageId: String
}

protocol ConversationUseCase {
    /// 发送一轮对话并等待完成，返回承载结果的会话与消息标识。
    func send(_ request: ConversationRequest) async throws -> ConversationResponse
    /// 取消当前进行中的对话流（无进行中对话时为无操作）。
    func cancelCurrent() async throws
}
