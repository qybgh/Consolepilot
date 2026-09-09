import Foundation

/// 会话领域实体（纯值类型，不依赖 GRDB；持久化映射见 `SessionRecord`）。
struct Session: Identifiable, Sendable, Equatable {
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
}

struct SessionMeta: Sendable, Equatable {
    let actionId: String?
    let profileId: String?
    let provider: ProviderKind?
    let model: String?
    let sourceApp: String?
}

enum SessionChannel: String, Sendable, CaseIterable { case action, console, cli, push, tail }
