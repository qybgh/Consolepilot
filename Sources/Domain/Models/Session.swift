import Foundation

/// 会话领域实体（纯值类型，不依赖 GRDB；持久化映射见 `SessionRecord`）。
public struct Session: Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public let channel: SessionChannel
    public let actionId: String?
    public let profileId: String?
    public let provider: ProviderKind?
    public let model: String?
    public let sourceApp: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var archived: Bool

    public init(
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
}

public struct SessionMeta: Sendable, Equatable {
    public let actionId: String?
    public let profileId: String?
    public let provider: ProviderKind?
    public let model: String?
    public let sourceApp: String?

    public init(
        actionId: String?, profileId: String?, provider: ProviderKind?, model: String?, sourceApp: String?
    ) {
        self.actionId = actionId
        self.profileId = profileId
        self.provider = provider
        self.model = model
        self.sourceApp = sourceApp
    }
}

public enum SessionChannel: String, Sendable, CaseIterable { case action, console, cli, push }
