import Foundation

/// 统一流式聊天 Provider 契约：OpenAI-compatible / Anthropic / Mock 均实现
/// 同一 stream 接口；具体网络实现只存在于 Infrastructure。
public protocol AIProvider: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}
