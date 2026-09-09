/// 跨应用后台 Action 的统一用例契约（捕获、模板渲染、独立会话、通知）。
///
/// `sessionMode`、`autoShow`、`notifyOnDone`、`timeoutSec` 等语义来自
/// Action 配置本身，不在请求参数中重复；P1 前不接线。
public struct ActionExecutionRequest: Sendable, Equatable {
    public let actionId: String
    public let overrideInput: String?

    public init(actionId: String, overrideInput: String?) {
        self.actionId = actionId
        self.overrideInput = overrideInput
    }
}

public struct ActionExecutionResponse: Sendable, Equatable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public protocol ActionExecutionUseCase {
    /// 执行指定 Action 并在其独立后台会话中完成请求。
    func run(_ request: ActionExecutionRequest) async throws -> ActionExecutionResponse
}
