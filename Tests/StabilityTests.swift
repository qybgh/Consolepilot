import ConsolepilotDomain
import GRDB
import XCTest

@testable import ConsolepilotInfrastructure

/// PLAN §6.2 Mock 稳定性/性能门禁：
/// - 100 串行 Action 后请求注册表空、无残留任务、usage 恰好一次、无库锁错；
/// - 10 并发 Action 会话互不串线且终态注册表清空；
/// - 10,000 个 SSE delta 无丢失、无重复（内存回放 + 落库单行完整）；
/// - 配置加载（解析+校验）基准回归护栏。
final class StabilityTests: XCTestCase {
    @MainActor
    private struct Harness {
        let sessions: SessionStore
        let usage: UsageStore
        let coordinator: StreamCoordinator
        let runner: ActionRunner
    }

    private func makeConfigText(actions: [String]) -> String {
        let actionBlocks = actions.map { id in
            """
                [[actions]]
                id = "\(id)"
                name = "\(id)"
                profile = "local"
                userPrompt = "请总结：{{input}}"
                input = "prompt"
                sessionMode = "dedicated"
                timeoutSec = 30
            """
        }.joined(separator: "\n")
        return """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            \(actionBlocks)
            """
    }

    @MainActor
    private func makeHarness(actions: [String]) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotStability-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeConfigText(actions: actions).write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        let runner = ActionRunner(
            config: config, capture: TextCaptureService(config: config.current.capture),
            secrets: SecretResolver(), providers: [.openai: MockAIProvider(delay: .zero)],
            coordinator: coordinator, sessionStore: sessions)
        return Harness(sessions: sessions, usage: usage, coordinator: coordinator, runner: runner)
    }

    @MainActor
    func testOneHundredSerialActionRunsLeaveCleanRegistryAndExactUsage() async throws {
        let harness = try makeHarness(actions: ["summarize"])
        let sessions = harness.sessions
        let usage = harness.usage
        let coordinator = harness.coordinator
        let runner = harness.runner
        var sessionIDs: Set<String> = []
        for round in 1...100 {
            let sessionID = try await runner.run(
                actionId: "summarize", overrideInput: "第\(round)轮")
            sessionIDs.insert(sessionID)
            XCTAssertFalse(
                coordinator.isStreaming,
                "round \(round) 结束后请求注册表必须清空（无残留流/任务）")
            XCTAssertFalse(coordinator.isStreaming(sessionId: sessionID))
        }
        XCTAssertEqual(sessionIDs.count, 1, "dedicated 会话应按 actionId+sourceApp 复用一个会话")
        XCTAssertEqual(sessions.sessions.count, 1)
        let sessionID = try XCTUnwrap(sessionIDs.first)
        let users = sessions.history(sessionId: sessionID).filter { $0.role == .user }
        let assistants = sessions.history(sessionId: sessionID).filter { $0.role == .assistant }
        XCTAssertEqual(users.count, 100, "100 轮用户消息全部落库（无丢失）")
        XCTAssertEqual(assistants.count, 100, "100 轮助手回复全部落库（无丢失/无重复）")
        XCTAssertEqual(users.first?.content, "请总结：第1轮")
        XCTAssertEqual(users.last?.content, "请总结：第100轮")
        // 每轮恰好一次 usage：无重复、无丢失；若 SQLite 出现锁/忙错误而被静默吞掉，
        // 消息数或 usage 计数会小于期望，从而在此暴露。
        XCTAssertEqual(usage.summary(period: .all).requestCount, 100)
    }

    @MainActor
    func testTenConcurrentActionRunsStayIsolatedWithExactUsage() async throws {
        let actionIDs = (0..<10).map { "summarize-\($0)" }
        let harness = try makeHarness(actions: actionIDs)
        let sessions = harness.sessions
        let usage = harness.usage
        let coordinator = harness.coordinator
        let runner = harness.runner
        try await withThrowingTaskGroup(of: String.self) { group in
            for actionID in actionIDs {
                group.addTask {
                    try await runner.run(actionId: actionID, overrideInput: "第\(actionID)轮")
                }
            }
            for try await _ in group {}
        }
        XCTAssertFalse(coordinator.isStreaming, "10 个并发会话全部结束后注册表必须清空")
        XCTAssertEqual(sessions.sessions.count, 10, "每个 Action 独占独立后台会话")
        for actionID in actionIDs {
            guard let session = sessions.sessions.first(where: { $0.actionId == actionID }) else {
                XCTFail("缺少 action=\(actionID) 的会话")
                continue
            }
            let users = sessions.history(sessionId: session.id).filter { $0.role == .user }
            XCTAssertEqual(users.count, 1, "action=\(actionID) 会话只应有本轮一条用户消息")
            XCTAssertEqual(users.first?.content, "请总结：第\(actionID)轮", "并发会话内容不得串线")
        }
        XCTAssertEqual(usage.summary(period: .all).requestCount, 10)
    }

    @MainActor
    func testTenThousandDeltaStreamPersistsWithoutLossOrDuplication() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotTenKDelta-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "TenK",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        var batches = 0
        var reconstructed = ""
        coordinator.onDelta = { _, batch in
            batches += 1
            reconstructed += batch.text
        }
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            for _ in 0..<10_000 { continuation.yield(.delta("x")) }
            continuation.yield(.finished)
            continuation.finish()
        }
        await coordinator.consume(events, into: session.id)
        XCTAssertEqual(reconstructed.count, 10_000, "内存回放不得丢失 delta")
        XCTAssertLessThan(batches, 10_000, "UI 必须收到合帧批次而非逐 delta 回调")
        let stored = try await database.writer.read { db in try MessageRecord.fetchAll(db).map(\.entity) }
        XCTAssertEqual(stored.count, 1, "终态只应有一条助手消息")
        XCTAssertEqual(stored[0].content.count, 10_000, "落库正文不得丢失/重复 delta")
        XCTAssertEqual(Set(stored[0].content).count, 1, "落库正文必须是完整无污染的 10,000 个 x")
    }

    @MainActor
    func testConfigLoadBenchmarkStaysWithinRegressionGuard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotConfigBench-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let actions = (0..<10).map { "action-\($0)" }
        try makeConfigText(actions: actions).write(to: url, atomically: true, encoding: .utf8)

        // 冷启动一次（文件读取/页缓存），不计入样本。
        _ = try ConfigStore(loader: ConfigLoader(configURL: url))

        var samples: [Double] = []
        for _ in 0..<30 {
            let start = ContinuousClock.now
            _ = try ConfigStore(loader: ConfigLoader(configURL: url))
            samples.append(Double(start.duration(to: .now).components.attoseconds) / 1e15)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        XCTAssertLessThan(
            p95, 100,
            "配置解析+校验 P95 必须低于 100ms（回归护栏；典型值远低于此）")
    }
}
