import ConsolepilotDomain
import XCTest

@testable import ConsolepilotInfrastructure

/// P1-D：统一 Provider stream contract —— fixture 语料驱动的契约测试。
/// fixture 位于 Tests/Fixtures/providers/，由 Scripts/verify-provider-contract.sh 可重复执行。
final class ProviderContractTests: XCTestCase {
    // MARK: - 辅助

    private func makeRequest(provider: ProviderKind) -> ChatRequest {
        let profile = Profile(
            id: "test", provider: provider, baseURL: URL(string: "https://example.com/v1")!,
            model: "test", apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100,
            timeoutSec: 30, priceInput: nil, priceOutput: nil)
        return ChatRequest(
            profile: profile, apiKey: "secret", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hello")], overrides: nil)
    }

    private func loadFixture(_ name: String) -> Data {
        let bundle = Bundle(for: ProviderContractTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "txt") else {
            XCTFail("fixture \(name).txt 未打包进测试资源")
            return Data()
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            XCTFail("读取 fixture \(name).txt 失败：\(error)")
            return Data()
        }
    }

    private func collect(
        provider providerKind: ProviderKind, body: Data, status: Int = 200,
        headers: [String: String] = [:]
    ) async throws -> [StreamEvent] {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (response, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let provider: any AIProvider
        switch providerKind {
        case .openai: provider = OpenAICompatibleProvider(session: session)
        case .anthropic: provider = AnthropicProvider(session: session)
        }
        var collected: [StreamEvent] = []
        for try await event in provider.stream(makeRequest(provider: providerKind)) {
            collected.append(event)
        }
        return collected
    }

    private static func deltas(in events: [StreamEvent]) -> String {
        events.reduce(into: "") { text, event in
            if case .delta(let delta) = event { text += delta }
        }
    }

    private static func containsFailed(_ events: [StreamEvent]) -> Bool {
        events.contains {
            if case .failed = $0 { return true }
            return false
        }
    }

    // MARK: - OpenAI-compatible fixture

    func testOpenAICompatFixtureStreamEmitsTypedEvents() async throws {
        let events = try await collect(
            provider: .openai, body: loadFixture("openai-chat-completion-stream"))

        XCTAssertEqual(events.first, .started(model: "test"))
        XCTAssertEqual(events.last, .finished)
        XCTAssertFalse(Self.containsFailed(events))
        XCTAssertEqual(Self.deltas(in: events), "你好世界")
        XCTAssertTrue(events.contains(.usage(input: 9, output: 6)))
        XCTAssertTrue(events.contains(.finishReason("stop")))
    }

    func testOpenAICompatMalformedFrameFailsWithDecodingError() async throws {
        let events = try await collect(
            provider: .openai, body: loadFixture("openai-malformed-frame"))

        XCTAssertTrue(
            events.contains(.failed(.decoding("OpenAI SSE data 不是有效 JSON"))),
            "畸形 JSON 帧必须映射为 decoding 错误")
    }

    func testOpenAICompatStreamWithoutDoneFailsWithConnectionLost() async throws {
        let events = try await collect(provider: .openai, body: loadFixture("openai-no-done"))

        XCTAssertTrue(
            events.contains(.failed(.connectionLost)),
            "缺少 [DONE] 终止帧必须报告连接中断")
    }

    func testOpenAICompatProviderMapsHTTPStatusToTypedFailure() async throws {
        let statuses: [(Int, TransportError)] = [
            (401, .unauthorized),
            (403, .unauthorized),
            (500, .serverError(status: 500)),
            (503, .serverError(status: 503)),
        ]
        for (status, expected) in statuses {
            let events = try await collect(provider: .openai, body: Data(), status: status)
            XCTAssertTrue(
                events.contains(.failed(expected)),
                "HTTP \(status) 应映射为 \(expected)，实际 \(events)")
        }
    }

    // MARK: - Anthropic fixture

    func testAnthropicFixtureStreamEmitsTypedEvents() async throws {
        let events = try await collect(
            provider: .anthropic, body: loadFixture("anthropic-messages-stream"))

        XCTAssertEqual(events.first, .started(model: "test"))
        XCTAssertEqual(events.last, .finished)
        XCTAssertFalse(Self.containsFailed(events))
        XCTAssertEqual(Self.deltas(in: events), "你好世界")
        XCTAssertTrue(events.contains(.usage(input: 10, output: 0)))
        XCTAssertTrue(events.contains(.usage(input: 0, output: 8)))
    }

    func testAnthropicMalformedFrameFailsWithDecodingError() async throws {
        let events = try await collect(
            provider: .anthropic, body: loadFixture("anthropic-malformed-frame"))

        XCTAssertTrue(
            events.contains(.failed(.decoding("Anthropic SSE data 不是有效 JSON"))),
            "畸形 JSON 帧必须映射为 decoding 错误")
    }

    func testAnthropicStreamWithoutStopFailsWithConnectionLost() async throws {
        let events = try await collect(provider: .anthropic, body: loadFixture("anthropic-no-stop"))

        XCTAssertTrue(
            events.contains(.failed(.connectionLost)),
            "缺少 message_stop 终止事件必须报告连接中断")
    }

    // MARK: - 重试资格与错误映射

    func testTransportErrorRetryEligibility() {
        XCTAssertTrue(TransportError.rateLimited(retryAfter: nil).isRetryable)
        XCTAssertTrue(TransportError.serverError(status: 500).isRetryable)
        XCTAssertFalse(TransportError.serverError(status: 499).isRetryable)
        XCTAssertFalse(TransportError.unauthorized.isRetryable)
        XCTAssertFalse(TransportError.decoding("x").isRetryable)
        XCTAssertFalse(TransportError.cancelled.isRetryable)
    }
}
