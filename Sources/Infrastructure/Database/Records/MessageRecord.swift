import Foundation
import GRDB

/// 消息表的 GRDB record，负责 `Message` 领域实体与数据库行之间的映射。
struct MessageRecord: FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    var id: String
    var sessionId: String
    var role: String
    var content: String
    var state: String
    var createdAt: Date

    static let databaseTableName = "messages"

    enum Columns {
        static let id = Column("id")
        static let sessionId = Column("session_id")
        static let role = Column("role")
        static let content = Column("content")
        static let state = Column("state")
        static let createdAt = Column("created_at")
    }

    init(_ message: Message) {
        id = message.id
        sessionId = message.sessionId
        role = message.role.rawValue
        content = message.content
        state = message.state.rawValue
        createdAt = message.createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        sessionId = row["session_id"]
        role = row["role"]
        content = row["content"]
        state = row["state"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["session_id"] = sessionId
        container["role"] = role
        container["content"] = content
        container["state"] = state
        container["created_at"] = createdAt
    }

    var entity: Message {
        Message(
            id: id, sessionId: sessionId, role: MessageRole(rawValue: role) ?? .system,
            content: content, state: MessageState(rawValue: state) ?? .failed, createdAt: createdAt)
    }
}
