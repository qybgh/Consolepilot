import ConsolepilotDomain
import Foundation

package protocol AIProvider: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

package struct ChatRequest: Sendable, Equatable {
    package let profile: Profile
    package let apiKey: String
    package let systemPrompt: String?
    package let messages: [ChatMessage]
    package let overrides: ParamOverrides?

    package init(
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

package struct ChatMessage: Sendable, Equatable {
    package let role: MessageRole
    package let content: String

    package init(role: MessageRole, content: String) {
        self.role = role
        self.content = content
    }
}
