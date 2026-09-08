import Foundation

struct RequestBuilder {
    func buildOpenAI(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = try makeRequest(
            url: request.profile.baseURL, path: "chat/completions", apiKey: request.apiKey,
            contentType: "application/json")
        urlRequest.timeoutInterval = TimeInterval(request.profile.timeoutSec)
        let model = request.overrides?.model ?? request.profile.model
        var messages = request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        if let system = request.systemPrompt { messages.insert(["role": "system", "content": system], at: 0) }
        var body: [String: Any] = [
            "model": model, "messages": messages, "stream": true,
            "top_p": 0.9, "frequency_penalty": 0, "presence_penalty": 0,
        ]
        body["temperature"] = request.overrides?.temperature ?? request.profile.temperature
        body["max_tokens"] = request.overrides?.maxTokens ?? request.profile.maxTokens
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    func buildAnthropic(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = try makeRequest(
            url: request.profile.baseURL, path: "messages", apiKey: request.apiKey,
            contentType: "application/json")
        let model = request.overrides?.model ?? request.profile.model
        var messages = request.messages.filter { $0.role != .system }.map {
            ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content]
        }
        let system = request.systemPrompt ?? request.messages.first(where: { $0.role == .system })?.content
        var body: [String: Any] = [
            "model": model, "messages": messages, "stream": true,
            "max_tokens": request.overrides?.maxTokens ?? request.profile.maxTokens,
        ]
        if let system { body["system"] = system }
        body["temperature"] = request.overrides?.temperature ?? request.profile.temperature
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Anthropic authenticates with x-api-key and requires an explicit API
        // version header; Authorization: Bearer is OpenAI-specific.
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = TimeInterval(request.profile.timeoutSec)
        return urlRequest
    }

    private func makeRequest(url: URL, path: String, apiKey: String, contentType: String) throws -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TransportError.configInvalid("无效 baseURL")
        }
        components.path = components.path.hasSuffix("/") ? components.path + path : components.path + "/" + path
        guard let endpoint = components.url else { throw TransportError.configInvalid("无效 endpoint") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        return request
    }
}
