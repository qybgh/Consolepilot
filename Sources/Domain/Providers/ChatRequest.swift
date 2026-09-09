import Foundation

/// 统一的 Provider 流式请求：Profile 决定端点/模型/超时，overrides 按字段覆盖。
public struct ChatRequest: Sendable, Equatable {
    public let profile: Profile
    public let apiKey: String
    public let systemPrompt: String?
    public let messages: [ChatMessage]
    public let overrides: ParamOverrides?

    public init(
        profile: Profile, apiKey: String, systemPrompt: String?, messages: [ChatMessage],
        overrides: ParamOverrides?
    ) {
        self.profile = profile
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.overrides = overrides
    }
}
