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
            try Session
                .order(Session.Columns.updatedAt.desc, Session.Columns.id.desc)
                .fetchAll(db)
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
        var session = Session(channel: channel, title: title, meta: meta)
        do {
            try database.writer.write { db in try session.insert(db) }
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
            try database.writer.write { db in try session.update(db) }
            sessions[index] = session
        } catch { Log.error("重命名会话失败：\(error)", category: .domain) }
    }

    func delete(_ id: String) {
        do {
            _ = try database.writer.write { db in try Session.deleteOne(db, key: id) }
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
            _ = try database.writer.write { db in try Session.deleteAll(db) }
            sessions.removeAll()
            currentId = nil
            messages.removeAll()
            hasEarlierMessages = false
        } catch { Log.error("清空会话失败：\(error)", category: .domain) }
    }

    func appendMessage(_ message: Message) {
        do {
            var persisted = message
            try database.writer.write { db in try persisted.insert(db) }
            if message.sessionId == currentId { messages.append(message) }
            if let index = sessions.firstIndex(where: { $0.id == message.sessionId }) {
                sessions[index].updatedAt = message.createdAt
                try? database.writer.write { db in try sessions[index].update(db) }
                sortSessions()
            }
        } catch { Log.error("保存消息失败：\(error)", category: .domain) }
    }

    /// Inserts a streaming checkpoint or updates the existing assistant row.
    /// Checkpoints make an in-flight response recoverable after interruption or
    /// an app restart without creating duplicate assistant messages.
    func upsertMessage(_ message: Message) {
        do {
            var persisted = message
            try database.writer.write { db in
                try persisted.save(db)
            }
            if message.sessionId == currentId {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = message
                } else {
                    messages.append(message)
                }
            }
            if let index = sessions.firstIndex(where: { $0.id == message.sessionId }) {
                if message.createdAt > sessions[index].updatedAt {
                    sessions[index].updatedAt = message.createdAt
                    try? database.writer.write { db in try sessions[index].update(db) }
                }
                sortSessions()
            }
        } catch { Log.error("保存流式检查点失败：\(error)", category: .domain) }
    }

    private func sortSessions() {
        sessions.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id > $1.id
        }
    }

    func search(_ query: String) -> [Message] {
        guard !query.isEmpty else { return [] }
        do {
            return try database.writer.read { db in
                try Message.filter(Column("content").like("%\(query.replacingOccurrences(of: "%", with: "\\%"))%"))
                    .order(Column("created_at").desc).fetchAll(db)
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
            try Message
                .filter(Column("session_id") == sessionId)
                .order(Column("created_at").desc, Column("id").desc)
                .limit(messagePageSize + 1, offset: offset)
                .fetchAll(db)
        }
    }
}
