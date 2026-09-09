import AppKit
import ConsolepilotDomain
import XCTest

@testable import ConsolepilotInfrastructure

final class TransportTests: XCTestCase {
    func testTransportHTTPStatusMappingIsSharedAcrossProviders() throws {
        XCTAssertNoThrow(try TransportSupport.validateHTTPStatus(200))
        XCTAssertThrowsError(try TransportSupport.validateHTTPStatus(401)) { error in
            XCTAssertEqual(error as? TransportError, .unauthorized)
        }

        do {
            try TransportSupport.validateHTTPStatus(429, headers: ["Retry-After": "7"])
            XCTFail("expected rate limit")
        } catch let error as TransportError {
            XCTAssertEqual(error, .rateLimited(retryAfter: .seconds(7)))
        }

        do {
            try TransportSupport.validateHTTPStatus(503)
            XCTFail("expected server error")
        } catch let error as TransportError {
            XCTAssertEqual(error, .serverError(status: 503))
        }
    }

    func testTransportMapsTimeoutAndCancellationWithoutCollapsingToConnectionLost() {
        XCTAssertEqual(TransportSupport.map(URLError(.timedOut)), .network(.timedOut))
        XCTAssertEqual(TransportSupport.map(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(TransportSupport.map(CancellationError()), .cancelled)
    }

    func testMalformedProviderSSEPayloadIsReportedAsDecodingError() async throws {
        let profile = Profile(
            id: "test", provider: .openai, baseURL: URL(string: "https://example.com/v1")!, model: "test",
            apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100, timeoutSec: 30, priceInput: nil, priceOutput: nil)
        let request = ChatRequest(
            profile: profile, apiKey: "secret", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hello")], overrides: nil)
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"])!
            return (response, Data("data: {not-json}\n\n".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let provider = OpenAICompatibleProvider(session: URLSession(configuration: configuration))
        var events: [StreamEvent] = []
        for try await event in provider.stream(request) { events.append(event) }
        XCTAssertTrue(events.contains { $0 == .failed(.decoding("OpenAI SSE data 不是有效 JSON")) })
    }

    func testOpenAIStreamWithoutDoneFrameIsReportedAsConnectionLost() async throws {
        let profile = Profile(
            id: "test", provider: .openai, baseURL: URL(string: "https://example.com/v1")!, model: "test",
            apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100, timeoutSec: 30, priceInput: nil, priceOutput: nil)
        let request = ChatRequest(
            profile: profile, apiKey: "secret", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hello")], overrides: nil)
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\n".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let provider = OpenAICompatibleProvider(session: URLSession(configuration: configuration))
        var events: [StreamEvent] = []
        for try await event in provider.stream(request) { events.append(event) }
        XCTAssertTrue(events.contains { $0 == .failed(.connectionLost) })
    }

    func testOpenAIStreamTreatsDoneFrameAsTheOnlyNormalTerminalMarker() async throws {
        let profile = Profile(
            id: "test", provider: .openai, baseURL: URL(string: "https://example.com/v1")!, model: "test",
            apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100, timeoutSec: 30, priceInput: nil, priceOutput: nil)
        let request = ChatRequest(
            profile: profile, apiKey: "secret", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hello")], overrides: nil)
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let provider = OpenAICompatibleProvider(session: URLSession(configuration: configuration))
        var events: [StreamEvent] = []
        for try await event in provider.stream(request) { events.append(event) }
        XCTAssertEqual(events.last, .finished)
        XCTAssertFalse(
            events.contains {
                if case .failed = $0 { return true }
                return false
            })
        XCTAssertTrue(events.contains { $0 == .delta("ok") })
    }

    func testSSEDecoderHandlesSplitUTF8AndSplitLine() {
        var decoder = SSEDecoder()
        let bytes = Array("event: message\ndata: 你好\n\n".utf8)
        let split = bytes.firstIndex(of: 0xE4)! + 1
        XCTAssertTrue(decoder.consume(bytes[..<split]).isEmpty)
        XCTAssertEqual(decoder.consume(bytes[split...]), [SSEFrame(event: "message", data: "你好")])
    }

    func testSSEDecoderJoinsMultipleDataLinesAndIgnoresComments() {
        var decoder = SSEDecoder()
        let text = ": keepalive\nevent: delta\ndata: one\ndata: two\n\n"
        XCTAssertEqual(decoder.consume(text.utf8), [SSEFrame(event: "delta", data: "one\ntwo")])
    }

    func testSSEDecoderFlushesFinalFrameWithoutBlankLine() {
        var decoder = SSEDecoder()
        _ = decoder.consume("data: final".utf8)
        XCTAssertEqual(decoder.flush(), [SSEFrame(event: nil, data: "final")])
    }

    func testRequestBuilderHonorsOverridesAndProviderHeaders() throws {
        let profile = Profile(
            id: "test", provider: .openai, baseURL: URL(string: "https://example.com/v1")!, model: "base",
            apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100, timeoutSec: 30, priceInput: nil, priceOutput: nil)
        let request = ChatRequest(
            profile: profile, apiKey: "secret-value", systemPrompt: "system",
            messages: [ChatMessage(role: .user, content: "hello")],
            overrides: ParamOverrides(temperature: 0.8, maxTokens: 20, model: "override"))
        let built = try RequestBuilder().buildOpenAI(request)
        XCTAssertEqual(built.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(built.value(forHTTPHeaderField: "Authorization"), "Bearer secret-value")
        let body = try JSONDecoder().decode(
            OpenAICompatRequestBody.self, from: XCTUnwrap(built.httpBody))
        XCTAssertEqual(body.model, "override")
        XCTAssertEqual(body.maxTokens, 20)
        XCTAssertEqual(body.temperature, 0.8)
        XCTAssertEqual(body.stream, true)
        XCTAssertEqual(body.messages.map(\.content), ["system", "hello"])
        XCTAssertEqual(built.timeoutInterval, 30, "未设置 Action 级 timeoutSec 时回退 profile 默认值")

        let overridden = ChatRequest(
            profile: profile, apiKey: "secret-value", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hi")],
            overrides: ParamOverrides(temperature: nil, maxTokens: nil, model: nil, timeoutSec: 60))
        XCTAssertEqual(try RequestBuilder().buildOpenAI(overridden).timeoutInterval, 60)

        let anthropicProfile = Profile(
            id: "anthropic", provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!, model: "claude",
            apiKeyRef: "env:KEY", temperature: 0.2, maxTokens: 100, timeoutSec: 9, priceInput: nil, priceOutput: nil)
        let anthropicRequest = ChatRequest(
            profile: anthropicProfile, apiKey: "anthropic-secret", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "hello")], overrides: nil)
        let anthropicBuilt = try RequestBuilder().buildAnthropic(anthropicRequest)
        XCTAssertEqual(anthropicBuilt.value(forHTTPHeaderField: "x-api-key"), "anthropic-secret")
        XCTAssertEqual(anthropicBuilt.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(anthropicBuilt.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(anthropicBuilt.timeoutInterval, 9)
        let anthropicBody = try JSONDecoder().decode(
            AnthropicRequestBody.self, from: XCTUnwrap(anthropicBuilt.httpBody))
        XCTAssertNil(anthropicBody.system)
        XCTAssertEqual(anthropicBody.messages.map(\.content), ["hello"])
    }

    @MainActor
    func testStreamCoordinatorPersistsOnlyFinalAssistantMessage() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoordinator-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Test",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuation.yield(.started(model: "test"))
            for _ in 0..<1_000 { continuation.yield(.delta("x")) }
            continuation.yield(.finished)
            continuation.finish()
        }
        await coordinator.consume(events, into: session.id)
        XCTAssertFalse(coordinator.isStreaming)
        XCTAssertEqual(sessions.messages.last?.content.count, 1_000)
        let count = try await database.writer.read { db in try MessageRecord.fetchCount(db) }
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testStreamCoordinatorReportsCompletionTimingAndFinishReason() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoordinatorTiming-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Timing",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        struct Completion {
            var count: Int
            var reason: String?
            var first: Duration?
            var total: Duration?
        }
        var completion: Completion?
        coordinator.onCompleted = { _, _, count, reason, first, total in
            completion = Completion(count: count, reason: reason, first: first, total: total)
        }
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuation.yield(.started(model: "test"))
            continuation.yield(.delta("hello"))
            continuation.yield(.finishReason("stop"))
            continuation.yield(.finished)
            continuation.finish()
        }
        await coordinator.consume(events, into: session.id)
        XCTAssertEqual(completion?.count, 5)
        XCTAssertEqual(completion?.reason, "stop")
        XCTAssertNotNil(completion?.first)
        XCTAssertNotNil(completion?.total)
        if let first = completion?.first, let total = completion?.total {
            XCTAssertGreaterThanOrEqual(total, first)
        }
    }

    @MainActor
    func testStreamCoordinatorCoalescesThousandDeltas() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoalescing-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Coalescing",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        var batches = 0
        var reconstructed = ""
        coordinator.onDelta = { _, batch in
            batches += 1
            reconstructed += batch.text
        }
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            for _ in 0..<1_000 { continuation.yield(.delta("x")) }
            continuation.yield(.finished)
            continuation.finish()
        }
        await coordinator.consume(events, into: session.id)
        XCTAssertEqual(reconstructed.count, 1_000)
        XCTAssertLessThan(batches, 100, "UI must receive coalesced batches, not one callback per delta")
    }

    @MainActor
    func testStreamCoordinatorDoesNotWriteSQLiteDuringActiveStream() async throws {
        let trace = SQLTraceBox()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotTrace-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path) { sql in trace.append(sql) }
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Trace",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        trace.removeAll()
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation = $0 }
        let task = Task { await coordinator.consume(events, into: session.id) }
        continuation.yield(.started(model: "test"))
        continuation.yield(.delta("prefix"))
        try await Task.sleep(for: .milliseconds(40))
        let activeWrites = trace.values.filter {
            $0.localizedCaseInsensitiveContains("INSERT") || $0.localizedCaseInsensitiveContains("UPDATE")
        }
        XCTAssertTrue(activeWrites.isEmpty, "streaming must not persist assistant rows before terminal state")
        continuation.yield(.finished)
        continuation.finish()
        await task.value
        let finalWrites = trace.values.filter {
            $0.localizedCaseInsensitiveContains("INSERT") || $0.localizedCaseInsensitiveContains("UPDATE")
        }
        XCTAssertFalse(finalWrites.isEmpty, "terminal state must persist the assistant message")
    }

