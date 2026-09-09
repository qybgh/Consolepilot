import ConsolepilotDomain
import GRDB
import XCTest

@testable import ConsolepilotInfrastructure

/// P1-B：四个 Repository 协议的 SQLite/文件实现测试（全新 schema、WAL、分页、
/// 持久化 checkpoint、无效配置不覆盖最后有效配置）。
final class SQLiteRepositoryTests: XCTestCase {
    // MARK: - Helpers

    private func makeDatabasePath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotRepo-\(UUID().uuidString).sqlite"
        ).path
    }

    private func makeSession(id: String = UUID().uuidString, title: String, at date: Date = Date()) -> Session {
        Session(
            channel: .console, title: title,
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil),
            id: id, createdAt: date, updatedAt: date)
    }

    private func makeMessage(
        sessionId: String, content: String, at date: Date = Date(), id: String = UUID().uuidString
    ) -> Message {
        Message(id: id, sessionId: sessionId, role: .user, content: content, createdAt: date)
    }

    // MARK: - Session repository

    func testSessionRepositorySavesFetchesUpdatesAndCascadesDeletes() throws {
        let database = try AppDatabase(path: makeDatabasePath())
        let repository = SQLiteSessionRepository(database: database)
        let session = makeSession(id: "s1", title: "会话一")

        try repository.save(session)
        try repository.save(makeMessage(sessionId: "s1", content: "你好"))

        XCTAssertEqual(try repository.fetchSessions().map(\.id), ["s1"])
        XCTAssertEqual(try repository.fetchSession(id: "s1")?.title, "会话一")
        XCTAssertEqual(try repository.fetchMessages(sessionId: "s1", offset: 0, limit: 10).count, 1)

        var renamed = session
        renamed.title = "改名"
        try repository.save(renamed)
        XCTAssertEqual(try repository.fetchSession(id: "s1")?.title, "改名")

        try repository.deleteSession(id: "s1")
        XCTAssertNil(try repository.fetchSession(id: "s1"))
        XCTAssertTrue(try repository.fetchMessages(sessionId: "s1", offset: 0, limit: 10).isEmpty)
    }

    func testSessionRepositoryPaginatesMessagesNewestFirst() throws {
        let database = try AppDatabase(path: makeDatabasePath())
        let repository = SQLiteSessionRepository(database: database)
        try repository.save(makeSession(id: "s1", title: "分页"))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<5 {
            try repository.save(
                makeMessage(
                    sessionId: "s1", content: "m\(index)",
                    at: base.addingTimeInterval(TimeInterval(index)), id: "m\(index)"))
        }

        let page1 = try repository.fetchMessages(sessionId: "s1", offset: 0, limit: 2)
        XCTAssertEqual(page1.map(\.content), ["m4", "m3"])
        let page2 = try repository.fetchMessages(sessionId: "s1", offset: 2, limit: 2)
        XCTAssertEqual(page2.map(\.content), ["m2", "m1"])
        let page3 = try repository.fetchMessages(sessionId: "s1", offset: 4, limit: 2)
        XCTAssertEqual(page3.map(\.content), ["m0"])
    }

    func testSessionRepositorySearchMatchesContentAndRespectsLimit() throws {
        let database = try AppDatabase(path: makeDatabasePath())
        let repository = SQLiteSessionRepository(database: database)
        try repository.save(makeSession(id: "s1", title: "搜索"))
        try repository.save(makeMessage(sessionId: "s1", content: "含有目标词的消息", id: "hit1"))
        try repository.save(makeMessage(sessionId: "s1", content: "另一条", id: "miss"))
        try repository.save(makeMessage(sessionId: "s1", content: "再次目标词命中", id: "hit2"))

        let hits = try repository.searchMessages(matching: "目标词", limit: 10)
        XCTAssertEqual(Set(hits.map(\.id)), ["hit1", "hit2"])
        XCTAssertEqual(try repository.searchMessages(matching: "目标词", limit: 1).count, 1)
        XCTAssertTrue(try repository.searchMessages(matching: "", limit: 10).isEmpty)
    }

    func testRepositoryWritesSurviveReopenWithWALJournal() throws {
        let path = makeDatabasePath()
        let session = makeSession(id: "s1", title: "持久化")
        let message = makeMessage(sessionId: "s1", content: "检查点内容")
        let usage = Usage(
            profileId: "local", provider: .openai, model: "m", inputTokens: 10, outputTokens: 20)

        do {
            let database = try AppDatabase(path: path)
            let sessions = SQLiteSessionRepository(database: database)
            try sessions.save(session)
            try sessions.save(message)
            try SQLiteUsageRepository(database: database).record(usage)
            try SQLiteCaptureAuditRepository(database: database).record(
                CaptureLogEntry(
                    sourceApp: "Notes", sourceBundleId: "com.apple.Notes", characterCount: 3,
                    strategy: .accessibility, elapsed: .milliseconds(2)))
            let journal = try database.writer.read { db in
                try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
            }
            XCTAssertEqual(journal.lowercased(), "wal")
        }

        // 重新打开同一路径：写入必须已落盘（WAL checkpoint/持久化语义）。
        let reopened = try AppDatabase(path: path)
        let sessions = SQLiteSessionRepository(database: reopened)
        XCTAssertEqual(try sessions.fetchSession(id: "s1")?.title, "持久化")
        XCTAssertEqual(try sessions.fetchMessages(sessionId: "s1", offset: 0, limit: 10).map(\.content), ["检查点内容"])
        let summary = try SQLiteUsageRepository(database: reopened).fetchSummary(period: .all)
        XCTAssertEqual(summary.requestCount, 1)
        XCTAssertEqual(summary.inputTokens, 10)
    }

    // MARK: - Usage repository

    func testUsageRepositorySummarizesAllPeriods() throws {
        let database = try AppDatabase(path: makeDatabasePath())
        let repository = SQLiteUsageRepository(database: database)
        let now = Date()
        try repository.record(
            Usage(
                profileId: "local", provider: .openai, model: "a", inputTokens: 100, outputTokens: 50,
                costUSD: 0.01, createdAt: now))
        try repository.record(
            Usage(
                profileId: "local", provider: .anthropic, model: "b", inputTokens: 10, outputTokens: 5,
                costUSD: 0.02, createdAt: now.addingTimeInterval(-86_400)))
        try repository.record(
            Usage(
                profileId: "local", provider: .openai, model: "a", inputTokens: 1, outputTokens: 1,
                createdAt: now.addingTimeInterval(-8 * 86_400)))

        let today = try repository.fetchSummary(period: .today)
        XCTAssertEqual(today.requestCount, 1)
        XCTAssertEqual(today.inputTokens, 100)
        let week = try repository.fetchSummary(period: .week)
        XCTAssertEqual(week.requestCount, 2)
        XCTAssertEqual(week.byModel["a"]?.inputTokens, 100)
        let all = try repository.fetchSummary(period: .all)
        XCTAssertEqual(all.requestCount, 3)
        XCTAssertEqual(all.inputTokens, 111)
    }

    // MARK: - Capture audit repository

    func testCaptureAuditRepositoryPersistsMetadataOnly() throws {
        let database = try AppDatabase(path: makeDatabasePath())
        let repository = SQLiteCaptureAuditRepository(database: database)
        let entry = CaptureLogEntry(
            id: "audit-1", sourceApp: "Safari", sourceBundleId: "com.apple.Safari", characterCount: 42,
            strategy: .clipboard, elapsed: .milliseconds(1))
        try repository.record(entry)

        let columns = try database.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(capture_log)").compactMap { row -> String? in
                row["name"]
            }
        }
        XCTAssertFalse(columns.contains("content"))
        let loaded = try database.writer.read { db in
            try CaptureLogRecord.fetchOne(db, key: "audit-1")?.entity
        }
        XCTAssertEqual(loaded?.characterCount, 42)
        XCTAssertEqual(loaded?.sourceBundleId, "com.apple.Safari")
    }

    // MARK: - Configuration repository

    func testFileConfigurationRepositoryKeepsLastGoodOnInvalidReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotConfigRepo-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let template = """
            [general]
            port = %d
            theme = "tokyo-night"
            """
        try String(format: template, 8765).write(to: url, atomically: true, encoding: .utf8)
        let repository = try FileConfigurationRepository(loader: ConfigLoader(configURL: url))
        XCTAssertEqual(repository.current.general.port, 8765)

        try String(format: template, 0).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try repository.reload())
        XCTAssertEqual(repository.current.general.port, 8765, "无效配置不得替换最后有效配置")

        try String(format: template, 9999).write(to: url, atomically: true, encoding: .utf8)
        try repository.reload()
        XCTAssertEqual(repository.current.general.port, 9999)
    }
}
