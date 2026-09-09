import ConsolepilotDomain
import GRDB
import XCTest

@testable import ConsolepilotInfrastructure

final class DatabaseTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotTests-\(UUID().uuidString).sqlite"
        ).path
        return try AppDatabase(path: path)
    }

    private func makeSession(channel: SessionChannel = .console, title: String) -> Session {
        Session(
            channel: channel, title: title,
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
    }

    func testMigrationIsIdempotentAndEnablesWALAndForeignKeys() throws {
        let database = try makeDatabase()
        try Migrations.migrator.migrate(database.writer)
        let values = try database.writer.read { db in
            let journal: String = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
            let foreignKeys: Int = try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            return (journal, foreignKeys, tables)
        }
        XCTAssertEqual(values.0.lowercased(), "wal")
        XCTAssertEqual(values.1, 1)
        XCTAssertTrue(values.2.contains("sessions"))
        XCTAssertTrue(values.2.contains("messages"))
        XCTAssertTrue(values.2.contains("capture_log"))
    }

    func testCaptureLogContainsMetadataOnly() throws {
        let database = try makeDatabase()
        let entry = CaptureLogEntry(
            sourceApp: "Notes", sourceBundleId: "com.apple.Notes", characterCount: 12,
            strategy: .accessibility, elapsed: .milliseconds(3))
        var record = CaptureLogRecord(entry)
        try database.writer.write { db in try record.insert(db) }
        let columns = try database.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(capture_log)").compactMap { row -> String? in row["name"] }
        }
        XCTAssertFalse(columns.contains("content"))
        let loaded = try database.writer.read { db in
            try CaptureLogRecord.fetchOne(db, key: entry.id)?.entity
        }
        XCTAssertEqual(loaded?.id, entry.id)
        XCTAssertEqual(loaded?.characterCount, entry.characterCount)
        XCTAssertEqual(loaded?.strategy, entry.strategy)
        XCTAssertEqual(loaded?.sourceBundleId, entry.sourceBundleId)
        XCTAssertEqual(loaded?.elapsed, entry.elapsed)
    }

    func testSessionCascadeDeletesMessages() throws {
        let database = try makeDatabase()
        let session = makeSession(title: "Test")
        let message = Message(sessionId: session.id, role: .user, content: "hello")
        var sessionRecord = SessionRecord(session)
        var messageRecord = MessageRecord(message)
        try database.writer.write { db in
            try sessionRecord.insert(db)
            try messageRecord.insert(db)
        }
        _ = try database.writer.write { db in try SessionRecord.deleteOne(db, key: session.id) }
        let count = try database.writer.read { db in try MessageRecord.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testSessionStoreDeletesCurrentSessionAndSelectsNext() throws {
        let database = try makeDatabase()
        let store = try SessionStore(database: database)
        let first = store.create(
            channel: .console, title: "First",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        store.appendMessage(Message(sessionId: first.id, role: .user, content: "first"))
        let second = store.create(
            channel: .console, title: "Second",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        store.delete(second.id)
        XCTAssertEqual(store.currentId, first.id)
        XCTAssertEqual(store.messages.map(\.content), ["first"])
        XCTAssertEqual(store.sessions.map(\.id), [first.id])
    }

    @MainActor
    func testSessionStoreDeletesAllSessionsAndMessages() throws {
        let database = try makeDatabase()
        let store = try SessionStore(database: database)
        let session = store.create(
            channel: .console, title: "Delete all",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        store.appendMessage(Message(sessionId: session.id, role: .assistant, content: "content"))
        store.deleteAll()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.currentId)
        XCTAssertTrue(store.messages.isEmpty)
        let counts = try database.writer.read { db in
            (try SessionRecord.fetchCount(db), try MessageRecord.fetchCount(db))
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
    }

    @MainActor
    func testSessionStorePaginatesMessagesNewestFirstButPresentsChronologically() throws {
        let database = try makeDatabase()
        let session = makeSession(title: "Paged")
        var sessionRecord = SessionRecord(session)
        try database.writer.write { db in
            try sessionRecord.insert(db)
            for index in 0..<55 {
                var message = MessageRecord(
                    Message(
                        id: String(format: "%03d", index), sessionId: session.id, role: .user,
                        content: "message-\(index)", createdAt: Date(timeIntervalSince1970: Double(index))))
                try message.insert(db)
            }
        }
        let store = try SessionStore(database: database)
        XCTAssertEqual(store.messages.count, 12)
        XCTAssertEqual(store.messages.first?.content, "message-43")
        XCTAssertEqual(store.messages.last?.content, "message-54")
        XCTAssertTrue(store.hasEarlierMessages)

        let secondPage = store.loadEarlierMessages()
        XCTAssertEqual(secondPage.count, 12)
        XCTAssertEqual(store.messages.first?.content, "message-31")
        XCTAssertEqual(store.messages.last?.content, "message-54")

        _ = store.loadEarlierMessages()
        _ = store.loadEarlierMessages()
        let finalPage = store.loadEarlierMessages()
        XCTAssertEqual(finalPage.count, 7)
        XCTAssertEqual(store.messages.first?.content, "message-0")
        XCTAssertFalse(store.hasEarlierMessages)
    }

    func testTenThousandMessageLatestPageQueryStaysWithinPlanThreshold() throws {
        let database = try makeDatabase()
        let session = makeSession(title: "Performance")
        var sessionRecord = SessionRecord(session)
        try database.writer.write { db in
            try sessionRecord.insert(db)
            for index in 0..<10_000 {
                var message = MessageRecord(
                    Message(
                        id: String(format: "%05d", index), sessionId: session.id, role: .assistant,
                        content: "message-\(index)", createdAt: Date(timeIntervalSince1970: Double(index))))
                try message.insert(db)
            }
        }

        // Warm the SQLite page cache, then collect enough samples to avoid a
        // single scheduler hiccup deciding the result.
        _ = try database.writer.read { db in
            try MessageRecord.filter(Column("session_id") == session.id)
                .order(Column("created_at").desc, Column("id").desc).limit(13).fetchAll(db)
        }
        var samples: [Double] = []
        for _ in 0..<30 {
            let start = ContinuousClock.now
            let rows = try database.writer.read { db in
                try MessageRecord.filter(Column("session_id") == session.id)
                    .order(Column("created_at").desc, Column("id").desc).limit(13).fetchAll(db)
            }
            XCTAssertEqual(rows.count, 13)
            samples.append(Double(start.duration(to: .now).components.attoseconds) / 1e15)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        XCTAssertLessThan(p95, 20, "10k-message latest-page query P95 must remain below 20ms")
    }
}
