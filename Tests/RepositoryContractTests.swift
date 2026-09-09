import ConsolepilotDomain
import XCTest

/// P0-C 空壳契约测试：以内存 fake 固定四个 Repository 协议的存在与契约方向，
/// 供 P1-B 的 SQLite/文件实现对照（fake 不代表最终实现语义）。
final class RepositoryContractTests: XCTestCase {
    private func makeConfig(port: UInt16) -> AppConfig {
        AppConfig(
            general: GeneralConfig(
                port: port, theme: "tokyo-night", opacity: 0.92, alwaysOnTop: true,
                fontName: "SF Mono", fontSize: 13, compactFontSize: 11, scrollbackLines: 100_000),
            server: ServerConfig(authTokenRef: "${env:CONSOLEPILOT_TEST_SECRET}", maxBodyBytes: 1_048_576),
            capture: CaptureConfig(
                strategy: [.clipboard], simulatedCopyWait: .milliseconds(120), restoreClipboard: true,
                maxInputChars: 40_000, excludeBundleIds: []),
            profiles: [], actions: [])
    }

    func testSessionRepositoryContractPinsSessionAndMessageLifecycle() throws {
        let repository = MemorySessionRepository()
        let session = Session(
            channel: .console, title: "会话",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let first = Message(sessionId: session.id, role: .user, content: "一")
        let second = Message(sessionId: session.id, role: .assistant, content: "二")

        try repository.save(session)
        XCTAssertEqual(try repository.fetchSessions(), [session])
        XCTAssertEqual(try repository.fetchSession(id: session.id)?.id, session.id)
        XCTAssertNil(try repository.fetchSession(id: "missing"))

        try repository.save(first)
        try repository.save(second)
        let page = try repository.fetchMessages(sessionId: session.id, offset: 0, limit: 1)
        XCTAssertEqual(page, [first])
        let rest = try repository.fetchMessages(sessionId: session.id, offset: 1, limit: 10)
        XCTAssertEqual(rest, [second])
        XCTAssertTrue(try repository.fetchMessages(sessionId: "missing", offset: 0, limit: 10).isEmpty)

        var updated = first
        updated.content = "一（已修订）"
        try repository.save(updated)
        let all = try repository.fetchMessages(sessionId: session.id, offset: 0, limit: 10)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(updated))
        XCTAssertEqual(try repository.searchMessages(matching: "修订", limit: 10), [updated])

        try repository.deleteSession(id: session.id)
        XCTAssertTrue(try repository.fetchSessions().isEmpty)
        XCTAssertTrue(try repository.fetchMessages(sessionId: session.id, offset: 0, limit: 10).isEmpty)

        let extra = Session(
            channel: .console, title: "另一个",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        try repository.save(extra)
        try repository.deleteAllSessions()
        XCTAssertTrue(try repository.fetchSessions().isEmpty)
    }

    func testUsageRepositoryContractPinsRecordingAndAggregation() throws {
        let repository = MemoryUsageRepository()
        let first = Usage(profileId: "local", provider: .openai, model: "m1", inputTokens: 10, outputTokens: 1)
        let second = Usage(profileId: "local", provider: .openai, model: "m1", inputTokens: 20, outputTokens: 2)

        try repository.record(first)
        try repository.record(second)

        let summary = try repository.fetchSummary(period: .all)
        XCTAssertEqual(summary.requestCount, 2)
        XCTAssertEqual(summary.inputTokens, 30)
        XCTAssertEqual(summary.outputTokens, 3)
    }

    func testCaptureAuditRepositoryContractPinsMetadataOnlyRecording() throws {
        let repository = MemoryCaptureAuditRepository()
        let entry = CaptureLogEntry(
            sourceApp: "TextEdit", sourceBundleId: "com.apple.TextEdit", characterCount: 42,
            strategy: .clipboard, elapsed: .milliseconds(3))

        try repository.record(entry)

        XCTAssertEqual(repository.recorded.count, 1)
        XCTAssertEqual(repository.recorded[0], entry)
    }

    func testConfigurationRepositoryContractPinsReloadRetainsLastGood() throws {
        let initial = makeConfig(port: 8765)
        let replacement = makeConfig(port: 9000)
        let repository = MemoryConfigurationRepository(current: initial)
        XCTAssertEqual(repository.current.general.port, 8765)

        repository.nextResult = .success(replacement)
        try repository.reload()
        XCTAssertEqual(repository.current.general.port, 9000)

        repository.nextResult = .failure(ConfigError.invalid("模拟失败"))
        XCTAssertThrowsError(try repository.reload())
        XCTAssertEqual(repository.current.general.port, 9000, "失败时必须保留最后有效配置")
    }
}

private final class MemorySessionRepository: SessionRepository {
    private(set) var sessions: [Session] = []
    private var messagesBySession: [String: [Message]] = [:]

    func fetchSessions() throws -> [Session] { sessions }

    func fetchSession(id: String) throws -> Session? {
        sessions.first { $0.id == id }
    }

    func fetchMessages(sessionId: String, offset: Int, limit: Int) throws -> [Message] {
        let messages = messagesBySession[sessionId] ?? []
        guard offset < messages.count else { return [] }
        return Array(messages[offset..<min(messages.count, offset + limit)])
    }

    func searchMessages(matching query: String, limit: Int) throws -> [Message] {
        messagesBySession.values.flatMap { $0 }
            .filter { $0.content.localizedCaseInsensitiveContains(query) }
            .prefix(limit).map { $0 }
    }

    func save(_ session: Session) throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    func save(_ message: Message) throws {
        var messages = messagesBySession[message.sessionId] ?? []
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        messagesBySession[message.sessionId] = messages
    }

    func deleteSession(id: String) throws {
        sessions.removeAll { $0.id == id }
        messagesBySession[id] = nil
    }

    func deleteAllSessions() throws {
        sessions.removeAll()
        messagesBySession.removeAll()
    }
}

private final class MemoryUsageRepository: UsageRepository {
    private var records: [Usage] = []

    func record(_ usage: Usage) throws {
        records.append(usage)
    }

    func fetchSummary(period: UsagePeriod) throws -> UsageSummary {
        let filtered: [Usage]
        if period == .all {
            filtered = records
        } else {
            let interval: TimeInterval = period == .today ? 86_400 : 7 * 86_400
            filtered = records.filter { $0.createdAt >= Date().addingTimeInterval(-interval) }
        }
        return UsageSummary(
            inputTokens: filtered.reduce(0) { $0 + $1.inputTokens },
            outputTokens: filtered.reduce(0) { $0 + $1.outputTokens },
            costUSD: filtered.compactMap(\.costUSD).reduce(0, +),
            requestCount: filtered.count,
            byModel: [:])
    }
}

private final class MemoryCaptureAuditRepository: CaptureAuditRepository {
    private(set) var recorded: [CaptureLogEntry] = []

    func record(_ entry: CaptureLogEntry) throws {
        recorded.append(entry)
    }
}

private final class MemoryConfigurationRepository: ConfigurationRepository {
    private(set) var current: AppConfig
    var nextResult: Result<AppConfig, Error> = .failure(ConfigError.invalid("未设置结果"))

    init(current: AppConfig) {
        self.current = current
    }

    func reload() throws {
        current = try nextResult.get()
    }
}
