import Foundation

// OpenAI-compatible `/chat/completions` 线格式的强类型 DTO。全部平铺声明以
// 满足 nesting ≤1；只声明用到的字段，未知字段由 JSONDecoder 自动忽略。

struct OpenAICompatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAICompatRequestBody: Codable {
    let model: String
    let messages: [OpenAICompatMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }
}

struct OpenAICompatStreamChunk: Decodable {
    let choices: [OpenAICompatStreamChoice]?
    let usage: OpenAICompatStreamUsage?
}

struct OpenAICompatStreamChoice: Decodable {
    let delta: OpenAICompatStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

struct OpenAICompatStreamDelta: Decodable {
    let content: String?
}

struct OpenAICompatStreamUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}
