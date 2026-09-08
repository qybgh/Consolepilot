import Foundation

protocol AIProvider: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

struct ChatRequest: Sendable, Equatable {
    let profile: Profile
    let apiKey: String
    let systemPrompt: String?
    let messages: [ChatMessage]
    let overrides: ParamOverrides?
}

struct ChatMessage: Sendable, Equatable {
    let role: MessageRole
    let content: String
}
