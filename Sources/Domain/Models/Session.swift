import Foundation
import GRDB

struct Session: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    let id: String
    var title: String
    let channel: SessionChannel
    let actionId: String?
    let profileId: String?
    let provider: ProviderKind?
    let model: String?
    let sourceApp: String?
    let createdAt: Date
    var updatedAt: Date
    var archived: Bool

    static let databaseTableName = "sessions"

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let channel = Column("channel")
        static let actionId = Column("action_id")
        static let profileId = Column("profile_id")
        static let provider = Column("provider")
        static let model = Column("model")
        static let sourceApp = Column("source_app")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let archived = Column("archived")
    }

    init(
        channel: SessionChannel, title: String, meta: SessionMeta, id: String = UUID().uuidString,
        createdAt: Date = Date(), updatedAt: Date? = nil, archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.actionId = meta.actionId
        self.profileId = meta.profileId
        self.provider = meta.provider
        self.model = meta.model
        self.sourceApp = meta.sourceApp
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.archived = archived
    }

    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        channel = SessionChannel(rawValue: row["channel"] as String) ?? .console
        actionId = row["action_id"]
        profileId = row["profile_id"]
        if let raw: String = row["provider"] { provider = ProviderKind(rawValue: raw) } else { provider = nil }
        model = row["model"]
        sourceApp = row["source_app"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
        archived = row["archived"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["title"] = title
        container["channel"] = channel.rawValue
        container["action_id"] = actionId
        container["profile_id"] = profileId
        container["provider"] = provider?.rawValue
        container["model"] = model
        container["source_app"] = sourceApp
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["archived"] = archived
    }
}

struct SessionMeta: Sendable, Equatable, Codable {
    let actionId: String?
    let profileId: String?
    let provider: ProviderKind?
    let model: String?
    let sourceApp: String?
}

enum SessionChannel: String, Sendable, CaseIterable, Codable { case action, console, cli, push, tail }
