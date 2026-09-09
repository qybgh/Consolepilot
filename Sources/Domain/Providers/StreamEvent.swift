/// 流式响应事件（跨 Provider 统一），供 StreamCoordinator 汇聚。
public enum StreamEvent: Sendable, Equatable {
    case started(model: String)
    case delta(String)
    case usage(input: Int, output: Int)
    case finishReason(String)
    case finished
    case failed(TransportError)
}
