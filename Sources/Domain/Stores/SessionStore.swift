import ConsolepilotDomain
import Foundation
import GRDB
import Observation

@MainActor @Observable
final class SessionStore {
    private static let messagePageSize = 12
    private let database: AppDatabase
    private(set) var sessions: [Session]
    private(set) var currentId: String?
    private(set) var messages: [Message]
    private(set) var hasEarlierMessages: Bool

    init(database: AppDatabase) throws {
        self.database = database
        let loadedSessions = try database.writer.read { db in
            try SessionRecord
                .order(SessionRecord.Columns.updatedAt.desc, SessionRecord.Columns.id.desc)
                .fetchAll(db)
                .map(\.entity)
        }
        let loadedCurrentId = loadedSessions.first?.id
        let loadedPage =
            try loadedCurrentId.map { id in
                try Self.fetchMessagePage(database: database, sessionId: id, offset: 0)
            } ?? []
        self.sessions = loadedSessions
        self.currentId = loadedCurrentId
        self.messages = Array(loadedPage.prefix(Self.messagePageSize).reversed())
        self.hasEarlierMessages = loadedPage.count > Self.messagePageSize
    }

    func create(channel: SessionChannel, title: String, meta: SessionMeta) -> Session {
        let session = Session(channel: channel, title: title, meta: meta)
        do {
            var record = SessionRecord(session)
            try database.writer.write { db in try record.insert(db) }
            sessions.insert(session, at: 0)
            currentId = session.id
            messages = []
            hasEarlierMessages = false
        } catch {
            Log.error("创建会话失败：\(error)", category: .domain)
        }
        return session
    }

    func select(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentId = id
        do {
            let page = try Self.fetchMessagePage(database: database, sessionId: id, offset: 0)
            messages = Array(page.prefix(Self.messagePageSize).reversed())
            hasEarlierMessages = page.count > Self.messagePageSize
        } catch {
            Log.error("读取会话消息失败：\(error)", category: .domain)
            messages = []
            hasEarlierMessages = false
        }
    }

    @discardableResult
    func loadEarlierMessages() -> [Message] {
        guard let currentId, hasEarlierMessages else { return [] }
        do {
            let page = try Self.fetchMessagePage(
                database: database, sessionId: currentId, offset: messages.count)
            let older = Array(page.prefix(Self.messagePageSize).reversed())
            messages.insert(contentsOf: older, at: 0)
            hasEarlierMessages = page.count > Self.messagePageSize
            return older
        } catch {
            Log.error("读取更早消息失败：\(error)", category: .domain)
            return []
        }
    }

    func rename(_ id: String, to title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        session.title = title
        session.updatedAt = Date()
        do {
            let record = SessionRecord(session)
            try database.writer.write { db in try record.update(db) }
            sessions[index] = session
        } catch { Log.error("重命名会话失败：\(error)", category: .domain) }
    }

    func delete(_ id: String) {
        do {
            _ = try database.writer.write { db in try SessionRecord.deleteOne(db, key: id) }
            sessions.removeAll { $0.id == id }
            if currentId == id {
                currentId = sessions.first?.id
                if let next = currentId,
                    let page = try? Self.fetchMessagePage(database: database, sessionId: next, offset: 0)
                {
                    messages = Array(page.prefix(Self.messagePageSize).reversed())
                    hasEarlierMessages = page.count > Self.messagePageSize
                } else {
                    messages = []
                    hasEarlierMessages = false
                }
            }
        } catch { Log.error("删除会话失败：\(error)", category: .domain) }
    }

    func deleteAll() {
        do {
            _ = try database.writer.write { db in try SessionRecord.deleteAll(db) }
            sessions.removeAll()
            currentId = nil
            messages.removeAll()
            hasEarlierMessages = false
        } catch { Log.error("清空会话失败：\(error)", category: .domain) }
    }

    func appendMessage(_ message: Message) {
        do {
            var record = MessageRecord(message)
            try database.writer.write { db in try record.insert(db) }
            if message.sessionId == currentId { messages.append(message) }
            touchSession(message.sessionId, at: message.createdAt, force: true)
        } catch { Log.error("保存消息失败：\(error)", category: .domain) }
    }

    /// Inserts a streaming checkpoint or updates the existing assistant row.
    /// Checkpoints make an in-flight response recoverable after interruption or
    /// an app restart without creating duplicate assistant messages.
    func upsertMessage(_ message: Message) {
        do {
            var record = MessageRecord(message)
            try database.writer.write { db in try record.save(db) }
            if message.sessionId == currentId {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = message
                } else {
                    messages.append(message)
                }
            }
            touchSession(message.sessionId, at: message.createdAt, force: false)
        } catch { Log.error("保存流式检查点失败：\(error)", category: .domain) }
    }

    /// 消息落库后推进会话的 `updatedAt` 并重排。新消息强制推进；
    /// 检查点仅在其时间晚于会话时间时推进，避免旧检查点覆盖更新。
    private func touchSession(_ sessionId: String, at date: Date, force: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }),
            force || date > sessions[index].updatedAt
        else { return }
        sessions[index].updatedAt = date
        let record = SessionRecord(sessions[index])
        try? database.writer.write { db in try record.update(db) }
        sortSessions()
    }

    private func sortSessions() {
        sessions.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id > $1.id
        }
    }

    func search(_ query: String) -> [Message] {
        guard !query.isEmpty else { return [] }
        let escaped = query.replacingOccurrences(of: "%", with: "\\%")
        do {
            return try database.writer.read { db in
                try MessageRecord
                    .filter(Column("content").like("%\(escaped)%"))
                    .order(Column("created_at").desc)
                    .fetchAll(db)
                    .map(\.entity)
            }
        } catch {
            Log.error("搜索消息失败：\(error)", category: .domain)
            return []
        }
    }

    func session(id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    private static func fetchMessagePage(
        database: AppDatabase, sessionId: String, offset: Int
    ) throws -> [Message] {
        try database.writer.read { db in
            try MessageRecord
                .filter(Column("session_id") == sessionId)
                .order(Column("created_at").desc, Column("id").desc)
                .limit(messagePageSize + 1, offset: offset)
                .fetchAll(db)
                .map(\.entity)
        }
    }
}
