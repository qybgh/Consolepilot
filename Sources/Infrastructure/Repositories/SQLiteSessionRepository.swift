import ConsolepilotDomain
import Foundation
import GRDB

/// `SessionRepository` 的 SQLite 实现（全新 schema，无迁移兼容分支，D8）。
///
/// 分页语义与现有 UI 一致：`fetchMessages` 按 `created_at desc, id desc`
/// 返回「最新在前」的一页；`offset` 从 0 开始。
package struct SQLiteSessionRepository: SessionRepository {
    private let writer: DatabaseWriter

    package init(database: AppDatabase) {
        writer = database.writer
    }

    package func fetchSessions() throws -> [Session] {
        try writer.read { db in
            try SessionRecord
                .order(SessionRecord.Columns.updatedAt.desc, SessionRecord.Columns.id.desc)
                .fetchAll(db)
                .map(\.entity)
        }
    }

    package func fetchSession(id: String) throws -> Session? {
        try writer.read { db in
            try SessionRecord.fetchOne(db, key: id)?.entity
        }
    }

    package func fetchMessages(sessionId: String, offset: Int, limit: Int) throws -> [Message] {
        precondition(offset >= 0 && limit >= 0, "分页参数必须非负")
        guard limit > 0 else { return [] }
        return try writer.read { db in
            try MessageRecord
                .filter(MessageRecord.Columns.sessionId == sessionId)
                .order(MessageRecord.Columns.createdAt.desc, MessageRecord.Columns.id.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
                .map(\.entity)
        }
    }

    package func searchMessages(matching query: String, limit: Int) throws -> [Message] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let escaped = query.replacingOccurrences(of: "%", with: "\\%")
        return try writer.read { db in
            try MessageRecord
                .filter(MessageRecord.Columns.content.like("%\(escaped)%"))
                .order(MessageRecord.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
                .map(\.entity)
        }
    }

    package func save(_ session: Session) throws {
        try writer.write { db in
            var record = SessionRecord(session)
            try record.save(db)
        }
    }

    package func save(_ message: Message) throws {
        try writer.write { db in
            var record = MessageRecord(message)
            try record.save(db)
        }
    }

    package func deleteSession(id: String) throws {
        try writer.write { db in
            _ = try SessionRecord.deleteOne(db, key: id)
        }
    }

    package func deleteAllSessions() throws {
        try writer.write { db in
            _ = try SessionRecord.deleteAll(db)
        }
    }
}
