import ConsolepilotDomain
import Foundation

/// 把统一 `ChatRequest` 转成各 Provider 的强类型请求体与请求头。
struct RequestBuilder {
    func buildOpenAI(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = try makeRequest(url: request.profile.baseURL, path: "chat/completions", apiKey: request.apiKey)
        urlRequest.timeoutInterval = TimeInterval(request.overrides?.timeoutSec ?? request.profile.timeoutSec)
        let model = request.overrides?.model ?? request.profile.model
        var messages = request.messages.map {
            OpenAICompatMessage(role: $0.role.rawValue, content: $0.content)
        }
        if let system = request.systemPrompt {
            messages.insert(OpenAICompatMessage(role: "system", content: system), at: 0)
        }
        let body = OpenAICompatRequestBody(
            model: model, messages: messages, stream: true,
            temperature: request.overrides?.temperature ?? request.profile.temperature,
            maxTokens: request.overrides?.maxTokens ?? request.profile.maxTokens,
            topP: 0.9, frequencyPenalty: 0, presencePenalty: 0)
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    func buildAnthropic(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = try makeRequest(url: request.profile.baseURL, path: "messages", apiKey: request.apiKey)
        urlRequest.timeoutInterval = TimeInterval(request.overrides?.timeoutSec ?? request.profile.timeoutSec)
        let model = request.overrides?.model ?? request.profile.model
        let messages = request.messages.filter { $0.role != .system }.map {
            AnthropicChatMessage(role: $0.role == .assistant ? "assistant" : "user", content: $0.content)
        }
        let system = request.systemPrompt ?? request.messages.first(where: { $0.role == .system })?.content
        let body = AnthropicRequestBody(
            model: model, messages: messages, system: system,
            maxTokens: request.overrides?.maxTokens ?? request.profile.maxTokens,
            stream: true,
            temperature: request.overrides?.temperature ?? request.profile.temperature)
        urlRequest.httpBody = try JSONEncoder().encode(body)
        // Anthropic authenticates with x-api-key and requires an explicit API
        // version header; Authorization: Bearer is OpenAI-specific.
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    private func makeRequest(url: URL, path: String, apiKey: String) throws -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TransportError.configInvalid("无效 baseURL")
        }
        components.path = components.path.hasSuffix("/") ? components.path + path : components.path + "/" + path
        guard let endpoint = components.url else { throw TransportError.configInvalid("无效 endpoint") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