    @MainActor
    func testStreamCoordinatorInterruptPersistsCompleteReceivedPrefix() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotInterruptPrefix-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Interrupt",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation = $0 }
        let task = Task { await coordinator.consume(events, into: session.id) }
        continuation.yield(.started(model: "test"))
        continuation.yield(.delta("prefix-"))
        continuation.yield(.delta("完整-"))
        try await Task.sleep(for: .milliseconds(20))
        coordinator.interrupt(sessionId: session.id)
        task.cancel()
        continuation.finish()
        await task.value

        let stored = try await database.writer.read { db in try MessageRecord.fetchAll(db).map(\.entity) }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].content, "prefix-完整-")
        XCTAssertEqual(stored[0].state, .interrupted)
    }

    @MainActor
    func testStreamCoordinatorKeepsConcurrentSessionDraftsIsolated() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotConcurrentCoordinator-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let first = sessions.create(
            channel: .console, title: "First",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let second = sessions.create(
            channel: .console, title: "Second",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        var emitted: [String: String] = [:]
        coordinator.onDelta = { sessionId, batch in emitted[sessionId, default: ""] += batch.text }

        var firstContinuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
        let firstEvents = AsyncThrowingStream<StreamEvent, Error> { firstContinuation = $0 }
        var secondContinuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
        let secondEvents = AsyncThrowingStream<StreamEvent, Error> { secondContinuation = $0 }
        let firstTask = Task { await coordinator.consume(firstEvents, into: first.id) }
        let secondTask = Task { await coordinator.consume(secondEvents, into: second.id) }
        await Task.yield()

        firstContinuation.yield(.delta("abc"))
        secondContinuation.yield(.delta("xyz"))
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(coordinator.draft(sessionId: first.id)?.text, "abc")
        XCTAssertEqual(coordinator.draft(sessionId: second.id)?.text, "xyz")
        XCTAssertTrue(coordinator.isStreaming(sessionId: first.id))
        XCTAssertTrue(coordinator.isStreaming(sessionId: second.id))

        firstContinuation.yield(.delta("def"))
        secondContinuation.yield(.finished)
        secondContinuation.finish()
        await secondTask.value
        XCTAssertTrue(coordinator.isStreaming(sessionId: first.id))
        XCTAssertFalse(coordinator.isStreaming(sessionId: second.id))

        firstContinuation.yield(.finished)
        firstContinuation.finish()
        await firstTask.value
        XCTAssertEqual(emitted[first.id], "def")
        let stored = try await database.writer.read { db in try MessageRecord.fetchAll(db).map(\.entity) }
        XCTAssertEqual(stored.first(where: { $0.sessionId == first.id })?.content, "abcdef")
        XCTAssertEqual(stored.first(where: { $0.sessionId == second.id })?.content, "xyz")
    }

    @MainActor
    func testStreamCoordinatorPersistsEarlyPrefixWhenStreamEndsWithoutFinishedEvent() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotEarlyInterrupt-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Early interrupt",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuation.yield(.started(model: "test"))
            continuation.yield(.delta("early prefix"))
            // Simulates provider cancellation before it emits `.finished`.
            continuation.finish()
        }

        await coordinator.consume(events, into: session.id)

        let stored = try await database.writer.read { db in try MessageRecord.fetchAll(db).map(\.entity) }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.content, "early prefix")
        XCTAssertEqual(stored.first?.state, .interrupted)
    }

    func testTemplateEngineRendersKnownPlaceholdersAndLeavesNoTokens() {
        let engine = TemplateEngine()
        let context = TemplateContext(
            input: "selected", selection: "selected", clipboard: "clip",
            frontmost: FrontmostInfo(appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Doc"),
            now: Date(timeIntervalSince1970: 0), language: "Swift")
        let output = engine.render(
            "{{app}} {{bundleId}} {{windowTitle}} {{input}} {{selection}} {{clipboard}} {{language}}", context: context)
        XCTAssertEqual(output, "Notes com.apple.Notes Doc selected selected clip Swift")
        XCTAssertEqual(TemplateEngine.placeholders(in: "{{input}} {{input}} {{unknown}}"), ["input", "unknown"])
    }

    func testMockProviderStreamsLocallyAndReportsUsage() async throws {
        let profile = Profile(
            id: "mock", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!,
            model: "mock-stream-v1", apiKeyRef: "", temperature: 0, maxTokens: 100,
            timeoutSec: 10, priceInput: 0, priceOutput: 0)
        let request = ChatRequest(
            profile: profile, apiKey: "", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "你好")], overrides: nil)
        var text = ""
        var usage: (Int, Int)?
        for try await event in MockAIProvider(delay: .zero).stream(request) {
            if case .delta(let value) = event { text += value }
            if case .usage(let input, let output) = event { usage = (input, output) }
        }
        XCTAssertTrue(text.contains("Consolepilot 本地 Mock Provider"))
        XCTAssertNotNil(usage)
    }

    func testMockProviderDoesNotEchoUserPromptInAssistantReply() async throws {
        let profile = Profile(
            id: "mock", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!,
            model: "mock-stream-v1", apiKeyRef: "", temperature: 0, maxTokens: 100,
            timeoutSec: 10, priceInput: 0, priceOutput: 0)
        let prompt = "这是一段不应被助手重复的用户输入"
        let request = ChatRequest(
            profile: profile, apiKey: "", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: prompt)], overrides: nil)
        var text = ""
        for try await event in MockAIProvider(delay: .zero).stream(request) {
            if case .delta(let value) = event { text += value }
        }
        XCTAssertFalse(text.contains("已收到："))
        XCTAssertFalse(text.contains(prompt))
    }

    @MainActor
    func testDelayedMockProviderCompletesThroughMainActorCoordinator() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotMockCoordinator-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Mock",
            meta: SessionMeta(
                actionId: nil, profileId: "mock", provider: .openai, model: "mock-stream-v1",
                sourceApp: nil))
        sessions.appendMessage(Message(sessionId: session.id, role: .user, content: "集成测试"))
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        let profile = Profile(
            id: "mock", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!,
            model: "mock-stream-v1", apiKeyRef: "", temperature: 0, maxTokens: 100,
            timeoutSec: 10, priceInput: 0, priceOutput: 0)
        let request = ChatRequest(
            profile: profile, apiKey: "", systemPrompt: nil,
            messages: [ChatMessage(role: .user, content: "集成测试")], overrides: nil)
        await coordinator.consume(
            MockAIProvider(delay: .milliseconds(1)).stream(request), into: session.id)
        XCTAssertTrue(
            sessions.messages.contains {
                $0.role == .assistant && $0.content.contains("Consolepilot 本地 Mock Provider")
            })
        XCTAssertEqual(usage.summary(period: .all).requestCount, 1)
    }
}

private final class SQLTraceBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [String] = []
    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
    func removeAll() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }
}
