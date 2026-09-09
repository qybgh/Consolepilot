import ConsolepilotDomain
import Foundation
import GRDB

/// 会话表的 GRDB record，负责 `Session` 领域实体与数据库行之间的映射。
struct SessionRecord: FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    var id: String
    var title: String
    var channel: String
    var actionId: String?
    var profileId: String?
    var provider: String?
    var model: String?
    var sourceApp: String?
    var createdAt: Date
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

    init(_ session: Session) {
        id = session.id
        title = session.title
        channel = session.channel.rawValue
        actionId = session.actionId
        profileId = session.profileId
        provider = session.provider?.rawValue
        model = session.model
        sourceApp = session.sourceApp
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        archived = session.archived
    }

    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        channel = row["channel"]
        actionId = row["action_id"]
        profileId = row["profile_id"]
        provider = row["provider"]
        model = row["model"]
        sourceApp = row["source_app"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
        archived = row["archived"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["channel"] = channel
        container["action_id"] = actionId
        container["profile_id"] = profileId
        container["provider"] = provider
        container["model"] = model
        container["source_app"] = sourceApp
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["archived"] = archived
    }

    var entity: Session {
        Session(
            channel: SessionChannel(rawValue: channel) ?? .console, title: title,
            meta: SessionMeta(
                actionId: actionId, profileId: profileId, provider: provider.flatMap(ProviderKind.init),
                model: model, sourceApp: sourceApp),
            id: id, createdAt: createdAt, updatedAt: updatedAt, archived: archived)
    }
}
