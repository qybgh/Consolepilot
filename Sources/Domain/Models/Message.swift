import Foundation
import GRDB

struct Message: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    let id: String
    let sessionId: String
    let role: MessageRole
    var content: String
    var state: MessageState
    let createdAt: Date

    static let databaseTableName = "messages"

    init(
        id: String = UUID().uuidString, sessionId: String, role: MessageRole, content: String,
        state: MessageState = .complete, createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.state = state
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        sessionId = row["session_id"]
        role = MessageRole(rawValue: row["role"] as String) ?? .system
        content = row["content"]
        state = MessageState(rawValue: row["state"] as String) ?? .failed
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["session_id"] = sessionId
        container["role"] = role.rawValue
        container["content"] = content
        container["state"] = state.rawValue
        container["created_at"] = createdAt
    }
}

enum MessageRole: String, Sendable, CaseIterable, Codable { case system, user, assistant, tool }
enum MessageState: String, Sendable, Codable { case complete, interrupted, failed }

struct MessageHeader: Sendable, Equatable, Codable {
    let timestamp: Date
    let role: MessageRole
    let channel: SessionChannel
    let model: String?
    let sourceApp: String?
}
