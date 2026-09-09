import Foundation

// Anthropic Messages API（stream-json）线格式的强类型 DTO。全部平铺声明以
// 满足 nesting ≤1；只声明用到的字段，未知字段由 JSONDecoder 自动忽略。

struct AnthropicChatMessage: Codable {
    let role: String
    let content: String
}

struct AnthropicRequestBody: Codable {
    let model: String
    let messages: [AnthropicChatMessage]
    let system: String?
    let maxTokens: Int
    let stream: Bool
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, messages, system, stream, temperature
        case maxTokens = "max_tokens"
    }
}

struct AnthropicMessageStart: Decodable {
    let message: AnthropicMessageStartPayload?
}

struct AnthropicMessageStartPayload: Decodable {
    let usage: AnthropicUsageBox?
}

struct AnthropicContentBlockDelta: Decodable {
    let delta: AnthropicTextDelta?
}

struct AnthropicTextDelta: Decodable {
    let text: String?
}

struct AnthropicMessageDelta: Decodable {
    let usage: AnthropicUsageBox?
}

struct AnthropicUsageBox: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
